import { Router } from 'express';
import { z } from 'zod';
import { ShopType } from '@prisma/client';
import { prisma } from '../lib/prisma';
import { parse, optStr } from '../lib/validate';
import { requirePermission, shopIdOf } from '../middleware/auth';
import { readSettings, ShopSettingsSchema } from '../services/settings.service';
import { logActivity } from '../lib/activity';
import { forbidden } from '../lib/errors';

export const shopRouter = Router();

shopRouter.get('/', async (req, res) => {
  const shop = await prisma.shop.findUniqueOrThrow({ where: { id: shopIdOf(req) } });
  res.json({ ...shop, settings: readSettings(shop.settings) });
});

const ShopUpdate = z.object({
  name: z.string().trim().min(1, 'Please enter shop name').optional(),
  address: optStr,
  contactNumber: optStr,
  gstNumber: optStr,
  upiId: optStr,
  logoUrl: optStr,
  thanksNote: optStr,
  shopType: z.nativeEnum(ShopType).optional(),
  settings: ShopSettingsSchema.partial().optional(),
});

shopRouter.put('/', requirePermission('settings.manage'), async (req, res) => {
  const shopId = shopIdOf(req);
  const body = parse(ShopUpdate, req.body);
  const u = req.user!;
  // Only admins may change shop type, printer type, price option & UPI (as in the original settings screen).
  const adminOnly = body.shopType || body.upiId !== undefined || body.settings?.printerType || body.settings?.defaultPriceOption;
  if (adminOnly && u.role !== 'ADMIN' && u.role !== 'SUPER_ADMIN') throw forbidden('Only Admins can change these settings');

  const current = await prisma.shop.findUniqueOrThrow({ where: { id: shopId } });
  const { settings, ...rest } = body;
  const merged = settings ? { ...readSettings(current.settings), ...settings } : undefined;
  const shop = await prisma.shop.update({ where: { id: shopId }, data: { ...rest, ...(merged && { settings: merged }) } });
  await logActivity(u, 'shop_updated', 'Updated shop settings', { fields: Object.keys(body) });
  res.json({ ...shop, settings: readSettings(shop.settings) });
});
