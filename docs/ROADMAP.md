# Roadmap

## Immediately next
- [ ] Run on an Android phone (USB: `adb reverse tcp:4000 tcp:4000` + `flutter run --release --dart-define=API_URL=http://localhost:4000`).
- [ ] Compile & smoke-test Android APK and iOS build (camera permission, image picker, printing dialog).

## Phase 1 gaps (Retail/Bakery core)
- [ ] Excel export (.xlsx) for reports/products/customers + Excel import (endpoints `/products/import`, `/customers/import` exist).
- [ ] Direct Bluetooth ESC/POS printing (58/80mm) + KOT printer selection (settings fields already exist).
- [ ] Multi-brand pricing & stock per product (original's "Multi-Brand Pricing & Stock (Retails)").
- [ ] Supplier invoice OCR for purchase entry (use own key/service; never the original's key).
- [ ] "Printer Settings" deep-link scroll in Settings (`/settings?section=printer` currently opens top).
- [ ] Image storage: move `backend/uploads` to object storage for production; resize/thumbnail server-side.
- [ ] Production: HTTPS hosting for API, strong JWT_SECRET, remove Android cleartext flag, CI for tests.

## Phase 2
- [ ] Distributor: load stock to line person, returns (good/damaged/old), line stock reports.

## Phase 3
- [ ] Parking: entry tickets, exit billing by duration.
- [ ] Logistics: lorry receipts (LR), vehicles, consolidated invoices.
