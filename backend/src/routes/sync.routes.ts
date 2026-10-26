import { BillStatus } from '@prisma/client';
import { Router } from 'express';
import { z } from 'zod';
import { prisma } from '../lib/prisma';
import { parse } from '../lib/validate';
import { branchIdOf, requirePermission, shopIdOf } from '../middleware/auth';
import { CheckoutSchema, checkout } from '../services/billing.service';

export const syncRouter = Router();

/**
 * Delta pull for the offline cache: everything changed since ?since= (ISO).
 * The client stores serverTime and sends it back next time.
 */
syncRouter.get('/pull', async (req, res) => {
  const shopId = shopIdOf(req);
  const branchId = await branchIdOf(req);
  const since = req.query.since ? new Date(req.query.since as string) : new Date(0);
  const serverTime = new Date();
  const changed = { updatedAt: { gt: since } };
  const [shop, branches, categories, products, customers, bills] = await Promise.all([
    prisma.shop.findUniqueOrThrow({ where: { id: shopId } }),
    prisma.branch.findMany({ where: { shopId, ...changed } }),
    prisma.category.findMany({ where: { shopId, ...changed } }),
    prisma.product.findMany({ where: { shopId, OR: [changed, { branches: { some: { branchId, ...changed } } }] }, include: { branches: true } }),
    prisma.customer.findMany({ where: { shopId, ...changed } }),
    prisma.bill.findMany({
      where: { shopId, branchId, ...changed, billDate: { gte: new Date(Date.now() - 7 * 86_400_000) } },
      include: { items: true },
    }),
  ]);
  res.json({ serverTime, shop, branches, categories, products, customers, bills });
});

/**
 * Push bills created while offline. Idempotent per bill id; returns per-bill result.
 * A bill that is already on the server (re-sent after a sync whose reply was lost, or re-imported from a
 * device backup file) counts as ok with `duplicate: true` – including one that was cancelled meanwhile.
 */
syncRouter.post('/push', requirePermission('bills.create'), async (req, res) => {
  const { bills } = parse(z.object({ bills: z.array(z.unknown()).max(500) }), req.body);
  const shopId = shopIdOf(req);
  const branchId = await branchIdOf(req);
  const results: { id?: string; ok: boolean; billNo?: string; duplicate?: boolean; error?: string }[] = [];
  for (const raw of bills) {
    const r = CheckoutSchema.safeParse(raw);
    if (!r.success) {
      const id = (raw as { id?: unknown } | null)?.id;
      results.push({ id: typeof id === 'string' ? id : undefined, ok: false, error: r.error.issues[0]?.message });
      continue;
    }
    try {
      const existing = await prisma.bill.findUnique({ where: { id: r.data.id }, select: { shopId: true, billNo: true, status: true } });
      if (existing && existing.shopId === shopId && existing.status !== BillStatus.WAITING) {
        results.push({ id: r.data.id, ok: true, billNo: existing.billNo, duplicate: true });
        continue;
      }
      const b = await checkout(req.user!, shopId, branchId, r.data);
      results.push({ id: b.id, ok: true, billNo: b.billNo });
    } catch (e) {
      results.push({ id: r.data.id, ok: false, error: (e as Error).message });
    }
  }
  res.json({ results, synced: results.filter((x) => x.ok).length });
});
