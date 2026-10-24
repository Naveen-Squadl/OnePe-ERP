import { BillKind, BillStatus, Prisma } from '@prisma/client';
import { prisma } from '../lib/prisma';
import { num, round2, round3 } from '../lib/money';

export interface ReportFilter {
  shopId: string;
  from: Date;
  to: Date;
  branchId?: string; // undefined = all branches
  userId?: string;
  customerId?: string;
}

const billWhere = (f: ReportFilter, kind?: BillKind): Prisma.BillWhereInput => ({
  shopId: f.shopId,
  branchId: f.branchId,
  userId: f.userId,
  customerId: f.customerId,
  kind,
  status: BillStatus.COMPLETED,
  isCancelled: false,
  isDeleted: false,
  billDate: { gte: f.from, lte: f.to },
});

async function bills(f: ReportFilter, kind?: BillKind) {
  return prisma.bill.findMany({ where: billWhere(f, kind), include: { items: true }, orderBy: { billDate: 'asc' } });
}

type Bucket = 'hour' | 'day' | 'week' | 'month';

function bucketKey(d: Date, b: Bucket): string {
  const p = (n: number) => String(n).padStart(2, '0');
  switch (b) {
    case 'hour':
      return `${p(d.getHours())}:00`;
    case 'day':
      return `${d.getFullYear()}-${p(d.getMonth() + 1)}-${p(d.getDate())}`;
    case 'week': {
      const s = new Date(d);
      s.setDate(d.getDate() - ((d.getDay() + 6) % 7));
      return `W ${s.getFullYear()}-${p(s.getMonth() + 1)}-${p(s.getDate())}`;
    }
    case 'month':
      return `${d.getFullYear()}-${p(d.getMonth() + 1)}`;
  }
}

/** Business / dashboard summary (Gross, Discounts, Net, Expenses, Net Collection, trend). */
export async function businessSummary(f: ReportFilter, bucket: Bucket | 'auto' = 'auto') {
  const [sales, expenses, payments] = await Promise.all([
    bills(f, BillKind.SALE),
    bills(f, BillKind.EXPENSE),
    prisma.customerPayment.findMany({ where: { shopId: f.shopId, branchId: f.branchId, createdAt: { gte: f.from, lte: f.to } } }),
  ]);
  const days = (f.to.getTime() - f.from.getTime()) / 86_400_000;
  const b: Bucket = bucket !== 'auto' ? bucket : days <= 1.01 ? 'hour' : days <= 62 ? 'day' : days <= 200 ? 'week' : 'month';

  const gross = round2(sales.reduce((s, x) => s + num(x.subtotal) + num(x.totalGst) + num(x.itemDiscount), 0));
  const discounts = round2(sales.reduce((s, x) => s + num(x.itemDiscount) + num(x.discount) + num(x.loyaltyPointsRedeemed), 0));
  const net = round2(sales.reduce((s, x) => s + num(x.totalAmount), 0));
  const exp = round2(expenses.reduce((s, x) => s + num(x.totalAmount), 0));
  const collected = round2(sales.reduce((s, x) => s + num(x.receivedAmount) - num(x.changeAmount), 0) + payments.reduce((s, p) => s + num(p.amount), 0));

  const byMethod: Record<string, number> = {};
  for (const x of sales) {
    if (x.paymentMethod === 'SPLIT') {
      byMethod.CASH = round2((byMethod.CASH ?? 0) + num(x.cashAmount));
      byMethod.UPI = round2((byMethod.UPI ?? 0) + num(x.upiAmount));
      byMethod.CARD = round2((byMethod.CARD ?? 0) + num(x.cardAmount));
    } else {
      byMethod[x.paymentMethod] = round2((byMethod[x.paymentMethod] ?? 0) + num(x.totalAmount));
    }
  }

  const trend = new Map<string, { label: string; revenue: number; bills: number }>();
  for (const x of sales) {
    const k = bucketKey(x.billDate, b);
    const t = trend.get(k) ?? { label: k, revenue: 0, bills: 0 };
    t.revenue = round2(t.revenue + num(x.totalAmount));
    t.bills++;
    trend.set(k, t);
  }
  const series = [...trend.values()].sort((a, c) => a.label.localeCompare(c.label));
  const peak = series.reduce<(typeof series)[number] | null>((m, t) => (!m || t.revenue > m.revenue ? t : m), null);

  const items = new Map<string, { name: string; qty: number; amount: number }>();
  for (const x of sales)
    for (const i of x.items) {
      const k = i.productId ?? i.productName;
      const r = items.get(k) ?? { name: i.productName, qty: 0, amount: 0 };
      r.qty = round3(r.qty + num(i.quantity));
      r.amount = round2(r.amount + num(i.lineTotal));
      items.set(k, r);
    }

  return {
    range: { from: f.from, to: f.to, bucket: b },
    grossSales: gross,
    discounts,
    netSales: net,
    expenses: exp,
    netCollection: round2(collected - exp),
    netAfterExpenses: round2(net - exp),
    transactions: sales.length,
    expenseVouchers: expenses.length,
    paymentsReceived: round2(payments.reduce((s, p) => s + num(p.amount), 0)),
    byPaymentMethod: byMethod,
    trend: series,
    peak,
    topItems: [...items.values()].sort((a, c) => c.amount - a.amount).slice(0, 10),
  };
}

/** Product × qty/amount matrix, grouped by category. */
export async function salesMatrix(f: ReportFilter) {
  const rows = await bills(f, BillKind.SALE);
  const cats = new Map((await prisma.category.findMany({ where: { shopId: f.shopId } })).map((c) => [c.id, c.name]));
  const m = new Map<string, { productId: string | null; name: string; category: string; qty: number; amount: number; gst: number }>();
  for (const b of rows)
    for (const i of b.items) {
      const k = i.productId ?? i.productName;
      const r = m.get(k) ?? { productId: i.productId, name: i.productName, category: (i.categoryId && cats.get(i.categoryId)) || 'Uncategorized', qty: 0, amount: 0, gst: 0 };
      r.qty = round3(r.qty + num(i.quantity));
      r.amount = round2(r.amount + num(i.lineTotal));
      r.gst = round2(r.gst + num(i.gstAmount));
      m.set(k, r);
    }
  const items = [...m.values()].sort((a, b) => a.category.localeCompare(b.category) || b.amount - a.amount);

  // Customer × product grid (rows = customers, columns = products), as shown in the Sales Matrix tab.
  const products = items.map((i) => i.name);
  const grid = new Map<string, { customer: string; cells: Record<string, { qty: number; amount: number }>; qty: number; amount: number }>();
  for (const b of rows) {
    const key = b.customerId ?? 'walk-in';
    const r = grid.get(key) ?? { customer: b.customerName ?? 'Walk-in', cells: {}, qty: 0, amount: 0 };
    for (const i of b.items) {
      const c = (r.cells[i.productName] ??= { qty: 0, amount: 0 });
      c.qty = round3(c.qty + num(i.quantity));
      c.amount = round2(c.amount + num(i.lineTotal));
      r.qty = round3(r.qty + num(i.quantity));
      r.amount = round2(r.amount + num(i.lineTotal));
    }
    grid.set(key, r);
  }
  const customers = [...grid.values()].sort((a, b) => b.amount - a.amount);
  return {
    items,
    products,
    customers,
    activeCustomers: customers.length,
    totalQty: round3(items.reduce((s, i) => s + i.qty, 0)),
    totalAmount: round2(items.reduce((s, i) => s + i.amount, 0)),
  };
}

/** Customer outstanding summary as of now. filter: all | due | settled */
export async function customerOutstanding(shopId: string, filter: 'all' | 'due' | 'settled' = 'all') {
  const customers = await prisma.customer.findMany({ where: { shopId }, orderBy: { name: 'asc' } });
  const ids = customers.map((c) => c.id);
  const [billAgg, payAgg] = await Promise.all([
    prisma.bill.groupBy({
      by: ['customerId'],
      where: { shopId, customerId: { in: ids }, kind: BillKind.SALE, status: BillStatus.COMPLETED, isCancelled: false, isDeleted: false },
      _sum: { totalAmount: true, receivedAmount: true, changeAmount: true },
    }),
    prisma.customerPayment.groupBy({ by: ['customerId'], where: { shopId, customerId: { in: ids } }, _sum: { amount: true } }),
  ]);
  const billed = new Map(billAgg.map((b) => [b.customerId, b._sum]));
  const paid = new Map(payAgg.map((p) => [p.customerId, num(p._sum.amount)]));
  const rows = customers
    .map((c) => {
      const b = billed.get(c.id);
      const totalBilled = num(b?.totalAmount);
      const totalReceived = round2(num(b?.receivedAmount) - num(b?.changeAmount) + (paid.get(c.id) ?? 0));
      const outstanding = num(c.currentBalance);
      return {
        id: c.id, name: c.name, phone: c.phone, createdAt: c.createdAt,
        openingBalance: num(c.openingBalance), totalBilled, totalReceived, outstandingBalance: outstanding,
        status: outstanding > 0.009 ? 'DUE' : outstanding < -0.009 ? 'ADVANCE' : 'SETTLED',
      };
    })
    .filter((r) => (filter === 'due' ? r.status === 'DUE' : filter === 'settled' ? r.status !== 'DUE' : true));
  return {
    customers: rows,
    totalDue: round2(rows.filter((r) => r.outstandingBalance > 0).reduce((s, r) => s + r.outstandingBalance, 0)),
    totalAdvance: round2(rows.filter((r) => r.outstandingBalance < 0).reduce((s, r) => s - r.outstandingBalance, 0)),
  };
}

/** Customer-wise sales in a range. */
export async function customerSales(f: ReportFilter) {
  const rows = await bills(f, BillKind.SALE);
  const m = new Map<string, { customerId: string | null; name: string; phone: string | null; bills: number; amount: number; received: number }>();
  for (const b of rows) {
    const k = b.customerId ?? 'walk-in';
    const r = m.get(k) ?? { customerId: b.customerId, name: b.customerName ?? 'Walk-in', phone: b.customerContact, bills: 0, amount: 0, received: 0 };
    r.bills++;
    r.amount = round2(r.amount + num(b.totalAmount));
    r.received = round2(r.received + num(b.receivedAmount) - num(b.changeAmount));
    m.set(k, r);
  }
  return [...m.values()].sort((a, b) => b.amount - a.amount);
}

/** Staff sales summary + item-wise breakdown per user. */
export async function userSales(f: ReportFilter) {
  const rows = await bills(f, BillKind.SALE);
  const m = new Map<string, { userId: string | null; userName: string; billCount: number; total: number; items: Map<string, { name: string; qty: number; amount: number }> }>();
  for (const b of rows) {
    const k = b.userId ?? 'unknown';
    const r = m.get(k) ?? { userId: b.userId, userName: b.userName ?? 'Unknown User', billCount: 0, total: 0, items: new Map() };
    r.billCount++;
    r.total = round2(r.total + num(b.totalAmount));
    for (const i of b.items) {
      const it = r.items.get(i.productName) ?? { name: i.productName, qty: 0, amount: 0 };
      it.qty = round3(it.qty + num(i.quantity));
      it.amount = round2(it.amount + num(i.lineTotal));
      r.items.set(i.productName, it);
    }
    m.set(k, r);
  }
  const users = [...m.values()].map((u) => ({ ...u, items: [...u.items.values()].sort((a, b) => b.amount - a.amount) }));
  return { users, grandTotal: round2(users.reduce((s, u) => s + u.total, 0)) };
}

/** Inventory valuation by product & storage location. */
export async function inventoryValuation(shopId: string, branchId?: string, location?: string) {
  const products = await prisma.product.findMany({
    where: { shopId, isActive: true, trackStock: true, ...(location && { storageLocation: location }) },
    include: { branches: branchId ? { where: { branchId } } : true, category: { select: { name: true } } },
    orderBy: { name: 'asc' },
  });
  const rows = products.map((p) => {
    const stock = round3(p.branches.reduce((s, b) => s + num(b.stock), 0));
    const unit = num(p.purchasePrice ?? p.basePrice);
    return {
      id: p.id, name: p.name, category: p.category?.name ?? 'General', location: p.storageLocation ?? 'Unassigned',
      stock, unitPrice: unit, basePrice: num(p.basePrice), value: round2(stock * unit), isLowStock: stock <= num(p.lowStockThreshold),
    };
  });
  const byLocation = new Map<string, { location: string; products: number; qty: number; value: number }>();
  for (const r of rows) {
    const l = byLocation.get(r.location) ?? { location: r.location, products: 0, qty: 0, value: 0 };
    l.products++;
    l.qty = round3(l.qty + r.stock);
    l.value = round2(l.value + r.value);
    byLocation.set(r.location, l);
  }
  return { items: rows, locations: [...byLocation.values()], totalValue: round2(rows.reduce((s, r) => s + r.value, 0)) };
}

/** GSTR-1 style HSN summary (Table 12) + rate-slab summary. */
export async function gstSummary(f: ReportFilter) {
  const rows = await bills(f, BillKind.SALE);
  const hsn = new Map<string, { hsnCode: string; rate: number; qty: number; taxable: number; cgst: number; sgst: number; igst: number; totalTax: number; gross: number }>();
  const slabs = new Map<number, { rate: number; taxable: number; cgst: number; sgst: number; igst: number; gross: number }>();
  const invoices = rows.map((b) => ({
    billNo: b.billNo, date: b.billDate, customer: b.customerName ?? 'Retail Customer',
    taxable: num(b.subtotal), gst: num(b.totalGst), total: num(b.totalAmount),
  }));
  for (const b of rows)
    for (const i of b.items) {
      const rate = num(i.gstPercent);
      const taxable = num(i.taxableAmount);
      const tax = num(i.gstAmount);
      const igst = i.isIgst ? tax : 0;
      const cgst = i.isIgst ? 0 : round2(tax / 2);
      const sgst = i.isIgst ? 0 : round2(tax - cgst);
      const key = `${i.hsnCode ?? 'N/A'}@${rate}`;
      const h = hsn.get(key) ?? { hsnCode: i.hsnCode ?? 'N/A', rate, qty: 0, taxable: 0, cgst: 0, sgst: 0, igst: 0, totalTax: 0, gross: 0 };
      h.qty = round3(h.qty + num(i.quantity));
      h.taxable = round2(h.taxable + taxable);
      h.cgst = round2(h.cgst + cgst);
      h.sgst = round2(h.sgst + sgst);
      h.igst = round2(h.igst + igst);
      h.totalTax = round2(h.totalTax + tax);
      h.gross = round2(h.gross + taxable + tax);
      hsn.set(key, h);
      const s = slabs.get(rate) ?? { rate, taxable: 0, cgst: 0, sgst: 0, igst: 0, gross: 0 };
      s.taxable = round2(s.taxable + taxable);
      s.cgst = round2(s.cgst + cgst);
      s.sgst = round2(s.sgst + sgst);
      s.igst = round2(s.igst + igst);
      s.gross = round2(s.gross + taxable + tax);
      slabs.set(rate, s);
    }
  const hsnRows = [...hsn.values()].sort((a, b) => a.hsnCode.localeCompare(b.hsnCode));
  const sum = (k: 'taxable' | 'cgst' | 'sgst' | 'igst') => round2(hsnRows.reduce((s, r) => s + r[k], 0));
  return {
    hsn: hsnRows,
    slabs: [...slabs.values()].sort((a, b) => a.rate - b.rate),
    invoices,
    totals: { taxable: sum('taxable'), cgst: sum('cgst'), sgst: sum('sgst'), igst: sum('igst'), totalTax: round2(sum('cgst') + sum('sgst') + sum('igst')) },
  };
}

export async function purchaseReport(f: ReportFilter) {
  const purchases = await prisma.purchase.findMany({
    where: { shopId: f.shopId, branchId: f.branchId, invoiceDate: { gte: f.from, lte: f.to } },
    include: { items: true },
    orderBy: { invoiceDate: 'asc' },
  });
  const suppliers = new Map<string, { name: string; bills: number; total: number; paid: number; balance: number }>();
  const products = new Map<string, { name: string; qty: number; amount: number }>();
  for (const p of purchases) {
    const k = p.supplierName ?? 'Unknown Supplier';
    const s = suppliers.get(k) ?? { name: k, bills: 0, total: 0, paid: 0, balance: 0 };
    s.bills++;
    s.total = round2(s.total + num(p.totalAmount));
    s.paid = round2(s.paid + num(p.amountPaid));
    s.balance = round2(s.balance + num(p.balanceDue));
    suppliers.set(k, s);
    for (const i of p.items) {
      const r = products.get(i.productId) ?? { name: i.productName, qty: 0, amount: 0 };
      r.qty = round3(r.qty + num(i.quantity));
      r.amount = round2(r.amount + num(i.total));
      products.set(i.productId, r);
    }
  }
  return {
    purchases,
    suppliers: [...suppliers.values()],
    products: [...products.values()].sort((a, b) => b.amount - a.amount),
    totals: {
      bills: purchases.length,
      amount: round2(purchases.reduce((s, p) => s + num(p.totalAmount), 0)),
      paid: round2(purchases.reduce((s, p) => s + num(p.amountPaid), 0)),
      due: round2(purchases.reduce((s, p) => s + num(p.balanceDue), 0)),
    },
  };
}

export async function branchSales(f: ReportFilter) {
  const rows = await prisma.bill.groupBy({
    by: ['branchId'],
    where: billWhere({ ...f, branchId: undefined }, BillKind.SALE),
    _sum: { totalAmount: true },
    _count: true,
  });
  const branches = new Map((await prisma.branch.findMany({ where: { shopId: f.shopId } })).map((b) => [b.id, b.name]));
  return rows.map((r) => ({ branchId: r.branchId, branchName: branches.get(r.branchId) ?? r.branchId, bills: r._count, total: num(r._sum.totalAmount) }));
}
