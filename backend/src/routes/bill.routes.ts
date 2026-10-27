import { Router } from 'express';
import { BillKind, BillStatus, Prisma } from '@prisma/client';
import { prisma } from '../lib/prisma';
import { parse } from '../lib/validate';
import { requireFeature } from '../lib/features';
import { branchIdOf, requirePermission, shopIdOf } from '../middleware/auth';
import { notFound } from '../lib/errors';
import {
  billInclude,
  cancelBill,
  checkout,
  CheckoutSchema,
  markKotPrinted,
  permanentlyDeleteBill,
  restoreBill,
  softDeleteBill,
} from '../services/billing.service';

export const billRouter = Router();

billRouter.get('/', requirePermission('bills.view', 'bills.create'), async (req, res) => {
  const shopId = shopIdOf(req);
  const q = (req.query.q as string | undefined)?.trim();
  const status = req.query.status as string | undefined; // waiting | completed
  const allBranches = req.query.allBranches === 'true';
  const from = req.query.from ? new Date(req.query.from as string) : undefined;
  const to = req.query.to ? new Date(req.query.to as string) : undefined;
  const where: Prisma.BillWhereInput = {
    shopId,
    ...(!allBranches && { branchId: await branchIdOf(req) }),
    isDeleted: req.query.deleted === 'true',
    ...(status === 'waiting' && { status: BillStatus.WAITING }),
    ...(status === 'completed' && { status: BillStatus.COMPLETED }),
    ...(req.query.kind && { kind: req.query.kind as BillKind }),
    ...((from || to) && { billDate: { gte: from, lte: to } }),
    ...(q && {
      OR: [
        { billNo: { contains: q, mode: 'insensitive' } },
        { customerName: { contains: q, mode: 'insensitive' } },
        { customerContact: { contains: q } },
      ],
    }),
  };
  // Cashiers / billers only see their own bills.
  if (req.user!.role === 'CASHIER' || req.user!.role === 'BILLER') where.userId = req.user!.id;
  const take = Math.min(Number(req.query.limit ?? 200), 1000);
  res.json(await prisma.bill.findMany({ where, include: billInclude, orderBy: { billDate: 'desc' }, take }));
});

billRouter.get('/:id', async (req, res) => {
  const b = await prisma.bill.findFirst({ where: { id: req.params.id, shopId: shopIdOf(req) }, include: { ...billInclude, customer: true } });
  if (!b) throw notFound('Bill');
  res.json(b);
});

/** Create / update a bill. status=WAITING parks it (tables / waiting list), COMPLETED checks out. */
billRouter.post('/checkout', requirePermission('bills.create'), async (req, res) => {
  const input = parse(CheckoutSchema, req.body);
  const bill = await checkout(req.user!, shopIdOf(req), await branchIdOf(req), input);
  res.status(201).json(bill);
});

billRouter.post('/:id/kot', requirePermission('bills.create'), requireFeature('kot'), async (req, res) => {
  res.json(await markKotPrinted(shopIdOf(req), req.params.id));
});

billRouter.post('/:id/cancel', requirePermission('bills.cancel'), async (req, res) => {
  res.json(await cancelBill(req.user!, shopIdOf(req), req.params.id, String(req.body?.reason ?? '')));
});

billRouter.delete('/:id', requirePermission('bills.delete'), async (req, res) => {
  res.json(await softDeleteBill(req.user!, shopIdOf(req), req.params.id));
});

billRouter.post('/:id/restore', requirePermission('bills.cancel', 'bills.delete'), async (req, res) => {
  res.json(await restoreBill(req.user!, shopIdOf(req), req.params.id));
});

billRouter.delete('/:id/permanent', requirePermission('bills.delete'), async (req, res) => {
  await permanentlyDeleteBill(req.user!, shopIdOf(req), req.params.id);
  res.json({ ok: true });
});
