import { ShopType } from '@prisma/client';
import type { RequestHandler } from 'express';
import { prisma } from './prisma';
import { forbidden } from './errors';
import { shopIdOf } from '../middleware/auth';

/**
 * Optional features of a shop. The business type decides which are available and which are on by default;
 * the admin can switch available ones in Settings → Features (stored in Shop.settings.features).
 * Mirror: app/lib/core/features.dart – change both together.
 */
export const FEATURES = ['tables', 'kot', 'stock', 'batches', 'barcode', 'purchases', 'credit', 'loyalty', 'locations'] as const;
export type Feature = (typeof FEATURES)[number];

/** true / false = default when available; null = not available for this business type. */
export const FEATURE_DEFAULTS: Record<ShopType, Record<Feature, boolean | null>> = {
  RESTAURANT: { tables: true, kot: true, stock: true, batches: true, barcode: false, purchases: true, credit: true, loyalty: false, locations: false },
  RETAIL: { tables: null, kot: null, stock: true, batches: false, barcode: true, purchases: true, credit: true, loyalty: false, locations: true },
  SERVICES: { tables: null, kot: null, stock: false, batches: null, barcode: false, purchases: false, credit: true, loyalty: true, locations: null },
  OTHER: { tables: false, kot: false, stock: true, batches: false, barcode: true, purchases: true, credit: true, loyalty: false, locations: false },
};

export const FEATURE_LABELS: Record<Feature, string> = {
  tables: 'Tables & dine-in',
  kot: 'Kitchen order tickets (KOT)',
  stock: 'Stock tracking',
  batches: 'Batches & expiry',
  barcode: 'Barcodes & labels',
  purchases: 'Purchases & suppliers',
  credit: 'Customer credit (dues)',
  loyalty: 'Loyalty points',
  locations: 'Storage locations',
};

/** Effective on/off of every feature for a shop. Batches need stock tracking. */
export function shopFeatures(shopType: ShopType, settings: unknown): Record<Feature, boolean> {
  const chosen = ((settings as { features?: Record<string, unknown> } | null)?.features ?? {}) as Record<string, unknown>;
  const out = {} as Record<Feature, boolean>;
  for (const f of FEATURES) {
    const def = FEATURE_DEFAULTS[shopType][f];
    out[f] = def !== null && (typeof chosen[f] === 'boolean' ? (chosen[f] as boolean) : def);
  }
  out.batches &&= out.stock;
  return out;
}

export async function hasFeature(shopId: string, f: Feature) {
  const shop = await prisma.shop.findUniqueOrThrow({ where: { id: shopId }, select: { shopType: true, settings: true } });
  return shopFeatures(shop.shopType, shop.settings)[f];
}

/** Route guard: 403 when the feature is switched off for the shop. */
export const requireFeature =
  (f: Feature): RequestHandler =>
  async (req, _res, next) => {
    if (!(await hasFeature(shopIdOf(req), f))) throw forbidden(`${FEATURE_LABELS[f]} is turned off for this shop (Settings → Features)`);
    next();
  };
