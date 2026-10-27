import { ShopType } from '@prisma/client';
import { z } from 'zod';
import { Feature, FEATURES, shopFeatures } from '../lib/features';

/** Shop-level settings stored in Shop.settings (JSON). */
export const ShopSettingsSchema = z.object({
  gstInclusive: z.boolean().default(false),
  /** Receipt sections. */
  showLogoAndShop: z.boolean().default(true),
  showBillDetails: z.boolean().default(true),
  showCustomerAccount: z.boolean().default(true),
  /** Rupees spent per 1 loyalty point earned (feature `loyalty`). 1 point = ₹1 when redeemed. */
  loyaltyPointsRatio: z.number().positive().default(100),
  whatsappCustomerShare: z.boolean().default(false),
  /** Feature `locations`. */
  storageLocations: z.array(z.string()).default(['Showroom', 'Warehouse']),
  /** Feature `tables` (branches can add their own). */
  tableNames: z.array(z.string()).default([]),
  /** Feature `batches`: "expiring" = within this many days. */
  expiryReminderDays: z.number().int().min(0).default(3),
  /** Feature switches chosen by the admin; missing ones use the business-type default (lib/features.ts). */
  features: z.record(z.enum(FEATURES), z.boolean()).default({}),
});

export type ShopSettings = z.infer<typeof ShopSettingsSchema>;

export function readSettings(raw: unknown): ShopSettings {
  const r = ShopSettingsSchema.safeParse(raw ?? {});
  return r.success ? r.data : ShopSettingsSchema.parse({});
}

/** Settings plus the effective feature switches ([on]) of a shop. */
export type ShopConfig = ShopSettings & { on: Record<Feature, boolean> };

export function readShopConfig(shop: { shopType: ShopType; settings: unknown }): ShopConfig {
  return { ...readSettings(shop.settings), on: shopFeatures(shop.shopType, shop.settings) };
}

/** Shop as sent to the app: validated settings + effective `features`. */
export function shopView<T extends { shopType: ShopType; settings: unknown }>(shop: T) {
  return { ...shop, settings: readSettings(shop.settings), features: shopFeatures(shop.shopType, shop.settings) };
}
