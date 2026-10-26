# OnePe POS ERP — project guide for Claude

Multi-tenant POS + inventory system (bakery / restaurant / retail / salon), a functional and visual
rebuild of **LABAN POS** (https://bakery-pos-490b7.web.app) under the **OnePe** brand.
One Flutter codebase (web, Android, iOS) talking to our own Node/Postgres REST API.

More context: `docs/LOCAL_SETUP.md` (run locally + LAN/IP builds), `docs/SESSION_LOG.md` (what was done and why), `docs/ORIGINAL_APP_REFERENCE.md`
(how the original looks/behaves), `docs/ROADMAP.md` (what's next), `README.md` (setup + API list).

## Ground rules
- **Never reuse LABAN's branding, logo, Firebase keys, or the OCR.space key** embedded in their bundle. Everything is "OnePe".
- The user's **live original app account ("Grand Sallon", a salon) is read-only**. If browsing it with Claude in Chrome: look only — never bill, save, edit or delete. Close own tabs when done.
- Stack decision (made by the user): Flutter + Node/Express + Prisma + PostgreSQL. **Not Firebase.**
- Every product must support a photo (user requirement).

## Layout
```
backend/   Node 22+/26, TypeScript, Express 5, Prisma 6.19, Zod 3, JWT, multer
  prisma/schema.prisma   all models (Shop, Branch, User, Category, Product, ProductBranch, Customer,
                         CustomerPrice, CustomerPayment, Supplier, SupplierPayment, Bill, BillItem,
                         StockBatch, StockMovement, Purchase, PurchaseItem, ReturnNote, ActivityLog,
                         Enquiry, Sequence)
  prisma/seed.ts         super admin + demo bakery
  src/services/          billing (checkout/edit/cancel/restore/delete), stock (FIFO batches),
                         ledger, report, settings, session
  src/routes/            one router per resource; index.ts mounts them under /api
  src/lib/               config, errors, permissions (role matrix), sequence (bill numbers), money, activity
  test/api.test.ts       end-to-end tests (creates & deletes its own shop)
  uploads/               product photos / logos (gitignored), served at /uploads
app/       Flutter 3.41 / Dart 3.11, provider + go_router (assets/brand logos, assets/fonts Manrope)
  lib/core/      api.dart (JSON client, uploadImage, mediaUrl), config.dart (API_URL), theme.dart (AppColors), format.dart
  lib/models/    models.dart (thin typed wrappers over JSON maps)
  lib/state/     session.dart (auth/tenant/branch), catalog.dart, cart.dart (mirrors server totals, offline queue)
  lib/services/  print_service.dart (PDF receipts/KOT/labels/reports, WhatsApp), offline_queue.dart
  lib/ui/widgets/ brand.dart (GradientAppBar, GreenButton, CategoryChip, ProductImage, PhotoPickerBox, RowAction…),
                  app_shell.dart (AppScaffold, AppDrawer, navItems), common.dart (Loader, guard, confirm…)
  lib/ui/screens/ pos/, bills/, products/, customers/, stock/, purchases/, reports/, admin/, settings…
docker-compose.yml  Postgres 16 (user/pass/db: onepe/onepe/onepe_pos, port 5432)
```

## Commands
```bash
docker compose up -d                          # Postgres (Docker Desktop must be running: `open -a Docker`)
cd backend && npm run dev                     # API on :4000 (listens on all interfaces)
cd backend && npm test                        # e2e tests – must stay green (currently 5/5)
cd backend && npx tsc --noEmit -p .           # typecheck
cd backend && npx prisma migrate dev --name <change>   # after editing schema.prisma
cd backend && npm run db:seed                 # idempotent
cd app && flutter analyze                     # must report "No issues found!"
cd app && flutter build web --release --dart-define=API_URL=http://localhost:4000
cd app/build/web && python3 -m http.server 8080 --bind 127.0.0.1   # serve web build
cd app && flutter run -d chrome --dart-define=API_URL=http://localhost:4000
```
Logins (seed): super admin `admin@onepe.local / ChangeMe@123`, shop admin `demo@onepe.local / Demo@1234`,
cashier `cashier@onepe.local / Cashier@123`.

### Android
The phone talks to the **API**, never to Postgres directly.
- USB: enable USB debugging → `adb reverse tcp:4000 tcp:4000` → `flutter run --release --dart-define=API_URL=http://localhost:4000`
- Wi-Fi: `flutter build apk --release --dart-define=API_URL=http://<mac-lan-ip>:4000` (Mac IP 192.168.0.31 on 2026-10-24; check `ipconfig getifaddr en0`).
- Emulator: `API_URL=http://10.0.2.2:4000`.
- `usesCleartextTraffic="true"` is set in AndroidManifest for dev HTTP — remove for production (HTTPS).
- Release APK runs on the user's Nexgo N82 (2026-10-24); iOS not yet built. Release builds need `isMinifyEnabled = false` (Nexgo SDK).

## Conventions & gotchas
- Server is authoritative for money: `billing.service.ts` `computeLine/computeTotals`; `app/lib/state/cart.dart` mirrors them for preview only. Change both together.
- Bills use **client-generated UUIDs**; `POST /bills/checkout` is idempotent (offline replay).
- **Completed bills are issued tax invoices – never edited or deleted** (API returns 409; `editing: true` is rejected). Only **Cancel**
  (admin/manager, reason required → `Bill.cancelReason`, number kept, stock/balances reverted, optional "load items into a new bill");
  **Restore** of a cancelled bill is shop-admin only. Waiting orders (not billed yet) can be continued (normal Proceed/payment flow) or deleted.
- Stock: per-branch `ProductBranch.stock` + FIFO `StockBatch`; bill items store `batchAllocations` so reversals restore exact batches. Every change writes a `StockMovement`. Negative stock is allowed.
- Bill number: `<SHOP INITIALS>-<BRANCH CODE>[-EXP]-<YYYYMMDD>-<SEQ3>` (e.g. `ODB-MAIN-20261015-001`), via `lib/sequence.ts`.
- Permissions: `src/lib/permissions.ts` role matrix; routes use `requirePermission(...)`; Flutter hides menu items via `session.can(...)`.
- Tenant/branch context: `shopIdOf(req)`, `branchIdOf(req)` (header `X-Branch-Id`; super admin uses `X-Shop-Id`).
- Prisma Decimals are serialized to JSON numbers by the replacer in `app.ts`.
- helmet is configured with `crossOriginResourcePolicy: cross-origin` so the Flutter web app can load `/uploads` images.
- `backend/package.json` pins `@types/express-serve-static-core` 5.0.7 (dev dep + override) so `req.params` are `string`.
- `app/pubspec.yaml` has `dependency_overrides: image: 4.9.2` because `pdf 3.12` caps `archive <4.1` (newer `image` breaks web compile).
- Flutter web caches aggressively — when checking a rebuild in Chrome, load `http://127.0.0.1:8080/?v=N#/pos`.
- UI follows the **OnePe brand guide** (Downloads/4. BRAND GUIDELINES): OnePe Blue `#084E8F` + Lime `#D3E278` primary, Navy `#183461`, Amber, Leaf, Cream, Coral secondary;
  **Manrope** only (bundled in `app/assets/fonts`); logos in `app/assets/brand` (`BrandLogo` widget – lime on blue/navy, blue on white; never recolour/redraw).
  Tokens live in `app/lib/core/theme.dart` (`AppColors`); primary action = lime with navy text (`GreenButton`, name kept); blue rounded app bars; lime "step" strip
  under blue panels is the brand element. POS: phone = blue header + floating navy dock with lime cart button; wide (≥900) = navy side rail + cart panel.
  Check phone layouts at 360×640 (5.5").
- Checkout: cart **Proceed** → pop-up Print Bill / Collect Payment / Print + Collect / Save without printing (`pos/bill_actions.dart`;
  the two Collect options only when Settings → Payments → OnePe payment collection is on – saved on the device, default on everywhere; when off, a
  "Payment received?" pop-up asks Cash / UPI / Card / Split with per-mode amounts that must equal the total) → bill saved (`ONEPE` when collecting,
  else the confirmed mode, or CREDIT) → bill PDF → printer and/or OnePe payment app (multipart POST `pdf` + `images` to `http://127.0.0.1:8080/` on the terminal).
- Printing: per-device `PrinterConfig` (SharedPreferences) with two `PrinterTarget`s – `bill` and `kitchen` (KOT; used only when
  "Same as bill printer" is off). Each: Nexgo N82 (2" only), Bluetooth ESC/POS raster (2"/3"/4", bill also A5/A4) or system dialog.
  Native code: `android/app/src/main/java/com/onepe/onepe_pos/` (PrinterChannel, PdfRaster, NexgoPrinter, BluetoothEscPos) + `libs/ps-n86Release-v2.1.10.aar`
  (Nexgo SDK, taken from `OnePe-Android-Printer-Plugin-main`). Channel `onepe/printer`.
- Don't add attribution/branding of the original anywhere; don't commit `.env` or `uploads/`.
- Git repo on GitHub; commit/push only when the user asks ("git push").
