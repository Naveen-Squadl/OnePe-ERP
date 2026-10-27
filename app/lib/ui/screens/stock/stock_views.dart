import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/api.dart';
import '../../../core/format.dart';
import '../../../core/theme.dart';
import '../../../services/print_service.dart';
import '../../../state/catalog.dart';
import '../../widgets/common.dart';

/// "+ Inward Batch" dialog (quantity, batch no., purchase price, expiry). Returns true when stock was added.
Future<bool> inwardBatch(BuildContext context, Map<String, dynamic> p) async {
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
  if (ok != true || q == null || q <= 0 || !context.mounted) return false;
  final r = await guard(context, () => Api.instance.post('/stock/inward', {
        'productId': p['id'],
        'quantity': q,
        if (batch.text.isNotEmpty) 'batchNumber': batch.text,
        if (expiry != null) 'expiryDate': expiry!.toIso8601String(),
        'purchasePrice': double.tryParse(price.text),
      }));
  if (r == null || !context.mounted) return false;
  showSnack(context, '✅ Inwarded ${qty(q)} units for ${p['name']} (Batch: ${r['batchNumber']})');
  context.read<Catalog>().load();
  return true;
}



/// Inventory → Batches & Expiry.
class StockBatchesView extends StatefulWidget {
  const StockBatchesView({super.key});
  @override
  State<StockBatchesView> createState() => _StockBatchesViewState();
}

class _StockBatchesViewState extends State<StockBatchesView> {
  String _batchFilter = 'all';

  @override
  Widget build(BuildContext context) => _batches();

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
            key: ValueKey('batches$_batchFilter'),
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
}
