import { Router } from 'express';
import { z } from 'zod';
import { prisma } from '../lib/prisma';
import { parse } from '../lib/validate';
import { branchIdOf, requirePermission, shopIdOf } from '../middleware/auth';
import { badRequest, notFound } from '../lib/errors';
import { round2 } from '../lib/money';
import { moveStock } from '../services/stock.service';
import { nextSequence } from '../lib/sequence';
import { logActivity } from '../lib/activity';

export const returnRouter = Router();

returnRouter.get('/', requirePermission('bills.view'), async (req, res) => {
  res.json(await prisma.returnNote.findMany({ where: { shopId: shopIdOf(req) }, orderBy: { createdAt: 'desc' }, take: 300 }));
});

const Body = z.object({
  customerId: z.string().uuid().nullish(),
  billId: z.string().nullish(),
  condition: z.enum(['good', 'damaged', 'old_stock']),
  settlement: z.enum(['cash_refund', 'account_credit']),
  items: z.array(z.object({ productId: z.string().uuid(), quantity: z.coerce.number().positive(), price: z.coerce.number().min(0) })).min(1),
});

/** Customer return note. Good items are restocked; damaged / old stock are only logged. */
returnRouter.post('/', requirePermission('bills.create'), async (req, res) => {
  const shopId = shopIdOf(req);
  const branchId = await branchIdOf(req);
  const body = parse(Body, req.body);
  if (body.settlement === 'account_credit' && !body.customerId) throw badRequest('Select a customer for account credit');
  const user = req.user!;

  const note = await prisma.$transaction(async (tx) => {
    const customer = body.customerId ? await tx.customer.findFirst({ where: { id: body.customerId, shopId } }) : null;
    if (body.customerId && !customer) throw notFound('Customer');
    const products = await tx.product.findMany({ where: { shopId, id: { in: body.items.map((i) => i.productId) } } });
    const byId = new Map(products.map((p) => [p.id, p]));
    const items = body.items.map((i) => {
      const p = byId.get(i.productId);
      if (!p) throw badRequest(`Product ${i.productId} not found`);
      return { ...i, productName: p.name };
    });
    const total = round2(items.reduce((s, i) => s + i.quantity * i.price, 0));
    const d = new Date();
    const day = `${d.getFullYear()}${String(d.getMonth() + 1).padStart(2, '0')}${String(d.getDate()).padStart(2, '0')}`;
    const returnNo = `SHOP-RET-${day}-${String(await nextSequence(tx, shopId, `ret:${day}`)).padStart(3, '0')}`;

    for (const i of items) {
      const type = body.condition === 'good' ? 'return_good' : body.condition === 'damaged' ? 'return_damage' : 'return_old_stock';
      const ctx = { shopId, branchId, userId: user.id, userName: user.name, refType: 'return', refId: returnNo, note: `Customer Return (${body.condition}) ${returnNo}` };
      if (body.condition === 'good') {
        await moveStock(tx, ctx, i.productId, i.productName, i.quantity, type);
      } else {
        // Logged in the ledger with zero stock effect ("Excluded from Stock").
        await moveStock(tx, { ...ctx, note: `${ctx.note} – ${i.quantity} units excluded from stock` }, i.productId, i.productName, 0, type);
      }
    }
    if (customer && body.settlement === 'account_credit') {
      await tx.customer.update({ where: { id: customer.id }, data: { currentBalance: { decrement: total } } });
    }
    return tx.returnNote.create({
      data: { shopId, branchId, returnNo, customerId: customer?.id, billId: body.billId, condition: body.condition, settlement: body.settlement, totalAmount: total, items, userId: user.id, userName: user.name },
    });
  });
  await logActivity(user, 'return_created', `Return ${note.returnNo} – ₹${note.totalAmount}`);
  res.status(201).json(note);
});
