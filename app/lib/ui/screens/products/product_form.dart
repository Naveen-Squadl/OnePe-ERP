import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../core/api.dart';
import '../../../core/format.dart';
import '../../../core/theme.dart';
import '../../../models/models.dart';
import '../../../services/print_service.dart';
import '../../../state/catalog.dart';
import '../../../state/session.dart';
import '../../widgets/brand.dart';
import '../../widgets/common.dart';
import '../../widgets/scanner.dart';

/// Add / Edit Product dialog. Returns true when saved.
Future<bool> showProductForm(BuildContext context, [Product? product]) async =>
    await showDialog<bool>(context: context, barrierDismissible: false, builder: (_) => _ProductDialog(product: product)) ?? false;

class _ProductDialog extends StatefulWidget {
  final Product? product;
  const _ProductDialog({this.product});
  @override
  State<_ProductDialog> createState() => _ProductDialogState();
}

class _ProductDialogState extends State<_ProductDialog> {
  final _form = GlobalKey<FormState>();
  late final p = widget.product;
  late String? _imageUrl = p?.imageUrl;
  late final _name = TextEditingController(text: p?.name);
  late final _barcode = TextEditingController(text: p?.barcode);
  late final _hsn = TextEditingController(text: p?.hsnCode);
  late final _base = TextEditingController(text: p == null ? '' : _n(p!.basePrice));
  late final _max = TextEditingController(text: p?.maxPrice == null ? '' : _n(p!.maxPrice!));
  late final _purchase = TextEditingController(text: p?.purchasePrice == null ? '' : _n(p!.purchasePrice!));
  late final _gst = TextEditingController(text: p == null ? '0' : _n(p!.gstPercent));
  late final _low = TextEditingController(text: p == null ? '5' : _n(p!.lowStockThreshold));
  final _opening = TextEditingController(text: '0');
  final _batch = TextEditingController();
  DateTime? _expiry;
  late String? _categoryId = p?.categoryId;
  late String? _location = p?.storageLocation;
  late bool _variable = p?.isPriceVariable ?? false;
  late bool _track = p?.trackStock ?? (context.read<Session>().shop?.has('stock') ?? true);
  late bool _igst = p?.raw['isIgst'] == true;
  late String _availability = p == null ? 'all_branches' : (p!.branchScope == 'ALL' ? 'all_branches' : 'specific_branches');
  final Map<String, ({bool enabled, TextEditingController price})> _branchCfg = {};
  bool _busy = false;

  static String _n(double v) => v % 1 == 0 ? v.toStringAsFixed(0) : v.toString();
  double get _gstRate => double.tryParse(_gst.text) ?? 0;

  @override
  void initState() {
    super.initState();
    final session = context.read<Session>();
    for (final b in session.branches) {
      final row = p?.branches.where((x) => x['branchId'] == b.id).firstOrNull;
      _branchCfg[b.id] = (
        enabled: row == null ? (p == null && b.id == session.activeBranchId) : row['enabled'] == true,
        price: TextEditingController(text: row?['price'] == null ? '' : toDouble(row!['price']).toString()),
      );
    }
  }

  void _autoBarcode() {
    // 13-digit numeric code: "29" (in-store prefix) + time-based digits.
    final t = DateTime.now().millisecondsSinceEpoch.toString();
    setState(() => _barcode.text = '29${t.substring(t.length - 11)}');
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _busy = true);
    final body = {
      'name': _name.text.trim(),
      'categoryId': _categoryId,
      'imageUrl': _imageUrl,
      'barcode': _barcode.text.trim().isEmpty ? null : _barcode.text.trim(),
      'hsnCode': _hsn.text.trim().isEmpty ? null : _hsn.text.trim(),
      'basePrice': double.parse(_base.text),
      'maxPrice': double.tryParse(_max.text),
      'purchasePrice': double.tryParse(_purchase.text),
      'gstPercent': _gstRate,
      'isIgst': _igst,
      'isPriceVariable': _variable,
      'trackStock': _track,
      'lowStockThreshold': double.tryParse(_low.text) ?? 5,
      'storageLocation': _location,
      'isActive': p?.raw['isActive'] != false, // archive / restore happen in the product list
      'availability': _availability,
      'branches': [
        for (final e in _branchCfg.entries) {'branchId': e.key, 'enabled': e.value.enabled, 'price': double.tryParse(e.value.price.text)},
      ],
      if (p == null) 'openingStock': double.tryParse(_opening.text) ?? 0,
      if (p == null && _batch.text.isNotEmpty) 'batchNumber': _batch.text,
      if (p == null && _expiry != null) 'expiryDate': _expiry!.toIso8601String(),
    };
    final ok = await guard(context, () => p == null ? Api.instance.post('/products', body) : Api.instance.put('/products/${p!.id}', body),
        success: p == null ? 'Product added!' : 'Product updated!');
    if (mounted) setState(() => _busy = false);
    if (ok != null && mounted) Navigator.pop(context, true);
  }

  Widget _section({required Color color, required Widget child}) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: color.withValues(alpha: .07), borderRadius: BorderRadius.circular(12), border: Border.all(color: color.withValues(alpha: .35))),
        child: child,
      );

  @override
  Widget build(BuildContext context) {
    final session = context.watch<Session>();
    final cats = context.watch<Catalog>().categories;
    final locations = session.shop?.settings.storageLocations ?? const ['Showroom', 'Warehouse'];
    bool has(String feature) => session.shop?.has(feature) ?? false;
    final stock = has('stock');
    const gap = SizedBox(height: 14);
    final half = _n(_gstRate / 2);
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 600),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 22, 24, 8),
            child: Row(children: [
              Icon(p == null ? Icons.add_box : Icons.edit_note, color: AppColors.blue),
              const SizedBox(width: 10),
              Text(p == null ? 'Add Product' : 'Edit Product', style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w600)),
            ]),
          ),
          Flexible(
            child: Form(
              key: _form,
              child: ListView(shrinkWrap: true, padding: const EdgeInsets.fromLTRB(24, 6, 24, 6), children: [
                PhotoPickerBox(url: _imageUrl, label: 'Product Photo', onChanged: (u) => setState(() => _imageUrl = u)),
                gap,
                TextFormField(controller: _name, decoration: const InputDecoration(labelText: 'Product Name *'), validator: (v) => v!.trim().isEmpty ? 'Required' : null),
                gap,
                if (has('barcode')) ...[
                  _section(
                    color: AppColors.blue,
                    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      const Row(children: [
                        Icon(Icons.qr_code_2, size: 18, color: AppColors.blue),
                        SizedBox(width: 6),
                        Text('Product Barcode / QR Code', style: TextStyle(color: AppColors.blue, fontWeight: FontWeight.w600)),
                      ]),
                      const SizedBox(height: 10),
                      TextFormField(
                        controller: _barcode,
                        decoration: InputDecoration(
                          prefixIcon: const Icon(Icons.qr_code),
                          hintText: 'Barcode / Item Code',
                          suffixIcon: IconButton(
                            icon: const Icon(Icons.photo_camera, color: AppColors.blue),
                            onPressed: () async {
                              final code = await scanBarcode(context);
                              if (code != null) setState(() => _barcode.text = code);
                            },
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      FilledButton.icon(
                        onPressed: () async {
                          final code = await scanBarcode(context);
                          if (code != null) setState(() => _barcode.text = code);
                        },
                        icon: const Icon(Icons.qr_code_scanner),
                        label: const Text('Scan with Camera'),
                      ),
                      const SizedBox(height: 8),
                      Wrap(spacing: 8, children: [
                        OutlinedButton.icon(onPressed: _autoBarcode, icon: const Icon(Icons.auto_awesome, size: 16), label: const Text('Auto-Generate')),
                        OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(foregroundColor: AppColors.navy),
                          onPressed: _barcode.text.trim().isEmpty
                              ? null
                              : () => PrintService.printBarcodeLabel(name: _name.text.isEmpty ? 'Product' : _name.text, code: _barcode.text.trim(), price: double.tryParse(_base.text) ?? 0),
                          icon: const Icon(Icons.print, size: 16),
                          label: const Text('Print Label'),
                        ),
                      ]),
                    ]),
                  ),
                  gap,
                ],
                DropdownButtonFormField<String?>(
                  initialValue: cats.any((c) => c.id == _categoryId) ? _categoryId : null,
                  decoration: const InputDecoration(labelText: 'Category *', prefixIcon: Icon(Icons.category_outlined)),
                  items: [for (final c in cats) DropdownMenuItem(value: c.id, child: Text(c.isExpenseCategory ? '${c.name} (Expense)' : c.name))],
                  onChanged: (v) => setState(() => _categoryId = v),
                  validator: (v) => v == null ? 'Select a category' : null,
                ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: () {
                      Navigator.pop(context, false);
                      context.go('/inventory?tab=categories');
                    },
                    icon: const Icon(Icons.add, size: 16),
                    label: const Text('Add/Manage Categories'),
                  ),
                ),
                Row(children: [
                  Expanded(
                    child: TextFormField(
                      controller: _base,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(labelText: 'Base Price (₹) *'),
                      validator: (v) => double.tryParse(v ?? '') == null ? 'Enter a price' : null,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextFormField(
                      controller: _max,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(labelText: 'Max Price (₹)'),
                      validator: (v) {
                        final m = double.tryParse(v ?? ''), b = double.tryParse(_base.text);
                        return m != null && b != null && m < b ? 'Must be ≥ base price' : null;
                      },
                    ),
                  ),
                ]),
                gap,
                Row(children: [
                  Expanded(child: TextFormField(controller: _hsn, decoration: const InputDecoration(labelText: 'HSN / SAC Code', prefixIcon: Icon(Icons.confirmation_number_outlined)))),
                  const SizedBox(width: 10),
                  Expanded(
                    child: p == null && stock
                        ? TextFormField(controller: _opening, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Stock Qty'))
                        : TextFormField(controller: _purchase, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Purchase Price (₹)')),
                  ),
                ]),
                if (p == null && stock) ...[
                  gap,
                  TextFormField(controller: _purchase, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Purchase Price (₹)')),
                ],
                gap,
                _section(
                  color: AppColors.blue,
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    const Text('⚖️ GST Tax Structure (CGST / SGST / IGST)', style: TextStyle(color: AppColors.blue, fontWeight: FontWeight.w600, fontSize: 13)),
                    const SizedBox(height: 10),
                    DropdownButtonFormField<String>(
                      initialValue: ['0', '5', '12', '18', '28'].contains(_n(_gstRate)) ? _n(_gstRate) : '0',
                      decoration: const InputDecoration(labelText: 'Total GST Rate (%)'),
                      items: [for (final g in ['0', '5', '12', '18', '28']) DropdownMenuItem(value: g, child: Text(g))],
                      onChanged: (v) => setState(() => _gst.text = v!),
                    ),
                    const SizedBox(height: 10),
                    Row(children: [
                      Expanded(child: _ro('CGST (%)', _igst ? '0' : half)),
                      const SizedBox(width: 8),
                      Expanded(child: _ro('SGST (%)', _igst ? '0' : half)),
                      const SizedBox(width: 8),
                      Expanded(child: _ro('IGST (%)', _n(_gstRate))),
                    ]),
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      title: const Text('Bill as IGST (inter-state supply)'),
                      value: _igst,
                      onChanged: (v) => setState(() => _igst = v!),
                    ),
                  ]),
                ),
                gap,
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Variable Price'),
                  subtitle: const Text('Ask for price when adding to cart'),
                  value: _variable,
                  onChanged: (v) => setState(() => _variable = v!),
                ),
                if (stock)
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Track stock'),
                    subtitle: const Text('Turn off for services that have no inventory'),
                    value: _track,
                    onChanged: (v) => setState(() => _track = v!),
                  ),
                if (stock && _track) ...[
                  Row(children: [
                    if (has('locations')) ...[
                      Expanded(
                        child: DropdownButtonFormField<String?>(
                          initialValue: locations.contains(_location) ? _location : null,
                          decoration: const InputDecoration(labelText: 'Storage Location'),
                          items: [const DropdownMenuItem(value: null, child: Text('Unassigned')), for (final l in locations) DropdownMenuItem(value: l, child: Text(l))],
                          onChanged: (v) => setState(() => _location = v),
                        ),
                      ),
                      const SizedBox(width: 10),
                    ],
                    Expanded(child: TextFormField(controller: _low, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Low stock alert at'))),
                  ]),
                  if (p == null && has('batches')) ...[
                    gap,
                    _section(
                      color: AppColors.orange,
                      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                        const Text('Food & Perishables (Optional)', style: TextStyle(fontWeight: FontWeight.w600)),
                        const SizedBox(height: 8),
                        TextFormField(controller: _batch, decoration: const InputDecoration(labelText: 'Batch / Lot No. (Optional)', hintText: 'Leave empty to auto-generate')),
                        const SizedBox(height: 8),
                        Text(_expiry == null ? 'Expiry Date: Not Set (Optional)' : 'Expiry Date: ${dateOnly(_expiry!)}'),
                        Wrap(spacing: 6, children: [
                          for (final d in [1, 2, 3, 7, 30]) ActionChip(label: Text('+$d d'), onPressed: () => setState(() => _expiry = DateTime.now().add(Duration(days: d)))),
                          if (_expiry != null) ActionChip(label: const Text('Clear'), onPressed: () => setState(() => _expiry = null)),
                        ]),
                      ]),
                    ),
                  ],
                ],
                if (session.branches.length > 1) ...[
                  gap,
                  _section(
                    color: AppColors.navy,
                    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      const Text('Branch Availability & Pricing', style: TextStyle(fontWeight: FontWeight.w600)),
                      const SizedBox(height: 8),
                      SegmentedButton<String>(
                        segments: const [ButtonSegment(value: 'all_branches', label: Text('All Branches')), ButtonSegment(value: 'specific_branches', label: Text('Specific'))],
                        selected: {_availability},
                        onSelectionChanged: (s) => setState(() => _availability = s.first),
                      ),
                      for (final b in session.branches)
                        Row(children: [
                          if (_availability == 'specific_branches')
                            Checkbox(value: _branchCfg[b.id]!.enabled, onChanged: (v) => setState(() => _branchCfg[b.id] = (enabled: v!, price: _branchCfg[b.id]!.price))),
                          Expanded(child: Text(b.name)),
                          SizedBox(
                            width: 140,
                            child: TextField(controller: _branchCfg[b.id]!.price, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Branch price', isDense: true)),
                          ),
                        ]),
                    ]),
                  ),
                ],
                const SizedBox(height: 8),
              ]),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 4, 24, 20),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Align(alignment: Alignment.centerRight, child: TextButton(onPressed: _busy ? null : () => Navigator.pop(context, false), child: const Text('Cancel'))),
              FilledButton(onPressed: _busy ? null : _save, child: Text(_busy ? 'Saving...' : 'Save')),
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _ro(String label, String value) => InputDecorator(
        decoration: InputDecoration(labelText: label, isDense: true, fillColor: AppColors.blueTint),
        child: Text(value),
      );
}
