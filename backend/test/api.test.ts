/**
 * End-to-end API tests against the dev database. Each run creates a fresh shop through the
 * super admin, so it never touches the demo data.  Run: npm test
 */
import { test, before, after } from 'node:test';
import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';
import type { Server } from 'node:http';
import 'dotenv/config';
import { createApp } from '../src/app';
import { prisma } from '../src/lib/prisma';
import { computeLine, computeTotals } from '../src/services/billing.service';

process.env.NODE_ENV = 'test';
let server: Server;
let base = '';
let admin = '';
let shopId = '';
const tag = Date.now().toString(36);

async function api(path: string, token: string, init: { method?: string; body?: unknown } = {}) {
  const res = await fetch(`${base}/api${path}`, {
    method: init.method ?? (init.body ? 'POST' : 'GET'),
    headers: { 'content-type': 'application/json', ...(token && { authorization: `Bearer ${token}` }) },
    body: init.body ? JSON.stringify(init.body) : undefined,
  });
  const json = await res.json().catch(() => null);
  return { status: res.status, json };
}

const login = async (email: string, password: string) => (await api('/auth/login', '', { body: { email, password } })).json.token as string;

before(async () => {
  server = createApp().listen(0);
  base = `http://127.0.0.1:${(server.address() as any).port}`;
  const su = await login(process.env.SUPERADMIN_EMAIL!, process.env.SUPERADMIN_PASSWORD!);
  const shop = await api('/admin/shops', su, {
    body: { shopName: `Test Shop ${tag}`, ownerName: 'Owner', email: `owner-${tag}@test.local`, password: 'Password1', plan: 'BASIC', shopType: 'BAKERY' },
  });
  assert.equal(shop.status, 201, JSON.stringify(shop.json));
  shopId = shop.json.id;
  admin = await login(`owner-${tag}@test.local`, 'Password1');
  await api('/shop', admin, { method: 'PUT', body: { settings: { enableLoyaltyPoints: true, loyaltyPointsRatio: 100 } } });
});

after(async () => {
  await prisma.shop.delete({ where: { id: shopId } }).catch(() => undefined);
  await prisma.$disconnect();
  server.close();
});

test('pure totals: GST exclusive / inclusive, discounts, loyalty', () => {
  assert.deepEqual(computeLine(2, 100, 0, 5, false), { taxable: 200, gst: 10, lineTotal: 210 });
  assert.deepEqual(computeLine(1, 105, 0, 5, true), { taxable: 100, gst: 5, lineTotal: 105 });
  const t = computeTotals([{ taxableAmount: 200, gstAmount: 10, discount: 0 }], 'percent', 10, 5);
  assert.equal(t.discount, 21);
  assert.equal(t.total, 184);
  const r = computeTotals([{ taxableAmount: 435.6, gstAmount: 0, discount: 0 }], 'flat', 0, 0, 'down');
  assert.equal(r.total, 435);
  assert.equal(r.roundOff, -0.6);
  const u = computeTotals([{ taxableAmount: 435.6, gstAmount: 0, discount: 0 }], 'flat', 0, 0, 'up');
  assert.equal(u.total, 436);
  assert.equal(u.roundOff, 0.4);
});

test('full sale lifecycle: credit sale, payment, edit, cancel, restore, delete', async () => {
  const cat = (await api('/categories', admin, { body: { name: 'Cakes' } })).json;
  const prod = await api('/products', admin, {
    body: { name: 'Plum Cake', categoryId: cat.id, basePrice: 100, gstPercent: 5, barcode: `PC${tag}`, openingStock: 20, expiryDate: new Date(Date.now() + 86_400_000).toISOString() },
  });
  assert.equal(prod.status, 201, JSON.stringify(prod.json));
  assert.equal(prod.json.stock, 20);

  const byCode = await api(`/products/barcode/PC${tag}`, admin);
  assert.equal(byCode.json.id, prod.json.id);

  // Credit sale to a new customer captured by phone: 3 × 100 + 5% GST = 315, pays 100.
  const billId = randomUUID();
  const sale = await api('/bills/checkout', admin, {
    body: { id: billId, customerPhone: '9123456789', customerName: 'Asha', items: [{ productId: prod.json.id, quantity: 3 }], paymentMethod: 'CASH', receivedAmount: 100, giveChange: false },
  });
  assert.equal(sale.status, 201, JSON.stringify(sale.json));
  assert.equal(sale.json.totalAmount, 315);
  assert.equal(sale.json.customerClosingBal, 215);
  assert.equal(sale.json.loyaltyPointsEarned, 3);
  assert.match(sale.json.billNo, /^[A-Z0-9]{2,3}-MAIN-\d{8}-\d{3}$/);
  const customerId = sale.json.customerId;

  // Replaying the same bill id (offline retry) is idempotent.
  const replay = await api('/bills/checkout', admin, { body: { id: billId, items: [{ productId: prod.json.id, quantity: 3 }] } });
  assert.equal(replay.json.billNo, sale.json.billNo);
  assert.equal((await api(`/products/${prod.json.id}`, admin)).json.stock, 17);

  // Customer pays 115 → balance 100.
  const pay = await api(`/customers/${customerId}/payments`, admin, { body: { amount: 115, method: 'UPI' } });
  assert.equal(pay.json.customer.currentBalance, 100);

  // Edit bill: 3 → 1 unit (105), restocks 2 units and re-computes the balance.
  const edit = await api('/bills/checkout', admin, {
    body: { id: billId, editing: true, customerId, items: [{ productId: prod.json.id, quantity: 1 }], paymentMethod: 'CASH', receivedAmount: 100, giveChange: false },
  });
  assert.equal(edit.json.totalAmount, 105);
  assert.equal(edit.json.billNo, sale.json.billNo);
  assert.equal((await api(`/products/${prod.json.id}`, admin)).json.stock, 19);
  let cust = (await api(`/customers/${customerId}`, admin)).json;
  assert.equal(cust.currentBalance, -110); // 0 + 105 − 100 − 115 payment
  assert.equal(cust.loyaltyPoints, 1);

  // Ledger agrees with the live balance.
  const ledger = (await api(`/customers/${customerId}/ledger`, admin)).json;
  assert.equal(ledger.closing, cust.currentBalance);

  // Cancel reverts stock + balance; restore re-applies.
  await api(`/bills/${billId}/cancel`, admin, { body: {} });
  assert.equal((await api(`/products/${prod.json.id}`, admin)).json.stock, 20);
  assert.equal((await api(`/customers/${customerId}`, admin)).json.currentBalance, -115);
  await api(`/bills/${billId}/restore`, admin, { body: {} });
  assert.equal((await api(`/products/${prod.json.id}`, admin)).json.stock, 19);

  // Soft delete then permanent delete; stock returns once.
  await api(`/bills/${billId}`, admin, { method: 'DELETE' });
  const deleted = (await api('/bills?deleted=true', admin)).json;
  assert.ok(deleted.some((b: any) => b.id === billId));
  await api(`/bills/${billId}/permanent`, admin, { method: 'DELETE' });
  assert.equal((await api(`/products/${prod.json.id}`, admin)).json.stock, 20);

  // Batches were restored too.
  const batches = (await api('/stock/batches', admin)).json;
  assert.equal(batches.reduce((s: number, b: any) => s + b.remainingQuantity, 0), 20);
  cust = (await api(`/customers/${customerId}`, admin)).json;
  assert.equal(cust.currentBalance, -115);
});

test('waiting bills, walk-in validation, expense vouchers, reports', async () => {
  const prod = (await api('/products', admin, { body: { name: 'Tea', basePrice: 20, openingStock: 100 } })).json;

  // Parked table order does not touch stock.
  const tableBill = randomUUID();
  const waiting = await api('/bills/checkout', admin, { body: { id: tableBill, status: 'WAITING', tableName: 'T1', items: [{ productId: prod.id, quantity: 2 }] } });
  assert.equal(waiting.json.status, 'WAITING');
  assert.equal((await api(`/products/${prod.id}`, admin)).json.stock, 100);
  const kot = await api(`/bills/${tableBill}/kot`, admin, { body: {} });
  assert.equal(kot.json.items[0].quantity, 2);
  const done = await api('/bills/checkout', admin, { body: { id: tableBill, tableName: 'T1', items: [{ productId: prod.id, quantity: 2, kotPrintedQuantity: 2 }], receivedAmount: 50 } });
  assert.equal(done.json.changeAmount, 10);
  assert.equal((await api(`/products/${prod.id}`, admin)).json.stock, 98);

  // Walk-in underpayment is rejected.
  const under = await api('/bills/checkout', admin, { body: { id: randomUUID(), items: [{ productId: prod.id, quantity: 1 }], receivedAmount: 5 } });
  assert.equal(under.status, 400);

  // Expense voucher with an ad-hoc line.
  const exp = await api('/bills/checkout', admin, { body: { id: randomUUID(), kind: 'EXPENSE', items: [{ productName: 'Milk supply', quantity: 1, soldPrice: 15 }] } });
  assert.equal(exp.status, 201, JSON.stringify(exp.json));
  assert.match(exp.json.billNo, /-EXP-/);

  const summary = (await api('/reports/summary?preset=today', admin)).json;
  assert.equal(summary.netSales, 40);
  assert.equal(summary.expenses, 15);
  assert.equal(summary.netCollection, 140); // 40 sales + 115 customer payment − 15 expense
  const matrix = (await api('/reports/sales-matrix?preset=today', admin)).json;
  assert.ok(matrix.items.some((i: any) => i.name === 'Tea' && i.qty === 2));
});

test('purchases inward stock & supplier balance; returns; permissions', async () => {
  const prod = (await api('/products', admin, { body: { name: 'Flour 1kg', basePrice: 60 } })).json;
  const po = await api('/purchases', admin, {
    body: { newSupplier: { name: 'Mill Co' }, status: 'PENDING', items: [{ productId: prod.id, quantity: 10, unitPrice: 40, gstPercent: 5 }], amountPaid: 100 },
  });
  assert.equal(po.status, 201, JSON.stringify(po.json));
  assert.equal(po.json.totalAmount, 420);
  assert.equal((await api(`/products/${prod.id}`, admin)).json.stock, 0);
  await api(`/purchases/${po.json.id}/inward`, admin, { body: { location: 'Warehouse' } });
  assert.equal((await api(`/products/${prod.id}`, admin)).json.stock, 10);
  const sup = (await api('/suppliers?q=Mill', admin)).json[0];
  assert.equal(sup.currentBalance, 320);

  const ret = await api('/returns', admin, { body: { condition: 'good', settlement: 'cash_refund', items: [{ productId: prod.id, quantity: 2, price: 60 }] } });
  assert.equal(ret.status, 201);
  assert.match(ret.json.returnNo, /^SHOP-RET-\d{8}-\d{3}$/);
  assert.equal((await api(`/products/${prod.id}`, admin)).json.stock, 12);

  // Cashier: may bill, may not delete bills or manage products.
  const staff = await api('/users', admin, { body: { name: 'Cash', email: `cash-${tag}@test.local`, password: 'secret12', role: 'CASHIER' } });
  assert.equal(staff.status, 201, JSON.stringify(staff.json));
  const cashier = await login(`cash-${tag}@test.local`, 'secret12');
  const b = await api('/bills/checkout', cashier, { body: { id: randomUUID(), items: [{ productId: prod.id, quantity: 1 }] } });
  assert.equal(b.status, 201);
  assert.equal((await api(`/bills/${b.json.id}`, cashier, { method: 'DELETE' })).status, 403);
  assert.equal((await api('/products', cashier, { body: { name: 'X', basePrice: 1 } })).status, 403);

  // Plan limit: BASIC = 4 users (owner + cashier + 2 more ok, 5th rejected).
  for (const i of [1, 2]) await api('/users', admin, { body: { name: `S${i}`, email: `s${i}-${tag}@test.local`, password: 'secret12', role: 'BILLER' } });
  const over = await api('/users', admin, { body: { name: 'S3', email: `s3-${tag}@test.local`, password: 'secret12', role: 'BILLER' } });
  assert.equal(over.status, 400);
  assert.match(over.json.error, /User limit reached/);
});

test('product photo upload is stored and served', async () => {
  // 1x1 transparent PNG
  const png = Buffer.from('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==', 'base64');
  const form = new FormData();
  form.append('file', new Blob([png], { type: 'image/png' }), 'p.png');
  const res = await fetch(`${base}/api/uploads`, { method: 'POST', headers: { authorization: `Bearer ${admin}` }, body: form });
  assert.equal(res.status, 201);
  const { url } = (await res.json()) as { url: string };
  assert.match(url, /^\/uploads\/.+\.png$/);
  const img = await fetch(`${base}${url}`);
  assert.equal(img.status, 200);
  assert.equal(img.headers.get('cross-origin-resource-policy'), 'cross-origin');
  const prod = await api('/products', admin, { body: { name: 'Photo Cake', basePrice: 10, imageUrl: url } });
  assert.equal(prod.json.imageUrl, url);
  const bad = new FormData();
  bad.append('file', new Blob(['hello'], { type: 'text/plain' }), 'x.txt');
  assert.equal((await fetch(`${base}/api/uploads`, { method: 'POST', headers: { authorization: `Bearer ${admin}` }, body: bad })).status, 400);
});
