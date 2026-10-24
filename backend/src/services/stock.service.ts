import { Tx } from '../lib/prisma';
import { num, round3 } from '../lib/money';

export interface BatchAllocation {
  batchId: string;
  qty: number;
}

export interface MoveCtx {
  shopId: string;
  branchId: string;
  userId?: string;
  userName?: string;
  refType?: string;
  refId?: string;
  note?: string;
}

/** Ensure a ProductBranch row exists and return current stock. */
async function ensureRow(tx: Tx, productId: string, branchId: string) {
  return tx.productBranch.upsert({
    where: { productId_branchId: { productId, branchId } },
    create: { productId, branchId, stock: 0 },
    update: {},
  });
}

/**
 * Apply a signed stock change for a product in a branch and append to the stock ledger.
 * Negative stock is allowed (POS must never block a sale), reports flag it.
 */
export async function moveStock(
  tx: Tx,
  ctx: MoveCtx,
  productId: string,
  productName: string,
  delta: number,
  type: string,
) {
  await ensureRow(tx, productId, ctx.branchId);
  const row = await tx.productBranch.update({
    where: { productId_branchId: { productId, branchId: ctx.branchId } },
    data: { stock: { increment: delta } },
  });
  await tx.stockMovement.create({
    data: {
      shopId: ctx.shopId,
      branchId: ctx.branchId,
      productId,
      productName,
      type,
      quantity: delta,
      balanceAfter: row.stock,
      refType: ctx.refType,
      refId: ctx.refId,
      note: ctx.note,
      userId: ctx.userId,
      userName: ctx.userName,
    },
  });
  return num(row.stock);
}

/** Set absolute stock (manual correction). */
export async function setStock(tx: Tx, ctx: MoveCtx, productId: string, productName: string, target: number) {
  const row = await ensureRow(tx, productId, ctx.branchId);
  const delta = round3(target - num(row.stock));
  if (delta === 0) return target;
  return moveStock(tx, ctx, productId, productName, delta, 'manual_correction');
}

/** Consume batches FIFO (earliest expiry first, then oldest). Returns what was taken. */
export async function consumeBatches(
  tx: Tx,
  shopId: string,
  branchId: string,
  productId: string,
  qty: number,
): Promise<BatchAllocation[]> {
  if (qty <= 0) return [];
  const batches = await tx.stockBatch.findMany({
    where: { shopId, branchId, productId, remainingQuantity: { gt: 0 } },
    orderBy: [{ expiryDate: { sort: 'asc', nulls: 'last' } }, { createdAt: 'asc' }],
  });
  const out: BatchAllocation[] = [];
  let left = qty;
  for (const b of batches) {
    if (left <= 0) break;
    const take = Math.min(left, num(b.remainingQuantity));
    await tx.stockBatch.update({ where: { id: b.id }, data: { remainingQuantity: { decrement: take } } });
    out.push({ batchId: b.id, qty: take });
    left = round3(left - take);
  }
  return out;
}

export async function restoreBatches(tx: Tx, allocations: BatchAllocation[] | null | undefined) {
  for (const a of allocations ?? []) {
    await tx.stockBatch.updateMany({ where: { id: a.batchId }, data: { remainingQuantity: { increment: a.qty } } });
  }
}

/** Create an inward batch and add stock. */
export async function inwardBatch(
  tx: Tx,
  ctx: MoveCtx,
  p: {
    productId: string;
    productName: string;
    quantity: number;
    batchNumber?: string | null;
    expiryDate?: Date | null;
    purchasePrice?: number | null;
    location?: string | null;
    purchaseId?: string | null;
    type?: string;
  },
) {
  const batchNumber = p.batchNumber?.trim() || autoBatchNumber();
  const batch = await tx.stockBatch.create({
    data: {
      shopId: ctx.shopId,
      branchId: ctx.branchId,
      productId: p.productId,
      batchNumber,
      inwardQuantity: p.quantity,
      remainingQuantity: p.quantity,
      purchasePrice: p.purchasePrice ?? undefined,
      expiryDate: p.expiryDate ?? undefined,
      location: p.location ?? undefined,
      purchaseId: p.purchaseId ?? undefined,
      notes: ctx.note,
    },
  });
  await moveStock(tx, { ...ctx, note: ctx.note ?? `Batch: ${batchNumber}` }, p.productId, p.productName, p.quantity, p.type ?? 'inward_batch');
  return batch;
}

/** B-yyMMdd-HHmm style auto batch number (matches "Auto-Generate Date Batch"). */
export function autoBatchNumber(d = new Date()) {
  const p = (n: number) => String(n).padStart(2, '0');
  return `B-${String(d.getFullYear()).slice(2)}${p(d.getMonth() + 1)}${p(d.getDate())}-${p(d.getHours())}${p(d.getMinutes())}`;
}
