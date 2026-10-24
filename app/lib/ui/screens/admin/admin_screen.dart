import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/api.dart';
import '../../../core/format.dart';
import '../../../core/theme.dart';
import '../../../state/session.dart';
import '../../widgets/brand.dart';
import '../../widgets/common.dart';

/// Super Admin console: system stats, shops & subscriptions, users, activity, enquiries.
class AdminScreen extends StatefulWidget {
  const AdminScreen({super.key});
  @override
  State<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends State<AdminScreen> {
  int _v = 0;
  void _reload() => setState(() => _v++);

  @override
  Widget build(BuildContext context) {
    final session = context.watch<Session>();
    return DefaultTabController(
      length: 5,
      child: Scaffold(
        appBar: GradientAppBar(
          title: const Text('Super Admin'),
          actions: [
            IconButton(tooltip: 'Refresh Data', onPressed: _reload, icon: const Icon(Icons.refresh)),
            IconButton(tooltip: 'Sign Out', onPressed: session.logout, icon: const Icon(Icons.logout)),
          ],
          bottom: const TabBar(isScrollable: true, tabAlignment: TabAlignment.start, tabs: [
            Tab(text: 'Overview'),
            Tab(text: 'All Shops'),
            Tab(text: 'Users'),
            Tab(text: 'Activity Logs'),
            Tab(text: 'Inquiries'),
          ]),
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: () async {
            if (await showDialog<bool>(context: context, builder: (_) => const _ShopDialog()) == true) _reload();
          },
          icon: const Icon(Icons.add_business),
          label: const Text('Add New Shop'),
        ),
        body: TabBarView(children: [
          _overview(),
          _shops(),
          _users(),
          _activity(),
          _enquiries(),
        ]),
      ),
    );
  }

  Widget _overview() => Loader<Map<String, dynamic>>(
        key: ValueKey('stats$_v'),
        load: () async => Map<String, dynamic>.from(await Api.instance.get('/admin/stats')),
        builder: (context, s, _) => ListView(padding: const EdgeInsets.all(12), children: [
          Text('Welcome, Super Admin!', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
          const Text('Manage all shops and users from here'),
          const SizedBox(height: 12),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final t in [
              ('Total Shops', '${s['totalShops']} (${s['activeShops']} active)', Icons.store),
              ('Total Users', '${s['totalUsers']} (${s['activeUsers']} active)', Icons.people),
              ("Today's Activity", '${s['todayActivity']}', Icons.bolt),
            ])
              SizedBox(width: 260, child: StatTile(label: t.$1, value: t.$2, icon: t.$3)),
          ]),
          const SizedBox(height: 16),
          const Text('Subscription Plans', style: TextStyle(fontWeight: FontWeight.w800)),
          Wrap(spacing: 8, children: [
            for (final e in Map<String, dynamic>.from(s['subscriptionBreakdown']).entries) Chip(label: Text('${e.key}: ${e.value}')),
          ]),
          const SizedBox(height: 16),
          const Text('Recent Activity (Last 7 Days)', style: TextStyle(fontWeight: FontWeight.w800)),
          for (final a in s['recentActivity'])
            ListTile(dense: true, title: Text(a['description']), subtitle: Text('${a['action']} • ${a['userName'] ?? 'system'} • ${dateTime(DateTime.parse(a['createdAt']))}')),
        ]),
      );

  Widget _shops() => Loader<List>(
        key: ValueKey('shops$_v'),
        load: () async => await Api.instance.get('/admin/shops') as List,
        builder: (context, shops, _) => shops.isEmpty
            ? ListView(children: const [SizedBox(height: 60), EmptyState(icon: Icons.store, title: 'No shops yet', subtitle: 'Create your first shop to get started')])
            : ListView.separated(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
                itemCount: shops.length,
                separatorBuilder: (_, _) => const SizedBox(height: 6),
                itemBuilder: (_, i) {
                  final s = Map<String, dynamic>.from(shops[i]);
                  final exp = s['subscriptionExpiry'] == null ? null : DateTime.parse(s['subscriptionExpiry']);
                  final expired = exp != null && exp.isBefore(DateTime.now());
                  return Card(
                    child: ListTile(
                      leading: CircleAvatar(child: Text((s['name'] as String).characters.first.toUpperCase())),
                      title: Text(s['name'], style: const TextStyle(fontWeight: FontWeight.w700)),
                      subtitle: Text([
                        'Owner: ${s['ownerEmail']}',
                        '${s['shopType']} • ${s['plan']}',
                        'Users ${s['_count']['users']}/${s['maxUsers']} • Outlets ${s['_count']['branches']}/${s['maxBranches']}',
                        if (exp != null) '${expired ? 'Expired' : 'Expires'} ${dateOnly(exp)}',
                        'Created: ${dateOnly(DateTime.parse(s['createdAt']))}',
                      ].join(' • ')),
                      trailing: Wrap(crossAxisAlignment: WrapCrossAlignment.center, children: [
                        Pill(s['isActive'] == true ? 'Active' : 'Inactive', s['isActive'] == true ? StatusColors.ok : StatusColors.muted),
                        if (expired) const Padding(padding: EdgeInsets.only(left: 4), child: Pill('Plan Expired', StatusColors.due)),
                        PopupMenuButton<String>(
                          onSelected: (v) async {
                            switch (v) {
                              case 'sub':
                                if (await showDialog<bool>(context: context, builder: (_) => _SubscriptionDialog(shop: s)) == true) _reload();
                              case 'toggle':
                                final r = await guard(context, () => Api.instance.put('/admin/shops/${s['id']}', {'isActive': s['isActive'] != true}),
                                    success: '${s['name']} ${s['isActive'] == true ? 'deactivated' : 'activated'}');
                                if (r != null) _reload();
                              case 'delete':
                                if (await confirm(context, 'Delete Shop', 'Permanently delete ${s['name']} and ALL its data (bills, products, users)? This cannot be undone.', danger: true, ok: 'Delete') &&
                                    context.mounted) {
                                  final r = await guard(context, () => Api.instance.delete('/admin/shops/${s['id']}'), success: '${s['name']} deleted');
                                  if (r != null) _reload();
                                }
                            }
                          },
                          itemBuilder: (_) => [
                            const PopupMenuItem(value: 'sub', child: Text('Edit Subscription')),
                            PopupMenuItem(value: 'toggle', child: Text(s['isActive'] == true ? 'Deactivate' : 'Activate')),
                            const PopupMenuItem(value: 'delete', child: Text('Delete')),
                          ],
                        ),
                      ]),
                    ),
                  );
                },
              ),
      );

  Widget _users() => Loader<List>(
        key: ValueKey('users$_v'),
        load: () async => await Api.instance.get('/admin/users') as List,
        builder: (context, users, _) => ListView(padding: const EdgeInsets.all(12), children: [
          for (final u in users)
            ListTile(
              leading: Icon(u['role'] == 'SUPER_ADMIN' ? Icons.shield : Icons.person),
              title: Text('${u['name']} • ${u['email']}'),
              subtitle: Text('${(u['role'] as String).replaceAll('_', ' ')}${u['shop'] != null ? ' • Shop: ${u['shop']['name']}' : ''}'
                  '${u['lastLoginAt'] != null ? ' • Last Login ${dateTime(DateTime.parse(u['lastLoginAt']))}' : ''}'),
              trailing: u['role'] == 'SUPER_ADMIN'
                  ? null
                  : Switch(
                      value: u['isActive'] == true,
                      onChanged: (v) async {
                        final r = await guard(context, () => Api.instance.put('/admin/users/${u['id']}', {'isActive': v}));
                        if (r != null) _reload();
                      },
                    ),
            ),
        ]),
      );

  Widget _activity() => Loader<List>(
        key: ValueKey('act$_v'),
        load: () async => await Api.instance.get('/admin/activity', {'limit': 300}) as List,
        builder: (context, logs, _) => logs.isEmpty
            ? ListView(children: const [SizedBox(height: 60), EmptyState(icon: Icons.history, title: 'No activity yet', subtitle: 'Activity logs will appear here')])
            : ListView(padding: const EdgeInsets.all(12), children: [
                for (final a in logs)
                  ListTile(
                    dense: true,
                    leading: const Icon(Icons.bolt_outlined),
                    title: Text(a['description']),
                    subtitle: Text('${a['action']} • By: ${a['userName'] ?? 'system'} • ${dateTime(DateTime.parse(a['createdAt']))}'),
                  ),
              ]),
      );

  Widget _enquiries() => Loader<List>(
        key: ValueKey('enq$_v'),
        load: () async => await Api.instance.get('/admin/enquiries') as List,
        builder: (context, list, _) => list.isEmpty
            ? ListView(children: const [SizedBox(height: 60), EmptyState(icon: Icons.mark_email_unread_outlined, title: 'No inquiries yet')])
            : ListView(padding: const EdgeInsets.all(12), children: [
                for (final e in list)
                  Card(
                    child: ListTile(
                      title: Text('${e['name']} • ${e['businessType'] ?? 'Business'}'),
                      subtitle: Text('${e['contactNo']}${e['location'] != null ? ' • ${e['location']}' : ''} • Submitted on: ${dateTime(DateTime.parse(e['createdAt']))}'),
                      trailing: Wrap(crossAxisAlignment: WrapCrossAlignment.center, children: [
                        IconButton(tooltip: 'Call', onPressed: () => launchUrl(Uri.parse('tel:${e['contactNo']}')), icon: const Icon(Icons.call)),
                        IconButton(
                          tooltip: 'WhatsApp',
                          onPressed: () {
                            final digits = (e['contactNo'] as String).replaceAll(RegExp(r'[^0-9]'), '');
                            final to = digits.length == 10 ? '91$digits' : digits;
                            launchUrl(Uri.parse('https://wa.me/$to?text=${Uri.encodeComponent('Hello ${e['name']}, regarding your OnePe POS inquiry...')}'),
                                mode: LaunchMode.externalApplication);
                          },
                          icon: const Icon(Icons.chat),
                        ),
                        DropdownButton<String>(
                          value: e['status'],
                          underline: const SizedBox.shrink(),
                          items: const [
                            DropdownMenuItem(value: 'NEW', child: Text('New')),
                            DropdownMenuItem(value: 'CONTACTED', child: Text('Contacted')),
                            DropdownMenuItem(value: 'CLOSED', child: Text('Closed')),
                          ],
                          onChanged: (v) async {
                            final r = await guard(context, () => Api.instance.put('/admin/enquiries/${e['id']}', {'status': v}));
                            if (r != null) _reload();
                          },
                        ),
                      ]),
                    ),
                  ),
              ]),
      );
}

class _ShopDialog extends StatefulWidget {
  const _ShopDialog();
  @override
  State<_ShopDialog> createState() => _ShopDialogState();
}

class _ShopDialogState extends State<_ShopDialog> {
  final _form = GlobalKey<FormState>();
  final _shop = TextEditingController(), _owner = TextEditingController(), _email = TextEditingController(), _password = TextEditingController();
  final _address = TextEditingController(), _contact = TextEditingController(), _branches = TextEditingController(text: '1');
  String _type = 'RETAIL', _plan = 'BASIC';
  DateTime _expiry = DateTime.now().add(const Duration(days: 365));
  bool _busy = false;

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Create New Shop'),
        content: SizedBox(
          width: 460,
          child: Form(
            key: _form,
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                TextFormField(controller: _shop, decoration: const InputDecoration(labelText: 'Shop Name *'), validator: (v) => v!.trim().isEmpty ? 'Please enter shop name' : null),
                const SizedBox(height: 8),
                TextFormField(controller: _owner, decoration: const InputDecoration(labelText: 'Owner Name *'), validator: (v) => v!.trim().isEmpty ? 'Please enter owner name' : null),
                const SizedBox(height: 8),
                TextFormField(controller: _email, decoration: const InputDecoration(labelText: 'Admin Email *'), validator: (v) => v!.contains('@') ? null : 'Please enter email'),
                const SizedBox(height: 8),
                TextFormField(controller: _password, obscureText: true, decoration: const InputDecoration(labelText: 'Admin Password *'), validator: (v) => v!.length < 8 ? 'Password must be at least 8 characters' : null),
                const SizedBox(height: 8),
                TextFormField(controller: _address, decoration: const InputDecoration(labelText: 'Address')),
                const SizedBox(height: 8),
                TextFormField(controller: _contact, decoration: const InputDecoration(labelText: 'Contact Number')),
                const SizedBox(height: 8),
                DropdownButtonFormField(
                  initialValue: _type,
                  decoration: const InputDecoration(labelText: 'Shop Type'),
                  items: const [
                    DropdownMenuItem(value: 'BAKERY', child: Text('Bakery / Restaurant')),
                    DropdownMenuItem(value: 'RETAIL', child: Text('Retail Store')),
                    DropdownMenuItem(value: 'DISTRIBUTOR', child: Text('Distributor')),
                  ],
                  onChanged: (v) => setState(() => _type = v!),
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField(
                  initialValue: _plan,
                  decoration: const InputDecoration(labelText: 'Subscription Plan'),
                  items: const [
                    DropdownMenuItem(value: 'FREE', child: Text('Free (1 user)')),
                    DropdownMenuItem(value: 'BASIC', child: Text('Basic (4 users)')),
                    DropdownMenuItem(value: 'STANDARD', child: Text('Standard (6 users, 2 outlets)')),
                    DropdownMenuItem(value: 'PREMIUM', child: Text('Premium (10 users, 3 outlets)')),
                    DropdownMenuItem(value: 'ENTERPRISE', child: Text('Enterprise (50 users, 10 outlets)')),
                  ],
                  onChanged: (v) => setState(() => _plan = v!),
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _branches,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Maximum allowed branches'),
                  validator: (v) => (int.tryParse(v ?? '') ?? 0) < 1 ? 'Must allow at least 1 branch' : null,
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text('Expiry: ${dateOnly(_expiry)}'),
                  trailing: const Icon(Icons.event),
                  onTap: () async {
                    final d = await showDatePicker(context: context, initialDate: _expiry, firstDate: DateTime.now(), lastDate: DateTime(2100));
                    if (d != null) setState(() => _expiry = d);
                  },
                ),
              ]),
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(
            onPressed: _busy
                ? null
                : () async {
                    if (!_form.currentState!.validate()) return;
                    setState(() => _busy = true);
                    final r = await guard(context, () => Api.instance.post('/admin/shops', {
                          'shopName': _shop.text, 'ownerName': _owner.text, 'email': _email.text, 'password': _password.text,
                          'address': _address.text, 'contactNumber': _contact.text, 'shopType': _type, 'plan': _plan,
                          'maxBranches': int.parse(_branches.text), 'subscriptionExpiry': _expiry.toIso8601String(),
                        }), success: '✅ Shop created successfully');
                    if (mounted) setState(() => _busy = false);
                    if (r != null && context.mounted) Navigator.pop(context, true);
                  },
            child: const Text('Create Shop'),
          ),
        ],
      );
}

class _SubscriptionDialog extends StatefulWidget {
  final Map<String, dynamic> shop;
  const _SubscriptionDialog({required this.shop});
  @override
  State<_SubscriptionDialog> createState() => _SubscriptionDialogState();
}

class _SubscriptionDialogState extends State<_SubscriptionDialog> {
  late String plan = widget.shop['plan'];
  late String type = widget.shop['shopType'];
  late final users = TextEditingController(text: '${widget.shop['maxUsers']}');
  late final branches = TextEditingController(text: '${widget.shop['maxBranches']}');
  late DateTime expiry = widget.shop['subscriptionExpiry'] == null ? DateTime.now().add(const Duration(days: 365)) : DateTime.parse(widget.shop['subscriptionExpiry']);

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text('Edit Subscription: ${widget.shop['name']}'),
        content: SizedBox(
          width: 400,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            DropdownButtonFormField(
              initialValue: plan,
              decoration: const InputDecoration(labelText: 'Plan'),
              items: [for (final p in ['FREE', 'BASIC', 'STANDARD', 'PREMIUM', 'ENTERPRISE']) DropdownMenuItem(value: p, child: Text(p))],
              onChanged: (v) => setState(() => plan = v!),
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField(
              initialValue: type,
              decoration: const InputDecoration(labelText: 'Shop Type'),
              items: [for (final t in ['BAKERY', 'RETAIL', 'DISTRIBUTOR', 'PARKING', 'LOGISTICS']) DropdownMenuItem(value: t, child: Text(t))],
              onChanged: (v) => setState(() => type = v!),
            ),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(child: TextField(controller: users, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Max Users'))),
              const SizedBox(width: 8),
              Expanded(child: TextField(controller: branches, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Max Branches'))),
            ]),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text('Expiry: ${dateOnly(expiry)}'),
              trailing: const Icon(Icons.event),
              onTap: () async {
                final d = await showDatePicker(context: context, initialDate: expiry, firstDate: DateTime(2020), lastDate: DateTime(2100));
                if (d != null) setState(() => expiry = d);
              },
            ),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(
            onPressed: () async {
              final r = await guard(context, () => Api.instance.put('/admin/shops/${widget.shop['id']}', {
                    'plan': plan, 'shopType': type, 'maxUsers': int.tryParse(users.text), 'maxBranches': int.tryParse(branches.text),
                    'subscriptionExpiry': expiry.toIso8601String(),
                  }), success: 'Subscription updated');
              if (r != null && context.mounted) Navigator.pop(context, true);
            },
            child: const Text('Save'),
          ),
        ],
      );
}
