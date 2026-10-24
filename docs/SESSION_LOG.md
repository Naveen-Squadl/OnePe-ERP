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
