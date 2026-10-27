/// Business types and optional features. The business type decides which features are available and
/// which are on by default; the admin can switch available ones in Settings → Features.
/// Mirror of backend/src/lib/features.ts – change both together. (The server sends each shop's effective
/// switches as `shop.features`; this table drives the Settings screen.)
class BusinessType {
  final String id;
  final String label;
  final String hint;
  const BusinessType(this.id, this.label, this.hint);
}

const businessTypes = [
  BusinessType('RESTAURANT', 'Restaurant / QSR / Bakery', 'Tables, KOT to the kitchen, batches & expiry'),
  BusinessType('RETAIL', 'Retail', 'Barcodes, stock, purchases, storage locations'),
  BusinessType('SERVICES', 'Services', 'Salon, spa, repairs… services without stock, loyalty'),
  BusinessType('OTHER', 'Others', 'Every feature available – switch on what you need'),
];

String businessTypeLabel(String id) => businessTypes.where((t) => t.id == id).firstOrNull?.label ?? id;

class FeatureInfo {
  final String key;
  final String label;
  final String description;

  /// Settings → Features group: Selling, Inventory or Purchases.
  final String group;
  const FeatureInfo(this.key, this.label, this.description, this.group);
}

const featureInfo = [
  FeatureInfo('tables', 'Tables & dine-in', 'Pick a table for an order and keep it open until the guest pays', 'Selling'),
  FeatureInfo('kot', 'Kitchen order tickets (KOT)', 'SEND TO KITCHEN in the cart and a kitchen printer', 'Selling'),
  FeatureInfo('credit', 'Customer credit (dues)', 'Bill a customer without full payment and collect later', 'Selling'),
  FeatureInfo('loyalty', 'Loyalty points', 'Customers earn points on bills and redeem them', 'Selling'),
  FeatureInfo('barcode', 'Barcodes & labels', 'Scan items at the counter and print barcode labels', 'Selling'),
  FeatureInfo('stock', 'Stock tracking', 'Stock levels, stock entry and stock history', 'Inventory'),
  FeatureInfo('batches', 'Batches & expiry', 'Batch numbers and expiry dates with reminders (needs stock tracking)', 'Inventory'),
  FeatureInfo('locations', 'Storage locations', 'Showroom, warehouse… where stock is kept', 'Inventory'),
  FeatureInfo('purchases', 'Purchases & suppliers', 'Purchase bills, pending POs and supplier balances', 'Purchases'),
];

/// true / false = default when available; null = not available for the business type.
const featureDefaults = <String, Map<String, bool?>>{
  'RESTAURANT': {'tables': true, 'kot': true, 'stock': true, 'batches': true, 'barcode': false, 'purchases': true, 'credit': true, 'loyalty': false, 'locations': false},
  'RETAIL': {'tables': null, 'kot': null, 'stock': true, 'batches': false, 'barcode': true, 'purchases': true, 'credit': true, 'loyalty': false, 'locations': true},
  'SERVICES': {'tables': null, 'kot': null, 'stock': false, 'batches': null, 'barcode': false, 'purchases': false, 'credit': true, 'loyalty': true, 'locations': null},
  'OTHER': {'tables': false, 'kot': false, 'stock': true, 'batches': false, 'barcode': true, 'purchases': true, 'credit': true, 'loyalty': false, 'locations': false},
};

bool featureAvailable(String shopType, String key) => featureDefaults[shopType]?[key] != null;

/// Effective switches for a business type and the admin's choices (same rules as the server).
Map<String, bool> effectiveFeatures(String shopType, Map<String, dynamic> chosen) {
  final out = <String, bool>{
    for (final f in featureInfo)
      f.key: featureAvailable(shopType, f.key) && (chosen[f.key] is bool ? chosen[f.key] as bool : featureDefaults[shopType]![f.key]!),
  };
  out['batches'] = out['batches']! && out['stock']!;
  return out;
}
