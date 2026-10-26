import 'dart:convert';

import 'package:flutter/foundation.dart' hide Category;

import '../core/api.dart';
import '../core/format.dart';
import '../models/models.dart';
import '../services/customer_cache.dart';
import '../services/local_store.dart';
import '../services/offline_photos.dart';
import '../services/offline_queue.dart';

/// Products + categories for the active branch (used by POS and pickers).
/// Every successful load is saved on the device per branch; when the server can't be reached the saved
/// copy is used ([savedAt] is then set) so billing keeps working offline. Shown stock = server stock minus
/// the items of offline bills not uploaded yet.
class Catalog extends ChangeNotifier {
  Catalog() {
    // Back online → live data; offline bills uploaded → stock from the server again.
    Api.online.addListener(() {
      if (Api.online.value && savedAt != null) load();
    });
    var pending = OfflineQueue.pending.value;
    OfflineQueue.pending.addListener(() {
      if (OfflineQueue.pending.value < pending && Api.online.value) load();
      pending = OfflineQueue.pending.value;
    });
  }

  static const filePrefix = 'catalog_';
  final _api = Api.instance;
  List<Product> products = [];
  List<Category> categories = [];
  bool loading = false;
  String? error;

  /// When the products on screen were saved – non-null only while working from the device copy.
  DateTime? savedAt;

  Future<void> load() async {
    loading = true;
    error = null;
    notifyListeners();
    final file = '$filePrefix${_api.branchId ?? 'default'}.json';
    try {
      final res = await Future.wait([_api.get('/products'), _api.get('/categories')]);
      await _apply(res[0] as List, res[1] as List);
      savedAt = null;
      LocalStore.write(file, jsonEncode({'savedAt': DateTime.now().toIso8601String(), 'products': res[0], 'categories': res[1]}));
      OfflinePhotos.prefetch(products.map((p) => p.imageUrl));
      CustomerCache.refresh();
    } on ApiException catch (e) {
      final saved = e.isNetwork ? await LocalStore.read(file) : null;
      if (saved != null) {
        final data = jsonDecode(saved) as Map<String, dynamic>;
        await _apply(data['products'] as List, data['categories'] as List);
        savedAt = DateTime.tryParse(data['savedAt'] ?? '');
      } else {
        error = e.message;
      }
    }
    loading = false;
    notifyListeners();
  }

  Future<void> _apply(List products, List categories) async {
    // Quantities in this branch's offline bills that the server doesn't know about yet.
    final sold = <String, double>{};
    for (final e in await OfflineQueue.all()) {
      if (e['branchId'] != null && e['branchId'] != _api.branchId) continue;
      for (final i in (e['bill']['items'] as List? ?? const [])) {
        final id = i['productId'] as String?;
        if (id != null) sold[id] = (sold[id] ?? 0) + toDouble(i['quantity']);
      }
    }
    this.products = [
      for (final e in products)
        Product({
          ...Map<String, dynamic>.from(e),
          if (sold[e['id']] != null && e['trackStock'] != false) 'stock': toDouble(e['stock']) - sold[e['id']]!,
        }),
    ];
    this.categories = categories.map((e) => Category.fromJson(e)).toList();
  }

  List<Product> filter({String? categoryId, String query = '', bool expense = false}) {
    final q = query.trim().toLowerCase();
    return products.where((p) {
      if (p.isExpense != expense) return false;
      if (categoryId != null && p.categoryId != categoryId) return false;
      if (q.isEmpty) return true;
      return p.name.toLowerCase().contains(q) || p.barcode == query.trim() || (p.hsnCode ?? '').startsWith(q);
    }).toList();
  }

  Product? byBarcode(String code) => products.where((p) => p.barcode == code.trim()).firstOrNull;
}
