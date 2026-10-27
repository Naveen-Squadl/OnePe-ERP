import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api.dart';
import '../../core/format.dart';
import '../../core/theme.dart';
import '../../models/models.dart';
import '../../services/customer_cache.dart';
import '../../state/session.dart';
import '../screens/customers/customers_screen.dart';
import 'common.dart';

/// Searchable customer picker (bottom sheet). Users who may manage customers can also add a
/// new one from the search text (a typed mobile number or name is prefilled).
Future<Customer?> pickCustomer(BuildContext context) => showModalBottomSheet<Customer>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => const _CustomerPicker(),
    );

class _CustomerPicker extends StatefulWidget {
  const _CustomerPicker();
  @override
  State<_CustomerPicker> createState() => _CustomerPickerState();
}

class _CustomerPickerState extends State<_CustomerPicker> {
  String q = '';
  bool _offline = false;
  late Future<List<Customer>> future = _load();

  /// Server search; offline → the customers saved on this device.
  Future<List<Customer>> _load() async {
    try {
      final list = await Api.instance.get('/customers', {'q': q}) as List;
      if (q.isEmpty) CustomerCache.save(list);
      _offline = false;
      return list.map((e) => Customer(Map<String, dynamic>.from(e))).toList();
    } on ApiException catch (e) {
      if (!e.isNetwork) rethrow;
      _offline = true;
      return CustomerCache.search(q);
    }
  }

  bool get _isPhone => RegExp(r'^\d{10}$').hasMatch(q.trim());

  Future<void> _add() async {
    final t = q.trim();
    final digits = RegExp(r'^\d+$').hasMatch(t);
    final c = await customerForm(context, phone: digits ? t : null, name: digits || t.isEmpty ? null : t);
    if (c != null && mounted) Navigator.pop(context, c);
  }

  Widget _addTile(String label) => ListTile(
        leading: const CircleAvatar(backgroundColor: AppColors.green, foregroundColor: Colors.white, child: Icon(Icons.person_add_alt_1)),
        title: Text(label, style: const TextStyle(fontWeight: FontWeight.w600, color: AppColors.green)),
        subtitle: const Text('Name, mobile, address, GSTIN, opening balance'),
        onTap: _add,
      );

  @override
  Widget build(BuildContext context) => SizedBox(
        height: MediaQuery.of(context).size.height * .8,
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: SearchField(
              hint: 'Search / Add customer by name or mobile number',
              suffix: context.read<Session>().can('customers.manage')
                  ? IconButton(tooltip: 'Add new customer', icon: const Icon(Icons.person_add_alt_1, color: AppColors.green), onPressed: _add)
                  : null,
              onChanged: (v) => setState(() {
                q = v;
                future = _load();
              }),
            ),
          ),
          Expanded(
            child: FutureBuilder<List<Customer>>(
              future: future,
              builder: (c, s) {
                if (!s.hasData) return const Center(child: CircularProgressIndicator());
                final canAdd = context.read<Session>().can('customers.manage');
                final unknownPhone = _isPhone && !s.data!.any((c) => c.phone == q.trim());
                // Offer "add" when nothing matches, or a typed mobile isn't an existing customer (online only).
                final showAdd = canAdd && !_offline && (s.data!.isEmpty || unknownPhone);
                final addLabel = _isPhone ? 'Add new customer with ${q.trim()}' : (q.trim().isEmpty ? 'Add new customer' : 'Add "${q.trim()}" as new customer');
                if (s.data!.isEmpty && !showAdd && !(_offline && unknownPhone)) {
                  return EmptyState(icon: Icons.person_search, title: _offline ? 'Offline – no saved customer matches.' : 'No customers match your search.');
                }
                return ListView(children: [
                  if (_offline)
                    const Padding(
                      padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
                      child: Text('Offline – showing customers saved on this device (balances as of last sync).',
                          style: TextStyle(fontSize: 12, color: AppColors.muted, fontWeight: FontWeight.w600)),
                    ),
                  if (_offline && unknownPhone) ...[
                    ListTile(
                      leading: const CircleAvatar(backgroundColor: AppColors.green, foregroundColor: Colors.white, child: Icon(Icons.phone_android)),
                      title: Text('Use ${q.trim()} for this bill', style: const TextStyle(fontWeight: FontWeight.w600, color: AppColors.green)),
                      subtitle: const Text('Customer is created when the bill syncs'),
                      onTap: () => Navigator.pop(context, Customer.phoneOnly(q.trim())),
                    ),
                    const Divider(height: 1),
                  ],
                  if (showAdd) ...[
                    _addTile(addLabel),
                    const Divider(height: 1),
                  ],
                  for (final cu in s.data!)
                    ListTile(
                      leading: CircleAvatar(child: Text(cu.name.characters.first.toUpperCase())),
                      title: Text(cu.name),
                      subtitle: Text([cu.phone, if (cu.loyaltyPoints > 0) '★ ${cu.loyaltyPoints.toStringAsFixed(0)} pts'].whereType<String>().join(' • ')),
                      trailing: Text(
                        balanceText(cu.balance),
                        style: TextStyle(color: cu.balance > 0 ? StatusColors.due : StatusColors.ok, fontWeight: FontWeight.w600),
                      ),
                      onTap: () => Navigator.pop(context, cu),
                    ),
                ]);
              },
            ),
          ),
        ]),
      );
}
