import { z } from 'zod';
import { Bill, BillItem, BillKind, BillStatus, PaymentMethod, Prisma, Role } from '@prisma/client';
import { prisma, Tx } from '../lib/prisma';
import { num, round2, round3 } from '../lib/money';
import { badRequest, conflict, forbidden, notFound } from '../lib/errors';
import { nextBillNo } from '../lib/sequence';
import { logActivity } from '../lib/activity';
import { AuthUser } from '../middleware/auth';
import { consumeBatches, moveStock, restoreBatches, BatchAllocation } from './stock.service';
import { readSettings, ShopSettings } from './settings.service';

export const CheckoutSchema = z.object({
  id: z.string().uuid(),
  kind: z.nativeEnum(BillKind).default(BillKind.SALE),
  status: z.nativeEnum(BillStatus).default(BillStatus.COMPLETED),
  /** Legacy flag from old clients – editing completed bills is no longer allowed (rejected below). */
  editing: z.boolean().default(false),
  tableName: z.string().trim().nullish(),
  customerId: z.string().uuid().nullish(),
  /** Quick customer capture by mobile (auto-creates "New Customer" if unknown). */
  customerPhone: z.string().trim().regex(/^\d{10}$/, 'Must be 10 digits').nullish(),
  customerName: z.string().trim().nullish(),
  items: z
    .array(
      z.object({
        productId: z.string().uuid().nullish(),
        productName: z.string().trim().nullish(),
        quantity: z.coerce.number().positive(),
        soldPrice: z.coerce.number().min(0).nullish(),
        priceType: z.enum(['base', 'last', 'max', 'custom', 'branch']).default('base'),
        discount: z.coerce.number().min(0).default(0),
        note: z.string().nullish(),
        kotPrintedQuantity: z.coerce.number().min(0).default(0),
      }),
    )
    .min(1, 'Cart is empty'),
  discountType: z.enum(['flat', 'percent']).default('flat'),
  discountValue: z.coerce.number().min(0).default(0),
  loyaltyPointsToRedeem: z.coerce.number().min(0).default(0),
  /** Round the payable total to a whole rupee: down (435.60 → 435) or up (→ 436). */
  roundMode: z.enum(['none', 'down', 'up']).default('none'),
  paymentMethod: z.nativeEnum(PaymentMethod).default(PaymentMethod.CASH),
  receivedAmount: z.coerce.number().min(0).nullish(),
  cashAmount: z.coerce.number().min(0).default(0),
  upiAmount: z.coerce.number().min(0).default(0),
  cardAmount: z.coerce.number().min(0).default(0),
  /** Return excess cash as change instead of crediting the customer's account. */
  giveChange: z.boolean().default(true),
  note: z.string().nullish(),
  billDate: z.coerce.date().nullish(),
});
export type CheckoutInput = z.infer<typeof CheckoutSchema>;

export const billInclude = { items: true } as const;
export type BillWithItems = Bill & { items: BillItem[] };

interface PricedItem {
  productId: string | null;
  productName: string;
  categoryId: string | null;
  hsnCode: string | null;
  quantity: number;
  originalPrice: number;
  soldPrice: number;
  priceType: string;
  discount: number;
  gstPercent: number;
  isIgst: boolean;
  taxableAmount: number;
  gstAmount: number;
  lineTotal: number;
  note: string | null;
  kotPrintedQuantity: number;
  trackStock: boolean;
}

/** Pure totals computation – shared with the client preview and unit tests. */
export function computeLine(
  qty: number,
  price: number,
  discount: number,
  gstPercent: number,
  gstInclusive: boolean,
) {
  const gross = round2(qty * price - discount);
  if (gstInclusive) {
    const taxable = round2(gross / (1 + gstPercent / 100));
    return { taxable, gst: round2(gross - taxable), lineTotal: gross };
  }
  const gst = round2((gross * gstPercent) / 100);
  return { taxable: gross, gst, lineTotal: round2(gross + gst) };
}

export function computeTotals(
  lines: { taxableAmount: number; gstAmount: number; discount: number }[],
  discountType: 'flat' | 'percent',
  discountValue: number,
  loyaltyRedeem: number,
  roundMode: 'none' | 'down' | 'up' = 'none',
) {
  const subtotal = round2(lines.reduce((s, l) => s + l.taxableAmount, 0));
  const totalGst = round2(lines.reduce((s, l) => s + l.gstAmount, 0));
  const itemDiscount = round2(lines.reduce((s, l) => s + l.discount, 0));
  const gross = round2(subtotal + totalGst);
  let discount = discountType === 'percent' ? round2((gross * Math.min(discountValue, 100)) / 100) : discountValue;
  discount = Math.min(discount, gross);
  const redeem = Math.min(loyaltyRedeem, round2(gross - discount));
  const exact = round2(gross - discount - redeem);
  const total = roundMode === 'down' ? Math.floor(exact + 1e-9) : roundMode === 'up' ? Math.ceil(exact - 1e-9) : exact;
  const roundOff = round2(total - exact);
  return { subtotal, totalGst, itemDiscount, discount: round2(discount), loyaltyRedeem: round2(redeem), roundOff, total };
}

async function priceItems(
  tx: Tx,
  shopId: string,
  branchId: string,
  customerId: string | null,
  input: CheckoutInput,
  settings: ShopSettings,
): Promise<PricedItem[]> {
  const ids = input.items.map((i) => i.productId).filter((x): x is string => !!x);
  const products = await tx.product.findMany({
    where: { shopId, id: { in: ids } },
    include: { branches: { where: { branchId } } },
  });
  const byId = new Map(products.map((p) => [p.id, p]));
  const lastPrices = customerId
    ? new Map(
        (await tx.customerPrice.findMany({ where: { customerId, productId: { in: ids } } })).map((c) => [
          c.productId,
          num(c.lastPrice),
        ]),
      )
    : new Map<string, number>();

  return input.items.map((i) => {
    const p = i.productId ? byId.get(i.productId) : undefined;
    if (i.productId && !p) throw badRequest(`Product ${i.productId} not found`);
    if (!p && !i.productName) throw badRequest('Ad-hoc item needs a productName');
    if (p && p.branchScope === 'SPECIFIC' && !p.branches[0]?.enabled) {
      throw badRequest(`${p.name} is not available in current branch`);
    }
    const branchPrice = p?.branches[0]?.price != null ? num(p.branches[0].price) : null;
    const original = branchPrice ?? (p ? num(p.basePrice) : num(i.soldPrice));
    let sold: number;
    switch (i.priceType) {
      case 'max':
        sold = p?.maxPrice != null ? num(p.maxPrice) : original;
        break;
      case 'last':
        sold = (p && lastPrices.get(p.id)) ?? original;
        break;
      case 'custom':
        if (i.soldPrice == null) throw badRequest(`Enter price for ${p?.name ?? i.productName}`);
        sold = i.soldPrice;
        break;
      default:
        sold = i.soldPrice ?? original;
    }
    const gstPercent = input.kind === BillKind.EXPENSE ? 0 : p ? num(p.gstPercent) : 0;
    const line = computeLine(i.quantity, sold, i.discount, gstPercent, settings.gstInclusive);
    return {
      productId: p?.id ?? null,
      productName: p?.name ?? i.productName!,
      categoryId: p?.categoryId ?? null,
      hsnCode: p?.hsnCode ?? null,
      quantity: round3(i.quantity),
      originalPrice: original,
      soldPrice: round2(sold),
      priceType: i.priceType,
      discount: round2(i.discount),
      gstPercent,
      isIgst: p?.isIgst ?? false,
      taxableAmount: line.taxable,
      gstAmount: line.gst,
      lineTotal: line.lineTotal,
      note: i.note ?? null,
      kotPrintedQuantity: i.kotPrintedQuantity,
      trackStock: p?.trackStock ?? false,
    };
  });
}

/** Apply stock + customer side effects of a completed bill. */
async function applyEffects(tx: Tx, bill: BillWithItems, user: AuthUser | null, settings: ShopSettings, label: string) {
  if (bill.kind === BillKind.SALE) {
    for (const it of bill.items) {
      if (!it.productId) continue;
      const product = await tx.product.findUnique({ where: { id: it.productId }, select: { trackStock: true } });
      if (!product?.trackStock) continue;
      await moveStock(
        tx,
        { shopId: bill.shopId, branchId: bill.branchId, userId: user?.id, userName: user?.name, refType: 'bill', refId: bill.id, note: `${label}${bill.billNo}` },
        it.productId,
        it.productName,
        -num(it.quantity),
        'sale',
      );
      const alloc = await consumeBatches(tx, bill.shopId, bill.branchId, it.productId, num(it.quantity));
      await tx.billItem.update({ where: { id: it.id }, data: { batchAllocations: alloc as unknown as Prisma.InputJsonValue } });
    }
  }

  if (bill.customerId && bill.kind === BillKind.SALE) {
    const c = await tx.customer.findUniqueOrThrow({ where: { id: bill.customerId } });
    const opening = num(c.currentBalance);
    const applied = round2(num(bill.receivedAmount) - num(bill.changeAmount));
    const closing = round2(opening + num(bill.totalAmount) - applied);
    const earned = settings.enableLoyaltyPoints ? Math.floor(num(bill.totalAmount) / settings.loyaltyPointsRatio) : 0;
    await tx.customer.update({
      where: { id: c.id },
      data: {
        currentBalance: closing,
        loyaltyPoints: { increment: earned - num(bill.loyaltyPointsRedeemed) },
      },
    });
    await tx.bill.update({
      where: { id: bill.id },
      data: { customerOpeningBal: opening, customerClosingBal: closing, loyaltyPointsEarned: earned },
    });
    for (const it of bill.items) {
      if (!it.productId) continue;
      await tx.customerPrice.upsert({
        where: { customerId_productId: { customerId: c.id, productId: it.productId } },
        create: { customerId: c.id, productId: it.productId, lastPrice: it.soldPrice },
        update: { lastPrice: it.soldPrice },
      });
    }
  }
}

/** Undo stock + customer side effects of a completed bill (cancel / delete / edit). */
async function revertEffects(tx: Tx, bill: BillWithItems, user: AuthUser | null, label: string) {
  if (bill.kind === BillKind.SALE) {
    for (const it of bill.items) {
      if (!it.productId) continue;
      const allocs = it.batchAllocations as unknown as BatchAllocation[] | null;
      const product = await tx.product.findUnique({ where: { id: it.productId }, select: { trackStock: true } });
      if (!product?.trackStock) continue;
      await moveStock(
        tx,
        { shopId: bill.shopId, branchId: bill.branchId, userId: user?.id, userName: user?.name, refType: 'bill', refId: bill.id, note: `${label}${bill.billNo}` },
        it.productId,
        it.productName,
        num(it.quantity),
        'sale_reversal',
      );
      await restoreBatches(tx, allocs);
      await tx.billItem.update({ where: { id: it.id }, data: { batchAllocations: Prisma.DbNull } });
    }
  }
  if (bill.customerId && bill.kind === BillKind.SALE) {
    const applied = round2(num(bill.receivedAmount) - num(bill.changeAmount));
    await tx.customer.update({
      where: { id: bill.customerId },
      data: {
        currentBalance: { decrement: round2(num(bill.totalAmount) - applied) },
        loyaltyPoints: { increment: num(bill.loyaltyPointsRedeemed) - num(bill.loyaltyPointsEarned) },
      },
    });
  }
}

async function resolveCustomer(tx: Tx, shopId: string, input: CheckoutInput) {
  if (input.customerId) {
    const c = await tx.customer.findFirst({ where: { id: input.customerId, shopId } });
    if (!c) throw notFound('Customer');
    return c;
  }
  if (input.customerPhone) {
    const existing = await tx.customer.findFirst({ where: { shopId, phone: input.customerPhone } });
    if (existing) return existing;
    return tx.customer.create({
      data: { shopId, phone: input.customerPhone, name: input.customerName?.trim() || 'New Customer' },
    });
  }
  return null;
}

export async function checkout(user: AuthUser, shopId: string, branchId: string, input: CheckoutInput): Promise<BillWithItems> {
  return prisma.$transaction(
    async (tx) => {
      const shop = await tx.shop.findUniqueOrThrow({ where: { id: shopId } });
      const settings = readSettings(shop.settings);
      const branch = await tx.branch.findUniqueOrThrow({ where: { id: branchId } });
      const existing = await tx.bill.findUnique({ where: { id: input.id }, include: billInclude });

      if (existing && existing.shopId !== shopId) throw forbidden();
      if (existing && existing.status === BillStatus.COMPLETED) {
        // A completed bill is an issued tax invoice: it is never changed. Corrections = cancel + new bill.
        if (input.editing) throw conflict('Completed bills cannot be edited. Cancel the bill and create a new one.');
        // Idempotent replay from an offline device.
        return existing;
      }
      if (existing?.isDeleted || existing?.isCancelled) throw conflict('Bill is cancelled or deleted');

      const customer = input.kind === BillKind.SALE ? await resolveCustomer(tx, shopId, input) : null;
      if (input.paymentMethod === PaymentMethod.CREDIT && !customer) {
        throw badRequest('Select a customer for credit sales');
      }

      // Expense vouchers may only contain expense-category items; sales may not.
      if (input.kind === BillKind.EXPENSE || input.items.some((i) => i.productId)) {
        const prodIds = input.items.map((i) => i.productId).filter((x): x is string => !!x);
        const cats = await tx.product.findMany({ where: { id: { in: prodIds } }, select: { category: { select: { isExpenseCategory: true } } } });
        const hasExpense = cats.some((c) => c.category?.isExpenseCategory);
        const hasSale = cats.some((c) => !c.category?.isExpenseCategory);
        if (input.kind === BillKind.SALE && hasExpense) throw badRequest('Cannot mix expense items with customer sales.');
        if (input.kind === BillKind.EXPENSE && hasSale) throw badRequest('Cannot mix sales items with an expense voucher.');
      }

      const lines = await priceItems(tx, shopId, branchId, customer?.id ?? null, input, settings);

      const availablePoints = customer ? num(customer.loyaltyPoints) : 0;
      const redeemReq = settings.enableLoyaltyPoints ? Math.min(input.loyaltyPointsToRedeem, availablePoints) : 0;
      const totals = computeTotals(lines, input.discountType, input.discountValue, redeemReq, input.roundMode);

      // Payment
      let received: number;
      if (input.paymentMethod === PaymentMethod.CREDIT) received = 0;
      else if (input.paymentMethod === PaymentMethod.SPLIT) received = round2(input.cashAmount + input.upiAmount + input.cardAmount);
      else received = input.receivedAmount ?? totals.total;
      if (!customer && input.kind === BillKind.SALE && received < totals.total && input.status === BillStatus.COMPLETED) {
        throw badRequest('Received amount is less than bill total. Select a customer to record the balance as due.');
      }
      const change = customer && !input.giveChange ? 0 : Math.max(0, round2(received - totals.total));

      if (existing) await tx.billItem.deleteMany({ where: { billId: existing.id } });

      const billNo = existing?.billNo ?? (await nextBillNo(tx, shopId, shop.name, branch.code, input.kind, input.billDate ?? new Date()));
      const data = {
        shopId,
        branchId,
        billNo,
        kind: input.kind,
        status: input.status,
        tableName: input.tableName ?? null,
        customerId: customer?.id ?? null,
        customerName: customer?.name ?? input.customerName ?? null,
        customerContact: customer?.phone ?? input.customerPhone ?? null,
        subtotal: totals.subtotal,
        totalGst: totals.totalGst,
        itemDiscount: totals.itemDiscount,
        discount: totals.discount,
        loyaltyPointsRedeemed: totals.loyaltyRedeem,
        roundOff: totals.roundOff,
        totalAmount: totals.total,
        receivedAmount: input.status === BillStatus.COMPLETED ? received : 0,
        changeAmount: input.status === BillStatus.COMPLETED ? change : 0,
        paymentMethod: input.paymentMethod,
        cashAmount: input.paymentMethod === PaymentMethod.CASH ? received : input.cashAmount,
        upiAmount: input.paymentMethod === PaymentMethod.UPI ? received : input.upiAmount,
        cardAmount: input.paymentMethod === PaymentMethod.CARD ? received : input.cardAmount,
        note: input.note ?? null,
        userId: existing?.userId ?? user.id,
        userName: existing?.userName ?? user.name,
        billDate: input.billDate ?? existing?.billDate ?? new Date(),
        items: {
          create: lines.map(({ trackStock: _t, ...l }) => l),
        },
      };

      const bill = existing
        ? await tx.bill.update({ where: { id: existing.id }, data, include: billInclude })
        : await tx.bill.create({ data: { id: input.id, ...data }, include: billInclude });

      if (bill.status === BillStatus.COMPLETED) {
        await applyEffects(tx, bill, user, settings, 'Bill: ');
      }
      return tx.bill.findUniqueOrThrow({ where: { id: bill.id }, include: billInclude });
    },
    { timeout: 20000 },
  );
}

async function loadBill(tx: Tx, shopId: string, id: string) {
  const b = await tx.bill.findFirst({ where: { id, shopId }, include: billInclude });
  if (!b) throw notFound('Bill');
  return b;
}

/** Cancel a completed bill (admin / manager): keeps its number, reverts stock and balances. */
export async function cancelBill(user: AuthUser, shopId: string, id: string, reason: string) {
  return prisma.$transaction(async (tx) => {
    const b = await loadBill(tx, shopId, id);
    if (b.isCancelled) return b;
    if (b.status !== BillStatus.COMPLETED) throw conflict('Waiting orders are not billed yet – delete the order instead.');
    if (b.isDeleted) throw conflict('Bill is deleted');
    if (!reason.trim()) throw badRequest('Enter a reason for cancelling the bill');
    await revertEffects(tx, b, user, 'Reversed from Cancelled Bill: ');
    const out = await tx.bill.update({
      where: { id },
      data: { isCancelled: true, cancelledAt: new Date(), cancelledByUserId: user.id, cancelledByUserName: user.name, cancelReason: reason.trim() },
      include: billInclude,
    });
    await logActivity(user, 'bill_cancelled', `Cancelled bill ${b.billNo}: ${reason.trim()}`, { billId: id, total: num(b.totalAmount), reason: reason.trim() }, tx, shopId);
    return out;
  });
}

export async function softDeleteBill(user: AuthUser, shopId: string, id: string) {
  return prisma.$transaction(async (tx) => {
    const b = await loadBill(tx, shopId, id);
    if (b.isDeleted) return b;
    if (b.status === BillStatus.COMPLETED) throw conflict('Completed bills cannot be deleted. Cancel the bill instead.');
    const out = await tx.bill.update({
      where: { id },
      data: { isDeleted: true, deletedAt: new Date(), deletedByUserId: user.id, deletedByUserName: user.name },
      include: billInclude,
    });
    await logActivity(user, 'bill_deleted', `Deleted bill ${b.billNo} for ₹${num(b.totalAmount)}`, { billId: id, total: num(b.totalAmount) }, tx, shopId);
    return out;
  });
}

export async function restoreBill(user: AuthUser, shopId: string, id: string) {
  return prisma.$transaction(async (tx) => {
    const b = await loadBill(tx, shopId, id);
    if (!b.isDeleted && !b.isCancelled) return b;
    if (b.isCancelled && user.role !== Role.ADMIN && user.role !== Role.SUPER_ADMIN) throw forbidden('Only the shop admin can restore a cancelled bill');
    const out = await tx.bill.update({
      where: { id },
      data: {
        isDeleted: false, deletedAt: null, deletedByUserId: null, deletedByUserName: null,
        isCancelled: false, cancelledAt: null, cancelledByUserId: null, cancelledByUserName: null, cancelReason: null,
      },
      include: billInclude,
    });
    if (out.status === BillStatus.COMPLETED) {
      const shop = await tx.shop.findUniqueOrThrow({ where: { id: shopId } });
      await applyEffects(tx, out, user, readSettings(shop.settings), 'Re-deducted from Restored Bill: ');
    }
    await logActivity(user, 'bill_restored', `Restored bill ${b.billNo}`, { billId: id }, tx, shopId);
    return tx.bill.findUniqueOrThrow({ where: { id }, include: billInclude });
  });
}

export async function permanentlyDeleteBill(user: AuthUser, shopId: string, id: string) {
  return prisma.$transaction(async (tx) => {
    const b = await loadBill(tx, shopId, id);
    if (b.status === BillStatus.COMPLETED) throw conflict('Completed bills are kept for the record and cannot be deleted.');
    await tx.bill.delete({ where: { id } });
    await logActivity(user, 'bill_deleted', `Permanently deleted bill ${b.billNo}`, { billId: id, permanent: true }, tx, shopId);
  });
}

/** Marks items as sent to kitchen (KOT) – returns only the not-yet-printed quantities. */
export async function markKotPrinted(shopId: string, id: string) {
  return prisma.$transaction(async (tx) => {
    const b = await loadBill(tx, shopId, id);
    const pending = b.items
      .map((i) => ({ productName: i.productName, note: i.note, quantity: round3(num(i.quantity) - num(i.kotPrintedQuantity)) }))
      .filter((i) => i.quantity > 0);
    for (const i of b.items) {
      await tx.billItem.update({ where: { id: i.id }, data: { kotPrintedQuantity: i.quantity } });
    }
    return { billNo: b.billNo, tableName: b.tableName, items: pending };
  });
}
