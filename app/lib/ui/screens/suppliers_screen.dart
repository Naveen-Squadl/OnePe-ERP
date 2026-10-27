import 'package:flutter/material.dart';

import '../../core/api.dart';
import '../../core/format.dart';
import '../../core/theme.dart';
import '../widgets/app_shell.dart';
import '../widgets/common.dart';
import '../widgets/form_dialog.dart';

/// Purchases → Suppliers. Suppliers are archived, never deleted (only with a settled balance).
class SuppliersScreen extends StatefulWidget {
  const SuppliersScreen({super.key});
  @override
  State<SuppliersScreen> createState() => _SuppliersScreenState();
}

class _SuppliersScreenState extends State<SuppliersScreen> {
  String _q = '';
  bool _archived = false;
  int _v = 0;

  Future<void> _edit([Map<String, dynamic>? s]) async {
    final opening = toDouble(s?['openingBalance']);
    final r = await showFormDialog(context, title: s == null ? 'Add Supplier' : 'Edit Supplier', fields: [
      FieldSpec('name', 'Supplier Name', initial: s?['name'], required: true),
      FieldSpec('phone', 'Phone', initial: s?['phone'], keyboard: TextInputType.phone),
      FieldSpec('address', 'Address', initial: s?['address']),
      FieldSpec('gstin', 'GSTIN', initial: s?['gstin']),
      // Due = you owe the supplier; Advance = you paid the supplier ahead.
      FieldSpec('openingBalance', 'Opening Balance', initial: opening.abs().toString(), keyboard: TextInputType.number),
      FieldSpec('openingType', 'Opening balance is', initial: opening < 0 ? 'advance' : 'payable', options: const [('payable', 'Due'), ('advance', 'Advance')]),
    ]);
    if (r == null || !mounted) return;
    final body = {
      for (final k in const ['name', 'phone', 'address', 'gstin']) k: r[k],
      'openingBalance': (double.tryParse(r['openingBalance']!) ?? 0).abs() * (r['openingType'] == 'advance' ? -1 : 1),
    };
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
            Text(supplierBalanceText(toDouble(s['currentBalance']))),
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

  /// Archive instead of delete: only with a settled balance; purchases and payments are kept.
  Future<void> _archive(Map<String, dynamic> s) async {
    final bal = toDouble(s['currentBalance']);
    if (bal.abs() > 0.009) {
      return showSnack(context, bal > 0 ? 'You owe ${s['name']} ${money(bal)} – pay or settle it before archiving' : '${s['name']} has ${money(-bal)} advance from you – settle it before archiving',
          error: true);
    }
    if (!await confirm(context, 'Archive ${s['name']}?',
            'They are hidden from the supplier list and the purchase form. Their purchases and payments are kept, and reports do not change. Restore them any time from Archived.',
            ok: 'Archive') ||
        !mounted) {
      return;
    }
    final r = await guard(context, () => Api.instance.post('/suppliers/${s['id']}/archive'), success: '${s['name']} archived');
    if (r != null) setState(() => _v++);
  }

  Future<void> _restore(Map<String, dynamic> s) async {
    final r = await guard(context, () => Api.instance.post('/suppliers/${s['id']}/restore'), success: '${s['name']} restored');
    if (r != null) setState(() => _v++);
  }

  @override
  Widget build(BuildContext context) => AppScaffold(
        title: 'Suppliers',
        fab: _archived ? null : FloatingActionButton.extended(onPressed: () => _edit(), icon: const Icon(Icons.add), label: const Text('Add Supplier')),
        body: Column(children: [
          Padding(padding: const EdgeInsets.fromLTRB(12, 12, 12, 4), child: SearchField(hint: 'Search suppliers by name or phone...', onChanged: (v) => setState(() => _q = v))),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Wrap(spacing: 6, children: [
              ChoiceChip(label: const Text('Active'), selected: !_archived, onSelected: (_) => setState(() => _archived = false)),
              ChoiceChip(label: const Text('Archived'), selected: _archived, onSelected: (_) => setState(() => _archived = true)),
            ]),
          ),
          Expanded(
            child: Loader<List>(
              key: ValueKey('$_q$_archived$_v'),
              load: () async => await Api.instance.get('/suppliers', {'q': _q, 'filter': _archived ? 'archived' : null}) as List,
              builder: (context, list, _) => list.isEmpty
                  ? ListView(children: [
                      const SizedBox(height: 60),
                      EmptyState(icon: Icons.local_shipping_outlined, title: _archived ? 'No archived suppliers.' : 'No suppliers added yet. Tap + to add one.'),
                    ])
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(12, 8, 12, 96),
                      itemCount: list.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 6),
                      itemBuilder: (_, i) {
                        final s = Map<String, dynamic>.from(list[i]);
                        final bal = toDouble(s['currentBalance']);
                        final color = bal > 0.009 ? StatusColors.due : (bal < -0.009 ? StatusColors.advance : StatusColors.muted);
                        return Card(
                          child: ListTile(
                            leading: const CircleAvatar(child: Icon(Icons.local_shipping)),
                            title: Text(s['name'], style: const TextStyle(fontWeight: FontWeight.w700)),
                            subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              if ([s['phone'], s['gstin']].whereType<String>().isNotEmpty) Text([s['phone'], s['gstin']].whereType<String>().join(' • ')),
                              Text(supplierBalanceText(bal), style: TextStyle(color: color, fontWeight: FontWeight.w700)),
                            ]),
                            trailing: PopupMenuButton<String>(
                              onSelected: (v) => switch (v) {
                                'pay' => _pay(s),
                                'edit' => _edit(s),
                                'archive' => _archive(s),
                                _ => _restore(s),
                              },
                              itemBuilder: (_) => _archived
                                  ? const [PopupMenuItem(value: 'restore', child: Text('Restore Supplier'))]
                                  : const [
                                      PopupMenuItem(value: 'pay', child: Text('Record Payment')),
                                      PopupMenuItem(value: 'edit', child: Text('Edit Supplier')),
                                      PopupMenuItem(value: 'archive', child: Text('Archive Supplier')),
                                    ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ),
        ]),
      );
}
