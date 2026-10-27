import 'package:flutter/material.dart';

import '../../core/api.dart';
import '../../core/format.dart';
import '../../core/theme.dart';
import '../widgets/app_shell.dart';
import '../widgets/common.dart';
import '../widgets/form_dialog.dart';

class SuppliersScreen extends StatefulWidget {
  const SuppliersScreen({super.key});
  @override
  State<SuppliersScreen> createState() => _SuppliersScreenState();
}

class _SuppliersScreenState extends State<SuppliersScreen> {
  String _q = '';
  int _v = 0;

  Future<void> _edit([Map<String, dynamic>? s]) async {
    final r = await showFormDialog(context, title: s == null ? 'Add Supplier' : 'Edit Supplier', fields: [
      FieldSpec('name', 'Supplier Name', initial: s?['name'], required: true),
      FieldSpec('phone', 'Phone', initial: s?['phone'], keyboard: TextInputType.phone),
      FieldSpec('address', 'Address', initial: s?['address']),
      FieldSpec('gstin', 'GSTIN', initial: s?['gstin']),
      FieldSpec('openingBalance', 'Opening Balance (payable)', initial: s == null ? '0' : '${s['openingBalance']}', keyboard: TextInputType.number),
    ]);
    if (r == null || !mounted) return;
    final body = {...r, 'openingBalance': double.tryParse(r['openingBalance']!) ?? 0};
    final ok = await guard(context, () => s == null ? Api.instance.post('/suppliers', body) : Api.instance.put('/suppliers/${s['id']}', body));
    if (ok != null) setState(() => _v++);
  }

  Future<void> _pay(Map<String, dynamic> s) async {
    String method = 'CASH';
    final amount = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, set) => AlertDialog(
          title: Text('Record Payment - ${s['name']}'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            Text('Current Outstanding Balance: ${money(toDouble(s['currentBalance']))}'),
            const SizedBox(height: 12),
            TextField(controller: amount, autofocus: true, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Amount Paid (₹)')),
            const SizedBox(height: 12),
            DropdownButtonFormField(
              initialValue: method,
              decoration: const InputDecoration(labelText: 'Payment Mode'),
              items: const [
                DropdownMenuItem(value: 'CASH', child: Text('Cash')),
                DropdownMenuItem(value: 'UPI', child: Text('UPI')),
                DropdownMenuItem(value: 'BANK', child: Text('Bank Transfer')),
                DropdownMenuItem(value: 'CHEQUE', child: Text('Cheque')),
              ],
              onChanged: (v) => set(() => method = v!),
            ),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Record')),
          ],
        ),
      ),
    );
    final v = double.tryParse(amount.text);
    if (ok != true || v == null || !mounted) return;
    final r = await guard(context, () => Api.instance.post('/suppliers/${s['id']}/payments', {'amount': v, 'method': method}), success: 'Paid via $method');
    if (r != null) setState(() => _v++);
  }

  @override
  Widget build(BuildContext context) => AppScaffold(
        title: 'Suppliers',
        fab: FloatingActionButton.extended(onPressed: () => _edit(), icon: const Icon(Icons.add), label: const Text('Add Supplier')),
        body: Column(children: [
          Padding(padding: const EdgeInsets.all(12), child: SearchField(hint: 'Search suppliers by name or phone...', onChanged: (v) => setState(() => _q = v))),
          Expanded(
            child: Loader<List>(
              key: ValueKey('$_q$_v'),
              load: () async => await Api.instance.get('/suppliers', {'q': _q}) as List,
              builder: (context, list, _) => list.isEmpty
                  ? ListView(children: const [SizedBox(height: 60), EmptyState(icon: Icons.local_shipping_outlined, title: 'No suppliers added yet. Tap + to add one.')])
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 96),
                      itemCount: list.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 6),
                      itemBuilder: (_, i) {
                        final s = Map<String, dynamic>.from(list[i]);
                        final bal = toDouble(s['currentBalance']);
                        return Card(
                          child: ListTile(
                            leading: const CircleAvatar(child: Icon(Icons.local_shipping)),
                            title: Text(s['name'], style: const TextStyle(fontWeight: FontWeight.w700)),
                            subtitle: Text([s['phone'], s['gstin']].whereType<String>().join(' • ')),
                            trailing: Wrap(crossAxisAlignment: WrapCrossAlignment.center, children: [
                              Text('Pending: ${money(bal)}', style: TextStyle(color: bal > 0 ? StatusColors.due : StatusColors.ok, fontWeight: FontWeight.w700)),
                              PopupMenuButton<String>(
                                onSelected: (v) async {
                                  if (v == 'pay') return _pay(s);
                                  if (v == 'edit') return _edit(s);
                                  if (await confirm(context, 'Delete Supplier', 'Delete ${s['name']}?', danger: true, ok: 'Delete') && context.mounted) {
                                    final r = await guard(context, () => Api.instance.delete('/suppliers/${s['id']}'));
                                    if (r != null) setState(() => _v++);
                                  }
                                },
                                itemBuilder: (_) => const [
                                  PopupMenuItem(value: 'pay', child: Text('Record Payment')),
                                  PopupMenuItem(value: 'edit', child: Text('Edit Supplier')),
                                  PopupMenuItem(value: 'delete', child: Text('Delete Supplier')),
                                ],
                              ),
                            ]),
                          ),
                        );
                      },
                    ),
            ),
          ),
        ]),
      );
}
