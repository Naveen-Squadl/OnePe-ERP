import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/api.dart';
import '../../../core/format.dart';
import '../../../core/theme.dart';
import '../../../models/models.dart';
import '../../../services/print_service.dart';
import '../../../state/catalog.dart';
import '../../../state/session.dart';
import '../../widgets/app_shell.dart';
import '../../widgets/brand.dart';
import '../../widgets/common.dart';
import 'product_form.dart';

class ProductsScreen extends StatefulWidget {
  const ProductsScreen({super.key});
  @override
  State<ProductsScreen> createState() => _ProductsScreenState();
}

class _ProductsScreenState extends State<ProductsScreen> {
  String _q = '';
  String _scope = 'this_branch';
  String? _categoryId;
  int _v = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (context.read<Catalog>().categories.isEmpty) context.read<Catalog>().load();
    });
  }

  Future<List<Product>> _load() async =>
      (await Api.instance.get('/products', {'q': _q, 'scope': _scope, 'categoryId': _categoryId}) as List).map((e) => Product(Map<String, dynamic>.from(e))).toList();

  Future<void> _open([Product? p]) async {
    final saved = await showProductForm(context, p);
    if (saved && mounted) {
      setState(() => _v++);
      context.read<Catalog>().load();
    }
  }

  Future<void> _delete(Product p) async {
    if (!await confirm(context, 'Delete Product', 'Are you sure you want to delete ${p.name}? Products used in bills are archived instead.', ok: 'Delete', danger: true)) return;
    if (!mounted) return;
    final r = await guard(context, () => Api.instance.delete('/products/${p.id}'), success: 'Product deleted');
    if (r != null && mounted) {
      setState(() => _v++);
      context.read<Catalog>().load();
    }
  }

  Future<void> _printLabel(Product p) async {
    if (p.barcode == null) return showSnack(context, 'Add a barcode to ${p.name} first (Edit → Auto-Generate).', error: true);
    final copies = await askNumber(context, 'Print Barcode • ${p.name}', label: 'Number of labels', initial: 1);
    if (copies == null || copies < 1) return;
    await PrintService.printBarcodeLabel(name: p.name, code: p.barcode!, price: p.price, copies: copies.toInt());
  }

  Future<void> _export(List<Product> list) => PrintService.exportTablePdf(
        title: 'Products',
        subtitle: '${list.length} products',
        headers: ['Name', 'Category', 'Barcode', 'HSN', 'Base Price', 'Max Price', 'GST %', 'Stock'],
        rows: [
          for (final p in list)
            [p.name, p.categoryName ?? '-', p.barcode ?? '-', p.hsnCode ?? '-', p.basePrice.toStringAsFixed(2), p.maxPrice?.toStringAsFixed(2) ?? '-', p.gstPercent.toStringAsFixed(0), qty(p.stock)],
        ],
      );

  @override
  Widget build(BuildContext context) {
    final cats = context.watch<Catalog>().categories;
    final multiBranch = context.watch<Session>().branches.length > 1;
    List<Product> current = const [];
    return AppScaffold(
      title: 'Product Management',
      actions: [
        IconButton(tooltip: 'Export products (PDF)', onPressed: () => _export(current), icon: const Icon(Icons.download_rounded)),
      ],
      fab: FloatingActionButton.extended(onPressed: () => _open(), icon: const Icon(Icons.add), label: const Text('Add Product')),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: _RoundSearch(hint: 'Search products by name, barcode or HSN...', onChanged: (v) => setState(() => _q = v)),
        ),
        SizedBox(
          height: 56,
          child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.fromLTRB(16, 10, 16, 6), children: [
            CategoryChip(label: 'All', color: AppColors.blue, selected: _categoryId == null, onTap: () => setState(() => _categoryId = null)),
            for (final (i, c) in cats.indexed)
              CategoryChip(label: c.name, color: AppColors.forIndex(i), selected: _categoryId == c.id, onTap: () => setState(() => _categoryId = c.id)),
            if (multiBranch) ...[
              const SizedBox(width: 8),
              FilterChip(
                label: Text(_scope == 'this_branch' ? 'My Outlet' : 'All Outlets (Consolidated)'),
                selected: _scope == 'all_branches',
                onSelected: (v) => setState(() => _scope = v ? 'all_branches' : 'this_branch'),
              ),
            ],
          ]),
        ),
        const Divider(height: 1),
        Expanded(
          child: Loader<List<Product>>(
            key: ValueKey('$_q$_scope$_categoryId$_v'),
            load: _load,
            builder: (context, list, reload) {
              current = list;
              if (list.isEmpty) {
                return ListView(children: const [SizedBox(height: 60), EmptyState(icon: Icons.inventory_2_outlined, title: 'No products match your search or filter.')]);
              }
              return ListView.separated(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 96),
                itemCount: list.length,
                separatorBuilder: (_, _) => const SizedBox(height: 10),
                itemBuilder: (_, i) {
                  final p = list[i];
                  final ci = cats.indexWhere((c) => c.id == p.categoryId);
                  final color = ci < 0 ? AppColors.muted : AppColors.forIndex(ci);
                  final stock = _scope == 'all_branches' ? toDouble(p.raw['totalStock']) : p.stock;
                  return Card(
                    child: InkWell(
                      borderRadius: BorderRadius.circular(14),
                      onTap: () => _open(p),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Row(children: [
                          SizedBox(
                            width: 56,
                            height: 56,
                            child: p.imageUrl != null
                                ? ProductImage(url: p.imageUrl, radius: BorderRadius.circular(12))
                                : IconTile(Icons.inventory_2_rounded, color, size: 56),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text(p.name, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
                              const SizedBox(height: 4),
                              Wrap(crossAxisAlignment: WrapCrossAlignment.center, spacing: 6, runSpacing: 4, children: [
                                Text(money(p.price).replaceAll('.00', ''), style: const TextStyle(color: AppColors.price, fontWeight: FontWeight.w700)),
                                if (p.maxPrice != null) Text('- ${money(p.maxPrice).replaceAll('.00', '')}', style: const TextStyle(color: AppColors.muted)),
                                if (p.trackStock)
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                                    decoration: BoxDecoration(
                                      color: (stock <= 0 || p.isLowStock ? AppColors.danger : AppColors.green).withValues(alpha: .08),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                                      Icon(Icons.circle, size: 6, color: stock <= 0 || p.isLowStock ? AppColors.danger : AppColors.green),
                                      const SizedBox(width: 4),
                                      Text('Stock: ${qty(stock)}',
                                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: stock <= 0 || p.isLowStock ? AppColors.danger : AppColors.green)),
                                    ]),
                                  ),
                                if (p.barcode != null) Text('• ${p.barcode}', style: const TextStyle(fontSize: 11, color: AppColors.muted)),
                              ]),
                            ]),
                          ),
                          if (p.categoryName != null)
                            Container(
                              margin: const EdgeInsets.only(right: 8),
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(color: color.withValues(alpha: .08), borderRadius: BorderRadius.circular(8), border: Border.all(color: color.withValues(alpha: .4))),
                              child: Text(p.categoryName!, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w600)),
                            ),
                          RowAction(Icons.print, const Color(0xFF8E44AD), 'Print Barcode', () => _printLabel(p)),
                          RowAction(Icons.edit, AppColors.blue, 'Edit', () => _open(p)),
                          RowAction(Icons.delete_outline, AppColors.danger, 'Delete', () => _delete(p)),
                        ]),
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ]),
    );
  }
}

/// Rounded, filled search bar used on list screens.
class _RoundSearch extends StatelessWidget {
  final String hint;
  final ValueChanged<String> onChanged;
  const _RoundSearch({required this.hint, required this.onChanged});

  @override
  Widget build(BuildContext context) => TextField(
        onChanged: onChanged,
        decoration: InputDecoration(
          hintText: hint,
          prefixIcon: const Icon(Icons.search),
          fillColor: const Color(0xFFF0F3F8),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: AppColors.border)),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: AppColors.border)),
          isDense: true,
        ),
      );
}
