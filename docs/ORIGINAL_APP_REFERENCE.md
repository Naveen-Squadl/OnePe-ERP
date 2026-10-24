# Original app reference (LABAN POS v5.3.2) — observed 2026-10-15

Read-only notes for keeping OnePe visually and functionally aligned. Do not copy branding.

## Visual language
- Header: blue → light-blue horizontal gradient (≈ #2F80ED → #56CCF2), white icons, centred white bold title,
  back arrow on inner pages. Font: Poppins.
- Background #F7F8FA; white cards, radius ~14–16, light border; dialogs light grey (#F1F3F7) radius ~24.
- Primary action: green gradient button with icon ("Proceed to Payment"); FABs green extended ("Add Product",
  "Add Customer", "Add Staff"). Secondary: green outlined ("Apply Bill Discount"). Prices green; totals blue.
- Category chips: pill with coloured dot and tinted background; selected = solid blue.
- Row actions: small tinted icon buttons (print purple, edit blue, delete red, wallet orange, history blue).

## POS (home)
- Top bar: ☰, store icon … "Reports ⇄" pill (toggles to reports view, label becomes "Shop ⇄"), new order (cart+),
  bills list, profile avatar, sync, cart, ☰.
- "Order Details" collapsible card: Storage/Counter (table), Customer, Mobile, Loyalty Points.
- Search bar with grid-toggle + QR scan icons; category chip row.
- Product card: image area (photo or blue bag placeholder) + category badge top-left, "N in Cart" green badge,
  name, green price, "Stock: N" (red when ≤0), full-width "+ Add" → becomes [− qty✎ +] with green card border.
- Right cart pane: item card (name + line total blue; price dropdown "Basic: ₹180 / Max: ₹300 / Custom / Edit";
  − [qty✎] +; "Add Discount"); bottom summary sheet: Subtotal, Tax (GST), TOTAL (big blue),
  Apply Bill Discount, Proceed to Payment.
- Payment Summary dialog: Bill Total card, "Add Bill Discount", Customer Mobile, Received Amount, Change,
  Cancel, "Confirm Amount".

## Drawer ("Navigation Menu")
Gradient header (shop name, "… POS System", "Exp: <date>" chip). Items with coloured square icons + chevrons:
Dashboard, Manage Products (count badge), Manage Categories, Manage Customers, Manage Suppliers,
Purchase History, Settings, Printer Settings, Sync Cloud Data, Bills History, Reports & Analytics,
Stock Management, User Management, Branches. Footer: user name + role, logout, version.

## Other screens
- Dashboard: Period chips (Today/This Week/This Month/Last Month/Custom); Sales Summary with 7 icon metrics
  (Gross, Discounts, Net Sales, Expenses, Net Collection, Transactions, Avg. Value) + formula banner;
  "Sales Trends & Velocity" hourly bars 6 AM–10 PM ("1-Hr Slots"); Payment Methods; Top Selling Products.
- Products: search, chips, rows (icon/photo tile, name, "₹base - ₹max", stock pill, category tag, print/edit/delete).
  Add Product dialog: photo box, name, barcode box (field + camera, "Scan with Camera", Auto-Generate, Print Label),
  Category + "Add/Manage Categories", Base/Max/Last price, HSN/SAC, Stock Qty, GST box (Total → CGST/SGST/IGST),
  Multi-Brand Pricing & Stock (brand, price, qty, location), Variable Price checkbox. (Brands not yet in OnePe.)
- Customers: avatar letter, phone, "Balance: ₹0.00" pill; wallet/history/edit/delete; purchase history dialog.
- Bills History: gradient header with search + Waiting/Completed tabs; actions export/deleted/calendar;
  cards "Walk-in Customer", "#002 ⏱ 05:00 PM", COMPLETED pill, Guest/items/method/"Billed by", amount, edit/cancel/delete.
  Bill Details dialog: Date/Time/Table, Customer, Order Summary, Subtotal/GST/Grand Total, Preview/Edit/Print.
  Bill no format seen: `GS-COUNTER-20261013-002`.
- Reports (3 columns): Filters & Controls (Today/Yesterday/Last 7 Days/This Month/Last Month, date range,
  Line Person/Staff filter, Customer filter, Reset), tabs (Sales Matrix, Customer Sales, Outstanding, User Sales,
  Inventory, Stock History, GST & Taxes, Purchase Reports), Quick Actions & Export (Excel, PDF, WhatsApp,
  Manage Line Stock, Report Analytics card). Sales Matrix = customers × products, cells "qty / ₹amount".
- Shop Settings: Add Logo, name, address, contact, Shop Type, Default Printer Type, Default Selling Price Option,
  Loyalty toggle, WhatsApp toggles, GST number, Thanks note, UPI ID, Table Management, Storage Locations,
  Multi-Branch link, SAVE SETTINGS, Upload to Cloud, Deep Sync.
- Stock Management: category dropdown, search, location dropdown, Inward/Outward/Set segmented,
  rows with stock pill, "N Batches" dropdown, qty box + green ✓.
- User Management: avatar, name, email, "⚡ Online" chip, role tag, edit/delete; "Add Staff".

## Features in the original not yet in OnePe
Excel export/import, Bluetooth ESC/POS printer pairing, invoice OCR, multi-brand pricing/stock per product,
distributor line stock (load/return), parking tickets, logistics LR/consolidated invoices, legal-policy acceptance screen.
