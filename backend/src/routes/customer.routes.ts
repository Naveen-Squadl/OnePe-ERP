import { Router } from 'express';
import { z } from 'zod';
import { PaymentMethod, Prisma } from '@prisma/client';
import { prisma } from '../lib/prisma';
import { parse, optStr } from '../lib/validate';
import { branchIdOf, requirePermission, shopIdOf } from '../middleware/auth';
import { notFound } from '../lib/errors';
import { nextSequence, yymmdd } from '../lib/sequence';
import { customerLedger, recalculateCustomerBalance } from '../services/ledger.service';
import { logActivity } from '../lib/activity';

export const customerRouter = Router();

async function own(req: any) {
  const c = await prisma.customer.findFirst({ where: { id: req.params.id, shopId: shopIdOf(req) } });
  if (!c) throw notFound('Customer');
  return c;
}

customerRouter.get('/', async (req, res) => {
  const q = (req.query.q as string | undefined)?.trim();
  const filter = req.query.filter as string | undefined; // due | settled
  const where: Prisma.CustomerWhereInput = {
    shopId: shopIdOf(req),
    ...(q && { OR: [{ name: { contains: q, mode: 'insensitive' } }, { phone: { contains: q } }, { gstin: { contains: q, mode: 'insensitive' } }] }),
    ...(filter === 'due' && { currentBalance: { gt: 0 } }),
    ...(filter === 'settled' && { currentBalance: { lte: 0 } }),
  };
  res.json(await prisma.customer.findMany({ where, orderBy: { name: 'asc' } }));
});

customerRouter.get('/phone/:phone', async (req, res) => {
  const c = await prisma.customer.findFirst({ where: { shopId: shopIdOf(req), phone: req.params.phone } });
  if (!c) throw notFound('Customer');
  res.json(c);
});

customerRouter.get('/:id', async (req, res) => {
  res.json(await own(req));
});

const Body = z.object({
  name: z.string().trim().min(1),
  phone: z.string().trim().regex(/^\d{10}$/, 'Must be 10 digits').nullish(),
  address: optStr,
  gstin: optStr,
  openingBalance: z.coerce.number().default(0),
});

customerRouter.post('/', requirePermission('customers.manage'), async (req, res) => {
  const body = parse(Body, req.body);
  const c = await prisma.customer.create({ data: { ...body, shopId: shopIdOf(req), currentBalance: body.openingBalance } });
  res.status(201).json(c);
});

customerRouter.put('/:id', requirePermission('customers.manage'), async (req, res) => {
  const c = await own(req);
  const body = parse(Body.partial(), req.body);
  await prisma.customer.update({ where: { id: c.id }, data: body });
  if (body.openingBalance !== undefined) await recalculateCustomerBalance(c.id);
  res.json(await prisma.customer.findUniqueOrThrow({ where: { id: c.id } }));
});

customerRouter.delete('/:id', requirePermission('customers.manage'), async (req, res) => {
  const c = await own(req);
  await prisma.customer.delete({ where: { id: c.id } });
  await logActivity(req.user!, 'customer_deleted', `Deleted customer ${c.name}`);
  res.json({ ok: true });
});

/** Purchase history (bills) for a customer. */
customerRouter.get('/:id/bills', async (req, res) => {
  const c = await own(req);
  res.json(
    await prisma.bill.findMany({ where: { customerId: c.id, isDeleted: false }, include: { items: true }, orderBy: { billDate: 'desc' }, take: 200 }),
  );
});

customerRouter.get('/:id/ledger', async (req, res) => {
  const c = await own(req);
  const from = req.query.from ? new Date(req.query.from as string) : undefined;
  const to = req.query.to ? new Date(req.query.to as string) : undefined;
  res.json(await customerLedger(c.id, from, to));
});

customerRouter.post('/:id/payments', requirePermission('customers.manage', 'bills.create'), async (req, res) => {
  const c = await own(req);
  const shopId = shopIdOf(req);
  const branchId = await branchIdOf(req);
  const body = parse(z.object({ amount: z.coerce.number().positive(), method: z.nativeEnum(PaymentMethod).default(PaymentMethod.CASH), note: optStr }), req.body);
  const result = await prisma.$transaction(async (tx) => {
    const seq = await nextSequence(tx, shopId, `pay:${yymmdd()}`);
    const receiptNo = `PAY-${yymmdd()}-${String(seq).padStart(3, '0')}`;
    const payment = await tx.customerPayment.create({
      data: { shopId, branchId, customerId: c.id, receiptNo, amount: body.amount, method: body.method, note: body.note, userId: req.user!.id, userName: req.user!.name },
    });
    const customer = await tx.customer.update({ where: { id: c.id }, data: { currentBalance: { decrement: body.amount } } });
    return { payment, customer, openingBalance: Number(c.currentBalance) };
  });
  await logActivity(req.user!, 'payment_received', `Payment of ₹${body.amount} recorded via ${body.method} for ${c.name}`);
  res.status(201).json(result);
});

customerRouter.post('/recalculate', requirePermission('customers.manage'), async (req, res) => {
  const customers = await prisma.customer.findMany({ where: { shopId: shopIdOf(req) }, select: { id: true } });
  for (const c of customers) await recalculateCustomerBalance(c.id);
  res.json({ recalculated: customers.length });
});

customerRouter.post('/import', requirePermission('customers.manage'), async (req, res) => {
  const shopId = shopIdOf(req);
  const rows = parse(z.array(Body), req.body);
  const existing = new Set((await prisma.customer.findMany({ where: { shopId }, select: { phone: true } })).map((c) => c.phone));
  let imported = 0;
  for (const r of rows) {
    if (r.phone && existing.has(r.phone)) continue;
    await prisma.customer.create({ data: { ...r, shopId, currentBalance: r.openingBalance } });
    if (r.phone) existing.add(r.phone);
    imported++;
  }
  res.json({ imported, skipped: rows.length - imported });
});
