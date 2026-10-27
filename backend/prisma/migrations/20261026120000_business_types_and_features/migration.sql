-- Business types: Restaurant / QSR / Bakery, Retail, Services, Others.
-- BAKERY → RESTAURANT, DISTRIBUTOR → RETAIL, PARKING / LOGISTICS → OTHER.
ALTER TYPE "ShopType" RENAME TO "ShopType_old";
CREATE TYPE "ShopType" AS ENUM ('RESTAURANT', 'RETAIL', 'SERVICES', 'OTHER');
ALTER TABLE "Shop" ALTER COLUMN "shopType" DROP DEFAULT;
ALTER TABLE "Shop" ALTER COLUMN "shopType" TYPE "ShopType" USING (
  CASE "shopType"::text
    WHEN 'BAKERY' THEN 'RESTAURANT'
    WHEN 'RETAIL' THEN 'RETAIL'
    WHEN 'DISTRIBUTOR' THEN 'RETAIL'
    ELSE 'OTHER'
  END
)::"ShopType";
ALTER TABLE "Shop" ALTER COLUMN "shopType" SET DEFAULT 'RETAIL';
DROP TYPE "ShopType_old";

-- Keep each shop's current KOT / tables / loyalty choice as explicit feature switches.
UPDATE "Shop"
SET "settings" = COALESCE("settings", '{}'::jsonb) || jsonb_build_object('features', jsonb_build_object(
  'kot', COALESCE(("settings"->>'enableKot')::boolean, false),
  'tables', COALESCE(("settings"->>'enableKot')::boolean, false)
            OR jsonb_array_length(COALESCE("settings"->'tableNames', '[]'::jsonb)) > 0
            OR EXISTS (SELECT 1 FROM "Branch" b WHERE b."shopId" = "Shop"."id" AND array_length(b."tableNames", 1) > 0),
  'loyalty', COALESCE(("settings"->>'enableLoyaltyPoints')::boolean, false)
))
WHERE NOT (COALESCE("settings", '{}'::jsonb) ? 'features');
