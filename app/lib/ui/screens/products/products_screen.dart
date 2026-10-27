import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/api.dart';
import '../../../core/format.dart';
import '../../../core/theme.dart';
import '../../../models/models.dart';
import '../../../services/print_service.dart';
import '../../../state/catalog.dart';
import '../../../state/session.dart';
import '../../history_sources.dart';
import '../../widgets/app_shell.dart';
import '../../widgets/brand.dart';
import '../../widgets/common.dart';
import '../stock/stock_views.dart';
import 'product_form.dart';

/// Inventory → Products: the product list with stock. Edit/add/delete need products.manage; stock changes
/// need inventory.manage – per row ("Inward Batch") or for many rows at once in "Stock entry" mode
/// (Inward / Outward / Set a quantity per product, e.g. for a stock take).
class ProductsScreen extends StatefulWidget {
  const ProductsScreen({super.key});

  /// Set by the Categories tab to open the list filtered to one category.
  static final categoryFilter = ValueNotifier<String?>(null);

  @override
  State<ProductsScreen> createState() => _ProductsScreenState();
}

class _ProductsScreenState extends State<ProductsScreen> {
  String _q = '';
  String _scope = 'this_branch';
  String? _categoryId = ProductsScreen.categoryFilter.value;
  int _v = 0;
  bool _stockEntry = false;

  String _mode = 'add'; // add (Inward) | remove (Outward) | set
  String? _location;
  final Map<String, TextEditingController> _qtyCtrls = {};

  Session get _session => context.read<Session>();
  bool get _canEdit => _session.can('products.manage') || _session.can('products.edit_limited');
  bool get _canManage => _session.can('products.manage');
  bool _has(String feature) => _session.shop?.has(feature) ?? false;
  bool get _canStock => _session.can('inventory.manage') && _has('stock');

  @override
  void initState() {
    super.initState();
    ProductsScreen.categoryFilter.addListener(_onCategoryFilter);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (context.read<Catalog>().categories.isEmpty) context.read<Catalog>().load();
    });
  }

  @override
  void dispose() {
    ProductsScreen.categoryFilter.removeListener(_onCategoryFilter);
    ProductsScreen.categoryFilter.value = null; // a category picked in the Categories tab applies once
    for (final c in _qtyCtrls.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _onCategoryFilter() => setState(() => _categoryId = ProductsScreen.categoryFilter.value);

  void _stockChanged() {
    setState(() => _v++);
    context.read<Catalog>().load();
  }

  Future<void> _inward(Product p) async {
    if (await inwardBatch(context, p.raw) && mounted) setState(() => _v++);
  }

  /// Stock entry mode: apply the typed quantity to one product.
  Future<void> _applyRow(Product p) async {
    final v = double.tryParse(_qtyCtrls[p.id]!.text);
    if (v == null || (v <= 0 && _mode != 'set')) return showSnack(context, 'Enter quantity', error: true);
    final r = await guard(
      context,
      () => _mode == 'add'
          ? Api.instance.post('/stock/inward', {'productId': p.id, 'quantity': v, 'location': _location})
          : Api.instance.post('/stock/adjust', {'productId': p.id, 'mode': _mode, 'quantity': v}),
    );
    if (r != null && mounted) {
      _qtyCtrls[p.id]!.text = '0';
      showSnack(context, '✅ Stock updated for ${p.name}');
      _stockChanged();
    }
  }

  Widget _stockEntryBar() {
    final locations = context.watch<Session>().shop?.settings.storageLocations ?? const ['Showroom', 'Warehouse'];
    _location ??= locations.isNotEmpty ? locations.first : null;
    final loc = DropdownButtonFormField<String?>(
      initialValue: locations.contains(_location) ? _location : null,
      isDense: true,
      decoration: const InputDecoration(prefixIcon: Icon(Icons.store, color: AppColors.blue), isDense: true, labelText: 'Location (Inward)'),
      items: [for (final l in locations) DropdownMenuItem(value: l, child: Text(l))],
      onChanged: (v) => setState(() => _location = v),
    );
    final seg = SegmentedButton<String>(
      segments: const [
        ButtonSegment(value: 'add', icon: Icon(Icons.south_west), label: Text('Inward')),
        ButtonSegment(value: 'remove', icon: Icon(Icons.north_east), label: Text('Outward')),
        ButtonSegment(value: 'set', icon: Icon(Icons.edit_outlined), label: Text('Set')),
      ],
      showSelectedIcon: false,
      selected: {_mode},
      onSelectionChanged: (s) => setState(() => _mode = s.first),
    );
    if (!_has('locations')) {
      _location = null;
      return Container(
        color: AppColors.lime.withValues(alpha: .25),
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
        child: SizedBox(width: double.infinity, child: seg),
      );
    }
    return Container(
      color: AppColors.lime.withValues(alpha: .25),
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      child: LayoutBuilder(
        builder: (context, b) => b.maxWidth > 700
            ? Row(children: [Expanded(child: loc), const SizedBox(width: 10), Expanded(child: seg)])
            : Column(children: [loc, const SizedBox(height: 8), SizedBox(width: double.infinity, child: seg)]),
      ),
    );
  }

  Widget _qtyEntry(Product p) {
    final ctrl = _qtyCtrls.putIfAbsent(p.id, () => TextEditingController(text: '0'));
    return Row(mainAxisSize: MainAxisSize.min, children: [
      SizedBox(
        width: 76,
        child: TextField(
          controller: ctrl,
          textAlign: TextAlign.center,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          style: const TextStyle(fontWeight: FontWeight.w700),
          decoration: InputDecoration(fillColor: AppColors.bg, isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none)),
          onTap: () => ctrl.selection = TextSelection(baseOffset: 0, extentOffset: ctrl.text.length),
          onSubmitted: (_) => _applyRow(p),
        ),
      ),
      const SizedBox(width: 6),
      Material(
        color: AppColors.green,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () => _applyRow(p),
          child: const SizedBox(width: 42, height: 42, child: Icon(Icons.check, color: Colors.white)),
        ),
      ),
    ]);
  }

  Future<List<Product>> _load() async =>
      (await Api.instance.get('/products', {'q': _q, 'scope': _scope, 'categoryId': _categoryId}) as List).map((e) => Product(Map<String, dynamic>.from(e))).toList();

  Future<void> _open([Product? p]) async {
    if (!_canEdit) return;
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
    final canStock = _canStock;
    final batches = canStock && _has('batches');
    final barcode = _has('barcode');
    final showStock = _has('stock');
    final history = showStock && _session.can('inventory.view');
    return AppScaffold(
      title: 'Products',
      fab: _canManage && !_stockEntry ? FloatingActionButton.extended(onPressed: () => _open(), icon: const Icon(Icons.add), label: const Text('Add Product')) : null,
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 8, 0),
          child: Row(children: [
            Expanded(child: _RoundSearch(hint: 'Search products by name, barcode or HSN...', onChanged: (v) => setState(() => _q = v))),
            IconButton(tooltip: 'Export products (PDF)', onPressed: () => _export(current), icon: const Icon(Icons.download_rounded, color: AppColors.navy)),
          ]),
        ),
        SizedBox(
          height: 56,
          child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.fromLTRB(16, 10, 16, 6), children: [
            CategoryChip(label: 'All', color: AppColors.blue, selected: _categoryId == null, onTap: () => setState(() => _categoryId = null)),
            for (final (i, c) in cats.indexed)
              CategoryChip(label: c.name, color: AppColors.forIndex(i), selected: _categoryId == c.id, onTap: () => setState(() => _categoryId = c.id)),
            if (canStock) ...[
              const SizedBox(width: 8),
              FilterChip(
                avatar: const Icon(Icons.fact_check_rounded, size: 18),
                label: const Text('Stock entry'),
                selected: _stockEntry,
                onSelected: (v) => setState(() => _stockEntry = v),
              ),
            ],
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
        if (_stockEntry) _stockEntryBar(),
        const Divider(height: 1),
        Expanded(
          child: Loader<List<Product>>(
            key: ValueKey('$_q$_scope$_categoryId$_v'),
            load: _load,
            builder: (context, all, reload) {
              final list = _stockEntry ? all.where((p) => p.trackStock).toList() : all;
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
                  final narrow = MediaQuery.of(context).size.width < 600;
                  final catTag = p.categoryName == null
                      ? null
                      : Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(color: color.withValues(alpha: .08), borderRadius: BorderRadius.circular(8), border: Border.all(color: color.withValues(alpha: .4))),
                          child: Text(p.categoryName!, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w700)),
                        );
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
                              Text(p.name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                              const SizedBox(height: 4),
                              Wrap(crossAxisAlignment: WrapCrossAlignment.center, spacing: 6, runSpacing: 4, children: [
                                Text(money(p.price).replaceAll('.00', ''), style: const TextStyle(color: AppColors.price, fontWeight: FontWeight.w700)),
                                if (p.maxPrice != null) Text('- ${money(p.maxPrice).replaceAll('.00', '')}', style: const TextStyle(color: AppColors.muted)),
                                if (showStock && p.trackStock)
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
                                if (barcode && p.barcode != null) Text('• ${p.barcode}', style: const TextStyle(fontSize: 11, color: AppColors.muted)),
                                if (narrow && catTag != null) catTag,
                              ]),
                            ]),
                          ),
                          if (_stockEntry)
                            _qtyEntry(p)
                          else if (narrow)
                            // Phones: one menu instead of the row buttons so the name keeps its width.
                            PopupMenuButton<String>(
                              tooltip: 'Actions',
                              icon: const Icon(Icons.more_vert_rounded, color: AppColors.navy),
                              onSelected: (v) => switch (v) {
                                'inward' => _inward(p),
                                'history' => showStockHistory(context, productId: p.id, productName: p.name),
                                'print' => _printLabel(p),
                                'edit' => _open(p),
                                _ => _delete(p),
                              },
                              itemBuilder: (_) => [
                                if (batches && p.trackStock)
                                  const PopupMenuItem(value: 'inward', child: ListTile(leading: Icon(Icons.move_to_inbox_rounded, color: AppColors.green), title: Text('Inward Batch'))),
                                if (history && p.trackStock)
                                  const PopupMenuItem(value: 'history', child: ListTile(leading: Icon(Icons.history_rounded), title: Text('Stock history'))),
                                if (barcode) const PopupMenuItem(value: 'print', child: ListTile(leading: Icon(Icons.print), title: Text('Print Barcode'))),
                                if (_canEdit) const PopupMenuItem(value: 'edit', child: ListTile(leading: Icon(Icons.edit, color: AppColors.blue), title: Text('Edit'))),
                                if (_canManage)
                                  const PopupMenuItem(value: 'delete', child: ListTile(leading: Icon(Icons.delete_outline, color: AppColors.danger), title: Text('Delete'))),
                              ],
                            )
                          else ...[
                            if (catTag != null) Padding(padding: const EdgeInsets.only(right: 8), child: catTag),
                            if (batches && p.trackStock) RowAction(Icons.move_to_inbox_rounded, AppColors.green, 'Inward Batch (with expiry)', () => _inward(p)),
                            if (history && p.trackStock)
                              RowAction(Icons.history_rounded, AppColors.navy, 'Stock history', () => showStockHistory(context, productId: p.id, productName: p.name)),
                            if (barcode) RowAction(Icons.print, AppColors.navy, 'Print Barcode', () => _printLabel(p)),
                            if (_canEdit) RowAction(Icons.edit, AppColors.blue, 'Edit', () => _open(p)),
                            if (_canManage) RowAction(Icons.delete_outline, AppColors.danger, 'Delete', () => _delete(p)),
                          ],
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
          fillColor: AppColors.bg,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: AppColors.border)),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: AppColors.border)),
          isDense: true,
        ),
      );
}
