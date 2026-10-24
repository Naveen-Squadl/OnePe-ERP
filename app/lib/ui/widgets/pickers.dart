import 'package:flutter/material.dart';

import '../../core/api.dart';
import '../../core/format.dart';
import '../../core/theme.dart';
import '../../models/models.dart';
import 'common.dart';

/// Searchable customer picker (bottom sheet).
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
  late Future<List<Customer>> future = _load();

  Future<List<Customer>> _load() async =>
      (await Api.instance.get('/customers', {'q': q}) as List).map((e) => Customer(Map<String, dynamic>.from(e))).toList();

  @override
  Widget build(BuildContext context) => SizedBox(
        height: MediaQuery.of(context).size.height * .8,
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: SearchField(
              hint: 'Search by customer name, phone number, GSTIN...',
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
                if (s.data!.isEmpty) return const EmptyState(icon: Icons.person_search, title: 'No customers match your search.');
                return ListView(children: [
                  for (final cu in s.data!)
                    ListTile(
                      leading: CircleAvatar(child: Text(cu.name.characters.first.toUpperCase())),
                      title: Text(cu.name),
                      subtitle: Text([cu.phone, if (cu.loyaltyPoints > 0) '★ ${cu.loyaltyPoints.toStringAsFixed(0)} pts'].whereType<String>().join(' • ')),
                      trailing: Text(
                        cu.balance > 0 ? 'Due: ${money(cu.balance)}' : (cu.balance < 0 ? 'Adv: ${money(-cu.balance)}' : 'Balance: ₹0.00'),
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
