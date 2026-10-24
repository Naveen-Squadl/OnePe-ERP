/**
 * Seeds a super admin and a demo bakery/retail shop with products so the app is usable immediately.
 * Safe to re-run (upserts by email / names).
 */
import 'dotenv/config';
import bcrypt from 'bcryptjs';
import { PrismaClient } from '@prisma/client';

const prisma = new PrismaClient();

async function main() {
  const email = (process.env.SUPERADMIN_EMAIL ?? 'admin@onepe.local').toLowerCase();
  const password = process.env.SUPERADMIN_PASSWORD ?? 'ChangeMe@123';
  await prisma.user.upsert({
    where: { email },
    create: { email, name: 'Super Admin', role: 'SUPER_ADMIN', passwordHash: await bcrypt.hash(password, 10) },
    update: {},
  });
  console.log(`Super admin: ${email} / ${password}`);

  const demoEmail = 'demo@onepe.local';
  if (await prisma.user.findUnique({ where: { email: demoEmail } })) {
    console.log('Demo shop already exists');
    return;
  }
  const shop = await prisma.shop.create({
    data: {
      name: 'OnePe Demo Bakery',
      ownerName: 'Demo Owner',
      ownerEmail: demoEmail,
      address: '12 MG Road, Bengaluru',
      contactNumber: '9876543210',
      shopType: 'BAKERY',
      plan: 'PREMIUM',
      maxUsers: 10,
      maxBranches: 3,
      subscriptionExpiry: new Date(Date.now() + 365 * 86_400_000),
      settings: { enableKot: true, enableLoyaltyPoints: true, loyaltyPointsRatio: 100, tableNames: ['T1', 'T2', 'T3', 'T4', 'T5', 'Parcel'] },
    },
  });
  const branch = await prisma.branch.create({
    data: { shopId: shop.id, name: 'Main Branch', code: 'MAIN', isMain: true, tableNames: ['T1', 'T2', 'T3', 'T4', 'T5', 'Parcel'] },
  });
  await prisma.user.create({
    data: { shopId: shop.id, branchId: branch.id, email: demoEmail, name: 'Demo Owner', role: 'ADMIN', passwordHash: await bcrypt.hash('Demo@1234', 10) },
  });
  await prisma.user.create({
    data: { shopId: shop.id, branchId: branch.id, email: 'cashier@onepe.local', name: 'Counter Cashier', role: 'CASHIER', passwordHash: await bcrypt.hash('Cashier@123', 10) },
  });

  const cats: Record<string, string> = {};
  for (const [i, name] of ['Cakes', 'Pastries', 'Breads', 'Beverages', 'Snacks'].entries()) {
    cats[name] = (await prisma.category.create({ data: { shopId: shop.id, name, sortOrder: i } })).id;
  }
  await prisma.category.create({ data: { shopId: shop.id, name: 'Expenses', isStockCategory: false, isExpenseCategory: true, sortOrder: 99 } });

  const products: [string, string, number, number, string, string][] = [
    ['Black Forest Cake 500g', 'Cakes', 450, 5, '1905', '8901000000011'],
    ['Pineapple Pastry', 'Pastries', 60, 5, '1905', '8901000000028'],
    ['Chocolate Truffle Pastry', 'Pastries', 80, 5, '1905', '8901000000035'],
    ['Butter Croissant', 'Breads', 70, 5, '1905', '8901000000042'],
    ['Milk Bread 400g', 'Breads', 45, 0, '1905', '8901000000059'],
    ['Cappuccino', 'Beverages', 120, 5, '2101', '8901000000066'],
    ['Masala Tea', 'Beverages', 30, 5, '0902', '8901000000073'],
    ['Veg Puff', 'Snacks', 35, 5, '1905', '8901000000080'],
    ['Samosa', 'Snacks', 20, 5, '2106', '8901000000097'],
  ];
  for (const [name, cat, price, gst, hsn, barcode] of products) {
    const p = await prisma.product.create({
      data: { shopId: shop.id, name, categoryId: cats[cat], basePrice: price, maxPrice: price * 1.1, purchasePrice: price * 0.6, gstPercent: gst, hsnCode: hsn, barcode, storageLocation: 'Showroom' },
    });
    await prisma.productBranch.create({ data: { productId: p.id, branchId: branch.id, stock: 50 } });
    await prisma.stockBatch.create({
      data: { shopId: shop.id, branchId: branch.id, productId: p.id, batchNumber: 'OPENING', inwardQuantity: 50, remainingQuantity: 50, purchasePrice: price * 0.6, expiryDate: new Date(Date.now() + 5 * 86_400_000) },
    });
  }
  await prisma.customer.create({ data: { shopId: shop.id, name: 'Ravi Kumar', phone: '9000000001', openingBalance: 0 } });
  console.log('Demo shop: demo@onepe.local / Demo@1234  (cashier@onepe.local / Cashier@123)');
}

main()
  .catch((e) => {
    console.error(e);
    process.exit(1);
  })
  .finally(() => prisma.$disconnect());
