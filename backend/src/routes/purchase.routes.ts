import { Router } from 'express';
import { z } from 'zod';
import { PaymentMethod, Prisma, PurchaseStatus } from '@prisma/client';
import { prisma, Tx } from '../lib/prisma';
import { parse, optStr } from '../lib/validate';
import { requireFeature } from '../lib/features';
import { branchIdOf, requirePermission, shopIdOf } from '../middleware/auth';
import { badRequest, notFound } from '../lib/errors';
import { round2 } from '../lib/money';
import { inwardBatch } from '../services/stock.service';
import { nextSequence, yymmdd } from '../lib/sequence';
import { logActivity } from '../lib/activity';
import { AuthUser } from '../middleware/auth';

export const purchaseRouter = Router();
purchaseRouter.use(requirePermission('purchases.manage'), requireFeature('purchases'));

purchaseRouter.get('/', async (req, res) => {
  const shopId = shopIdOf(req);
  const from = req.query.from ? new Date(req.query.from as string) : undefined;
  const to = req.query.to ? new Date(req.query.to as string) : undefined;
  const status = req.query.status as PurchaseStatus | undefined;
  res.json(
    await prisma.purchase.findMany({
      where: { shopId, status, supplierId: (req.query.supplierId as string) || undefined, ...((from || to) && { invoiceDate: { gte: from, lte: to } }) },
      include: { items: true },
      orderBy: { invoiceDate: 'desc' },
      take: 500,
    }),
  );
});

purchaseRouter.get('/:id', async (req, res) => {
  const p = await prisma.purchase.findFirst({ where: { id: req.params.id, shopId: shopIdOf(req) }, include: { items: true, supplier: true } });
  if (!p) throw notFound('Purchase');
  res.json(p);
});

const PurchaseBody = z.object({
  supplierId: z.string().uuid().nullish(),
  /** Creates a supplier on the fly when no supplierId (e.g. from an OCR scan). */
  newSupplier: z.object({ name: z.string().trim().min(1), phone: optStr, gstin: optStr, address: optStr }).nullish(),
  invoiceNumber: z.string().trim().optional(),
  invoiceDate: z.coerce.date().default(() => new Date()),
  status: z.nativeEnum(PurchaseStatus).default(PurchaseStatus.RECEIVED),
  items: z
    .array(
      z.object({
        productId: z.string().uuid(),
        quantity: z.coerce.number().positive(),
        unitPrice: z.coerce.number().min(0),
        gstPercent: z.coerce.number().min(0).default(0),
        batchNumber: optStr,
        expiryDate: z.coerce.date().nullish(),
      }),
    )
    .min(1, 'No items added to bill yet.'),
  discountAmount: z.coerce.number().min(0).default(0),
  amountPaid: z.coerce.number().min(0).default(0),
  paymentMode: z.nativeEnum(PaymentMethod).default(PaymentMethod.CASH),
  location: optStr,
  notes: optStr,
});

async function receive(tx: Tx, user: AuthUser, purchaseId: string, branchId: string, location?: string | null) {
  const p = await tx.purchase.findUniqueOrThrow({ where: { id: purchaseId }, include: { items: true } });
  for (const it of p.items) {
    await inwardBatch(
      tx,
      { shopId: p.shopId, branchId, userId: user.id, userName: user.name, refType: 'purchase', refId: p.id, note: `Purchase: ${p.invoiceNumber}${it.batchNumber ? ` | Batch: ${it.batchNumber}` : ''}` },
      {
        productId: it.productId,
        productName: it.productName,
        quantity: Number(it.quantity),
        batchNumber: it.batchNumber,
        expiryDate: it.expiryDate,
        purchasePrice: Number(it.unitPrice),
        location: location ?? p.location,
        purchaseId: p.id,
        type: 'purchase_inward',
      },
    );
    await tx.product.update({ where: { id: it.productId }, data: { purchasePrice: it.unitPrice } });
  }
  await tx.purchase.update({ where: { id: p.id }, data: { status: PurchaseStatus.RECEIVED, receivedAt: new Date(), ...(location && { location }) } });
}

purchaseRouter.post('/', async (req, res) => {
  const shopId = shopIdOf(req);
  const branchId = await branchIdOf(req);
  const body = parse(PurchaseBody, req.body);
  const user = req.user!;
  const purchase = await prisma.$transaction(
    async (tx) => {
      let supplierId = body.supplierId ?? null;
      let supplierName: string | null = null;
      if (supplierId) {
        const s = await tx.supplier.findFirst({ where: { id: supplierId, shopId } });
        if (!s) throw notFound('Supplier');
        supplierName = s.name;
      } else if (body.newSupplier) {
        const s = await tx.supplier.create({ data: { shopId, ...body.newSupplier } });
        supplierId = s.id;
        supplierName = s.name;
      }
      const products = await tx.product.findMany({ where: { shopId, id: { in: body.items.map((i) => i.productId) } } });
      const byId = new Map(products.map((p) => [p.id, p]));
      const items = body.items.map((i) => {
        const p = byId.get(i.productId);
        if (!p) throw badRequest(`Product ${i.productId} not found`);
        const base = round2(i.quantity * i.unitPrice);
        return { ...i, productName: p.name, hsnCode: p.hsnCode, total: round2(base * (1 + i.gstPercent / 100)), base };
      });
      const gross = round2(items.reduce((s, i) => s + i.base, 0));
      const gst = round2(items.reduce((s, i) => s + i.total - i.base, 0));
      const total = round2(gross + gst - body.discountAmount);
      const invoiceNumber =
        body.invoiceNumber ||
        (body.status === PurchaseStatus.PENDING ? 'PO' : 'INV') + `-${yymmdd()}-${String(await nextSequence(tx, shopId, `po:${yymmdd()}`)).padStart(3, '0')}`;

      const p = await tx.purchase.create({
        data: {
          shopId, branchId, supplierId, supplierName, invoiceNumber, invoiceDate: body.invoiceDate, status: PurchaseStatus.PENDING,
          grossAmount: gross, gstAmount: gst, discountAmount: body.discountAmount, totalAmount: total,
          amountPaid: body.amountPaid, balanceDue: round2(total - body.amountPaid), paymentMode: body.paymentMode,
          location: body.location, notes: body.notes, userId: user.id, userName: user.name,
          items: { create: items.map(({ base: _b, ...i }) => i) },
        },
      });
      if (supplierId) {
        await tx.supplier.update({ where: { id: supplierId }, data: { currentBalance: { increment: round2(total - body.amountPaid) } } });
      }
      if (body.status === PurchaseStatus.RECEIVED) await receive(tx, user, p.id, branchId, body.location);
      return tx.purchase.findUniqueOrThrow({ where: { id: p.id }, include: { items: true } });
    },
    { timeout: 20000 },
  );
  await logActivity(user, 'purchase_created', `${purchase.status === 'PENDING' ? 'Purchase Order' : 'Purchase'} ${purchase.invoiceNumber} – ₹${purchase.totalAmount}`);
  res.status(201).json(purchase);
});

/** Inward a pending purchase order into stock. */
purchaseRouter.post('/:id/inward', async (req, res) => {
  const shopId = shopIdOf(req);
  const branchId = await branchIdOf(req);
  const { location } = parse(z.object({ location: optStr }), req.body ?? {});
  const p = await prisma.purchase.findFirst({ where: { id: req.params.id, shopId } });
  if (!p) throw notFound('Purchase');
  if (p.status === PurchaseStatus.RECEIVED) throw badRequest('Purchase already inwarded');
  await prisma.$transaction((tx) => receive(tx, req.user!, p.id, branchId, location), { timeout: 20000 });
  res.json(await prisma.purchase.findUniqueOrThrow({ where: { id: p.id }, include: { items: true } }));
});

purchaseRouter.delete('/:id', async (req, res) => {
  const p = await prisma.purchase.findFirst({ where: { id: req.params.id, shopId: shopIdOf(req) } });
  if (!p) throw notFound('Purchase');
  if (p.status === PurchaseStatus.RECEIVED) throw badRequest('Received purchases cannot be deleted; adjust stock instead');
  await prisma.$transaction([
    ...(p.supplierId ? [prisma.supplier.update({ where: { id: p.supplierId }, data: { currentBalance: { decrement: p.balanceDue } } })] : []),
    prisma.purchase.delete({ where: { id: p.id } }),
  ] as Prisma.PrismaPromise<unknown>[]);
  res.json({ ok: true });
});
