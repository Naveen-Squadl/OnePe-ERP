import { Router } from 'express';
import bcrypt from 'bcryptjs';
import { z } from 'zod';
import { Role } from '@prisma/client';
import { prisma } from '../lib/prisma';
import { parse } from '../lib/validate';
import { requirePermission, shopIdOf } from '../middleware/auth';
import { badRequest, forbidden, notFound } from '../lib/errors';
import { RoleDescriptions } from '../lib/permissions';
import { logActivity } from '../lib/activity';

export const userRouter = Router();
const select = { id: true, name: true, email: true, role: true, branchId: true, isActive: true, lastLoginAt: true, createdAt: true };
const StaffRoles = z.enum(['ADMIN', 'MANAGER', 'CASHIER', 'SALESMAN', 'BILLER', 'STORE_KEEPER', 'STOCK_MANAGER']);

userRouter.get('/roles', (_req, res) => {
  res.json(StaffRoles.options.map((r) => ({ role: r, permissions: RoleDescriptions[r as Role] })));
});

userRouter.get('/', requirePermission('users.manage'), async (req, res) => {
  const shopId = shopIdOf(req);
  const [users, shop] = await Promise.all([
    prisma.user.findMany({ where: { shopId }, select, orderBy: { createdAt: 'asc' } }),
    prisma.shop.findUniqueOrThrow({ where: { id: shopId }, select: { maxUsers: true } }),
  ]);
  res.json({ users, maxUsers: shop.maxUsers });
});

userRouter.post('/', requirePermission('users.manage'), async (req, res) => {
  const shopId = shopIdOf(req);
  const body = parse(
    z.object({
      name: z.string().trim().min(1, 'All fields are required'),
      email: z.string().trim().toLowerCase().email('Invalid email address'),
      password: z.string().min(6, 'Password must be at least 6 characters'),
      role: StaffRoles,
      branchId: z.string().uuid().nullish(),
    }),
    req.body,
  );
  const shop = await prisma.shop.findUniqueOrThrow({ where: { id: shopId } });
  const count = await prisma.user.count({ where: { shopId } });
  if (count >= shop.maxUsers) {
    throw badRequest(`User limit reached (${shop.maxUsers} users allowed). Please upgrade your plan or contact support to increase the limit.`);
  }
  if (body.branchId && !(await prisma.branch.findFirst({ where: { id: body.branchId, shopId } }))) throw notFound('Branch');
  const user = await prisma.user.create({
    data: { shopId, name: body.name, email: body.email, role: body.role, branchId: body.branchId ?? null, passwordHash: await bcrypt.hash(body.password, 10) },
    select,
  });
  await logActivity(req.user!, 'user_created', `Created ${body.role.toLowerCase()} ${body.name}`, { targetUserId: user.id, targetEmail: body.email });
  res.status(201).json(user);
});

userRouter.put('/:id', requirePermission('users.manage'), async (req, res) => {
  const shopId = shopIdOf(req);
  const body = parse(
    z.object({
      name: z.string().trim().min(1).optional(),
      role: StaffRoles.optional(),
      branchId: z.string().uuid().nullish(),
      isActive: z.boolean().optional(),
      password: z.string().min(6).optional(),
    }),
    req.body,
  );
  const target = await prisma.user.findFirst({ where: { id: req.params.id, shopId } });
  if (!target) throw notFound('User');
  if (target.id === req.user!.id && (body.isActive === false || (body.role && body.role !== target.role))) {
    throw forbidden('You cannot deactivate or change the role of your own account');
  }
  const { password, ...rest } = body;
  const user = await prisma.user.update({
    where: { id: target.id },
    data: { ...rest, ...(password && { passwordHash: await bcrypt.hash(password, 10) }) },
    select,
  });
  const action = body.isActive === undefined ? 'user_updated' : body.isActive ? 'user_activated' : 'user_deactivated';
  await logActivity(req.user!, action, `Updated user ${user.name}`, { targetUserId: user.id });
  res.json(user);
});

userRouter.delete('/:id', requirePermission('users.manage'), async (req, res) => {
  const shopId = shopIdOf(req);
  const target = await prisma.user.findFirst({ where: { id: req.params.id, shopId } });
  if (!target) throw notFound('User');
  if (target.id === req.user!.id) throw forbidden('You cannot delete your own account');
  await prisma.user.delete({ where: { id: target.id } });
  await logActivity(req.user!, 'user_deleted', `Deleted user ${target.name}`, { targetEmail: target.email });
  res.json({ ok: true });
});
