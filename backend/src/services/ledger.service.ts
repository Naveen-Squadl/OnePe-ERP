import { BillKind, BillStatus } from '@prisma/client';
import { prisma } from '../lib/prisma';
import { num, round2 } from '../lib/money';

export interface LedgerEntry {
  date: Date;
  ref: string;
  type: 'bill' | 'payment' | 'return';
  description: string;
  debit: number;
  credit: number;
  runningBalance: number;
  billId?: string;
}

const effectiveBill = { status: BillStatus.COMPLETED, kind: BillKind.SALE, isCancelled: false, isDeleted: false };

/** Raw (unsorted) debit/credit events for a customer. */
async function events(customerId: string, from?: Date, to?: Date) {
  const range = from || to ? { gte: from, lte: to } : undefined;
  const [bills, payments, returns] = await Promise.all([
    prisma.bill.findMany({ where: { customerId, ...effectiveBill, billDate: range }, include: { items: true } }),
    prisma.customerPayment.findMany({ where: { customerId, createdAt: range } }),
    prisma.returnNote.findMany({ where: { customerId, settlement: 'account_credit', createdAt: range } }),
  ]);
  const out: Omit<LedgerEntry, 'runningBalance'>[] = [];
  for (const b of bills) {
    const applied = round2(num(b.receivedAmount) - num(b.changeAmount));
    out.push({
      date: b.billDate,
      ref: b.billNo,
      type: 'bill',
      description: b.items.map((i) => `${i.productName} x${num(i.quantity)}`).join(', '),
      debit: num(b.totalAmount),
      credit: applied,
      billId: b.id,
    });
  }
  for (const p of payments) {
    out.push({ date: p.createdAt, ref: p.receiptNo, type: 'payment', description: `Payment Received (${p.method})${p.note ? ` – ${p.note}` : ''}`, debit: 0, credit: num(p.amount) });
  }
  for (const r of returns) {
    out.push({ date: r.createdAt, ref: r.returnNo, type: 'return', description: 'Customer Return (Account Credit)', debit: 0, credit: num(r.totalAmount) });
  }
  return out.sort((a, b) => a.date.getTime() - b.date.getTime());
}

export async function customerLedger(customerId: string, from?: Date, to?: Date) {
  const c = await prisma.customer.findUniqueOrThrow({ where: { id: customerId } });
  let opening = num(c.openingBalance);
  if (from) {
    const before = await events(customerId, undefined, new Date(from.getTime() - 1));
    opening = round2(before.reduce((s, e) => s + e.debit - e.credit, opening));
  }
  const entries = await events(customerId, from, to);
  let running = opening;
  const rows: LedgerEntry[] = entries.map((e) => {
    running = round2(running + e.debit - e.credit);
    return { ...e, runningBalance: running };
  });
  const totalDebit = round2(rows.reduce((s, r) => s + r.debit, 0));
  const totalCredit = round2(rows.reduce((s, r) => s + r.credit, 0));
  return { customer: c, opening, totalDebit, totalCredit, closing: running, entries: rows };
}

/** Recalculate a customer's live balance from scratch (Opening + Bills − Payments − Credits). */
export async function recalculateCustomerBalance(customerId: string) {
  const { closing } = await customerLedger(customerId);
  await prisma.customer.update({ where: { id: customerId }, data: { currentBalance: closing } });
  return closing;
}
