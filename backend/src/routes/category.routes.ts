import { Router } from 'express';
import { z } from 'zod';
import { prisma } from '../lib/prisma';
import { parse } from '../lib/validate';
import { requirePermission, shopIdOf } from '../middleware/auth';
import { notFound } from '../lib/errors';

export const categoryRouter = Router();

categoryRouter.get('/', async (req, res) => {
  const cats = await prisma.category.findMany({
    where: { shopId: shopIdOf(req) },
    orderBy: [{ sortOrder: 'asc' }, { name: 'asc' }],
    include: { _count: { select: { products: true } } },
  });
  res.json(cats);
});

const Body = z.object({
  name: z.string().trim().min(1, 'Category Name is required'),
  isStockCategory: z.boolean().default(true),
  isExpenseCategory: z.boolean().default(false),
  sortOrder: z.number().int().default(0),
});

categoryRouter.post('/', requirePermission('products.manage'), async (req, res) => {
  const body = parse(Body, req.body);
  res.status(201).json(await prisma.category.create({ data: { ...body, shopId: shopIdOf(req) } }));
});

categoryRouter.put('/:id', requirePermission('products.manage'), async (req, res) => {
  const shopId = shopIdOf(req);
  const body = parse(Body.partial(), req.body);
  const c = await prisma.category.findFirst({ where: { id: req.params.id, shopId } });
  if (!c) throw notFound('Category');
  res.json(await prisma.category.update({ where: { id: c.id }, data: body }));
});

categoryRouter.delete('/:id', requirePermission('products.manage'), async (req, res) => {
  const shopId = shopIdOf(req);
  const c = await prisma.category.findFirst({ where: { id: req.params.id, shopId } });
  if (!c) throw notFound('Category');
  await prisma.category.delete({ where: { id: c.id } }); // products keep existing, categoryId → null
  res.json({ ok: true });
});
