import { Router } from 'express';
import { z } from 'zod';
import { PaymentMethod, Prisma } from '@prisma/client';
import { prisma } from '../lib/prisma';
import { parse, optStr } from '../lib/validate';
import { requireFeature } from '../lib/features';
import { requirePermission, shopIdOf } from '../middleware/auth';
import { notFound } from '../lib/errors';
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

supplierRouter.delete('/:id', async (req, res) => {
  const s = await own(req);
  await prisma.supplier.delete({ where: { id: s.id } });
  res.json({ ok: true });
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
