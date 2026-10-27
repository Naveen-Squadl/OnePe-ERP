import 'package:flutter/material.dart';

import '../../widgets/app_shell.dart';
import '../categories_screen.dart';
import '../products/products_screen.dart';
import '../stock/stock_views.dart';

/// Inventory: Products (with stock) | Categories | Batches & Expiry | Stock History.
class InventoryScreen extends StatelessWidget {
  final String? tab;
  const InventoryScreen({super.key, this.tab});

  @override
  Widget build(BuildContext context) => HubScaffold(
        title: 'Inventory',
        initial: tab,
        tabs: [
          HubTab('products', 'Products', (_) => const ProductsScreen(), permissions: const ['products.manage', 'products.edit_limited', 'inventory.view']),
          HubTab('categories', 'Categories', (_) => const CategoriesScreen(), permissions: const ['products.manage']),
          HubTab('batches', 'Batches & Expiry', (_) => const StockBatchesView(), permissions: const ['inventory.view', 'inventory.manage'], feature: 'batches'),
          HubTab('history', 'Stock History', (_) => const StockHistoryView(), permissions: const ['inventory.view', 'inventory.manage'], feature: 'stock'),
        ],
      );
}
