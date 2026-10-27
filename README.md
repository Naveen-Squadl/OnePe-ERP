# OnePe POS ERP

Multi-tenant POS + inventory system for bakeries, restaurants and retail shops, modelled on the
feature set of LABAN POS (bakery-pos-490b7.web.app) and rebuilt under the OnePe brand.

```
OnePe_POS_ERP/
├── backend/            Node 22+ · TypeScript · Express 5 · Prisma 6 · PostgreSQL
│   ├── prisma/         schema.prisma, migrations, seed.ts
│   ├── src/
│   │   ├── lib/        config, auth helpers, permissions matrix, sequences, money
│   │   ├── services/   billing (checkout/edit/cancel/restore), stock (FIFO batches),
│   │   │               ledger, reports, settings, session
│   │   └── routes/     REST endpoints (see API below)
│   └── test/           end-to-end API tests (npm test)
├── app/                Flutter 3.41 client – web, Android, iOS from one codebase
│   └── lib/
│       ├── core/       API client, config, formatting, theme
│       ├── models/     typed models
│       ├── state/      Session, Catalog, Cart (provider)
│       ├── services/   printing (thermal/A4/KOT PDF), WhatsApp share, offline queue
│       └── ui/         router, shell/drawer, screens
└── docker-compose.yml  PostgreSQL 16
```

## Run it locally

```bash
# 1. Database
docker compose up -d

# 2. API  (http://localhost:4000)
cd backend
cp .env.example .env          # set JWT_SECRET for anything beyond local dev
npm install
npx prisma migrate deploy
npm run db:seed               # super admin + demo bakery
npm run dev

# 3. App
cd ../app
flutter pub get
flutter run -d chrome --dart-define=API_URL=http://localhost:4000
```

Seeded logins:

| Role        | Email                 | Password      |
|-------------|-----------------------|---------------|
| Super Admin | admin@onepe.local     | ChangeMe@123  |
| Shop Admin  | demo@onepe.local      | Demo@1234     |
| Cashier     | cashier@onepe.local   | Cashier@123   |

### Mobile builds

```bash
cd app
# Android emulator reaches the host machine at 10.0.2.2
flutter run -d emulator-5554 --dart-define=API_URL=http://10.0.2.2:4000
flutter build apk --release   --dart-define=API_URL=https://api.your-domain.com
flutter build ipa --release   --dart-define=API_URL=https://api.your-domain.com
flutter build web --release   --dart-define=API_URL=https://api.your-domain.com
```

For production remove `android:usesCleartextTraffic="true"` from `AndroidManifest.xml` and serve the API over HTTPS.

### Tests

```bash
cd backend && npm test        # end-to-end against the dev DB (creates and deletes its own shop)
cd app && flutter analyze
```

## Feature coverage – Phase 1 (Retail / Bakery core)

| Area | What is implemented |
|---|---|
| Auth & tenancy | JWT login, shop + branch context, plan expiry warning, inactive shop/user blocking |
| Roles | Super Admin, Admin, Manager, Cashier, Salesman, Biller, Store Keeper, Stock Manager with a permission matrix enforced by the API and the menu |
| POS | category chips, search, barcode/QR scan, list/2-col/3-col views, variable price items, base/last/max/custom price, item & bill discounts (flat/%), loyalty redeem, tables, hold/waiting list, KOT, expense vouchers, cash/UPI(QR)/card/credit, change vs. account credit, auto-create customer by mobile |
| Bills history | waiting/completed tabs, search, date filter, edit (reverts & re-applies stock/balances), cancel, soft delete, restore, permanent delete, print, WhatsApp, PDF export |
| Offline | bills checked out while offline are queued with a client UUID, auto-synced idempotently (`/sync/push`), and on Android backed up to `Download/OnePe/OfflineBills` (folder granted once → automatic recovery/clean-up); products/categories and photo thumbnails are kept on the device for offline billing |
| Products & categories | **product photos** (camera / gallery upload, shown on POS cards & lists), barcode auto-generate + label printing, per-branch availability & price, barcode, HSN, GST (CGST/SGST/IGST), stock/expense categories, opening stock with batch & expiry, archive-on-delete, bulk import endpoint |
| Customers | ledger with opening/running/closing balance, payments with receipts, bills & payment history, loyalty points |
| Suppliers & purchases | supplier payables, purchase bills, purchase orders → inward, batches & expiry, margin hints |
| Stock | per-branch stock, +Qty/−Qty/Set, inward batches, FIFO batch consumption with exact reversal, expiring/expired filters, immutable stock history, customer returns (good/damaged/old stock, cash refund/account credit) |
| Reports | business summary (gross, discounts, net, expenses, net collection, hourly/day/week/month trend, peak, payment split, top items), sales matrix, customer sales, outstanding, user sales, inventory valuation by location, GST HSN (GSTR-1 Table 12) + slab summary, purchases, branch-wise; PDF export |
| Branches | outlet limit from plan, tables & UPI per branch, outlet switcher |
| Settings | shop logo (printed on receipts), shop details, shop type, default price option, GST inclusive/exclusive, loyalty ratio, KOT, tables, storage locations, print sections, paper size (58/80mm/A4) |
| Printing | 58/80mm thermal receipt, A4 tax invoice with amount in words + UPI QR, KOT ticket, payment receipt – via the OS print dialog |
| Super Admin | system stats, create shop (+admin +main branch), subscription/plan/limits/expiry, activate/deactivate/delete, all users, activity logs, enquiries (call/WhatsApp/status) |

### Planned next phases
- Direct Bluetooth ESC/POS printing (58/80mm) and network printers
- Excel import/export in the client, invoice OCR for purchase entry
- Distributor line-stock (load to line / returns), Parking (entry/exit tickets), Logistics (lorry receipts, consolidated invoices)
- Real-time push (WebSocket) for multi-device bill sync

## UI

The layout mirrors the original app: blue gradient headers, Poppins type, a collapsible
**Order Details** card, colored category chips, photo product cards with in-cart steppers,
a right-hand cart with price-option dropdowns, the green **Proceed to Payment** action,
a **Reports ⇄ Shop** toggle that swaps the product grid for the 3-column reports view,
and the original's bill number format (`<SHOP INITIALS>-<BRANCH>-<YYYYMMDD>-<SEQ>`).

Uploaded images are stored under `backend/uploads/<shopId>/` and served from `/uploads`.
For production, point this at object storage (S3 / GCS) or back the folder up.

## API overview

All routes are under `/api`; tenant routes need `Authorization: Bearer <token>` and accept `X-Branch-Id` to pick the outlet (Admin/Manager).

| Group | Endpoints |
|---|---|
| auth | `POST /auth/login`, `GET /auth/me`, `POST /auth/change-password` |
| shop/branches/users | `GET/PUT /shop`, `CRUD /branches`, `CRUD /users`, `GET /users/roles` |
| catalog | `CRUD /categories`, `CRUD /products`, `GET /products/barcode/:code`, `POST /products/import` |
| customers | `CRUD /customers`, `GET /customers/phone/:phone`, `GET /customers/:id/ledger`, `GET /customers/:id/bills`, `GET /customers/payments`, `POST /customers/:id/payments`, `POST /customers/import` |
| bills | `GET /bills`, `GET /bills/:id`, `POST /bills/checkout`, `POST /bills/:id/kot`, `POST /bills/:id/cancel`, `DELETE /bills/:id`, `POST /bills/:id/restore`, `DELETE /bills/:id/permanent` |
| stock | `GET /stock`, `POST /stock/adjust`, `POST /stock/inward`, `GET /stock/batches`, `GET /stock/history` |
| purchasing | `CRUD /suppliers`, `POST /suppliers/:id/payments`, `GET/POST /purchases`, `POST /purchases/:id/inward`, `DELETE /purchases/:id`, `GET/POST /returns` |
| reports | `/reports/summary`, `sales-matrix`, `customer-sales`, `customer-ledger/:id`, `outstanding`, `user-sales`, `inventory`, `gst`, `purchases`, `branch-sales` (accept `preset` or `from`/`to`, `branch=all`) |
| sync | `GET /sync/pull?since=`, `POST /sync/push` |
| admin | `/admin/stats`, `/admin/plans`, `CRUD /admin/shops`, `/admin/users`, `/admin/activity`, `/admin/enquiries` |
| public | `POST /public/enquiries`, `GET /public/legal` |
| uploads | `POST /uploads` (multipart `file`, JPG/PNG/WEBP ≤ 3 MB) → `{ url }` |
