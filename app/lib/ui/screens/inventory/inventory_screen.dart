import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../state/session.dart';
import '../../history_sources.dart';
import '../../widgets/app_shell.dart';
import '../../widgets/history_panel.dart';
import '../categories_screen.dart';
import '../products/products_screen.dart';
import '../stock/stock_views.dart';

/// Inventory: Products (with stock) | Categories | Batches & Expiry; stock movements via the History button.
class InventoryScreen extends StatelessWidget {
  final String? tab;
  const InventoryScreen({super.key, this.tab});

  @override
  Widget build(BuildContext context) {
    final session = context.watch<Session>();
    return HubScaffold(
      title: 'Inventory',
      initial: tab,
      actions: [
        if (session.can('inventory.view') && (session.shop?.has('stock') ?? false))
          HistoryButton(tooltip: 'Stock history', onPressed: () => showStockHistory(context)),
      ],
      tabs: [
        HubTab('products', 'Products', (_) => const ProductsScreen(), permissions: const ['products.manage', 'products.edit_limited', 'inventory.view']),
        HubTab('categories', 'Categories', (_) => const CategoriesScreen(), permissions: const ['products.manage']),
        HubTab('batches', 'Batches & Expiry', (_) => const StockBatchesView(), permissions: const ['inventory.view', 'inventory.manage'], feature: 'batches'),
      ],
    );
  }
}
