import { Role } from '@prisma/client';

export const Permissions = [
  'bills.create',
  'bills.view',
  'bills.cancel',
  'bills.delete',
  'products.manage',
  'products.edit_limited',
  'customers.manage',
  'suppliers.manage',
  'inventory.view',
  'inventory.manage',
  'purchases.manage',
  'reports.view',
  'reports.export',
  'settings.manage',
  'users.manage',
  'branches.manage',
  'system.manage',
] as const;
export type Permission = (typeof Permissions)[number];

const ALL_SHOP: Permission[] = Permissions.filter((p) => p !== 'system.manage');

/** Role → permission matrix (mirrors the role descriptions shown in the staff screen). */
export const RolePermissions: Record<Role, Permission[]> = {
  SUPER_ADMIN: [...Permissions],
  ADMIN: ALL_SHOP,
  MANAGER: [
    'bills.create', 'bills.view', 'bills.cancel', 'bills.delete',
    'products.manage', 'customers.manage', 'suppliers.manage',
    'inventory.view', 'inventory.manage', 'purchases.manage',
    'reports.view', 'reports.export', 'settings.manage',
  ],
  CASHIER: ['bills.create', 'bills.view', 'customers.manage'],
  SALESMAN: ['bills.create', 'bills.view', 'reports.view', 'customers.manage'],
  BILLER: ['bills.create'],
  STORE_KEEPER: ['products.edit_limited', 'inventory.view', 'inventory.manage', 'purchases.manage', 'suppliers.manage'],
  STOCK_MANAGER: ['products.manage', 'inventory.view', 'inventory.manage', 'reports.view', 'purchases.manage', 'suppliers.manage'],
};

export const RoleDescriptions: Record<Role, string[]> = {
  SUPER_ADMIN: ['Global System Control (All shops & Subscriptions)'],
  ADMIN: ['Full Shop Control (Everything except global system settings)'],
  MANAGER: ['Create, View & Delete Bills', 'Manage Products, Customers & Inventory', 'Export Reports & Printer Settings'],
  CASHIER: ['Create Bills', 'View Bill History'],
  SALESMAN: ['Create & View Bills', 'View Reports'],
  BILLER: ['Create Bills (Fast Entry)'],
  STORE_KEEPER: ['Update Stock Quantities', 'Manage Purchases', 'Log Stock In/Out'],
  STOCK_MANAGER: ['Manage Product Master', 'Update Stock & Levels', 'Manage Inventory Master', 'View Inventory Reports'],
};

export const hasPermission = (role: Role, p: Permission) => RolePermissions[role].includes(p);
