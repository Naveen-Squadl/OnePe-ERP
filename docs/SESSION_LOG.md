# Session log

## Session 1 — 2026-10-15

### Goal (from the user)
Clone the app at https://bakery-pos-490b7.web.app/?category=retail-shop (logged in in their Chrome)
with all functionality and navigation, write the code incl. backend logic, then ship it as a Flutter app.

### How the original was analysed
1. Claude in Chrome wasn't connected at first, so the public bundle was downloaded and analysed:
   the original is **LABAN POS v5.3.2 (B125)** — itself a **Flutter web app on Firebase**
   (Auth + Firestore, Hive offline cache). ~2,600 app strings were extracted from `main.dart.js`
   to build the feature inventory (screens, labels, data fields, Firestore collections, business rules).
2. Later the user connected Claude in Chrome (needed `/chrome` + restarting with `claude --chrome --continue`)
   and the live app was walked through **read-only**: POS, Order Details, cart, price dropdown,
   payment dialog, drawer, Dashboard, Products (+ Add Product form), Customers (+ purchase history),
   Bills History (+ Bill Details, Print Preview), Reports (embedded in POS via "Reports ⇄"),
   Shop Settings, Stock Management, User Management. Nothing was billed/saved; a stray cart item was removed.

### Decisions (user)
- Architecture: **Flutter + Node/Postgres API** (chosen over Firebase).
- Scope: **Phase 1 = Retail/Bakery core**; Distributor, Parking, Logistics later.
- UI: match the original visually (done via screenshots).
- **Every product needs a photo** (added: upload endpoint + photo picker + display everywhere).

### What was built
- Backend: full schema, auth/JWT, role permissions, plans/limits, shops/branches/users, catalog with
  per-branch price & stock, customers with ledger/loyalty/payments, suppliers, purchases & POs,
  FIFO batches with expiry, stock ledger, returns, billing engine (waiting/KOT/checkout/edit/cancel/
  delete/restore/permanent delete, expense vouchers, split/credit payments), 9 reports, delta sync +
  idempotent offline push, super admin panel APIs, enquiries, image uploads.
- Flutter app: all Phase-1 screens restyled to match the original (see ORIGINAL_APP_REFERENCE.md),
  PDF printing (58/80mm, A4 invoice with amount-in-words + UPI QR, KOT, payment receipt, barcode labels),
  WhatsApp share, barcode scanning, offline bill queue.
- Tests: `backend/test/api.test.ts` – 5 suites passing. `flutter analyze` clean. Web build verified in Chrome
  (login, POS, cart, payment → bill saved, products with photos, bills, reports).

### Environment notes (this Mac)
- Node 26, Flutter 3.41.6 / Dart 3.11.4, Docker Desktop (start with `open -a Docker`), adb at /usr/local/bin/adb.
- Postgres runs in docker compose; API on :4000; web build served on :8080 (python http.server).
- Mac LAN IP was 192.168.0.31; macOS firewall disabled; API reachable from LAN.
- Demo data: shop "OnePe Demo Bakery" (9 products, 3 with sample photos from macOS wallpapers), customer Ravi Kumar.
  A couple of test bills exist in the demo shop.

### Where we stopped
User asked how to run on an Android phone. Instructions given (USB with `adb reverse`, or Wi-Fi APK
with the Mac's LAN IP). No device was connected yet; Android build not yet compiled. Next step: when the
user plugs in a phone with USB debugging, run `adb devices`, `adb reverse tcp:4000 tcp:4000`,
`flutter run --release --dart-define=API_URL=http://localhost:4000` from `app/`.

---

## Session 2026-10-24 – printing, OnePe payments, payment tracking, locked bills

### Done (committed earlier this session: ef5aec3 printing/payments, 34af0d2 KOT printer + icon/name)
- **Proceed flow**: "Charge" → **Proceed** → pop-up Print Bill / Collect Payment / Print + Collect / Save without printing
  (`pos/bill_actions.dart`, plain option cards, nothing highlighted). Collect = multipart POST (`pdf` + `images`) to the
  OnePe payment app at `http://127.0.0.1:8080/` on the terminal; bill saved as `ONEPE`.
- **Printing** (per device, `services/printer_config.dart`): bill + KOT/kitchen `PrinterTarget`s; Nexgo N82 built-in (2" only),
  Bluetooth ESC/POS raster (2"/3"/4", bill also A5/A4) or system dialog. Native Android code in
  `android/app/src/main/java/com/onepe/onepe_pos/` + Nexgo SDK AAR (taken from the user's printer plugin; plugin folder since deleted).
  Full-width dashed separators checked at all sizes. Release build needs `isMinifyEnabled = false` (R8 vs Nexgo SDK).
- App name **OnePe ERP**, launcher icon = OnePe logo (flutter_launcher_icons; its pbxproj edit had to be reverted).

### Done (committed 2026-10-26)
- **Settings → Payments → OnePe payment collection**: generic switch, default **on** everywhere, saved on the device
  (SharedPreferences `onepe.collect`). When **off**, after Proceed a **"Payment received?"** pop-up asks Cash / UPI / Card / Split;
  split = per-mode amounts that must equal the total → bill saved as CASH/UPI/CARD/SPLIT with `cashAmount/upiAmount/cardAmount`.
  Credit bills and expense vouchers skip it.
- `Bill.paymentLabel` / `Bill.splitParts` (models.dart): split breakdown on bill details, print preview and printed bills.
- Bills page: bill-details buttons fixed for phone width (icon-over-label, equal size); preview shows payment/split/received/change.
- **Completed bills are locked** (user decision): no Edit, no Delete (API 409). **Cancel** = admin/manager, reason required
  (`Bill.cancelReason`, migration `20261024105019_bill_cancel_reason`), optional "Load items into a new bill" (re-bill).
  **Restore** of a cancelled bill = shop admin only. Waiting orders: Continue (normal Proceed/payment flow) or Delete.
  Backend test lifecycle updated; 5/5 passing; `flutter analyze` clean.
- **Offline bill safety** (2026-10-26): `OfflineQueue` (offline_queue.dart) now auto-syncs every 30 s while bills are pending,
  on app resume and after login; entries keep shop, branch and sale time (`billDate`, so the bill gets that day's number).
  Pending count badge (POS header, drawer "Sync Cloud Data", Settings). Logout first tries to upload, then warns
  ("Logout anyway"). Android also writes each pending bill to `Download/OnePe/OfflineBills/bill_<id>.json` (native
  `OfflineBackup.java`, channel `onepe/backup`, MediaStore; WRITE_EXTERNAL_STORAGE only ≤ Android 9) – survives Clear storage
  and uninstall; **Settings → Import offline bills** (file_picker) re-queues them. `/sync/push` reports bills already on the
  server as `duplicate: true` (also when cancelled since) and returns the id of rejected bills. Verified with a live
  Dart run against the API (upload, duplicate re-import, other-shop entry stays queued, rejected bill keeps error) +
  new backend test; release APK + web build compile. Not yet tried on the N82 (backup file / import flow).
- **Offline catalog + storage control** (2026-10-26): `Catalog` saves `/products` + `/categories` per branch to
  `catalog_<branchId>.json` (`LocalStore`: app support folder; web → SharedPreferences) and falls back to it when the API is
  unreachable (amber "Offline – products & prices saved …" banner on POS, retry every 30 s); cleared on logout.
  Photos: server caps uploads at 1024 px (sharp) and serves `<photo>.thumb.webp` (300 px, ~14 KB, made on first request –
  `thumbnails` middleware before `/uploads` static). `ProductImage` uses thumbnails (`full: true` in the photo editor) via
  `cached_network_image` + `OfflinePhotos` cache (max 400 files, 60 days, prefetched after each catalog load; per-device switch).
  **Backup folder**: Android 10+ asks once (POS start, `backupFolder.asked`) to grant `Download/OnePe/OfflineBills` via
  ACTION_OPEN_DOCUMENT_TREE (persisted grant, `OfflineBackup.java` / MainActivity `pickFolder`; Android ≤9 = storage permission).
  With the grant the app lists the folder at start, re-queues unknown bills and deletes every file once its bill is on the
  server (incl. files from earlier installs). Settings → **Offline Data & Backup** (`offline_data_tiles.dart`): sync, backup
  folder, import files, saved products size, photo switch + size + clear. Checked: backend 5/5 (thumbnail test added),
  temp Dart test of the offline catalog fallback, analyze clean, APK + web build. Not yet run on a device.
- **Pricing rule (user decision)**: the line price is always the item price (branch price, else base) set by the admin in
  Products; the counter can only give discounts. Removed the cart price picker (Base/Last/Max/Custom) and the
  "Default Selling Price Option" setting. Entered prices only for variable-price products, expense items and ad-hoc lines;
  server enforces it in `priceItems` (legacy 'last'/'max' accepted but ignored). Offline bills (`/sync/push`,
  `checkout(..., {offline: true})`) keep the receipt price; a difference from the current item price is logged as
  activity `offline_price_difference`.
- **Customer name optional** (all shop types): API needs a mobile or a name; quick capture no longer stores
  "New Customer"; app shows the mobile when there is no name (`Customer.name` fallback, `savedName` for forms).
- **Offline behaviour**: `Api.online` flag (false after a network error, ping `/health` every 10 s while offline) →
  checkout queues instantly when offline, otherwise gives up after 10 s (`Cart.checkoutTimeout`; duplicate-safe by bill id).
  Old offline bills upload **only when idle** (`UserActivity`: no touch/key for 20 s and empty cart) in batches of 25
  that stop when the user is active; manual Sync / logout upload everything at once. Photo prefetch also waits for idle.
  Catalog shows stock minus unsent offline bills and reloads when back online / after an upload.
  `CustomerCache` (customers_<shop>.json, refreshed ≤ every 10 min) → offline customer search; offline a typed mobile
  can be used directly (`Customer.phoneOnly`, created on sync). Checked: backend 5/5 (pricing + optional-name tests),
  temp live Dart test (instant offline checkout, stock deduction, idle gating, customer cache), APK + web build.

### Environment
- Mac LAN IP **192.168.0.31**. API `npm run dev` on :4000; web build served by a no-cache python server on :8080.
- Builds: `flutter build apk --release --dart-define=API_URL=http://192.168.0.31:4000`,
  `flutter build web --release --pwa-strategy=none --dart-define=API_URL=http://192.168.0.31:4000`.
- Release APK installed on the user's **Nexgo N82**; Nexgo/Bluetooth printing and the OnePe app hand-off not yet confirmed on the device.
- Demo DB test data from this session: bills ODB-MAIN-20261024-010…021 (021 cancelled, reason "Wrong item test").
- Login 500 earlier was Docker Desktop hung + low disk; fix = restart Docker, `docker compose up -d`, free space.

### Next
- Confirm on the N82: built-in print, Bluetooth print, OnePe app collect, payment-received pop-up, offline mode (backup folder, saved catalog, idle sync).
- Open question to the user: with collection ON, should Print Bill / Save without printing also ask the payment mode (currently saves as Cash)?
- Returns / credit notes against a bill (`ReturnNote` model exists) as the GST-friendly correction path.
