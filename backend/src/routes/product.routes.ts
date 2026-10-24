import { Router } from 'express';
import { z } from 'zod';
import { BranchScope, Prisma } from '@prisma/client';
import { prisma } from '../lib/prisma';
import { parse, optStr } from '../lib/validate';
import { branchIdOf, requirePermission, shopIdOf } from '../middleware/auth';
import { forbidden, notFound } from '../lib/errors';
import { num } from '../lib/money';
import { inwardBatch } from '../services/stock.service';

export const productRouter = Router();

const include = { category: { select: { id: true, name: true, isExpenseCategory: true, isStockCategory: true } }, branches: true } as const;
type ProductRow = Prisma.ProductGetPayload<{ include: typeof include }>;

/** Flatten a product for the active branch (effective price + stock). */
function present(p: ProductRow, branchId: string) {
  const pb = p.branches.find((b) => b.branchId === branchId);
  const totalStock = p.branches.reduce((s, b) => s + num(b.stock), 0);
  return {
    ...p,
    price: pb?.price != null ? num(pb.price) : num(p.basePrice),
    stock: num(pb?.stock ?? 0),
    totalStock,
    availableHere: p.branchScope === BranchScope.ALL || !!pb?.enabled,
    isLowStock: p.trackStock && num(pb?.stock ?? 0) <= num(p.lowStockThreshold),
  };
}

productRouter.get('/', async (req, res) => {
  const shopId = shopIdOf(req);
  const branchId = await branchIdOf(req);
  const q = (req.query.q as string | undefined)?.trim();
  const scope = (req.query.scope as string) ?? 'this_branch'; // this_branch | all_branches
  const and: Prisma.ProductWhereInput[] = [];
  if (q) and.push({ OR: [{ name: { contains: q, mode: 'insensitive' } }, { barcode: q }, { hsnCode: { startsWith: q } }] });
  if (scope === 'this_branch') and.push({ OR: [{ branchScope: BranchScope.ALL }, { branches: { some: { branchId, enabled: true } } }] });
  const where: Prisma.ProductWhereInput = {
    shopId,
    isActive: req.query.includeInactive === 'true' ? undefined : true,
    categoryId: (req.query.categoryId as string) || undefined,
    AND: and,
  };
  const products = await prisma.product.findMany({ where, include, orderBy: { name: 'asc' } });
  res.json(products.map((p) => present(p, branchId)));
});

productRouter.get('/barcode/:code', async (req, res) => {
  const shopId = shopIdOf(req);
  const branchId = await branchIdOf(req);
  const p = await prisma.product.findFirst({ where: { shopId, barcode: req.params.code, isActive: true }, include });
  if (!p) throw notFound(`No matching product found for code: ${req.params.code}`);
  const out = present(p, branchId);
  if (!out.availableHere) throw forbidden(`${p.name} is not available in current branch`);
  res.json(out);
});

productRouter.get('/:id', async (req, res) => {
  const p = await prisma.product.findFirst({ where: { id: req.params.id, shopId: shopIdOf(req) }, include });
  if (!p) throw notFound('Product');
  res.json(present(p, await branchIdOf(req)));
});

const ProductBody = z.object({
  name: z.string().trim().min(1),
  categoryId: z.string().uuid().nullish(),
  barcode: optStr,
  hsnCode: optStr,
  unit: z.string().default('pcs'),
  basePrice: z.coerce.number().min(0),
  maxPrice: z.coerce.number().min(0).nullish(),
  purchasePrice: z.coerce.number().min(0).nullish(),
  gstPercent: z.coerce.number().min(0).max(28).default(0),
  isIgst: z.boolean().default(false),
  isPriceVariable: z.boolean().default(false),
  trackStock: z.boolean().default(true),
  lowStockThreshold: z.coerce.number().min(0).default(5),
  storageLocation: optStr,
  imageUrl: optStr,
  isActive: z.boolean().default(true),
  /** this_branch | all_branches | specific_branches */
  availability: z.enum(['this_branch', 'all_branches', 'specific_branches']).default('all_branches'),
  /** Branch overrides: price per outlet, enabled flag for specific availability. */
  branches: z.array(z.object({ branchId: z.string().uuid(), price: z.coerce.number().min(0).nullish(), enabled: z.boolean().default(true) })).default([]),
  /** Opening stock for the active branch (creates an inward batch). */
  openingStock: z.coerce.number().min(0).default(0),
  batchNumber: optStr,
  expiryDate: z.coerce.date().nullish(),
});

async function writeBranches(tx: Prisma.TransactionClient, productId: string, shopId: string, activeBranch: string, body: Partial<z.infer<typeof ProductBody>>) {
  if (!body.availability && !body.branches) return;
  const shopBranches = await tx.branch.findMany({ where: { shopId }, select: { id: true } });
  const valid = new Set(shopBranches.map((b) => b.id));
  const overrides = new Map((body.branches ?? []).filter((b) => valid.has(b.branchId)).map((b) => [b.branchId, b]));
  for (const { id } of shopBranches) {
    const o = overrides.get(id);
    const enabled =
      body.availability === 'this_branch' ? id === activeBranch : body.availability === 'specific_branches' ? !!o?.enabled : true;
    await tx.productBranch.upsert({
      where: { productId_branchId: { productId, branchId: id } },
      create: { productId, branchId: id, enabled, price: o?.price ?? null },
      update: { enabled, ...(o && { price: o.price ?? null }) },
    });
  }
}

productRouter.post('/', requirePermission('products.manage'), async (req, res) => {
  const shopId = shopIdOf(req);
  const branchId = await branchIdOf(req);
  const body = parse(ProductBody, req.body);
  const { availability, branches: _b, openingStock, batchNumber, expiryDate, ...data } = body;
  const product = await prisma.$transaction(async (tx) => {
    const p = await tx.product.create({
      data: { ...data, barcode: data.barcode || null, shopId, branchScope: availability === 'all_branches' ? BranchScope.ALL : BranchScope.SPECIFIC },
    });
    await writeBranches(tx, p.id, shopId, branchId, body);
    if (openingStock > 0 && p.trackStock) {
      await inwardBatch(tx, { shopId, branchId, userId: req.user!.id, userName: req.user!.name, note: 'Opening stock' }, {
        productId: p.id, productName: p.name, quantity: openingStock, batchNumber, expiryDate, purchasePrice: data.purchasePrice, location: data.storageLocation, type: 'manual_add',
      });
    }
    return tx.product.findUniqueOrThrow({ where: { id: p.id }, include });
  });
  res.status(201).json(present(product, branchId));
});

productRouter.put('/:id', requirePermission('products.manage', 'products.edit_limited'), async (req, res) => {
  const shopId = shopIdOf(req);
  const branchId = await branchIdOf(req);
  const existing = await prisma.product.findFirst({ where: { id: req.params.id, shopId } });
  if (!existing) throw notFound('Product');
  let body = parse(ProductBody.partial().omit({ openingStock: true, batchNumber: true, expiryDate: true }), req.body);
  // Store keepers may only edit descriptive fields, not prices.
  if (req.user!.role === 'STORE_KEEPER') {
    const { name, barcode, hsnCode, storageLocation, lowStockThreshold, unit } = body;
    body = { name, barcode, hsnCode, storageLocation, lowStockThreshold, unit };
  }
  const { availability, branches: _b, ...data } = body;
  const product = await prisma.$transaction(async (tx) => {
    await tx.product.update({
      where: { id: existing.id },
      data: {
        ...data,
        ...(data.barcode !== undefined && { barcode: data.barcode || null }),
        ...(availability && { branchScope: availability === 'all_branches' ? BranchScope.ALL : BranchScope.SPECIFIC }),
      },
    });
    await writeBranches(tx, existing.id, shopId, branchId, body);
    return tx.product.findUniqueOrThrow({ where: { id: existing.id }, include });
  });
  res.json(present(product, branchId));
});

productRouter.delete('/:id', requirePermission('products.manage'), async (req, res) => {
  const shopId = shopIdOf(req);
  const p = await prisma.product.findFirst({ where: { id: req.params.id, shopId } });
  if (!p) throw notFound('Product');
  const used = await prisma.billItem.count({ where: { productId: p.id } });
  if (used > 0) {
    await prisma.product.update({ where: { id: p.id }, data: { isActive: false } });
    res.json({ ok: true, archived: true });
    return;
  }
  await prisma.product.delete({ where: { id: p.id } });
  res.json({ ok: true });
});

/** Bulk import (client parses the Excel). Skips rows whose name or barcode already exist. */
productRouter.post('/import', requirePermission('products.manage'), async (req, res) => {
  const shopId = shopIdOf(req);
  const rows = parse(
    z.array(z.object({ name: z.string().trim().min(1), category: optStr, barcode: optStr, hsnCode: optStr, basePrice: z.coerce.number().min(0), maxPrice: z.coerce.number().nullish(), gstPercent: z.coerce.number().default(0) })),
    req.body,
  );
  const existing = await prisma.product.findMany({ where: { shopId }, select: { name: true, barcode: true } });
  const names = new Set(existing.map((e) => e.name.toLowerCase()));
  const codes = new Set(existing.map((e) => e.barcode).filter(Boolean));
  let imported = 0;
  let skipped = 0;
  for (const r of rows) {
    if (names.has(r.name.toLowerCase()) || (r.barcode && codes.has(r.barcode))) {
      skipped++;
      continue;
    }
    let categoryId: string | undefined;
    if (r.category) {
      const c = await prisma.category.upsert({ where: { shopId_name: { shopId, name: r.category } }, create: { shopId, name: r.category }, update: {} });
      categoryId = c.id;
    }
    await prisma.product.create({ data: { shopId, name: r.name, barcode: r.barcode || null, hsnCode: r.hsnCode, basePrice: r.basePrice, maxPrice: r.maxPrice, gstPercent: r.gstPercent, categoryId } });
    names.add(r.name.toLowerCase());
    if (r.barcode) codes.add(r.barcode);
    imported++;
  }
  res.json({ imported, skipped });
});
