import 'package:flutter/foundation.dart' hide Category;

import '../core/api.dart';
import '../models/models.dart';

/// Products + categories for the active branch (used by POS and pickers).
class Catalog extends ChangeNotifier {
  final _api = Api.instance;
  List<Product> products = [];
  List<Category> categories = [];
  bool loading = false;
  String? error;

  Future<void> load() async {
    loading = true;
    error = null;
    notifyListeners();
    try {
      final res = await Future.wait([_api.get('/products'), _api.get('/categories')]);
      products = (res[0] as List).map((e) => Product(Map<String, dynamic>.from(e))).toList();
      categories = (res[1] as List).map((e) => Category.fromJson(e)).toList();
    } on ApiException catch (e) {
      error = e.message;
    }
    loading = false;
    notifyListeners();
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
