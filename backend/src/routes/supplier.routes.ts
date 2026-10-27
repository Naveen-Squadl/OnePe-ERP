import { RequestHandler, Router } from 'express';
import { z } from 'zod';
import { PaymentMethod, Prisma } from '@prisma/client';
import { prisma } from '../lib/prisma';
import { dateRange, parse, optStr } from '../lib/validate';
import { requireFeature } from '../lib/features';
import { requirePermission, shopIdOf } from '../middleware/auth';
import { conflict, notFound } from '../lib/errors';
import { num } from '../lib/money';
import { logActivity } from '../lib/activity';

export const supplierRouter = Router();
supplierRouter.use(requirePermission('suppliers.manage', 'purchases.manage'), requireFeature('purchases'));

async function own(req: any) {
  const s = await prisma.supplier.findFirst({ where: { id: req.params.id, shopId: shopIdOf(req) } });
  if (!s) throw notFound('Supplier');
  return s;
}

supplierRouter.get('/', async (req, res) => {
  const q = (req.query.q as string | undefined)?.trim();
  const where: Prisma.SupplierWhereInput = {
    shopId: shopIdOf(req),
    isArchived: req.query.filter === 'archived',
    ...(q && { OR: [{ name: { contains: q, mode: 'insensitive' } }, { phone: { contains: q } }] }),
  };
  res.json(await prisma.supplier.findMany({ where, orderBy: { name: 'asc' } }));
});

const Body = z.object({ name: z.string().trim().min(1, 'Supplier Name is required'), phone: optStr, address: optStr, gstin: optStr, openingBalance: z.coerce.number().default(0) });

supplierRouter.post('/', async (req, res) => {
  const body = parse(Body, req.body);
  res.status(201).json(await prisma.supplier.create({ data: { ...body, shopId: shopIdOf(req), currentBalance: body.openingBalance } }));
});

supplierRouter.put('/:id', async (req, res) => {
  const s = await own(req);
  const { openingBalance, ...body } = parse(Body.partial(), req.body);
  const data: Prisma.SupplierUpdateInput = { ...body };
  if (openingBalance !== undefined) {
    data.openingBalance = openingBalance;
    data.currentBalance = { increment: openingBalance - Number(s.openingBalance) };
  }
  res.json(await prisma.supplier.update({ where: { id: s.id }, data }));
});

/**
 * Archive instead of delete: hidden from lists and the purchase form, purchases / payments kept, reports unchanged.
 * Only with a settled balance – pay what you owe, or use up the advance, first.
 */
const archive: RequestHandler = async (req, res) => {
  const s = await own(req);
  const balance = num(s.currentBalance);
  if (balance > 0.009) throw conflict(`You owe ${s.name} ₹${balance} – pay or settle it before archiving`);
  if (balance < -0.009) throw conflict(`${s.name} has ₹${-balance} advance from you – settle it before archiving`);
  const out = await prisma.supplier.update({ where: { id: s.id }, data: { isArchived: true, archivedAt: new Date() } });
  await logActivity(req.user!, 'supplier_archived', `Archived supplier ${s.name}`);
  res.json(out);
};

supplierRouter.post('/:id/archive', archive);
/** Older app versions call DELETE – suppliers are never deleted, only archived. */
supplierRouter.delete('/:id', archive);

supplierRouter.post('/:id/restore', async (req, res) => {
  const s = await own(req);
  const out = await prisma.supplier.update({ where: { id: s.id }, data: { isArchived: false, archivedAt: null } });
  await logActivity(req.user!, 'supplier_restored', `Restored archived supplier ${s.name}`);
  res.json(out);
});

/** Supplier payments in a period (Purchases → History). */
supplierRouter.get('/payments', async (req, res) => {
  const createdAt = dateRange(req.query);
  res.json(
    await prisma.supplierPayment.findMany({
      where: { shopId: shopIdOf(req), ...(createdAt && { createdAt }) },
      include: { supplier: { select: { name: true } } },
      orderBy: { createdAt: 'desc' },
      take: 1000,
    }),
  );
});

supplierRouter.get('/:id/purchases', async (req, res) => {
  const s = await own(req);
  res.json(await prisma.purchase.findMany({ where: { supplierId: s.id }, include: { items: true }, orderBy: { invoiceDate: 'desc' } }));
});

supplierRouter.post('/:id/payments', async (req, res) => {
  const s = await own(req);
  const body = parse(z.object({ amount: z.coerce.number().positive(), method: z.nativeEnum(PaymentMethod).default(PaymentMethod.CASH), note: optStr }), req.body);
  const [payment, supplier] = await prisma.$transaction([
    prisma.supplierPayment.create({ data: { shopId: s.shopId, supplierId: s.id, amount: body.amount, method: body.method, note: body.note, userId: req.user!.id } }),
    prisma.supplier.update({ where: { id: s.id }, data: { currentBalance: { decrement: body.amount } } }),
  ]);
  await logActivity(req.user!, 'supplier_payment', `Paid ₹${body.amount} to ${s.name} via ${body.method}`);
  res.status(201).json({ payment, supplier });
});
