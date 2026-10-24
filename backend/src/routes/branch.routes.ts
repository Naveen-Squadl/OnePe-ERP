import { Router } from 'express';
import { z } from 'zod';
import { prisma } from '../lib/prisma';
import { parse, optStr } from '../lib/validate';
import { requirePermission, shopIdOf } from '../middleware/auth';
import { badRequest, notFound } from '../lib/errors';
import { logActivity } from '../lib/activity';

export const branchRouter = Router();

branchRouter.get('/', async (req, res) => {
  const shopId = shopIdOf(req);
  const [branches, shop] = await Promise.all([
    prisma.branch.findMany({ where: { shopId }, orderBy: [{ isMain: 'desc' }, { createdAt: 'asc' }] }),
    prisma.shop.findUniqueOrThrow({ where: { id: shopId }, select: { maxBranches: true } }),
  ]);
  res.json({ branches, maxBranches: shop.maxBranches, limitReached: branches.length >= shop.maxBranches });
});

const BranchBody = z.object({
  name: z.string().trim().min(1),
  code: z.string().trim().toUpperCase().regex(/^[A-Z0-9]{2,8}$/, 'Code must be 2-8 letters/digits').optional(),
  address: optStr,
  contactNumber: optStr,
  upiId: optStr,
  tableNames: z.array(z.string().trim().min(1)).optional(),
  printer: z.record(z.unknown()).optional(),
  isActive: z.boolean().optional(),
});

branchRouter.post('/', requirePermission('branches.manage'), async (req, res) => {
  const shopId = shopIdOf(req);
  const body = parse(BranchBody, req.body);
  const shop = await prisma.shop.findUniqueOrThrow({ where: { id: shopId } });
  const count = await prisma.branch.count({ where: { shopId } });
  if (count >= shop.maxBranches) {
    throw badRequest(`You have reached the maximum allowed outlets (${shop.maxBranches}) set by the Super Admin. Contact Super Admin to increase outlet capacity.`);
  }
  const code = body.code ?? `BR${count + 1}`;
  const branch = await prisma.branch.create({
    data: { ...body, code, shopId, printer: (body.printer ?? {}) as any, isMain: count === 0 },
  });
  await logActivity(req.user!, 'branch_created', `Created branch ${branch.name}`);
  res.status(201).json(branch);
});

branchRouter.put('/:id', requirePermission('branches.manage'), async (req, res) => {
  const shopId = shopIdOf(req);
  const body = parse(BranchBody.partial(), req.body);
  const b = await prisma.branch.findFirst({ where: { id: req.params.id, shopId } });
  if (!b) throw notFound('Branch');
  const branch = await prisma.branch.update({ where: { id: b.id }, data: { ...body, printer: body.printer as any } });
  res.json(branch);
});

branchRouter.delete('/:id', requirePermission('branches.manage'), async (req, res) => {
  const shopId = shopIdOf(req);
  const b = await prisma.branch.findFirst({ where: { id: req.params.id, shopId } });
  if (!b) throw notFound('Branch');
  if (b.isMain) throw badRequest('The main branch cannot be deleted');
  const bills = await prisma.bill.count({ where: { branchId: b.id } });
  if (bills > 0) throw badRequest('Branch has bills. Deactivate it instead of deleting.');
  await prisma.branch.delete({ where: { id: b.id } });
  await logActivity(req.user!, 'branch_deleted', `Deleted branch ${b.name}`);
  res.json({ ok: true });
});
