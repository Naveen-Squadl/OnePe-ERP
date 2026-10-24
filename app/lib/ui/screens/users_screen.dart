import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api.dart';
import '../../core/theme.dart';
import '../../state/session.dart';
import '../widgets/app_shell.dart';
import '../widgets/brand.dart';
import '../widgets/common.dart';

class UsersScreen extends StatefulWidget {
  const UsersScreen({super.key});
  @override
  State<UsersScreen> createState() => _UsersScreenState();
}

class _UsersScreenState extends State<UsersScreen> {
  int _v = 0;
  List<Map<String, dynamic>> _roles = [];

  @override
  void initState() {
    super.initState();
    Api.instance.get('/users/roles').then((r) => setState(() => _roles = List<Map<String, dynamic>>.from(r)));
  }

  Future<void> _edit([Map<String, dynamic>? u]) async {
    final session = context.read<Session>();
    final name = TextEditingController(text: u?['name']);
    final email = TextEditingController(text: u?['email']);
    final password = TextEditingController();
    String role = u?['role'] ?? 'CASHIER';
    String? branchId = u?['branchId'] ?? session.activeBranchId;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, set) {
          final perms = _roles.where((r) => r['role'] == role).firstOrNull?['permissions'] as List? ?? const [];
          return AlertDialog(
            title: Text(u == null ? 'Add Staff' : 'Edit Staff: ${u['name']}'),
            content: SizedBox(
              width: 420,
              child: SingleChildScrollView(
                child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                  TextField(controller: name, decoration: const InputDecoration(labelText: 'Full Name *')),
                  const SizedBox(height: 10),
                  TextField(controller: email, enabled: u == null, decoration: const InputDecoration(labelText: 'Email *')),
                  const SizedBox(height: 10),
                  TextField(controller: password, obscureText: true, decoration: InputDecoration(labelText: u == null ? 'Password *' : 'New password (optional)')),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<String>(
                    initialValue: role,
                    decoration: const InputDecoration(labelText: 'Role'),
                    items: [for (final r in _roles) DropdownMenuItem(value: r['role'] as String, child: Text((r['role'] as String).replaceAll('_', ' ')))],
                    onChanged: (v) => set(() => role = v!),
                  ),
                  const SizedBox(height: 8),
                  const Text('Role Permissions:', style: TextStyle(fontWeight: FontWeight.w700)),
                  for (final p in perms) Text('• $p'),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<String?>(
                    initialValue: branchId,
                    decoration: const InputDecoration(labelText: 'Assigned Branch (Outlet)'),
                    items: [for (final b in session.branches) DropdownMenuItem(value: b.id, child: Text(b.name))],
                    onChanged: (v) => set(() => branchId = v),
                  ),
                ]),
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
              FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Save')),
            ],
          );
        },
      ),
    );
    if (ok != true || !mounted) return;
    final body = {
      'name': name.text.trim(),
      'role': role,
      'branchId': branchId,
      if (u == null) 'email': email.text.trim(),
      if (password.text.isNotEmpty) 'password': password.text,
    };
    final r = await guard(context, () => u == null ? Api.instance.post('/users', body) : Api.instance.put('/users/${u['id']}', body), success: 'Saved');
    if (r != null) setState(() => _v++);
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<Session>();
    final branchName = {for (final b in session.branches) b.id: b.name};
    return AppScaffold(
      title: 'User Management',
      actions: [IconButton(tooltip: 'Refresh Staff', onPressed: () => setState(() => _v++), icon: const Icon(Icons.refresh))],
      fab: FloatingActionButton.extended(onPressed: () => _edit(), icon: const Icon(Icons.person_add_alt_1), label: const Text('Add Staff')),
      body: Loader<Map<String, dynamic>>(
        key: ValueKey(_v),
        load: () async => Map<String, dynamic>.from(await Api.instance.get('/users')),
        builder: (context, data, _) {
          final users = List<Map<String, dynamic>>.from(data['users']);
          return ListView(padding: const EdgeInsets.fromLTRB(12, 12, 12, 96), children: [
            Text('Users: ${users.length} of ${data['maxUsers']} allowed by your plan', style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 8),
            for (final u in users)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(children: [
                      CircleAvatar(
                        radius: 24,
                        backgroundColor: u['role'] == 'ADMIN' ? AppColors.bg : AppColors.blueTint,
                        child: Icon(u['role'] == 'ADMIN' ? Icons.person : Icons.point_of_sale, color: u['role'] == 'ADMIN' ? AppColors.muted : AppColors.green),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(u['name'], style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
                          const SizedBox(height: 2),
                          Wrap(spacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
                            const Icon(Icons.mail_outline, size: 13, color: AppColors.muted),
                            Text(u['email'], style: const TextStyle(fontSize: 13, color: AppColors.muted)),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                              decoration: BoxDecoration(color: (u['isActive'] == true ? Color(0xFFFFF1CC) : AppColors.bg), borderRadius: BorderRadius.circular(6)),
                              child: Text(u['isActive'] == true ? '⚡ Active' : 'Inactive',
                                  style: TextStyle(fontSize: 11, color: u['isActive'] == true ? AppColors.orange : AppColors.muted, fontWeight: FontWeight.w600)),
                            ),
                            Text('• ${branchName[u['branchId']] ?? 'All outlets'}', style: const TextStyle(fontSize: 12, color: AppColors.muted)),
                          ]),
                        ]),
                      ),
                      Container(
                        margin: const EdgeInsets.only(right: 8),
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: (u['role'] == 'ADMIN' ? AppColors.muted : AppColors.green).withValues(alpha: .08),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: (u['role'] == 'ADMIN' ? AppColors.muted : AppColors.green).withValues(alpha: .4)),
                        ),
                        child: Text((u['role'] as String).replaceAll('_', ' '),
                            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: u['role'] == 'ADMIN' ? AppColors.muted : AppColors.green)),
                      ),
                      RowAction(Icons.edit, AppColors.blue, 'Edit User', () => _edit(u)),
                      if (u['id'] != session.user?.id) ...[
                        RowAction(u['isActive'] == true ? Icons.pause_circle_outline : Icons.play_circle_outline, AppColors.orange, u['isActive'] == true ? 'Deactivate' : 'Activate', () async {
                          final r = await guard(context, () => Api.instance.put('/users/${u['id']}', {'isActive': u['isActive'] != true}));
                          if (r != null) setState(() => _v++);
                        }),
                        RowAction(Icons.delete_outline, AppColors.danger, 'Delete User', () async {
                          if (await confirm(context, 'Delete User', 'Are you sure you want to delete ${u['name']}? This action cannot be undone.', danger: true, ok: 'Delete') && context.mounted) {
                            final r = await guard(context, () => Api.instance.delete('/users/${u['id']}'));
                            if (r != null) setState(() => _v++);
                          }
                        }),
                      ],
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
