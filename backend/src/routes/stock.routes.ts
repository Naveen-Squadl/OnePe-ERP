import { Router } from 'express';
import { z } from 'zod';
import { Prisma } from '@prisma/client';
import { prisma } from '../lib/prisma';
import { parse, optStr } from '../lib/validate';
import { branchIdOf, requirePermission, shopIdOf } from '../middleware/auth';
import { notFound } from '../lib/errors';
import { num } from '../lib/money';
import { inwardBatch, moveStock, setStock } from '../services/stock.service';

export const stockRouter = Router();
stockRouter.use(requirePermission('inventory.view', 'inventory.manage'));

/** Stock levels for stock-category products in the active branch. */
stockRouter.get('/', async (req, res) => {
  const shopId = shopIdOf(req);
  const branchId = await branchIdOf(req);
  const q = (req.query.q as string | undefined)?.trim();
  const products = await prisma.product.findMany({
    where: {
      shopId,
      isActive: true,
      trackStock: true,
      OR: [{ categoryId: null }, { category: { isStockCategory: true } }],
      ...(q && { name: { contains: q, mode: 'insensitive' } }),
    },
    include: {
      category: { select: { name: true } },
      branches: { where: { branchId } },
      batches: { where: { branchId, remainingQuantity: { gt: 0 } }, orderBy: { expiryDate: { sort: 'asc', nulls: 'last' } } },
    },
    orderBy: { name: 'asc' },
  });
  res.json(
    products.map(({ branches, ...p }) => ({
      ...p,
      stock: num(branches[0]?.stock ?? 0),
      isLowStock: num(branches[0]?.stock ?? 0) <= num(p.lowStockThreshold),
    })),
  );
});

const AdjustBody = z.object({
  productId: z.string().uuid(),
  mode: z.enum(['add', 'remove', 'set']),
  quantity: z.coerce.number().min(0),
  note: optStr,
});

stockRouter.post('/adjust', requirePermission('inventory.manage'), async (req, res) => {
  const shopId = shopIdOf(req);
  const branchId = await branchIdOf(req);
  const body = parse(AdjustBody, req.body);
  const p = await prisma.product.findFirst({ where: { id: body.productId, shopId } });
  if (!p) throw notFound('Product');
  const ctx = { shopId, branchId, userId: req.user!.id, userName: req.user!.name, note: body.note ?? undefined, refType: 'manual' };
  const stock = await prisma.$transaction((tx) =>
    body.mode === 'set'
      ? setStock(tx, ctx, p.id, p.name, body.quantity)
      : moveStock(tx, ctx, p.id, p.name, body.mode === 'add' ? body.quantity : -body.quantity, body.mode === 'add' ? 'manual_add' : 'manual_outward'),
  );
  res.json({ productId: p.id, stock });
});

stockRouter.post('/inward', requirePermission('inventory.manage'), async (req, res) => {
  const shopId = shopIdOf(req);
  const branchId = await branchIdOf(req);
  const body = parse(
    z.object({ productId: z.string().uuid(), quantity: z.coerce.number().positive(), batchNumber: optStr, expiryDate: z.coerce.date().nullish(), purchasePrice: z.coerce.number().nullish(), location: optStr, note: optStr }),
    req.body,
  );
  const p = await prisma.product.findFirst({ where: { id: body.productId, shopId } });
  if (!p) throw notFound('Product');
  const batch = await prisma.$transaction((tx) =>
    inwardBatch(tx, { shopId, branchId, userId: req.user!.id, userName: req.user!.name, note: body.note ?? undefined, refType: 'manual' }, {
      productId: p.id, productName: p.name, quantity: body.quantity, batchNumber: body.batchNumber, expiryDate: body.expiryDate, purchasePrice: body.purchasePrice, location: body.location ?? p.storageLocation,
    }),
  );
  res.status(201).json(batch);
});

/** Batch-wise stock report. filter: all | expiring | expired */
stockRouter.get('/batches', async (req, res) => {
  const shopId = shopIdOf(req);
  const branchId = await branchIdOf(req);
  const filter = (req.query.filter as string) ?? 'all';
  const days = Number(req.query.days ?? 3);
  const now = new Date();
  const soon = new Date(now.getTime() + days * 86_400_000);
  const where: Prisma.StockBatchWhereInput = {
    shopId,
    branchId,
    remainingQuantity: { gt: 0 },
    ...(filter === 'expiring' && { expiryDate: { gte: now, lte: soon } }),
    ...(filter === 'expired' && { expiryDate: { lt: now } }),
    ...(req.query.q && {
      OR: [
        { batchNumber: { contains: req.query.q as string, mode: 'insensitive' } },
        { product: { name: { contains: req.query.q as string, mode: 'insensitive' } } },
      ],
    }),
  };
  const batches = await prisma.stockBatch.findMany({
    where,
    include: { product: { select: { name: true, basePrice: true, unit: true } } },
    orderBy: [{ expiryDate: { sort: 'asc', nulls: 'last' } }],
  });
  res.json(
    batches.map((b) => ({
      ...b,
      daysLeft: b.expiryDate ? Math.ceil((b.expiryDate.getTime() - now.getTime()) / 86_400_000) : null,
    })),
  );
});

stockRouter.get('/history', async (req, res) => {
  const shopId = shopIdOf(req);
  const branchId = await branchIdOf(req);
  const from = req.query.from ? new Date(req.query.from as string) : undefined;
  const to = req.query.to ? new Date(req.query.to as string) : undefined;
  res.json(
    await prisma.stockMovement.findMany({
      where: {
        shopId,
        branchId,
        productId: (req.query.productId as string) || undefined,
        type: (req.query.type as string) || undefined,
        ...((from || to) && { createdAt: { gte: from, lte: to } }),
      },
      orderBy: { createdAt: 'desc' },
      take: Math.min(Number(req.query.limit ?? 500), 2000),
    }),
  );
});
