import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/api.dart';
import '../../../core/format.dart';
import '../../../core/theme.dart';
import '../../../services/print_service.dart';
import '../../../state/catalog.dart';
import '../../../state/session.dart';
import '../../widgets/app_shell.dart';
import '../../widgets/common.dart';

class StockScreen extends StatefulWidget {
  const StockScreen({super.key});
  @override
  State<StockScreen> createState() => _StockScreenState();
}

class _StockScreenState extends State<StockScreen> {
  String _q = '';
  String _batchFilter = 'all';
  int _v = 0;

  bool get _canManage => context.read<Session>().can('inventory.manage');

  Future<void> _inward(Map<String, dynamic> p) async {
    final qtyCtrl = TextEditingController();
    final batch = TextEditingController();
    final price = TextEditingController(text: p['purchasePrice']?.toString() ?? '');
    DateTime? expiry;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, set) => AlertDialog(
          title: Text('Inward Batch: ${p['name']}'),
          content: SizedBox(
            width: 400,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(controller: qtyCtrl, autofocus: true, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Quantity *')),
              const SizedBox(height: 10),
              TextField(controller: batch, decoration: const InputDecoration(labelText: 'Batch / Lot No.', hintText: 'Auto-Generate if empty')),
              const SizedBox(height: 10),
              TextField(controller: price, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Purchase Price (₹)')),
              const SizedBox(height: 10),
              Text(expiry == null ? 'Expiry: None' : 'Expiry: ${dateOnly(expiry!)}'),
              Wrap(spacing: 6, children: [
                for (final d in const [(1, '+1d (Milk)'), (2, '+2d'), (3, '+3d'), (7, '+7d (Dairy)'), (30, '+30d')])
                  ActionChip(label: Text(d.$2), onPressed: () => set(() => expiry = DateTime.now().add(Duration(days: d.$1)))),
                ActionChip(
                  label: const Text('Pick Date'),
                  onPressed: () async {
                    final d = await showDatePicker(context: c, firstDate: DateTime.now(), lastDate: DateTime(2100), initialDate: DateTime.now());
                    if (d != null) set(() => expiry = d);
                  },
                ),
              ]),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('+ Inward Batch')),
          ],
        ),
      ),
    );
    final q = double.tryParse(qtyCtrl.text);
    if (ok != true || q == null || q <= 0 || !mounted) return;
    final r = await guard(context, () => Api.instance.post('/stock/inward', {
          'productId': p['id'],
          'quantity': q,
          if (batch.text.isNotEmpty) 'batchNumber': batch.text,
          if (expiry != null) 'expiryDate': expiry!.toIso8601String(),
          'purchasePrice': double.tryParse(price.text),
        }));
    if (r != null && mounted) {
      showSnack(context, '✅ Inwarded ${qty(q)} units for ${p['name']} (Batch: ${r['batchNumber']})');
      setState(() => _v++);
    }
  }

  @override
  Widget build(BuildContext context) => DefaultTabController(
        length: 3,
        child: AppScaffold(
          title: 'Stock Management',
          bottom: const TabBar(tabs: [Tab(text: 'Stock Levels'), Tab(text: 'Batches & Expiry'), Tab(text: 'Stock History')]),
          body: TabBarView(children: [_levels(), _batches(), _history()]),
        ),
      );

  String _mode = 'add'; // add (Inward) | remove (Outward) | set
  String? _stockCategory;
  String? _stockLocation;
  final Map<String, TextEditingController> _qtyCtrls = {};

  Future<void> _applyRow(Map<String, dynamic> p) async {
    final ctrl = _qtyCtrls[p['id']]!;
    final v = double.tryParse(ctrl.text);
    if (v == null || (v <= 0 && _mode != 'set')) return showSnack(context, 'Enter quantity', error: true);
    final Future<dynamic> Function() call = _mode == 'add'
        ? () => Api.instance.post('/stock/inward', {'productId': p['id'], 'quantity': v, 'location': _stockLocation})
        : () => Api.instance.post('/stock/adjust', {'productId': p['id'], 'mode': _mode, 'quantity': v});
    final r = await guard(context, call);
    if (r != null && mounted) {
      ctrl.text = '0';
      showSnack(context, '✅ Stock updated for ${p['name']}');
      setState(() => _v++);
      context.read<Catalog>().load();
    }
  }

  Widget _levels() {
    final cats = context.watch<Catalog>().categories.where((c) => c.isStockCategory).toList();
    final locations = context.watch<Session>().shop?.settings.storageLocations ?? const ['Showroom', 'Warehouse'];
    _stockLocation ??= locations.isNotEmpty ? locations.first : null;
    final canManage = _canManage;
    InputDecoration box(Widget prefix) => InputDecoration(
          prefixIcon: prefix,
          fillColor: AppColors.bg,
          isDense: true,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.border)),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.border)),
        );
    return Column(children: [
      Container(
        color: Colors.white,
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Column(children: [
          DropdownButtonFormField<String?>(
            initialValue: _stockCategory,
            decoration: box(const Icon(Icons.inventory_2, color: AppColors.orange)),
            items: [
              const DropdownMenuItem(value: null, child: Text('All Categories (Entire Catalog)', style: TextStyle(fontWeight: FontWeight.w600))),
              for (final c in cats) DropdownMenuItem(value: c.id, child: Text(c.name)),
            ],
            onChanged: (v) => setState(() => _stockCategory = v),
          ),
          const SizedBox(height: 10),
          TextField(onChanged: (v) => setState(() => _q = v), decoration: box(const Icon(Icons.search)).copyWith(hintText: 'Search products by name...')),
          const SizedBox(height: 10),
          LayoutBuilder(builder: (context, b) {
            final loc = DropdownButtonFormField<String?>(
              initialValue: locations.contains(_stockLocation) ? _stockLocation : null,
              decoration: box(const Icon(Icons.store, color: AppColors.blue)),
              items: [for (final l in locations) DropdownMenuItem(value: l, child: Text(l))],
              onChanged: (v) => setState(() => _stockLocation = v),
            );
            final seg = SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'add', icon: Icon(Icons.check), label: Text('Inward')),
                ButtonSegment(value: 'remove', icon: Icon(Icons.remove_circle_outline), label: Text('Outward')),
                ButtonSegment(value: 'set', icon: Icon(Icons.edit_outlined), label: Text('Set')),
              ],
              showSelectedIcon: false,
              selected: {_mode},
              onSelectionChanged: (s) => setState(() => _mode = s.first),
            );
            return b.maxWidth > 700
                ? Row(children: [Expanded(child: loc), const SizedBox(width: 10), Expanded(child: seg)])
                : Column(children: [loc, const SizedBox(height: 10), SizedBox(width: double.infinity, child: seg)]);
          }),
        ]),
      ),
      const Divider(height: 1),
      Expanded(
        child: Loader<List>(
          key: ValueKey('levels$_q$_v'),
          load: () async => await Api.instance.get('/stock', {'q': _q}) as List,
          builder: (context, all, _) {
            final list = all.where((p) => _stockCategory == null || p['categoryId'] == _stockCategory).toList();
            if (list.isEmpty) {
              return ListView(children: const [SizedBox(height: 60), EmptyState(icon: Icons.warehouse_outlined, title: 'No stock items found in stock categories.')]);
            }
            return ListView.separated(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 24),
              itemCount: list.length,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (_, i) {
                final p = Map<String, dynamic>.from(list[i]);
                final stock = toDouble(p['stock']);
                final bad = stock <= 0 || p['isLowStock'] == true;
                final batches = List<Map<String, dynamic>>.from(p['batches'] ?? const []);
                final ctrl = _qtyCtrls.putIfAbsent(p['id'], () => TextEditingController(text: '0'));
                return Card(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
                    child: Row(children: [
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(p['name'], style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
                          const SizedBox(height: 6),
                          Wrap(spacing: 8, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: (bad ? AppColors.danger : AppColors.green).withValues(alpha: .08),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(color: (bad ? AppColors.danger : AppColors.green).withValues(alpha: .4)),
                              ),
                              child: Text('Stock: ${qty(stock)}', style: TextStyle(color: bad ? AppColors.danger : AppColors.green, fontWeight: FontWeight.w700, fontSize: 12)),
                            ),
                            PopupMenuButton<int>(
                              tooltip: 'Batches',
                              onSelected: (_) => _inward(p),
                              itemBuilder: (_) => [
                                if (canManage) const PopupMenuItem(value: 1, child: Text('+ Inward Batch (with expiry)', style: TextStyle(color: AppColors.blue, fontWeight: FontWeight.w600))),
                                if (batches.isEmpty) const PopupMenuItem(enabled: false, child: Text('No active batch tracking records for this item yet.')),
                                for (final b in batches)
                                  PopupMenuItem(
                                    enabled: false,
                                    child: Text('${b['batchNumber']} • ${qty(toDouble(b['remainingQuantity']))} left'
                                        '${b['expiryDate'] != null ? ' • Exp ${dateOnly(DateTime.parse(b['expiryDate']))}' : ''}'),
                                  ),
                              ],
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(borderRadius: BorderRadius.circular(6), border: Border.all(color: AppColors.border)),
                                child: Row(mainAxisSize: MainAxisSize.min, children: [
                                  const Icon(Icons.layers_outlined, size: 14),
                                  Text(' ${batches.length} Batches', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                                  const Icon(Icons.keyboard_arrow_down, size: 16),
                                ]),
                              ),
                            ),
                            Text('• ${p['category']?['name'] ?? 'General'}', style: const TextStyle(fontSize: 12, color: AppColors.muted)),
                          ]),
                        ]),
                      ),
                      if (canManage) ...[
                        SizedBox(
                          width: 84,
                          child: TextField(
                            controller: ctrl,
                            textAlign: TextAlign.center,
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            style: const TextStyle(fontWeight: FontWeight.w700, fontFamily: 'monospace'),
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
                            child: const SizedBox(width: 44, height: 44, child: Icon(Icons.check, color: Colors.white)),
                          ),
                        ),
                      ],
                    ]),
                  ),
                );
              },
            );
          },
        ),
      ),
    ]);
  }

  Widget _batches() => Column(children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Wrap(spacing: 6, children: [
            for (final f in const [('all', 'All Batches'), ('expiring', 'Expiring (≤3d)'), ('expired', 'Expired Only')])
              ChoiceChip(label: Text(f.$2), selected: _batchFilter == f.$1, onSelected: (_) => setState(() => _batchFilter = f.$1)),
          ]),
        ),
        Expanded(
          child: Loader<List>(
            key: ValueKey('batches$_batchFilter$_v'),
            load: () async => await Api.instance.get('/stock/batches', {'filter': _batchFilter}) as List,
            builder: (context, list, _) => list.isEmpty
                ? ListView(children: const [SizedBox(height: 60), EmptyState(icon: Icons.label_off_outlined, title: 'No stock batches found.')])
                : ListView(padding: const EdgeInsets.fromLTRB(12, 0, 12, 24), children: [
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton.icon(
                        onPressed: () => PrintService.exportTablePdf(
                          title: 'Batch-Wise Stock Report',
                          subtitle: 'Filter: $_batchFilter',
                          headers: ['Product', 'Batch', 'Inward', 'Remaining', 'Expiry', 'Status'],
                          rows: [
                            for (final b in list)
                              [b['product']['name'], b['batchNumber'], qty(toDouble(b['inwardQuantity'])), qty(toDouble(b['remainingQuantity'])),
                                b['expiryDate'] == null ? '-' : dateOnly(DateTime.parse(b['expiryDate'])), _expiryLabel(b['daysLeft'])],
                          ],
                        ),
                        icon: const Icon(Icons.picture_as_pdf_outlined),
                        label: const Text('Export Batch PDF'),
                      ),
                    ),
                    for (final b in list)
                      Card(
                        child: ListTile(
                          title: Text('${b['product']['name']} • ${b['batchNumber']}'),
                          subtitle: Text('Remaining ${qty(toDouble(b['remainingQuantity']))} of ${qty(toDouble(b['inwardQuantity']))}${b['location'] != null ? ' • ${b['location']}' : ''}'),
                          trailing: Pill(_expiryLabel(b['daysLeft']), _expiryColor(b['daysLeft'])),
                        ),
                      ),
                  ]),
          ),
        ),
      ]);

  static String _expiryLabel(dynamic d) => d == null ? 'No Expiry' : (d as num) < 0 ? 'EXPIRED' : d == 0 ? 'Expires Today' : '$d d left';
  static Color _expiryColor(dynamic d) => d == null ? StatusColors.muted : (d as num) < 0 ? StatusColors.due : d <= 3 ? StatusColors.waiting : StatusColors.ok;

  Widget _history() => Loader<List>(
        key: ValueKey('history$_v'),
        load: () async => await Api.instance.get('/stock/history', {'limit': 300}) as List,
        builder: (context, list, _) => list.isEmpty
            ? ListView(children: const [SizedBox(height: 60), EmptyState(icon: Icons.history, title: 'No stock movements yet')])
            : ListView.separated(
                padding: const EdgeInsets.all(12),
                itemCount: list.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (_, i) {
                  final m = list[i];
                  final q = toDouble(m['quantity']);
                  return ListTile(
                    dense: true,
                    leading: Icon(q >= 0 ? Icons.south_west : Icons.north_east, color: q >= 0 ? StatusColors.ok : StatusColors.due),
                    title: Text('${m['productName']} • ${(m['type'] as String).replaceAll('_', ' ')}'),
                    subtitle: Text('${dateTime(DateTime.parse(m['createdAt']))}${m['note'] != null ? ' • ${m['note']}' : ''}${m['userName'] != null ? ' • ${m['userName']}' : ''}'),
                    trailing: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
                      Text('${q >= 0 ? '+' : ''}${qty(q)}', style: TextStyle(fontWeight: FontWeight.w800, color: q >= 0 ? StatusColors.ok : StatusColors.due)),
                      Text('Bal ${qty(toDouble(m['balanceAfter']))}', style: const TextStyle(fontSize: 11)),
                    ]),
                  );
                },
              ),
      );
}
