import { NextFunction, Request, Response } from 'express';
import jwt from 'jsonwebtoken';
import { Role } from '@prisma/client';
import { prisma } from '../lib/prisma';
import { config } from '../lib/config';
import { forbidden, unauthorized, badRequest } from '../lib/errors';
import { hasPermission, Permission } from '../lib/permissions';

export interface AuthUser {
  id: string;
  name: string;
  email: string;
  role: Role;
  shopId: string | null;
  branchId: string | null;
}

declare global {
  // eslint-disable-next-line @typescript-eslint/no-namespace
  namespace Express {
    interface Request {
      user?: AuthUser;
    }
  }
}

export function signToken(u: AuthUser) {
  return jwt.sign({ sub: u.id }, config.jwtSecret, { expiresIn: config.jwtExpiresIn as any });
}

export async function authenticate(req: Request, _res: Response, next: NextFunction) {
  const h = req.headers.authorization;
  if (!h?.startsWith('Bearer ')) throw unauthorized();
  let sub: string;
  try {
    sub = (jwt.verify(h.slice(7), config.jwtSecret) as jwt.JwtPayload).sub as string;
  } catch {
    throw unauthorized('Session expired. Please log in again.');
  }
  const u = await prisma.user.findUnique({ where: { id: sub }, include: { shop: true } });
  if (!u || !u.isActive) throw unauthorized('This account has been disabled');
  if (u.shop && !u.shop.isActive) throw forbidden('Your shop account is inactive. Contact support.');
  req.user = { id: u.id, name: u.name, email: u.email, role: u.role, shopId: u.shopId, branchId: u.branchId };
  next();
}

export const requirePermission = (...perms: Permission[]) =>
  (req: Request, _res: Response, next: NextFunction) => {
    const u = req.user;
    if (!u) throw unauthorized();
    if (!perms.some((p) => hasPermission(u.role, p))) throw forbidden();
    next();
  };

export const requireSuperAdmin = (req: Request, _res: Response, next: NextFunction) => {
  if (req.user?.role !== Role.SUPER_ADMIN) throw forbidden('Super Admin only');
  next();
};

/** Shop context for tenant routes. Super admins may act on a shop via ?shopId= / X-Shop-Id. */
export function shopIdOf(req: Request): string {
  const u = req.user!;
  if (u.role === Role.SUPER_ADMIN) {
    const sid = (req.headers['x-shop-id'] as string) || (req.query.shopId as string);
    if (!sid) throw badRequest('shopId required for super admin');
    return sid;
  }
  if (!u.shopId) throw forbidden('No shop assigned');
  return u.shopId;
}

/**
 * Active branch for the request. Admin/Manager can switch outlets via X-Branch-Id;
 * other staff are pinned to their assigned branch.
 */
export async function branchIdOf(req: Request): Promise<string> {
  const u = req.user!;
  const shopId = shopIdOf(req);
  const requested = (req.headers['x-branch-id'] as string) || (req.query.branchId as string) || undefined;
  const canSwitch = u.role === Role.ADMIN || u.role === Role.MANAGER || u.role === Role.SUPER_ADMIN || !u.branchId;
  const id = canSwitch ? requested ?? u.branchId : u.branchId;
  if (id) {
    const b = await prisma.branch.findFirst({ where: { id, shopId } });
    if (b) return b.id;
  }
  const main = await prisma.branch.findFirst({ where: { shopId }, orderBy: [{ isMain: 'desc' }, { createdAt: 'asc' }] });
  if (!main) throw badRequest('Shop has no branch configured');
  return main.id;
}
