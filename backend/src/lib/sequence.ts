import { Tx } from './prisma';

/** Atomically increments and returns the next value of a shop-scoped counter. */
export async function nextSequence(tx: Tx, shopId: string, key: string): Promise<number> {
  const row = await tx.sequence.upsert({
    where: { shopId_key: { shopId, key } },
    create: { shopId, key, value: 1 },
    update: { value: { increment: 1 } },
  });
  return row.value;
}

export function yymmdd(d = new Date()): string {
  const p = (n: number) => String(n).padStart(2, '0');
  return `${String(d.getFullYear()).slice(2)}${p(d.getMonth() + 1)}${p(d.getDate())}`;
}

/** Short shop prefix from its name: "Grand Sallon" → "GS", "OnePe Demo Bakery" → "ODB". */
export function shopInitials(name: string): string {
  const words = name.replace(/[^A-Za-z0-9 ]/g, ' ').split(/\s+/).filter(Boolean);
  const initials = words.map((w) => w[0]).join('').toUpperCase().slice(0, 3);
  return initials || 'BL';
}

/** e.g. GS-MAIN-20261013-002 (expense: GS-MAIN-EXP-20261013-001); resets daily per branch. */
export async function nextBillNo(tx: Tx, shopId: string, shopName: string, branchCode: string, kind: 'SALE' | 'EXPENSE', d = new Date()) {
  const p = (n: number) => String(n).padStart(2, '0');
  const day = `${d.getFullYear()}${p(d.getMonth() + 1)}${p(d.getDate())}`;
  const prefix = `${shopInitials(shopName)}-${branchCode}${kind === 'EXPENSE' ? '-EXP' : ''}`;
  const seq = await nextSequence(tx, shopId, `bill:${branchCode}:${kind}:${day}`);
  return `${prefix}-${day}-${String(seq).padStart(3, '0')}`;
}
