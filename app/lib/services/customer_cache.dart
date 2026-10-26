import 'dart:convert';

import '../core/api.dart';
import '../models/models.dart';
import 'local_store.dart';
import 'offline_queue.dart';

/// Customers saved on the device so the POS customer search works offline (≈300 bytes per customer).
/// Balances shown offline are as of the last refresh; the server recalculates them when bills sync.
class CustomerCache {
  CustomerCache._();
  static const filePrefix = 'customers_';
  static DateTime? _refreshed;

  static String get _file => '$filePrefix${OfflineQueue.shopId ?? 'default'}.json';

  static Future<void> save(List customers) => LocalStore.write(_file, jsonEncode(customers));

  /// Refreshes the saved list, at most every 10 minutes (called after the catalog loads).
  static Future<void> refresh() async {
    if (_refreshed != null && DateTime.now().difference(_refreshed!) < const Duration(minutes: 10)) return;
    _refreshed = DateTime.now();
    try {
      await save(await Api.instance.get('/customers') as List);
    } catch (_) {
      _refreshed = null;
    }
  }

  /// Offline search by name, mobile or GSTIN.
  static Future<List<Customer>> search(String query) async {
    final saved = await LocalStore.read(_file);
    if (saved == null) return [];
    final q = query.trim().toLowerCase();
    return [
      for (final raw in jsonDecode(saved) as List)
        if (q.isEmpty ||
            '${raw['name'] ?? ''}'.toLowerCase().contains(q) ||
            '${raw['phone'] ?? ''}'.contains(q) ||
            '${raw['gstin'] ?? ''}'.toLowerCase().contains(q))
          Customer(Map<String, dynamic>.from(raw)),
    ];
  }
}
