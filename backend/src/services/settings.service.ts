import { z } from 'zod';

/** Shop-level settings stored in Shop.settings (JSON). */
export const ShopSettingsSchema = z.object({
  gstInclusive: z.boolean().default(false),
  enableKot: z.boolean().default(false),
  autoKotOnCheckout: z.boolean().default(false),
  paperSize: z.enum(['58mm', '80mm', 'A4']).default('58mm'),
  printerType: z.enum(['system', 'bluetooth', 'network']).default('system'),
  bluetoothPrinterName: z.string().nullable().default(null),
  bluetoothPrinterAddress: z.string().nullable().default(null),
  networkPrinterIp: z.string().nullable().default(null),
  kotPrinter: z.enum(['same_as_bill', 'system', 'bluetooth']).default('same_as_bill'),
  kotPrinterName: z.string().nullable().default(null),
  kotPrinterAddress: z.string().nullable().default(null),
  showLogoAndShop: z.boolean().default(true),
  showBillDetails: z.boolean().default(true),
  showCustomerAccount: z.boolean().default(true),
  enableLoyaltyPoints: z.boolean().default(false),
  /** Rupees spent per 1 loyalty point earned. 1 point = ₹1 when redeemed. */
  loyaltyPointsRatio: z.number().positive().default(100),
  enableFastPay: z.boolean().default(true),
  whatsappCustomerShare: z.boolean().default(false),
  whatsappDailyReport: z.boolean().default(false),
  storageLocations: z.array(z.string()).default(['Showroom', 'Warehouse']),
  tableNames: z.array(z.string()).default([]),
  expiryReminderDays: z.number().int().min(0).default(3),
});

export type ShopSettings = z.infer<typeof ShopSettingsSchema>;

export function readSettings(raw: unknown): ShopSettings {
  const r = ShopSettingsSchema.safeParse(raw ?? {});
  return r.success ? r.data : ShopSettingsSchema.parse({});
}
