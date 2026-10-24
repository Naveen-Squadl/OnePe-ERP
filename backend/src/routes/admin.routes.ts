import { Router } from 'express';
import bcrypt from 'bcryptjs';
import { z } from 'zod';
import { EnquiryStatus, Plan, ShopType } from '@prisma/client';
import { prisma } from '../lib/prisma';
import { parse, optStr } from '../lib/validate';
import { requireSuperAdmin } from '../middleware/auth';
import { conflict, notFound } from '../lib/errors';
import { logActivity } from '../lib/activity';

export const adminRouter = Router();
adminRouter.use(requireSuperAdmin);

export const PlanDefaults: Record<Plan, { maxUsers: number; maxBranches: number; label: string }> = {
  FREE: { maxUsers: 1, maxBranches: 1, label: '1 user, single outlet' },
  BASIC: { maxUsers: 4, maxBranches: 1, label: '4 users, cloud sync' },
  STANDARD: { maxUsers: 6, maxBranches: 2, label: '6 users, 2 outlets' },
  PREMIUM: { maxUsers: 10, maxBranches: 3, label: '10 users, 3 outlets' },
  ENTERPRISE: { maxUsers: 50, maxBranches: 10, label: '50 users, 10 outlets' },
};

adminRouter.get('/plans', (_req, res) => {
  res.json(Object.entries(PlanDefaults).map(([plan, v]) => ({ plan, ...v })));
});

adminRouter.get('/stats', async (_req, res) => {
  const today = new Date();
  today.setHours(0, 0, 0, 0);
  const [totalShops, activeShops, totalUsers, activeUsers, todayActivity, plans, recent] = await Promise.all([
    prisma.shop.count(),
    prisma.shop.count({ where: { isActive: true } }),
    prisma.user.count({ where: { role: { not: 'SUPER_ADMIN' } } }),
    prisma.user.count({ where: { role: { not: 'SUPER_ADMIN' }, isActive: true } }),
    prisma.activityLog.count({ where: { createdAt: { gte: today } } }),
    prisma.shop.groupBy({ by: ['plan'], _count: true }),
    prisma.activityLog.findMany({ where: { createdAt: { gte: new Date(Date.now() - 7 * 86_400_000) } }, orderBy: { createdAt: 'desc' }, take: 20 }),
  ]);
  res.json({ totalShops, activeShops, totalUsers, activeUsers, todayActivity, subscriptionBreakdown: Object.fromEntries(plans.map((p) => [p.plan, p._count])), recentActivity: recent });
});

adminRouter.get('/shops', async (_req, res) => {
  const shops = await prisma.shop.findMany({ orderBy: { createdAt: 'desc' }, include: { _count: { select: { users: true, branches: true } } } });
  res.json(shops);
});

adminRouter.get('/shops/:id', async (req, res) => {
  const shop = await prisma.shop.findUnique({
    where: { id: req.params.id },
    include: { branches: true, users: { select: { id: true, name: true, email: true, role: true, isActive: true, lastLoginAt: true } } },
  });
  if (!shop) throw notFound('Shop');
  res.json(shop);
});

const CreateShop = z.object({
  shopName: z.string().trim().min(1, 'Please enter shop name'),
  ownerName: z.string().trim().min(1, 'Please enter owner name'),
  email: z.string().trim().toLowerCase().email('Invalid email format. Please check and try again.'),
  password: z.string().min(8, 'Password must be at least 8 characters'),
  shopType: z.nativeEnum(ShopType).default(ShopType.RETAIL),
  plan: z.nativeEnum(Plan).default(Plan.BASIC),
  maxBranches: z.coerce.number().int().min(1, 'Must allow at least 1 branch').optional(),
  maxUsers: z.coerce.number().int().min(1).optional(),
  subscriptionExpiry: z.coerce.date().nullish(),
  address: optStr,
  contactNumber: optStr,
});

adminRouter.post('/shops', async (req, res) => {
  const body = parse(CreateShop, req.body);
  if (await prisma.user.findUnique({ where: { email: body.email } })) throw conflict('This email is already in use. Please use a different email.');
  const defaults = PlanDefaults[body.plan];
  const passwordHash = await bcrypt.hash(body.password, 10);
  const shop = await prisma.$transaction(async (tx) => {
    const s = await tx.shop.create({
      data: {
        name: body.shopName, ownerName: body.ownerName, ownerEmail: body.email, shopType: body.shopType, plan: body.plan,
        maxBranches: body.maxBranches ?? defaults.maxBranches, maxUsers: body.maxUsers ?? defaults.maxUsers,
        subscriptionExpiry: body.subscriptionExpiry ?? new Date(Date.now() + 365 * 86_400_000),
        address: body.address, contactNumber: body.contactNumber,
      },
    });
    const branch = await tx.branch.create({ data: { shopId: s.id, name: 'Main Branch', code: 'MAIN', isMain: true, address: body.address, contactNumber: body.contactNumber } });
    await tx.user.create({ data: { shopId: s.id, branchId: branch.id, name: body.ownerName, email: body.email, passwordHash, role: 'ADMIN' } });
    await tx.category.create({ data: { shopId: s.id, name: 'Expenses', isStockCategory: false, isExpenseCategory: true, sortOrder: 99 } });
    return s;
  });
  await logActivity(req.user!, 'shop_created', `Created shop: ${shop.name}`, { shopId: shop.id, adminEmail: body.email, plan: body.plan }, prisma, null);
  res.status(201).json(shop);
});

adminRouter.put('/shops/:id', async (req, res) => {
  const body = parse(
    z.object({
      name: z.string().trim().min(1).optional(),
      isActive: z.boolean().optional(),
      shopType: z.nativeEnum(ShopType).optional(),
      plan: z.nativeEnum(Plan).optional(),
      maxUsers: z.coerce.number().int().min(1).optional(),
      maxBranches: z.coerce.number().int().min(1, 'Must allow at least 1 branch').optional(),
      subscriptionStart: z.coerce.date().optional(),
      subscriptionExpiry: z.coerce.date().nullish(),
    }),
    req.body,
  );
  const s = await prisma.shop.findUnique({ where: { id: req.params.id } });
  if (!s) throw notFound('Shop');
  const shop = await prisma.shop.update({ where: { id: s.id }, data: body });
  const action = body.isActive === undefined ? (body.plan || body.subscriptionExpiry ? 'subscription_updated' : 'shop_updated') : body.isActive ? 'shop_activated' : 'shop_deactivated';
  await logActivity(req.user!, action, `Updated shop ${shop.name}`, { shopId: shop.id, ...body }, prisma, null);
  res.json(shop);
});

adminRouter.delete('/shops/:id', async (req, res) => {
  const s = await prisma.shop.findUnique({ where: { id: req.params.id } });
  if (!s) throw notFound('Shop');
  await prisma.shop.delete({ where: { id: s.id } });
  await logActivity(req.user!, 'shop_deleted', `Deleted shop: ${s.name}`, { shopId: s.id }, prisma, null);
  res.json({ ok: true });
});

adminRouter.get('/users', async (req, res) => {
  res.json(
    await prisma.user.findMany({
      where: { shopId: (req.query.shopId as string) || undefined },
      select: { id: true, name: true, email: true, role: true, isActive: true, shopId: true, branchId: true, lastLoginAt: true, createdAt: true, shop: { select: { name: true } } },
      orderBy: { createdAt: 'desc' },
    }),
  );
});

adminRouter.put('/users/:id', async (req, res) => {
  const body = parse(z.object({ isActive: z.boolean().optional(), password: z.string().min(6).optional(), name: z.string().optional() }), req.body);
  const u = await prisma.user.findUnique({ where: { id: req.params.id } });
  if (!u) throw notFound('User');
  const { password, ...rest } = body;
  const out = await prisma.user.update({ where: { id: u.id }, data: { ...rest, ...(password && { passwordHash: await bcrypt.hash(password, 10) }) }, select: { id: true, name: true, isActive: true } });
  res.json(out);
});

adminRouter.delete('/users/:id', async (req, res) => {
  const u = await prisma.user.findUnique({ where: { id: req.params.id } });
  if (!u) throw notFound('User');
  if (u.role === 'SUPER_ADMIN') throw conflict('Super Admins cannot be deleted this way');
  await prisma.user.delete({ where: { id: u.id } });
  await logActivity(req.user!, 'user_deleted', `Deleted user ${u.email}`, undefined, prisma, null);
  res.json({ ok: true });
});

adminRouter.get('/activity', async (req, res) => {
  const from = req.query.from ? new Date(req.query.from as string) : undefined;
  const to = req.query.to ? new Date(req.query.to as string) : undefined;
  res.json(
    await prisma.activityLog.findMany({
      where: { shopId: (req.query.shopId as string) || undefined, ...((from || to) && { createdAt: { gte: from, lte: to } }) },
      orderBy: { createdAt: 'desc' },
      take: Math.min(Number(req.query.limit ?? 200), 1000),
    }),
  );
});

adminRouter.get('/enquiries', async (_req, res) => {
  res.json(await prisma.enquiry.findMany({ orderBy: { createdAt: 'desc' } }));
});

adminRouter.put('/enquiries/:id', async (req, res) => {
  const { status } = parse(z.object({ status: z.nativeEnum(EnquiryStatus) }), req.body);
  res.json(await prisma.enquiry.update({ where: { id: req.params.id }, data: { status } }));
});

adminRouter.delete('/enquiries/:id', async (req, res) => {
  await prisma.enquiry.delete({ where: { id: req.params.id } });
  res.json({ ok: true });
});
