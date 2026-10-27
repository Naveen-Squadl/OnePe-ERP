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
    body: { shopName: `Test Shop ${tag}`, ownerName: 'Owner', email: `owner-${tag}@test.local`, password: 'Password1', plan: 'BASIC', shopType: 'RESTAURANT' },
  });
  assert.equal(shop.status, 201, JSON.stringify(shop.json));
  shopId = shop.json.id;
  admin = await login(`owner-${tag}@test.local`, 'Password1');
  await api('/shop', admin, { method: 'PUT', body: { settings: { features: { loyalty: true }, loyaltyPointsRatio: 100 } } });
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

test('full sale lifecycle: credit sale, payment, locked edit/delete, cancel, restore', async () => {
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

  // A completed bill is never edited or deleted.
  const edit = await api('/bills/checkout', admin, {
    body: { id: billId, editing: true, customerId, items: [{ productId: prod.json.id, quantity: 1 }], paymentMethod: 'CASH', receivedAmount: 100, giveChange: false },
  });
  assert.equal(edit.status, 409);
  assert.equal((await api(`/bills/${billId}`, admin, { method: 'DELETE' })).status, 409);
  assert.equal((await api(`/bills/${billId}/permanent`, admin, { method: 'DELETE' })).status, 409);
  assert.equal((await api(`/products/${prod.json.id}`, admin)).json.stock, 17);

  // Ledger agrees with the live balance.
  let cust = (await api(`/customers/${customerId}`, admin)).json;
  assert.equal(cust.currentBalance, 100);
  const ledger = (await api(`/customers/${customerId}/ledger`, admin)).json;
  assert.equal(ledger.closing, cust.currentBalance);

  // Cancel needs a reason; it reverts stock + balance. Restore (admin) re-applies.
  assert.equal((await api(`/bills/${billId}/cancel`, admin, { body: {} })).status, 400);
  const cancelled = await api(`/bills/${billId}/cancel`, admin, { body: { reason: 'Wrong item' } });
  assert.equal(cancelled.json.cancelReason, 'Wrong item');
  assert.equal((await api(`/products/${prod.json.id}`, admin)).json.stock, 20);
  assert.equal((await api(`/customers/${customerId}`, admin)).json.currentBalance, -115);
  await api(`/bills/${billId}/restore`, admin, { body: {} });
  assert.equal((await api(`/products/${prod.json.id}`, admin)).json.stock, 17);
  cust = (await api(`/customers/${customerId}`, admin)).json;
  assert.equal(cust.currentBalance, 100);

  // Batches follow the same path.
  const batches = (await api('/stock/batches', admin)).json;
  assert.equal(batches.reduce((s: number, b: any) => s + b.remainingQuantity, 0), 17);

  // Waiting orders (not billed yet) can be deleted, then removed for good.
  const parked = randomUUID();
  await api('/bills/checkout', admin, { body: { id: parked, status: 'WAITING', items: [{ productId: prod.json.id, quantity: 1 }] } });
  assert.equal((await api(`/bills/${parked}/cancel`, admin, { body: { reason: 'x' } })).status, 409);
  await api(`/bills/${parked}`, admin, { method: 'DELETE' });
  const deleted = (await api('/bills?deleted=true', admin)).json;
  assert.ok(deleted.some((b: any) => b.id === parked));
  assert.equal((await api(`/bills/${parked}/permanent`, admin, { method: 'DELETE' })).status, 200);
  assert.equal((await api(`/products/${prod.json.id}`, admin)).json.stock, 17);
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
  assert.equal(summary.netSales, 355); // 315 credit sale (kept – completed bills are never deleted) + 40
  assert.equal(summary.expenses, 15);
  assert.equal(summary.netCollection, 240); // 100 + 40 received on sales + 115 customer payment − 15 expense
  const matrix = (await api('/reports/sales-matrix?preset=today', admin)).json;
  assert.ok(matrix.items.some((i: any) => i.name === 'Tea' && i.qty === 2));

  // Offline bills: pushed with their sale date; re-pushing (lost reply / re-imported backup file) is a no-op,
  // also after the bill was cancelled. Invalid bills report their id.
  const yesterday = new Date(Date.now() - 86_400_000);
  const offline = { id: randomUUID(), billDate: yesterday.toISOString(), items: [{ productId: prod.id, quantity: 1 }], receivedAmount: 20 };
  const bad = { id: randomUUID(), items: [] };
  const push = (await api('/sync/push', admin, { body: { bills: [offline, bad] } })).json;
  assert.equal(push.results[0].ok, true);
  assert.equal(push.results[0].duplicate, undefined);
  assert.ok(push.results[0].billNo.includes(yesterday.toISOString().slice(0, 10).replaceAll('-', '')), push.results[0].billNo);
  assert.deepEqual([push.results[1].id, push.results[1].ok], [bad.id, false]);
  await api(`/bills/${offline.id}/cancel`, admin, { body: { reason: 'Test' } });
  const again = (await api('/sync/push', admin, { body: { bills: [offline] } })).json;
  assert.deepEqual([again.results[0].ok, again.results[0].duplicate, again.results[0].billNo], [true, true, push.results[0].billNo]);
  assert.equal((await api(`/products/${prod.id}`, admin)).json.stock, 98);

  // Prices: always the item price – a price sent by the counter (or a legacy 'last' / 'max' option) is ignored;
  // variable-price products take the entered price; an offline bill keeps its receipt price and is logged.
  const loose = (await api('/products', admin, { body: { name: 'Loose Sweets', basePrice: 1, isPriceVariable: true, trackStock: false } })).json;
  const priced = await api('/bills/checkout', admin, {
    body: { id: randomUUID(), items: [{ productId: prod.id, quantity: 1, soldPrice: 5, priceType: 'custom' }, { productId: prod.id, quantity: 1, priceType: 'last' }, { productId: loose.id, quantity: 1, soldPrice: 75, priceType: 'custom' }] },
  });
  assert.equal(priced.status, 201, JSON.stringify(priced.json));
  assert.deepEqual(priced.json.items.map((i: any) => i.soldPrice).sort(), [20, 20, 75]);
  const offlinePriced = { id: randomUUID(), items: [{ productId: prod.id, quantity: 1, soldPrice: 18 }] };
  const op = (await api('/sync/push', admin, { body: { bills: [offlinePriced] } })).json;
  assert.equal(op.results[0].ok, true);
  assert.equal((await api(`/bills/${offlinePriced.id}`, admin)).json.items[0].soldPrice, 18);
  const log = await prisma.activityLog.findFirst({ where: { shopId, action: 'offline_price_difference' } });
  assert.match(log!.description, /Tea sold at ₹18 \(item price now ₹20\)/);

  // Customer name is optional: a mobile number is enough (but one of them is needed).
  const byPhone = await api('/customers', admin, { body: { phone: '9000000001' } });
  assert.equal(byPhone.status, 201, JSON.stringify(byPhone.json));
  assert.equal(byPhone.json.name, '');
  assert.equal((await api('/customers', admin, { body: {} })).status, 400);
  const quick = await api('/bills/checkout', admin, { body: { id: randomUUID(), customerPhone: '9000000002', items: [{ productId: prod.id, quantity: 1 }] } });
  assert.equal(quick.json.customerName, null);
  assert.equal(quick.json.customerContact, '9000000002');
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
  // Tile thumbnail is generated on first request, then served as a file.
  for (let i = 0; i < 2; i++) {
    const thumb = await fetch(`${base}${url}.thumb.webp`);
    assert.equal(thumb.status, 200);
    assert.equal(thumb.headers.get('content-type'), 'image/webp');
  }
  assert.equal((await fetch(`${base}${url.replace('.png', '-missing.png')}.thumb.webp`)).status, 404);
  assert.equal((await fetch(`${base}/uploads/..%2F..%2Fpackage.json.thumb.webp`)).status, 404);
  const prod = await api('/products', admin, { body: { name: 'Photo Cake', basePrice: 10, imageUrl: url } });
  assert.equal(prod.json.imageUrl, url);
  const bad = new FormData();
  bad.append('file', new Blob(['hello'], { type: 'text/plain' }), 'x.txt');
  assert.equal((await fetch(`${base}/api/uploads`, { method: 'POST', headers: { authorization: `Bearer ${admin}` }, body: bad })).status, 400);
});

test('business type features: defaults, admin switches, enforcement', async () => {
  let shop = (await api('/shop', admin)).json;
  assert.equal(shop.shopType, 'RESTAURANT');
  assert.deepEqual([shop.features.kot, shop.features.tables, shop.features.loyalty, shop.features.barcode], [true, true, true, false]);

  // Services: no KOT / tables / batches at all, stock and purchases off by default.
  shop = (await api('/shop', admin, { method: 'PUT', body: { shopType: 'SERVICES' } })).json;
  assert.deepEqual([shop.features.kot, shop.features.tables, shop.features.stock, shop.features.purchases], [false, false, false, false]);
  assert.equal((await api('/purchases', admin)).status, 403);
  assert.equal((await api('/suppliers', admin)).status, 403);
  const prod = (await api('/products', admin, { body: { name: `Haircut ${tag}`, basePrice: 200, trackStock: false } })).json;
  assert.equal((await api('/stock/adjust', admin, { body: { productId: prod.id, mode: 'set', quantity: 1 } })).status, 403);
  const waiting = (await api('/bills/checkout', admin, { body: { id: randomUUID(), status: 'WAITING', items: [{ productId: prod.id, quantity: 1 }] } })).json;
  assert.equal((await api(`/bills/${waiting.id}/kot`, admin, { body: {} })).status, 403);

  // Switching a feature on (admin only) and credit off.
  shop = (await api('/shop', admin, { method: 'PUT', body: { settings: { features: { purchases: true, credit: false } } } })).json;
  assert.deepEqual([shop.features.purchases, shop.features.credit], [true, false]);
  assert.equal((await api('/purchases', admin)).status, 200);
  const due = await api('/bills/checkout', admin, {
    body: { id: randomUUID(), customerPhone: '9000000003', items: [{ productId: prod.id, quantity: 1 }], paymentMethod: 'CASH', receivedAmount: 50, giveChange: false },
  });
  assert.equal(due.status, 400);
  assert.match(due.json.error, /credit is turned off/);
  // KOT is not available for Services even when switched on.
  shop = (await api('/shop', admin, { method: 'PUT', body: { settings: { features: { kot: true } } } })).json;
  assert.equal(shop.features.kot, false);
  assert.deepEqual([shop.features.purchases, shop.features.credit], [true, false]); // earlier switches kept
});

test('history panels: dated lists of payments, activity and customer bills', async () => {
  const today = new Date();
  const start = new Date(today.getFullYear(), today.getMonth(), today.getDate()).toISOString();
  const end = new Date(today.getFullYear(), today.getMonth(), today.getDate(), 23, 59, 59).toISOString();
  const yesterday = new Date(Date.now() - 86_400_000).toISOString();

  // Customers → History: customer events only (added / edited …), not payments.
  const asha = (await api('/customers?q=9123456789', admin)).json[0];
  await api(`/customers/${asha.id}`, admin, { method: 'PUT', body: { name: 'Asha K' } });
  const events = (await api(`/customers/activity?from=${start}&to=${end}`, admin)).json;
  assert.ok(events.some((e: any) => e.action === 'customer_updated' && /name Asha → Asha K/.test(e.description)), JSON.stringify(events));
  assert.ok(events.every((e: any) => e.action.startsWith('customer_') || /advance/i.test(e.description)));
  assert.equal((await api(`/customers/activity?from=2000-01-01&to=2000-01-02`, admin)).json.length, 0);

  const sup = (await api(`/suppliers/payments?from=${start}&to=${end}`, admin)).json;
  assert.ok(Array.isArray(sup));

  const activity = (await api(`/shop/activity?from=${start}&to=${end}`, admin)).json;
  assert.ok(activity.some((a: any) => a.action === 'bill_cancelled'));

  const customer = asha.id;
  assert.ok((await api(`/customers/${customer}/bills?from=${start}&to=${end}`, admin)).json.length >= 1);
  assert.equal((await api(`/customers/${customer}/bills?from=2000-01-01&to=${yesterday.slice(0, 4)}-01-01`, admin)).json.length, 0);
});

test('opening balance is set only when a customer is created', async () => {
  const c = (await api('/customers', admin, { body: { name: 'Opening Test', phone: '9000000009', openingBalance: 250 } })).json;
  assert.deepEqual([c.openingBalance, c.currentBalance], [250, 250]);
  const change = await api(`/customers/${c.id}`, admin, { method: 'PUT', body: { name: 'Renamed', openingBalance: 999 } });
  assert.equal(change.status, 400);
  assert.match(change.json.error, /only be set when the customer is created/);
  const edit = await api(`/customers/${c.id}`, admin, { method: 'PUT', body: { name: 'Renamed', openingBalance: 250 } }); // unchanged value is fine
  assert.equal(edit.status, 200);
  assert.deepEqual([edit.json.name, edit.json.openingBalance, edit.json.currentBalance], ['Renamed', 250, 250]);
});

test('customer advance: take, use (full / part / with credit off), keep change, refund', async () => {
  // The shop is Services with customer credit switched off at this point (earlier test) – advances must still work.
  const svc = (await api('/products', admin, { body: { name: `Spa ${tag}`, basePrice: 300, trackStock: false } })).json;
  const c = (await api('/customers', admin, { body: { name: 'Advance Test', phone: '9000000010' } })).json;
  const bal = async () => (await api(`/customers/${c.id}`, admin)).json.currentBalance;

  await api(`/customers/${c.id}/payments`, admin, { body: { amount: 500, method: 'UPI' } });
  assert.equal(await bal(), -500);
  assert.ok((await api('/customers?filter=advance', admin)).json.some((x: any) => x.id === c.id));

  // Fully from advance.
  const b1 = (await api('/bills/checkout', admin, { body: { id: randomUUID(), customerId: c.id, items: [{ productId: svc.id, quantity: 1 }], paymentMethod: 'ADVANCE' } })).json;
  assert.deepEqual([b1.advanceUsed, b1.receivedAmount, b1.paymentMethod], [300, 0, 'ADVANCE']);
  assert.equal(await bal(), -200);
  // Not enough advance for a full ADVANCE bill.
  const short = await api('/bills/checkout', admin, { body: { id: randomUUID(), customerId: c.id, items: [{ productId: svc.id, quantity: 1 }], paymentMethod: 'ADVANCE' } });
  assert.equal(short.status, 400);
  assert.match(short.json.error, /collect the remaining 100/);
  // Part advance + cash (credit is off: allowed because the advance covers the rest).
  const b2 = (await api('/bills/checkout', admin, { body: { id: randomUUID(), customerId: c.id, items: [{ productId: svc.id, quantity: 1 }], paymentMethod: 'CASH', receivedAmount: 100, giveChange: false } })).json;
  assert.deepEqual([b2.advanceUsed, b2.receivedAmount], [200, 100]);
  assert.equal(await bal(), 0);
  // Credit off and no advance left → short payment refused.
  const due = await api('/bills/checkout', admin, { body: { id: randomUUID(), customerId: c.id, items: [{ productId: svc.id, quantity: 1 }], paymentMethod: 'CASH', receivedAmount: 100, giveChange: false } });
  assert.equal(due.status, 400);
  // Keep change as advance.
  await api('/bills/checkout', admin, { body: { id: randomUUID(), customerId: c.id, items: [{ productId: svc.id, quantity: 1 }], paymentMethod: 'CASH', receivedAmount: 500, giveChange: false } });
  assert.equal(await bal(), -200);

  // Refund part of the advance; more than available is refused.
  const ref = await api(`/customers/${c.id}/refunds`, admin, { body: { amount: 150, method: 'CASH' } });
  assert.equal(ref.status, 201, JSON.stringify(ref.json));
  assert.match(ref.json.payment.receiptNo, /^REF-/);
  assert.equal(await bal(), -50);
  assert.equal((await api(`/customers/${c.id}/refunds`, admin, { body: { amount: 100 } })).status, 400);

  const ledger = (await api(`/customers/${c.id}/ledger`, admin)).json;
  const text = ledger.entries.map((e: any) => e.description).join(' | ');
  assert.match(text, /Advance Received \(UPI\)/);
  assert.match(text, /₹300 paid from advance/);
  assert.match(text, /₹200 kept as advance/);
  assert.match(text, /Advance Refunded \(CASH\)/);
  assert.equal(ledger.closing, -50);

  // Customers → History lists the advance events (not plain payments of dues).
  const events = (await api('/customers/activity', admin)).json.map((e: any) => e.description).join(' | ');
  assert.match(events, /Advance of ₹500 received via UPI from Advance Test/);
  assert.match(events, /₹200 change kept as advance on bill .* for Advance Test/);
  assert.match(events, /Advance of ₹150 refunded via CASH to Advance Test/);
});

test('customers are archived, never deleted', async () => {
  const today = new Date();
  const range = `from=${new Date(today.getFullYear(), today.getMonth(), today.getDate()).toISOString()}&to=${new Date(today.getFullYear(), today.getMonth(), today.getDate(), 23, 59, 59).toISOString()}`;
  const c = (await api('/customers', admin, { body: { name: 'Archive Test', phone: '9000000020' } })).json;
  // Advance → refused; refund it, then archiving works.
  await api(`/customers/${c.id}/payments`, admin, { body: { amount: 80, method: 'CASH' } });
  const refused = await api(`/customers/${c.id}/archive`, admin, { body: {} });
  assert.equal(refused.status, 409);
  assert.match(refused.json.error, /advance – refund it/);
  await api(`/customers/${c.id}/refunds`, admin, { body: { amount: 80 } });
  const before = (await api(`/reports/summary?${range}`, admin)).json.netCollection;
  assert.equal((await api(`/customers/${c.id}`, admin, { method: 'DELETE' })).json.isArchived, true); // DELETE archives
  assert.ok(!(await api('/customers', admin)).json.some((x: any) => x.id === c.id));
  assert.ok((await api('/customers?filter=archived', admin)).json.some((x: any) => x.id === c.id));
  assert.equal((await api(`/reports/summary?${range}`, admin)).json.netCollection, before); // receipts kept
  assert.equal((await api(`/customers/${c.id}/ledger`, admin)).json.entries.length, 2);
  // The database refuses to delete a customer that has payment receipts.
  await assert.rejects(prisma.customer.delete({ where: { id: c.id } }));

  // Restore explicitly, archive again, then adding the same mobile brings the customer back.
  assert.equal((await api(`/customers/${c.id}/restore`, admin, { body: {} })).json.isArchived, false);
  await api(`/customers/${c.id}/archive`, admin, { body: {} });
  assert.equal((await api(`/customers/${c.id}/payments`, admin, { body: { amount: 10 } })).status, 409); // archived: no payments
  const again = await api('/customers', admin, { body: { name: 'Archive Test Again', phone: '9000000020', openingBalance: 999 } });
  assert.equal(again.status, 200);
  assert.deepEqual([again.json.id, again.json.isArchived, again.json.openingBalance, again.json.name], [c.id, false, 0, 'Archive Test Again']);
  assert.equal((await api('/customers', admin, { body: { phone: '9000000020' } })).status, 400); // active duplicate
  // Billing an archived customer's mobile also brings them back.
  await api(`/customers/${c.id}/archive`, admin, { body: {} });
  const svc = (await api('/products', admin, { body: { name: `Wash ${tag}`, basePrice: 50, trackStock: false } })).json;
  await api('/bills/checkout', admin, { body: { id: randomUUID(), customerPhone: '9000000020', items: [{ productId: svc.id, quantity: 1 }], paymentMethod: 'CASH', receivedAmount: 50 } });
  assert.equal((await api(`/customers/${c.id}`, admin)).json.isArchived, false);
});

test('suppliers are archived, never deleted', async () => {
  const s = (await api('/suppliers', admin, { body: { name: `Archive Supplier ${tag}`, openingBalance: 100 } })).json;
  const refused = await api(`/suppliers/${s.id}/archive`, admin, { body: {} });
  assert.equal(refused.status, 409);
  assert.match(refused.json.error, /You owe .* ₹100/);
  await api(`/suppliers/${s.id}/payments`, admin, { body: { amount: 100, method: 'CASH' } });
  assert.equal((await api(`/suppliers/${s.id}`, admin, { method: 'DELETE' })).json.isArchived, true); // DELETE archives
  assert.ok(!(await api('/suppliers', admin)).json.some((x: any) => x.id === s.id));
  assert.ok((await api('/suppliers?filter=archived', admin)).json.some((x: any) => x.id === s.id));
  await assert.rejects(prisma.supplier.delete({ where: { id: s.id } })); // payments keep it
  assert.equal((await api(`/suppliers/${s.id}/restore`, admin, { body: {} })).json.isArchived, false);
});

test('products are archived, never deleted; past bills keep them', async () => {
  const p = (await api('/products', admin, { body: { name: `Archive Item ${tag}`, basePrice: 40, barcode: `AR${tag}`, trackStock: false } })).json;
  const sold = (await api('/bills/checkout', admin, { body: { id: randomUUID(), items: [{ productId: p.id, quantity: 1 }], paymentMethod: 'CASH', receivedAmount: 40 } })).json;
  assert.equal((await api(`/products/${p.id}`, admin, { method: 'DELETE' })).json.isActive, false); // DELETE archives
  assert.ok(await prisma.product.findUnique({ where: { id: p.id } }), 'product row kept');
  assert.ok(!(await api('/products', admin)).json.some((x: any) => x.id === p.id));
  assert.ok((await api('/products?filter=archived', admin)).json.some((x: any) => x.id === p.id));
  assert.equal((await api(`/products/barcode/AR${tag}`, admin)).status, 404); // not scannable
  assert.equal((await api(`/bills/${sold.id}`, admin)).json.items[0].productName, `Archive Item ${tag}`); // past bill intact
  const blocked = await api('/bills/checkout', admin, { body: { id: randomUUID(), items: [{ productId: p.id, quantity: 1 }], paymentMethod: 'CASH', receivedAmount: 40 } });
  assert.equal(blocked.status, 400);
  assert.match(blocked.json.error, /is archived/);
  const reuse = await api('/products', admin, { body: { name: 'Other', basePrice: 1, barcode: `AR${tag}` } });
  assert.equal(reuse.status, 400);
  assert.match(reuse.json.error, /belongs to the archived product/);
  // A never-sold product is archived too (not deleted), and restore brings it back.
  const unsold = (await api('/products', admin, { body: { name: `Unsold ${tag}`, basePrice: 5, trackStock: false } })).json;
  await api(`/products/${unsold.id}/archive`, admin, { body: {} });
  assert.ok(await prisma.product.findUnique({ where: { id: unsold.id } }));
  assert.equal((await api(`/products/${p.id}/restore`, admin, { body: {} })).json.isActive, true);
  assert.equal((await api('/bills/checkout', admin, { body: { id: randomUUID(), items: [{ productId: p.id, quantity: 1 }], paymentMethod: 'CASH', receivedAmount: 40 } })).status, 201);
});

// Runs last: after the bills, payments, cancels, restores and returns above, every customer's stored live balance
// must equal the closing balance of their ledger (the balance is updated in the same transaction as each change).
test('customer live balance always equals the ledger closing balance', async () => {
  const customers = (await api('/customers', admin)).json;
  assert.ok(customers.length >= 3, `expected test customers, got ${customers.length}`);
  for (const c of customers) {
    const ledger = (await api(`/customers/${c.id}/ledger`, admin)).json;
    assert.equal(c.currentBalance, ledger.closing, `${c.name || c.phone}: live ${c.currentBalance} vs ledger ${ledger.closing}`);
  }
  assert.equal((await api('/customers/recalculate', admin, { body: {} })).status, 404); // repair endpoint removed
});
