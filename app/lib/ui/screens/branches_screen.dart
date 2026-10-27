import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api.dart';
import '../../state/session.dart';
import '../widgets/app_shell.dart';
import '../widgets/common.dart';
import '../widgets/form_dialog.dart';

class BranchesScreen extends StatefulWidget {
  const BranchesScreen({super.key});
  @override
  State<BranchesScreen> createState() => _BranchesScreenState();
}

class _BranchesScreenState extends State<BranchesScreen> {
  int _v = 0;

  Future<void> _edit([Map<String, dynamic>? b]) async {
    final tables = context.read<Session>().shop?.has('tables') ?? false;
    final r = await showFormDialog(context, title: b == null ? 'Add New Branch / Outlet' : 'Edit Branch: ${b['name']}', submit: b == null ? 'Create Branch' : 'Save Changes', fields: [
      FieldSpec('name', 'Branch Name', initial: b?['name'], required: true),
      FieldSpec('code', 'Short Code (used in bill numbers, e.g. MG1)', initial: b?['code']),
      FieldSpec('address', 'Address', initial: b?['address']),
      FieldSpec('contactNumber', 'Contact Number', initial: b?['contactNumber'], keyboard: TextInputType.phone),
      FieldSpec('upiId', 'UPI ID (for QR payments)', initial: b?['upiId']),
      if (tables) FieldSpec('tables', 'Dine-In Tables (comma separated)', initial: (b?['tableNames'] as List?)?.join(', ') ?? 'T1, T2, T3, T4, T5, Parcel'),
    ]);
    if (r == null || !mounted) return;
    final body = {
      'name': r['name'],
      if (r['code']!.isNotEmpty) 'code': r['code'],
      'address': r['address'],
      'contactNumber': r['contactNumber'],
      'upiId': r['upiId'],
      if (tables) 'tableNames': r['tables']!.split(',').map((t) => t.trim()).where((t) => t.isNotEmpty).toList(),
    };
    final ok = await guard(context, () => b == null ? Api.instance.post('/branches', body) : Api.instance.put('/branches/${b['id']}', body), success: 'Branch saved');
    if (ok != null && mounted) {
      setState(() => _v++);
      context.read<Session>().refresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<Session>();
    return AppScaffold(
      title: 'Branches',
      body: Loader<Map<String, dynamic>>(
        key: ValueKey(_v),
        load: () async => Map<String, dynamic>.from(await Api.instance.get('/branches')),
        builder: (context, data, _) {
          final branches = List<Map<String, dynamic>>.from(data['branches']);
          final limit = data['limitReached'] == true;
          return ListView(padding: const EdgeInsets.all(12), children: [
            Card(
              child: ListTile(
                leading: const Icon(Icons.info_outline),
                title: Text('Outlet Usage: ${branches.length} of ${data['maxBranches']} created${limit ? ' (LIMIT REACHED)' : ''}'),
                subtitle: const Text('Create and configure individual branch settings, dine-in tables and UPI IDs for each outlet.'),
                trailing: FilledButton.icon(
                  onPressed: limit
                      ? () => showSnack(context, 'You have reached the maximum allowed outlets (${data['maxBranches']}) set by the Super Admin. Contact Super Admin to increase outlet capacity.', error: true)
                      : () => _edit(),
                  icon: const Icon(Icons.add),
                  label: const Text('Add Branch'),
                ),
              ),
            ),
            const SizedBox(height: 8),
            for (final b in branches)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Card(
                  child: ListTile(
                    leading: Icon(Icons.storefront, color: b['id'] == session.activeBranchId ? Theme.of(context).colorScheme.primary : null),
                    title: Text('${b['name']} (${b['code']})${b['isMain'] == true ? ' • Main' : ''}', style: const TextStyle(fontWeight: FontWeight.w700)),
                    subtitle: Text([
                      if (b['address'] != null) b['address'],
                      if (b['upiId'] != null) 'UPI: ${b['upiId']}',
                      if ((b['tableNames'] as List).isNotEmpty) 'Tables: ${(b['tableNames'] as List).join(', ')}',
                    ].join(' • ')),
                    trailing: Wrap(children: [
                      if (b['id'] != session.activeBranchId)
                        TextButton(
                          onPressed: () {
                            session.switchBranch(b['id']);
                            showSnack(context, 'Switched active POS outlet to ${b['name']}');
                          },
                          child: const Text('Use here'),
                        ),
                      IconButton(tooltip: 'Branch Settings', onPressed: () => _edit(b), icon: const Icon(Icons.edit)),
                      if (b['isMain'] != true)
                        IconButton(
                          tooltip: 'Delete Branch',
                          onPressed: () async {
                            if (await confirm(context, 'Delete Branch', 'Delete ${b['name']}?', danger: true, ok: 'Delete') && context.mounted) {
                              final r = await guard(context, () => Api.instance.delete('/branches/${b['id']}'), success: 'Branch ${b['name']} deleted.');
                              if (r != null && context.mounted) {
                                setState(() => _v++);
                                context.read<Session>().refresh();
                              }
                            }
                          },
                          icon: const Icon(Icons.delete_outline),
                        ),
                    ]),
                  ),
                ),
              ),
          ]);
        },
      ),
    );
  }
}
