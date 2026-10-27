import { RequestHandler, Router } from 'express';
import { z } from 'zod';
import { PaymentMethod, Prisma } from '@prisma/client';
import { num } from '../lib/money';
import { prisma } from '../lib/prisma';
import { dateRange, parse, optStr } from '../lib/validate';
import { branchIdOf, requirePermission, shopIdOf } from '../middleware/auth';
import { badRequest, conflict, notFound } from '../lib/errors';
import { nextSequence, yymmdd } from '../lib/sequence';
import { customerLedger } from '../services/ledger.service';
import { logActivity } from '../lib/activity';

export const customerRouter = Router();

async function own(req: any) {
  const c = await prisma.customer.findFirst({ where: { id: req.params.id, shopId: shopIdOf(req) } });
  if (!c) throw notFound('Customer');
  return c;
}

customerRouter.get('/', async (req, res) => {
  const q = (req.query.q as string | undefined)?.trim();
  const filter = req.query.filter as string | undefined; // due | advance | settled | archived
  const where: Prisma.CustomerWhereInput = {
    shopId: shopIdOf(req),
    isArchived: filter === 'archived',
    ...(q && { OR: [{ name: { contains: q, mode: 'insensitive' } }, { phone: { contains: q } }, { gstin: { contains: q, mode: 'insensitive' } }] }),
    ...(filter === 'due' && { currentBalance: { gt: 0 } }),
    ...(filter === 'advance' && { currentBalance: { lt: 0 } }),
    ...(filter === 'settled' && { currentBalance: { lte: 0 } }),
  };
  res.json(await prisma.customer.findMany({ where, orderBy: { name: 'asc' } }));
});

customerRouter.get('/phone/:phone', async (req, res) => {
  const c = await prisma.customer.findFirst({ where: { shopId: shopIdOf(req), phone: req.params.phone } });
  if (!c) throw notFound('Customer');
  res.json(c);
});

/**
 * Customer events in a period (Customers → History): added, edited, archived, restored, imported, plus advances
 * received (payment above the due, change kept as advance) and refunded. Plain payments of dues are not listed.
 */
customerRouter.get('/activity', requirePermission('customers.manage'), async (req, res) => {
  const createdAt = dateRange(req.query);
  res.json(
    await prisma.activityLog.findMany({
      where: {
        shopId: shopIdOf(req),
        OR: [
          { action: { startsWith: 'customer_' } },
          { action: 'advance_refunded' },
          { action: 'payment_received', description: { contains: 'advance', mode: 'insensitive' } },
        ],
        ...(createdAt && { createdAt }),
      },
      orderBy: { createdAt: 'desc' },
      take: 1000,
    }),
  );
});

customerRouter.get('/:id', async (req, res) => {
  res.json(await own(req));
});

const customerLabel = (c: { name: string; phone: string | null }) => c.name || c.phone || 'customer';

const Body = z.object({
  /** Optional for every shop type – a customer can be just a mobile number. */
  name: z.string().trim().default(''),
  phone: z.string().trim().regex(/^\d{10}$/, 'Must be 10 digits').nullish(),
  address: optStr,
  gstin: optStr,
  /** Set once, when the customer is created; later changes go through payments / bills (keeps the ledger history). */
  openingBalance: z.coerce.number().default(0),
});
const UpdateBody = Body.omit({ openingBalance: true }).partial();

customerRouter.post('/', requirePermission('customers.manage'), async (req, res) => {
  const body = parse(Body, req.body);
  if (!body.name && !body.phone) throw badRequest('Enter a mobile number or a name');
  const shopId = shopIdOf(req);
  const same = body.phone ? await prisma.customer.findFirst({ where: { shopId, phone: body.phone } }) : null;
  if (same && !same.isArchived) throw badRequest(`${customerLabel(same)} already has mobile ${body.phone}`);
  if (same) {
    // Adding an archived customer's mobile again brings them back with their history (opening balance unchanged).
    const { openingBalance: _ignored, ...details } = body;
    const c = await prisma.customer.update({ where: { id: same.id }, data: { ...details, name: body.name || same.name, isArchived: false, archivedAt: null } });
    await logActivity(req.user!, 'customer_restored', `Restored archived customer ${customerLabel(c)}`);
    return res.status(200).json(c);
  }
  const c = await prisma.customer.create({ data: { ...body, shopId, currentBalance: body.openingBalance } });
  const opening = body.openingBalance ? ` with opening balance ₹${Math.abs(body.openingBalance)} ${body.openingBalance > 0 ? 'due' : 'advance'}` : '';
  await logActivity(req.user!, 'customer_created', `Added customer ${customerLabel(c)}${c.name && c.phone ? ` (${c.phone})` : ''}${opening}`, { customerId: c.id });
  res.status(201).json(c);
});

customerRouter.put('/:id', requirePermission('customers.manage'), async (req, res) => {
  const c = await own(req);
  const body = parse(UpdateBody, req.body);
  const opening = req.body?.openingBalance;
  if (opening != null && Number(opening) !== Number(c.openingBalance)) {
    throw badRequest('The opening balance can only be set when the customer is created. Record a payment instead.');
  }
  const out = await prisma.customer.update({ where: { id: c.id }, data: body });
  const labels = { name: 'name', phone: 'mobile', address: 'address', gstin: 'GSTIN' } as const;
  const changed = (Object.keys(labels) as (keyof typeof labels)[])
    .filter((k) => body[k] !== undefined && (body[k] ?? '') !== (c[k] ?? ''))
    .map((k) => `${labels[k]} ${c[k] || '–'} → ${out[k] || '–'}`);
  if (changed.length) await logActivity(req.user!, 'customer_updated', `Edited customer ${customerLabel(out)}: ${changed.join(', ')}`, { customerId: c.id });
  res.json(out);
});

/**
 * Archive instead of delete: hidden from lists and pickers, bills / payments / ledger kept, reports unchanged.
 * Only with a settled balance – a due must be collected and an advance refunded first.
 */
const archive: RequestHandler = async (req, res) => {
  const c = await own(req);
  const balance = num(c.currentBalance);
  if (balance > 0.009) throw conflict(`${customerLabel(c)} owes you ₹${balance} – collect or settle it before archiving`);
  if (balance < -0.009) throw conflict(`${customerLabel(c)} has ₹${-balance} advance – refund it before archiving`);
  const out = await prisma.customer.update({ where: { id: c.id }, data: { isArchived: true, archivedAt: new Date() } });
  await logActivity(req.user!, 'customer_archived', `Archived customer ${customerLabel(c)}`);
  res.json(out);
};

customerRouter.post('/:id/archive', requirePermission('customers.manage'), archive);
/** Older app versions call DELETE – customers are never deleted, only archived. */
customerRouter.delete('/:id', requirePermission('customers.manage'), archive);

customerRouter.post('/:id/restore', requirePermission('customers.manage'), async (req, res) => {
  const c = await own(req);
  const out = await prisma.customer.update({ where: { id: c.id }, data: { isArchived: false, archivedAt: null } });
  await logActivity(req.user!, 'customer_restored', `Restored archived customer ${customerLabel(c)}`);
  res.json(out);
});

/** Purchase history (bills) for a customer. */
customerRouter.get('/:id/bills', async (req, res) => {
  const c = await own(req);
  res.json(
    await prisma.bill.findMany({
      where: { customerId: c.id, isDeleted: false, ...(dateRange(req.query) && { billDate: dateRange(req.query) }) },
      include: { items: true },
      orderBy: { billDate: 'desc' },
      take: 500,
    }),
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
  if (c.isArchived) throw conflict(`${customerLabel(c)} is archived – restore them first`);
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
  const toAdvance = Math.min(body.amount, -num(result.customer.currentBalance));
  await logActivity(
    req.user!,
    'payment_received',
    toAdvance > 0
      ? `${toAdvance === body.amount ? 'Advance' : `Payment (₹${toAdvance} as advance)`} of ₹${body.amount} received via ${body.method} from ${customerLabel(c)}`
      : `Payment of ₹${body.amount} recorded via ${body.method} for ${customerLabel(c)}`,
  );
  res.status(201).json(result);
});

/** Give (part of) a customer's advance back. Money out: raises the balance towards zero. */
customerRouter.post('/:id/refunds', requirePermission('customers.manage'), async (req, res) => {
  const c = await own(req);
  if (c.isArchived) throw conflict(`${customerLabel(c)} is archived – restore them first`);
  const shopId = shopIdOf(req);
  const branchId = await branchIdOf(req);
  const body = parse(z.object({ amount: z.coerce.number().positive(), method: z.nativeEnum(PaymentMethod).default(PaymentMethod.CASH), note: optStr }), req.body);
  const result = await prisma.$transaction(async (tx) => {
    const fresh = await tx.customer.findUniqueOrThrow({ where: { id: c.id } });
    const advance = Math.max(0, -num(fresh.currentBalance));
    if (body.amount > advance + 0.009) throw badRequest(`Only ₹${advance} advance is available to refund`);
    const seq = await nextSequence(tx, shopId, `ref:${yymmdd()}`);
    const receiptNo = `REF-${yymmdd()}-${String(seq).padStart(3, '0')}`;
    const payment = await tx.customerPayment.create({
      data: { shopId, branchId, customerId: c.id, receiptNo, amount: body.amount, method: body.method, note: body.note, isRefund: true, userId: req.user!.id, userName: req.user!.name },
    });
    const customer = await tx.customer.update({ where: { id: c.id }, data: { currentBalance: { increment: body.amount } } });
    return { payment, customer, openingBalance: num(fresh.currentBalance) };
  });
  await logActivity(req.user!, 'advance_refunded', `Advance of ₹${body.amount} refunded via ${body.method} to ${customerLabel(c)}`);
  res.status(201).json(result);
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
  if (imported) await logActivity(req.user!, 'customer_imported', `Imported ${imported} customer(s)`);
  res.json({ imported, skipped: rows.length - imported });
});
