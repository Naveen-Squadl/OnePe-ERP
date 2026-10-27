import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api.dart';
import '../../models/models.dart';
import '../../state/catalog.dart';
import '../widgets/app_shell.dart';
import '../widgets/common.dart';
import 'products/products_screen.dart';

class CategoriesScreen extends StatefulWidget {
  const CategoriesScreen({super.key});
  @override
  State<CategoriesScreen> createState() => _CategoriesScreenState();
}

class _CategoriesScreenState extends State<CategoriesScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => context.read<Catalog>().load());
  }

  Future<void> _edit([Category? cat]) async {
    final name = TextEditingController(text: cat?.name);
    bool stock = cat?.isStockCategory ?? true;
    bool expense = cat?.isExpenseCategory ?? false;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, set) => AlertDialog(
          title: Text(cat == null ? 'Add Category' : 'Edit Category'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: name, autofocus: true, decoration: const InputDecoration(labelText: 'Category Name *', hintText: 'e.g. Cakes, Beverages, Snacks')),
            SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('Is Stock Category?'), subtitle: const Text('Items appear in Stock Management'), value: stock, onChanged: (v) => set(() => stock = v)),
            SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('Is Expense Category?'), subtitle: const Text('Items are billed as expense vouchers'), value: expense, onChanged: (v) => set(() => expense = v)),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Save')),
          ],
        ),
      ),
    );
    if (ok != true || name.text.trim().isEmpty || !mounted) return;
    final body = {'name': name.text.trim(), 'isStockCategory': stock, 'isExpenseCategory': expense};
    final r = await guard(context, () => cat == null ? Api.instance.post('/categories', body) : Api.instance.put('/categories/${cat.id}', body));
    if (r != null && mounted) context.read<Catalog>().load();
  }

  @override
  Widget build(BuildContext context) {
    final catalog = context.watch<Catalog>();
    return AppScaffold(
      title: 'Categories',
      fab: FloatingActionButton.extended(onPressed: () => _edit(), icon: const Icon(Icons.add), label: const Text('Add Category')),
      body: catalog.categories.isEmpty
          ? const EmptyState(icon: Icons.category_outlined, title: 'No categories found. Tap + to add one.')
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
              itemCount: catalog.categories.length,
              separatorBuilder: (_, _) => const SizedBox(height: 6),
              itemBuilder: (_, i) {
                final c = catalog.categories[i];
                return Card(
                  child: ListTile(
                    leading: Icon(c.isExpenseCategory ? Icons.money_off : Icons.category),
                    title: Text(c.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                    subtitle: Text('${c.productCount} products • tap to view'),
                    // Inventory hub: show this category's products in the Products tab.
                    onTap: () {
                      ProductsScreen.categoryFilter.value = c.id;
                      DefaultTabController.maybeOf(context)?.animateTo(0);
                    },
                    trailing: Wrap(spacing: 4, children: [
                      if (c.isStockCategory) const Pill('Stock Item', Colors.teal),
                      if (c.isExpenseCategory) const Pill('Expense', Colors.deepOrange),
                      PopupMenuButton<String>(
                        onSelected: (v) async {
                          if (v == 'edit') return _edit(c);
                          if (await confirm(context, 'Delete Category', 'Delete ${c.name}? Products will become uncategorized.', danger: true, ok: 'Delete') && context.mounted) {
                            final r = await guard(context, () => Api.instance.delete('/categories/${c.id}'));
                            if (r != null && context.mounted) context.read<Catalog>().load();
                          }
                        },
                        itemBuilder: (_) => const [PopupMenuItem(value: 'edit', child: Text('Edit Category')), PopupMenuItem(value: 'delete', child: Text('Delete Category'))],
                      ),
                    ]),
                  ),
                );
              },
            ),
    );
  }
}
