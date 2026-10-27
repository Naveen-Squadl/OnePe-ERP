import { User } from '@prisma/client';
import { prisma } from '../lib/prisma';
import { RolePermissions } from '../lib/permissions';
import { shopView } from './settings.service';

/** Everything the client needs after login / on app start. */
export async function sessionPayload(u: User) {
  const shop = u.shopId ? await prisma.shop.findUnique({ where: { id: u.shopId } }) : null;
  const branches = u.shopId
    ? await prisma.branch.findMany({ where: { shopId: u.shopId, isActive: true }, orderBy: [{ isMain: 'desc' }, { createdAt: 'asc' }] })
    : [];
  let plan: { status: 'active' | 'expiring' | 'expired'; daysLeft: number | null } | null = null;
  if (shop?.subscriptionExpiry) {
    const daysLeft = Math.ceil((shop.subscriptionExpiry.getTime() - Date.now()) / 86_400_000);
    plan = { status: daysLeft < 0 ? 'expired' : daysLeft <= 7 ? 'expiring' : 'active', daysLeft };
  }
  return {
    user: {
      id: u.id,
      name: u.name,
      email: u.email,
      role: u.role,
      shopId: u.shopId,
      branchId: u.branchId,
      permissions: RolePermissions[u.role],
    },
    shop: shop && shopView(shop),
    branches,
    plan,
  };
}
