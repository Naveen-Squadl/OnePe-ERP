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
  (Committed 2026-10-26 as b6a0fce.)

---

## Session 2026-10-26 – offline mode, pricing rule, menu & business types

### Done – committed & pushed to GitHub main (79b1779 offline mode, 3153e34 item price + optional customer name)
- **Offline bill safety**: `OfflineQueue` (offline_queue.dart) now auto-syncs every 30 s while bills are pending,
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

### Done – committed & pushed 2026-10-27 (menu & business types · history panels · customers / suppliers / products)
- **Menu consolidated** (2026-10-26, user-approved plan): 14 drawer items → 7 areas with tabs (`HubScaffold`):
  Inventory = Products (with stock; "Stock entry" mode = old Stock Levels; per-row Inward Batch) | Categories (tap → Products
  filtered) | Batches & Expiry | Stock History; Purchases = Inwarded | Pending POs | Suppliers; Reports = Overview (dashboard) |
  Reports (also inside the POS "Reports" mode); Settings = General | Printer | Users | Branches | Sync & Account. "Sync Cloud
  Data" left the menu (POS sync button + a drawer line while bills are pending). Old routes redirect to the tabs.
  Checked: analyze clean; temp widget test rendered every tab at 360 px and 1280 px with Manrope (no overflow).
  POS side rail (wide) and phone dock follow the same menu order (`_destinations` from `navItems`). The rail shows every
  area (no "More"); the dock shows what fits beside the cart button and adds "More" (drawer) only when needed
  (360 px admin: New Bill · Bills · Inventory · More; ≥ 600 px: all 7; cashier: New Bill · Bills · Customers).
  Counter screen renamed "Sell" → "New Bill" (user choice; matches the bill wording used everywhere).
- **Business types & features** (2026-10-26, user decision): types are now Restaurant / QSR / Bakery (`RESTAURANT`), Retail,
  Services, Others (Distributor → Retail, Parking/Logistics → Others; migration `20261026120000_business_types_and_features`
  also keeps each shop's KOT / tables / loyalty choice as `settings.features`). Nine features (tables, kot, stock, batches,
  barcode, purchases, credit, loyalty, locations) with per-type availability + defaults; admin switches them in Settings →
  Features (changing the type resets them to its recommended set). Server: effective `features` in the shop payload,
  `requireFeature` on KOT / stock changes / purchases / suppliers, credit + loyalty checks in billing, feature switches merge
  on save, admin-only. App: Purchases menu, Batches / History tabs, KOT / table / credit / points in the cart, scan button,
  stock badges, barcode / stock / location / batch fields (product form, purchases, stock entry), branch tables and the
  KOT printer all follow `shop.has()`. Settings regrouped: Business · Features · Billing & Receipt · Printers · Users ·
  Branches · Device & Account, each marked "whole shop" or "this device". Unused legacy settings dropped (printerType,
  paperSize, bluetooth/network/kot printer keys, enableFastPay, whatsappDailyReport, autoKotOnCheckout; enableKot /
  enableLoyaltyPoints → features). Tables and Kitchen screens for restaurants = next step.
  Checked: backend 6/6 (new feature test), analyze clean, temp widget test (settings tabs at 360/1280 px, Services vs
  Restaurant menus/tabs/POS). Dev DB backed up before the migration (scratchpad dump).
- **History button instead of history sections** (2026-10-27, user request): one shared panel
  (`widgets/history_panel.dart`: Today · Yesterday · Last 7 days · This month · calendar range, search, grouped by day,
  PDF export; bottom sheet on phones, right-side panel ≥ 900 px) opened from a 🕘 button at the top of each page
  (`ui/history_sources.dart`): Inventory → stock movements (+ "Stock history" per product), Purchases → received
  purchase bills + supplier payments, Customers → payments received, customer details → that customer's bills,
  Settings → shop activity log (admins), New Bill (POS header) → this outlet's bills, today by default. Removed tabs:
  Inventory "Stock History", Purchases "Inwarded" (Purchases = Pending POs · Suppliers), customer "Purchase History"
  (customer details = ledger only). New API: `GET /customers/payments`, `GET /suppliers/payments`, `GET /shop/activity`
  (settings.manage), `?from=&to=` on `/customers/:id/bills` (`dateRange()` in lib/validate.ts). Bills page keeps its own
  calendar filter. Checked: backend 7/7 (new history test), analyze clean, temp widget test (panel presets / calendar /
  search / grouping at 360 + 1280 px, buttons present, removed tabs gone). The API must be restarted after adding
  routes – `tsx watch` did not pick them up.
- **Removed "Recalculate & Sync Balances"** (Customers toolbar + `POST /customers/recalculate`, user decision): balances
  change in the same transaction as every bill / payment / cancel / restore / return, and editing an opening balance still
  recalculates that customer (`recalculateCustomerBalance`). Safety net instead: backend test "customer live balance always
  equals the ledger closing balance" (runs last, over all test customers). Backend 8/8.
- **Customer opening balance only at creation** (user decision): the form shows it only for a new customer; the API
  refuses a changed `openingBalance` on edit (400, same value accepted for old clients). `recalculateCustomerBalance`
  removed (no longer used). Form label "Customer Name" (no "(optional)"; still optional – a mobile is enough).
  Suppliers still allow editing their opening balance (open question). Backend 9/9.
- **Customer advance** (2026-10-27, user request; migration `…_customer_advance`: `Bill.advanceUsed`,
  `CustomerPayment.isRefund`, `PaymentMethod.ADVANCE`). Advance = customer balance below zero.
  Take: Receive Payment of any amount (dialog says "Receive Advance" / "kept as advance"; ledger "Advance Received").
  Use: cart **Advance** chip (on by default for a customer with advance, exclusive with Credit) → advance pays first,
  "From advance −₹x" in the summary, Proceed asks only for the rest (`Cart.advancePart` / `toCollect`); fully covered →
  method ADVANCE, no payment pop-up; OnePe collect is not offered when an advance is used (the PDF shows the full total).
  Server computes `advanceUsed` and allows a short-paid bill with customer credit OFF when the advance covers it.
  Keep change: payment pop-up option "Cash – keep change as advance" (`giveChange: false`). Refund: customer details
  ⇄ button → `POST /customers/:id/refunds` (≤ advance, REF- receipt, activity `advance_refunded`), "Advance Refunded"
  in the ledger, refund receipt print. Receipts show "Paid from Advance", "Kept as Advance" and balances below zero as
  "₹x Advance". Reports: net collection and the outstanding report subtract refunds.
  Customers list chips: **All · Due · Advance** with "· N · ₹total" (`GET /customers/summary`); Due only when customer
  credit is on; `filter=advance` (balance < 0). History "Payments & refunds". Checked: backend 10/10 (full advance flow
  incl. credit off, not-enough advance, keep change, refund limits, ledger wording), analyze clean, temp tests (cart
  maths, customer detail). DB backed up before the migration (scratchpad before_advance.dump).
- **Customer screen clean-up** (user feedback): chips are plain **All · Due · Advance** (no counts / amounts;
  `/customers/summary` removed). Customer details redesigned: one summary card that says the balance in words
  ("Naveen owes you ₹250" / "Naveen has ₹100 advance with you" / "All settled") with mobile · points · opening and
  Receive Payment/Advance + Refund Advance buttons (no FAB covering the list); Edit/Delete in a ⋮ menu; "Account
  statement" rows show type, date, bill/receipt no., "Billed ₹x" / "Paid ₹x" and a balance tag; "Balance now" at the
  end. No more Dr/Cr or negative numbers: `balanceText()` (format.dart) → "₹250 due" / "₹100 advance" / "Settled",
  also in the customers list, customer picker and cart. Checked by rendering the screen to PNG in a temporary widget
  test (Manrope + Material icons, mocked API via `http.runWithClient`) at 360 px and 1280 px – the old screen showed
  RenderFlex overflow on rows with both billed and paid amounts; the new one renders without errors.
- **Customers are archived, never deleted** (user decision; migration `…_customer_archive`: `Customer.isArchived` /
  `archivedAt`; `CustomerPayment → Customer` is now ON DELETE NO ACTION so payment receipts can never disappear with a
  customer – before, deleting a customer cascaded their receipts and changed past reports). `POST /customers/:id/archive`
  (also what `DELETE /customers/:id` does now) only with a settled balance (409: collect the due / refund the advance
  first); `POST /customers/:id/restore`; lists hide archived (`filter=archived` shows them); adding an archived
  customer's mobile again, or billing it, restores them (opening balance unchanged). App: "Archive Customer" with an
  explanation, Archived chip, Restore in list rows / detail ⋮ menu, amber "Archived" note with Restore on the detail
  card. Backend 11/11 (archive rules, reports unchanged, DB refuses deleting a customer with receipts, restore paths).
- **Opening balance direction**: Add Customer / Supplier asks the amount and, right under it, two buttons side by side
  **Due | Advance** (`FieldSpec.options` → SegmentedButton in form_dialog) instead of expecting a minus sign.
  **No helper texts anywhere** (user decision): removed from form fields, Settings (UPI), purchases (location) and
  number pop-ups (`askNumber` has no helper any more); available loyalty points moved into that pop-up's title.
  Checked by rendering the dialog at 360 px.
- **Suppliers archived, never deleted** (migration `…_supplier_archive`: `Supplier.isArchived/archivedAt`,
  `SupplierPayment → Supplier` ON DELETE NO ACTION). `POST /suppliers/:id/archive` (= `DELETE`) only when settled,
  `/restore`, `filter=archived`. Suppliers screen: Active / Archived chips, balances in words via `supplierBalanceText`
  ("You owe ₹x" / "₹x advance paid" / "Settled") instead of "Pending: ₹-x", Archive/Restore in the row menu.
  Supplier opening balance is still editable after creation (customers: creation only). Backend 12/12.
- **Products archived, never deleted** (user decision, no migration – archived = `Product.isActive = false`). Before:
  sold products were silently hidden with no way back, never-sold ones hard-deleted (cascading batches / branch prices).
  Now `POST /products/:id/archive` (= `DELETE`) and `/restore`, `GET /products?filter=archived`; archived products are
  not scannable, can't be sold (400 "… is archived – restore it", offline bills exempt), and their barcode can't be
  reused by a new product (400 pointing to the archived one). Past bills keep their own name / price per line.
  App: Inventory → Products "Archive" (explains; mentions remaining stock), "Archived" chip with Restore + stock history;
  the product form's "Active" switch is gone. Backend 13/13.
- **Archived customers take no payments**: no Receive Payment / Advance / Refund buttons on their details (amber
  "Archived" note with Restore instead); the API refuses payments and refunds for them (409 "restore them first").
- **Customers → History = customer events**, not payments: new activity entries `customer_created` (with opening
  balance), `customer_updated` (what changed, e.g. "name Asha → Asha K"), `customer_imported`, plus archived /
  restored; `GET /customers/activity` (customers.manage). `GET /customers/payments` removed (payments stay in each
  customer's account statement and in reports). Backend 13/13.
  Customer history also lists **advance events**: advance received (payment above the due – `payment_received`
  entries mentioning "advance", incl. older ones), **change kept as advance** on a bill (now logged by checkout), and
  advance refunded (`advance_refunded`). Plain payments of dues stay out.

### Environment
- Mac LAN IP **192.168.0.31** (it was briefly 192.168.29.39 on 2026-10-26) – always check `ipconfig getifaddr en0`.
  LAN run (2026-10-26): web built with `API_URL=http://192.168.0.31:4000` and served with
  `python3 -m http.server 8080 --bind 0.0.0.0` → http://192.168.0.31:8080; new release APK built for the same IP
  (not installed yet – no USB device). macOS firewall is off; API CORS allows any origin.
- API `npm run dev` on :4000 (restart it after `prisma migrate` – the running process keeps the old Prisma client and
  logins fail with 500); web build served by `python3 -m http.server 8080 --bind 127.0.0.1` from app/build/web.
- Builds: `flutter build apk --release --dart-define=API_URL=http://<mac-ip>:4000`,
  `flutter build web --release --dart-define=API_URL=http://localhost:4000` (open http://127.0.0.1:8080/?v=N#/pos).
- Release APK installed on the user's **Nexgo N82**; Nexgo/Bluetooth printing and the OnePe app hand-off not yet confirmed on the device.
- Demo shop is now RESTAURANT (features kot/tables/loyalty on, barcode off by default → POS scan button hidden until switched on).
- Demo DB test data: bills ODB-MAIN-20261024-010…021 (021 cancelled, "Wrong item test"); 2026-10-26 offline tests created and
  cancelled a few bills ("offline test", "offline queue test").
- Claude in Chrome extension was not connected this session → UI checked with temporary Flutter widget tests (Manrope font
  loaded, 360 px + 1280 px) instead of screenshots.
- Login 500 earlier was Docker Desktop hung + low disk; fix = restart Docker, `docker compose up -d`, free space.

### Next
- Restaurant-only screens: **Tables** (free/occupied grid, open/continue a table's order, KOT status) and **Kitchen** (KOT list).
- Services extras later (staff per service, appointments) – user to confirm.
- Confirm on the N82: built-in print, Bluetooth print, OnePe app collect, payment-received pop-up, offline mode (backup folder,
  saved catalog, idle sync), new menus/settings.
- Open question to the user: with collection ON, should Print Bill / Save without printing also ask the payment mode (currently saves as Cash)?
- Returns / credit notes against a bill (`ReturnNote` model exists) as the GST-friendly correction path.
