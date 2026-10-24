import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/api.dart';
import '../../../core/format.dart';
import '../../../core/theme.dart';
import '../../../models/models.dart';
import '../../../state/catalog.dart';
import '../../../state/session.dart';
import '../../widgets/app_shell.dart';
import '../../widgets/brand.dart';
import '../../widgets/common.dart';
import '../../widgets/scanner.dart';

class PurchasesScreen extends StatefulWidget {
  const PurchasesScreen({super.key});
  @override
  State<PurchasesScreen> createState() => _PurchasesScreenState();
}

class _PurchasesScreenState extends State<PurchasesScreen> {
  int _v = 0;

  Future<void> _new() async {
    final ok = await Navigator.of(context).push<bool>(MaterialPageRoute(builder: (_) => const PurchaseForm()));
    if (ok == true && mounted) {
      setState(() => _v++);
      context.read<Catalog>().load();
    }
  }

  Widget _list(String status) => Loader<List>(
        key: ValueKey('$status$_v'),
        load: () async => await Api.instance.get('/purchases', {'status': status}) as List,
        builder: (context, list, reload) => list.isEmpty
            ? ListView(children: [
                const SizedBox(height: 60),
                EmptyState(icon: Icons.receipt_outlined, title: status == 'PENDING' ? 'No pending purchase orders' : 'No purchases yet'),
              ])
            : ListView.separated(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
                itemCount: list.length,
                separatorBuilder: (_, _) => const SizedBox(height: 6),
                itemBuilder: (_, i) {
                  final p = Map<String, dynamic>.from(list[i]);
                  final items = List<Map<String, dynamic>>.from(p['items']);
                  final due = toDouble(p['balanceDue']);
                  return Card(
                    child: ExpansionTile(
                      title: Text('${p['invoiceNumber']} • ${p['supplierName'] ?? 'Unknown Supplier'}', style: const TextStyle(fontWeight: FontWeight.w700)),
                      subtitle: Text('${dateOnly(DateTime.parse(p['invoiceDate']))} • ${items.length} items${p['location'] != null ? ' • ${p['location']}' : ''}'),
                      trailing: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
                        Text(money(toDouble(p['totalAmount'])), style: const TextStyle(fontWeight: FontWeight.w800)),
                        Text(due > 0 ? 'Due ${money(due)}' : 'Paid', style: TextStyle(fontSize: 12, color: due > 0 ? StatusColors.due : StatusColors.ok)),
                      ]),
                      children: [
                        for (final it in items)
                          ListTile(
                            dense: true,
                            title: Text(it['productName']),
                            subtitle: Text('${qty(toDouble(it['quantity']))} × ${money(toDouble(it['unitPrice']))}${it['batchNumber'] != null ? ' • Batch: ${it['batchNumber']}' : ''}'
                                '${it['expiryDate'] != null ? ' • Exp: ${dateOnly(DateTime.parse(it['expiryDate']))}' : ''}'),
                            trailing: Text(money(toDouble(it['total']))),
                          ),
                        if (status == 'PENDING')
                          Padding(
                            padding: const EdgeInsets.all(12),
                            child: Wrap(spacing: 8, children: [
                              FilledButton.icon(
                                onPressed: () async {
                                  final locs = context.read<Session>().shop?.settings.storageLocations ?? const ['Main Store'];
                                  final loc = await showDialog<String>(
                                    context: context,
                                    builder: (c) => SimpleDialog(
                                      title: Text('Confirm destination storage location for ${items.length} product(s) from invoice ${p['invoiceNumber']}'),
                                      children: [for (final l in locs) SimpleDialogOption(onPressed: () => Navigator.pop(c, l), child: Text(l))],
                                    ),
                                  );
                                  if (loc == null || !context.mounted) return;
                                  final r = await guard(context, () => Api.instance.post('/purchases/${p['id']}/inward', {'location': loc}),
                                      success: '✅ PO materials inwarded into $loc');
                                  if (r != null) setState(() => _v++);
                                },
                                icon: const Icon(Icons.move_to_inbox),
                                label: const Text('Inward Stock'),
                              ),
                              OutlinedButton.icon(
                                onPressed: () async {
                                  if (await confirm(context, 'Delete PO', 'Delete purchase order ${p['invoiceNumber']}?', danger: true, ok: 'Delete') && context.mounted) {
                                    final r = await guard(context, () => Api.instance.delete('/purchases/${p['id']}'));
                                    if (r != null) setState(() => _v++);
                                  }
                                },
                                icon: const Icon(Icons.delete_outline),
                                label: const Text('Delete'),
                              ),
                            ]),
                          ),
                      ],
                    ),
                  );
                },
              ),
      );

  @override
  Widget build(BuildContext context) => DefaultTabController(
        length: 2,
        child: AppScaffold(
          title: 'Purchase Entry',
          bottom: const TabBar(tabs: [Tab(text: 'Inwarded Purchases'), Tab(text: 'Pending POs')]),
          fab: FloatingActionButton.extended(onPressed: _new, icon: const Icon(Icons.add), label: const Text('New Purchase Bill')),
          body: TabBarView(children: [_list('RECEIVED'), _list('PENDING')]),
        ),
      );
}

class _Line {
  final Product product;
  double quantity;
  double unitPrice;
  double gst;
  String? batch;
  DateTime? expiry;
  _Line(this.product, this.quantity, this.unitPrice, this.gst);
  double get total => quantity * unitPrice * (1 + gst / 100);
}

class PurchaseForm extends StatefulWidget {
  const PurchaseForm({super.key});
  @override
  State<PurchaseForm> createState() => _PurchaseFormState();
}

class _PurchaseFormState extends State<PurchaseForm> {
  final _lines = <_Line>[];
  List<Map<String, dynamic>> _suppliers = [];
  String? _supplierId;
  final _newSupplier = TextEditingController();
  final _invoice = TextEditingController();
  final _discount = TextEditingController(text: '0');
  final _paid = TextEditingController(text: '0');
  DateTime _date = DateTime.now();
  String _mode = 'CASH';
  String? _location;
  bool _asPo = false;
  int _step = 0;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    Api.instance.get('/suppliers').then((r) => setState(() => _suppliers = List<Map<String, dynamic>>.from(r)));
  }

  double get _total => _lines.fold<double>(0, (s, l) => s + l.total) - (double.tryParse(_discount.text) ?? 0);

  Future<void> _addItem([Product? preset]) async {
    final catalog = context.read<Catalog>();
    Product? p = preset;
    p ??= await showModalBottomSheet<Product>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        builder: (c) => _ProductSearch(products: catalog.products.where((x) => !x.isExpense).toList()),
      );
    if (p == null || !mounted) return;
    final q = TextEditingController(text: '1');
    final price = TextEditingController(text: (p.purchasePrice ?? 0).toString());
    final gst = TextEditingController(text: p.gstPercent.toStringAsFixed(0));
    final batch = TextEditingController();
    DateTime? expiry;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, set) => AlertDialog(
          title: Text('Add ${p!.name}'),
          content: SizedBox(
            width: 400,
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Text('Current stock: ${qty(p.stock)} • Sell price: ${money(p.price)}', style: Theme.of(c).textTheme.bodySmall),
                const SizedBox(height: 8),
                Row(children: [
                  Expanded(child: TextField(controller: q, autofocus: true, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Quantity'))),
                  const SizedBox(width: 8),
                  Expanded(child: TextField(controller: price, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Unit Price (₹)'))),
                  const SizedBox(width: 8),
                  SizedBox(width: 80, child: TextField(controller: gst, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'GST %'))),
                ]),
                const SizedBox(height: 10),
                const Align(alignment: Alignment.centerLeft, child: Text('Food & Perishables (Optional)', style: TextStyle(fontWeight: FontWeight.w700))),
                const SizedBox(height: 6),
                TextField(controller: batch, decoration: const InputDecoration(labelText: 'Batch / Lot No. (Optional)', hintText: 'e.g. B-01 or leave empty to auto-generate')),
                const SizedBox(height: 6),
                Text(expiry == null ? 'Expiry Date: Not Set (Optional)' : 'Expiry Date: ${dateOnly(expiry!)}'),
                Wrap(spacing: 6, children: [
                  for (final d in const [(1, '+1 Day (Milk)'), (2, '+2 Days'), (3, '+3 Days'), (7, '+7 Days (Dairy)'), (30, '+30 Days')])
                    ActionChip(label: Text(d.$2), onPressed: () => set(() => expiry = DateTime.now().add(Duration(days: d.$1)))),
                  if (expiry != null) ActionChip(label: const Text('Clear Expiry Date'), onPressed: () => set(() => expiry = null)),
                ]),
              ]),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Add Item')),
          ],
        ),
      ),
    );
    if (ok != true) return;
    setState(() => _lines.add(_Line(p!, double.tryParse(q.text) ?? 1, double.tryParse(price.text) ?? 0, double.tryParse(gst.text) ?? 0)
      ..batch = batch.text.isEmpty ? null : batch.text
      ..expiry = expiry));
  }

  Future<void> _save() async {
    if (_lines.isEmpty) return showSnack(context, 'No items added to bill yet.', error: true);
    setState(() => _busy = true);
    final body = {
      if (_supplierId != null) 'supplierId': _supplierId,
      if (_supplierId == null && _newSupplier.text.trim().isNotEmpty) 'newSupplier': {'name': _newSupplier.text.trim()},
      if (_invoice.text.trim().isNotEmpty) 'invoiceNumber': _invoice.text.trim(),
      'invoiceDate': _date.toIso8601String(),
      'status': _asPo ? 'PENDING' : 'RECEIVED',
      'items': [
        for (final l in _lines)
          {
            'productId': l.product.id,
            'quantity': l.quantity,
            'unitPrice': l.unitPrice,
            'gstPercent': l.gst,
            if (l.batch != null) 'batchNumber': l.batch,
            if (l.expiry != null) 'expiryDate': l.expiry!.toIso8601String(),
          },
      ],
      'discountAmount': double.tryParse(_discount.text) ?? 0,
      'amountPaid': double.tryParse(_paid.text) ?? 0,
      'paymentMode': _mode,
      'location': _location,
    };
    final r = await guard(context, () => Api.instance.post('/purchases', body),
        success: _asPo ? 'Purchase Order Raised Successfully!' : 'Purchase & Stock Inwarded Successfully!');
    if (mounted) setState(() => _busy = false);
    if (r != null && mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final locs = context.watch<Session>().shop?.settings.storageLocations ?? const ['Showroom', 'Warehouse'];
    return Scaffold(
      appBar: const GradientAppBar(title: Text('New Purchase Bill')),
      body: Stepper(
        currentStep: _step,
        onStepTapped: (s) => setState(() => _step = s),
        onStepContinue: () => _step == 0 ? setState(() => _step = 1) : _save(),
        onStepCancel: _step == 0 ? null : () => setState(() => _step = 0),
        controlsBuilder: (c, d) => Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Row(children: [
            FilledButton(onPressed: _busy ? null : d.onStepContinue, child: Text(_step == 0 ? 'Next: Bill Details' : (_asPo ? 'Raise Purchase Order' : 'Save & Inward Stock'))),
            if (d.onStepCancel != null) TextButton(onPressed: d.onStepCancel, child: Text('Back to Items (${_lines.length})')),
          ]),
        ),
        steps: [
          Step(
            title: Text('1. Items (${_lines.length})'),
            isActive: _step == 0,
            content: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Wrap(spacing: 8, children: [
                FilledButton.tonalIcon(onPressed: () => _addItem(), icon: const Icon(Icons.search), label: const Text('Search or Scan Product to Add')),
                OutlinedButton.icon(
                  onPressed: () async {
                    final code = await scanBarcode(context);
                    if (code == null || !context.mounted) return;
                    final p = context.read<Catalog>().byBarcode(code);
                    if (p == null) return showSnack(context, '❌ No product found for: $code', error: true);
                    _addItem(p);
                  },
                  icon: const Icon(Icons.qr_code_scanner),
                  label: const Text('Scan QR / Barcode'),
                ),
              ]),
              const SizedBox(height: 8),
              if (_lines.isEmpty) const Padding(padding: EdgeInsets.all(16), child: Text('No items added to bill yet.')),
              for (final l in _lines)
                Card(
                  child: ListTile(
                    title: Text(l.product.name),
                    subtitle: Text('${qty(l.quantity)} × ${money(l.unitPrice)} • GST ${l.gst.toStringAsFixed(0)}%'
                        '${l.batch != null ? ' • Batch: ${l.batch}' : ''}${l.expiry != null ? ' • Exp: ${dateOnly(l.expiry!)}' : ''}'
                        '${l.product.price > 0 && l.unitPrice > 0 ? ' • Margin: ${((l.product.price - l.unitPrice) / l.unitPrice * 100).toStringAsFixed(0)}%' : ''}'),
                    trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                      Text(money(l.total), style: const TextStyle(fontWeight: FontWeight.w700)),
                      IconButton(tooltip: 'Remove', onPressed: () => setState(() => _lines.remove(l)), icon: const Icon(Icons.close)),
                    ]),
                  ),
                ),
              if (_lines.isNotEmpty) Padding(padding: const EdgeInsets.all(8), child: Text('Items total: ${money(_lines.fold<double>(0, (s, l) => s + l.total))}', textAlign: TextAlign.right)),
            ]),
          ),
          Step(
            title: const Text('2. Bill Details'),
            isActive: _step == 1,
            content: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              DropdownButtonFormField<String?>(
                initialValue: _supplierId,
                decoration: const InputDecoration(labelText: 'Supplier'),
                items: [
                  const DropdownMenuItem(value: null, child: Text('— New / Unassigned —')),
                  for (final s in _suppliers) DropdownMenuItem(value: s['id'] as String, child: Text(s['name'])),
                ],
                onChanged: (v) => setState(() => _supplierId = v),
              ),
              if (_supplierId == null) ...[
                const SizedBox(height: 10),
                TextField(controller: _newSupplier, decoration: const InputDecoration(labelText: '✨ New Supplier name (optional)')),
              ],
              const SizedBox(height: 10),
              Row(children: [
                Expanded(child: TextField(controller: _invoice, decoration: const InputDecoration(labelText: 'Invoice No (auto if empty)'))),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      final d = await showDatePicker(context: context, initialDate: _date, firstDate: DateTime(2020), lastDate: DateTime.now());
                      if (d != null) setState(() => _date = d);
                    },
                    icon: const Icon(Icons.event),
                    label: Text(dateOnly(_date)),
                  ),
                ),
              ]),
              const SizedBox(height: 10),
              DropdownButtonFormField<String?>(
                initialValue: _location,
                decoration: const InputDecoration(labelText: 'Storage Location', helperText: 'Manage Locations in Settings'),
                items: [const DropdownMenuItem(value: null, child: Text('Unassigned')), for (final l in locs) DropdownMenuItem(value: l, child: Text(l))],
                onChanged: (v) => setState(() => _location = v),
              ),
              const SizedBox(height: 10),
              Row(children: [
                Expanded(child: TextField(controller: _discount, keyboardType: TextInputType.number, onChanged: (_) => setState(() {}), decoration: const InputDecoration(labelText: 'Discount (₹)'))),
                const SizedBox(width: 8),
                Expanded(child: TextField(controller: _paid, keyboardType: TextInputType.number, onChanged: (_) => setState(() {}), decoration: const InputDecoration(labelText: 'Amount Paid (₹)'))),
              ]),
              const SizedBox(height: 10),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'CASH', label: Text('Cash')),
                  ButtonSegment(value: 'UPI', label: Text('UPI')),
                  ButtonSegment(value: 'BANK', label: Text('Bank')),
                  ButtonSegment(value: 'CHEQUE', label: Text('Cheque')),
                ],
                selected: {_mode},
                onSelectionChanged: (s) => setState(() => _mode = s.first),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Raise as Purchase Order (pending stock inward)'),
                value: _asPo,
                onChanged: (v) => setState(() => _asPo = v),
              ),
              const Divider(),
              Text('Total Amount: ${money(_total)}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
              Text('Balance to Supplier: ${money(_total - (double.tryParse(_paid.text) ?? 0))}',
                  style: TextStyle(color: _total - (double.tryParse(_paid.text) ?? 0) > 0 ? StatusColors.due : StatusColors.ok)),
            ]),
          ),
        ],
      ),
    );
  }
}

class _ProductSearch extends StatefulWidget {
  final List<Product> products;
  const _ProductSearch({required this.products});
  @override
  State<_ProductSearch> createState() => _ProductSearchState();
}

class _ProductSearchState extends State<_ProductSearch> {
  String q = '';
  @override
  Widget build(BuildContext context) {
    final list = widget.products.where((p) => p.name.toLowerCase().contains(q.toLowerCase()) || p.barcode == q).toList();
    return SizedBox(
      height: MediaQuery.of(context).size.height * .8,
      child: Column(children: [
        Padding(padding: const EdgeInsets.all(16), child: SearchField(hint: 'Search product in list...', onChanged: (v) => setState(() => q = v))),
        Expanded(
          child: ListView(children: [
            for (final p in list)
              ListTile(
                title: Text(p.name),
                subtitle: Text('Stock: ${qty(p.stock)}${p.purchasePrice != null ? ' | Buy Price: ${money(p.purchasePrice)}' : ''}'),
                trailing: Text(money(p.price)),
                onTap: () => Navigator.pop(context, p),
              ),
          ]),
        ),
      ]),
    );
  }
}
