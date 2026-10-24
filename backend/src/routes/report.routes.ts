import { Request, Router } from 'express';
import { branchIdOf, requirePermission, shopIdOf } from '../middleware/auth';
import {
  branchSales, businessSummary, customerOutstanding, customerSales, gstSummary,
  inventoryValuation, purchaseReport, ReportFilter, salesMatrix, userSales,
} from '../services/report.service';
import { customerLedger } from '../services/ledger.service';
import { prisma } from '../lib/prisma';
import { notFound } from '../lib/errors';

export const reportRouter = Router();
reportRouter.use(requirePermission('reports.view', 'reports.export'));

const startOfDay = (d: Date) => new Date(d.getFullYear(), d.getMonth(), d.getDate());
const endOfDay = (d: Date) => new Date(d.getFullYear(), d.getMonth(), d.getDate(), 23, 59, 59, 999);

/** Resolve ?preset=today|yesterday|week|month|last_month or ?from=&to= into a range. */
export function resolveRange(q: Request['query']): { from: Date; to: Date } {
  const now = new Date();
  switch (q.preset) {
    case 'yesterday': {
      const y = new Date(now.getTime() - 86_400_000);
      return { from: startOfDay(y), to: endOfDay(y) };
    }
    case 'last7':
      return { from: startOfDay(new Date(now.getTime() - 6 * 86_400_000)), to: endOfDay(now) };
    case 'week': {
      const s = new Date(now);
      s.setDate(now.getDate() - ((now.getDay() + 6) % 7));
      return { from: startOfDay(s), to: endOfDay(now) };
    }
    case 'month':
      return { from: new Date(now.getFullYear(), now.getMonth(), 1), to: endOfDay(now) };
    case 'last_month':
      return { from: new Date(now.getFullYear(), now.getMonth() - 1, 1), to: endOfDay(new Date(now.getFullYear(), now.getMonth(), 0)) };
  }
  return {
    from: q.from ? startOfDay(new Date(q.from as string)) : startOfDay(now),
    to: q.to ? endOfDay(new Date(q.to as string)) : endOfDay(now),
  };
}

async function filter(req: Request): Promise<ReportFilter> {
  const shopId = shopIdOf(req);
  const all = req.query.branch === 'all';
  const restricted = req.user!.role === 'SALESMAN';
  return {
    shopId,
    ...resolveRange(req.query),
    branchId: all ? undefined : await branchIdOf(req),
    userId: restricted ? req.user!.id : (req.query.userId as string) || undefined,
    customerId: (req.query.customerId as string) || undefined,
  };
}

reportRouter.get('/summary', async (req, res) => {
  res.json(await businessSummary(await filter(req), (req.query.bucket as any) ?? 'auto'));
});
reportRouter.get('/sales-matrix', async (req, res) => {
  res.json(await salesMatrix(await filter(req)));
});
reportRouter.get('/customer-sales', async (req, res) => {
  res.json(await customerSales(await filter(req)));
});
reportRouter.get('/customer-ledger/:customerId', async (req, res) => {
  const shopId = shopIdOf(req);
  const c = await prisma.customer.findFirst({ where: { id: req.params.customerId, shopId } });
  if (!c) throw notFound('Customer');
  const { from, to } = resolveRange(req.query);
  res.json(await customerLedger(c.id, req.query.sinceRegistration === 'true' ? undefined : from, to));
});
reportRouter.get('/outstanding', async (req, res) => {
  res.json(await customerOutstanding(shopIdOf(req), (req.query.filter as any) ?? 'all'));
});
reportRouter.get('/user-sales', async (req, res) => {
  res.json(await userSales(await filter(req)));
});
reportRouter.get('/inventory', async (req, res) => {
  const all = req.query.branch === 'all';
  res.json(await inventoryValuation(shopIdOf(req), all ? undefined : await branchIdOf(req), (req.query.location as string) || undefined));
});
reportRouter.get('/gst', async (req, res) => {
  res.json(await gstSummary(await filter(req)));
});
reportRouter.get('/purchases', async (req, res) => {
  res.json(await purchaseReport(await filter(req)));
});
reportRouter.get('/branch-sales', async (req, res) => {
  res.json(await branchSales(await filter(req)));
});
