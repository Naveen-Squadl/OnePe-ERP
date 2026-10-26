import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/api.dart';
import '../../../core/format.dart';
import '../../../core/theme.dart';
import '../../../models/models.dart';
import '../../../services/print_service.dart';
import '../../../state/session.dart';
import '../../widgets/app_shell.dart';
import '../../widgets/brand.dart';
import '../../widgets/common.dart';
import '../../widgets/form_dialog.dart';
import '../bills/bills_screen.dart';

class CustomersScreen extends StatefulWidget {
  const CustomersScreen({super.key});
  @override
  State<CustomersScreen> createState() => _CustomersScreenState();
}

class _CustomersScreenState extends State<CustomersScreen> {
  String _q = '';
  String _filter = 'all';
  int _v = 0;

  @override
  Widget build(BuildContext context) => AppScaffold(
        title: 'Customer Management',
        actions: [
          IconButton(
            tooltip: 'Recalculate & Sync Balances',
            onPressed: () async {
              final r = await guard(context, () => Api.instance.post('/customers/recalculate'));
              if (r != null && context.mounted) {
                showSnack(context, 'Recalculated ${r['recalculated']} customer balances');
                setState(() => _v++);
              }
            },
            icon: const Icon(Icons.calculate_outlined),
          ),
        ],
        fab: FloatingActionButton.extended(
          onPressed: () async {
            if (await editCustomer(context) && mounted) setState(() => _v++);
          },
          icon: const Icon(Icons.person_add),
          label: const Text('Add Customer'),
        ),
        body: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
            child: SearchField(hint: 'Search by customer name, phone number, GSTIN...', onChanged: (v) => setState(() => _q = v)),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Wrap(spacing: 6, children: [
              for (final f in const [('all', 'All Customers'), ('due', 'Balance Due Only'), ('settled', 'Settled / Advance')])
                ChoiceChip(label: Text(f.$2), selected: _filter == f.$1, onSelected: (_) => setState(() => _filter = f.$1)),
            ]),
          ),
          Expanded(
            child: Loader<List<Customer>>(
              key: ValueKey('$_q$_filter$_v'),
              load: () async => (await Api.instance.get('/customers', {'q': _q, 'filter': _filter == 'all' ? null : _filter}) as List)
                  .map((e) => Customer(Map<String, dynamic>.from(e)))
                  .toList(),
              builder: (context, list, _) => list.isEmpty
                  ? ListView(children: const [SizedBox(height: 60), EmptyState(icon: Icons.people_outline, title: 'No customers found. Tap + to add one.')])
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(12, 8, 12, 96),
                      itemCount: list.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 6),
                      itemBuilder: (_, i) {
                        final c = list[i];
                        Future<void> open({bool pay = false, int tab = 0}) async {
                          await Navigator.of(context).push(MaterialPageRoute(builder: (_) => CustomerDetail(customer: c, openPayment: pay, initialTab: tab)));
                          setState(() => _v++);
                        }
                        return Card(
                          child: InkWell(
                            borderRadius: BorderRadius.circular(14),
                            onTap: open,
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Row(children: [
                                CircleAvatar(
                                  radius: 24,
                                  backgroundColor: AppColors.blueTint,
                                  child: Text(c.name.characters.first.toUpperCase(), style: const TextStyle(color: AppColors.blue, fontWeight: FontWeight.w800, fontSize: 18)),
                                ),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                    Text(c.name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                                    if (c.phone != null)
                                      Row(children: [
                                        const Icon(Icons.phone, size: 13, color: AppColors.muted),
                                        const SizedBox(width: 4),
                                        Text(c.phone!, style: const TextStyle(fontSize: 13, color: AppColors.muted)),
                                        if (c.loyaltyPoints > 0) Text('   ★ ${c.loyaltyPoints.toStringAsFixed(0)} pts', style: const TextStyle(fontSize: 12, color: AppColors.amberText)),
                                      ]),
                                    const SizedBox(height: 4),
                                    _BalanceText(c.balance),
                                  ]),
                                ),
                                if (MediaQuery.of(context).size.width < 600)
                                  // Phones: one menu instead of four buttons so name and phone keep their width.
                                  PopupMenuButton<String>(
                                    tooltip: 'Actions',
                                    icon: const Icon(Icons.more_vert_rounded, color: AppColors.navy),
                                    onSelected: (v) async {
                                      switch (v) {
                                        case 'pay':
                                          open(pay: true);
                                        case 'history':
                                          open(tab: 1);
                                        case 'edit':
                                          if (await editCustomer(context, c)) setState(() => _v++);
                                        case 'delete':
                                          if (await confirm(context, 'Delete Customer', 'Delete ${c.name}? Their bills stay in history.', danger: true, ok: 'Delete') && context.mounted) {
                                            final r = await guard(context, () => Api.instance.delete('/customers/${c.id}'));
                                            if (r != null) setState(() => _v++);
                                          }
                                      }
                                    },
                                    itemBuilder: (_) => const [
                                      PopupMenuItem(value: 'pay', child: ListTile(leading: Icon(Icons.account_balance_wallet, color: AppColors.orange), title: Text('Receive Payment'))),
                                      PopupMenuItem(value: 'history', child: ListTile(leading: Icon(Icons.history, color: AppColors.blue), title: Text('Purchase History'))),
                                      PopupMenuItem(value: 'edit', child: ListTile(leading: Icon(Icons.edit), title: Text('Edit Customer'))),
                                      PopupMenuItem(value: 'delete', child: ListTile(leading: Icon(Icons.delete_outline, color: AppColors.danger), title: Text('Delete Customer'))),
                                    ],
                                  )
                                else ...[
                                  RowAction(Icons.account_balance_wallet, AppColors.orange, 'Receive Payment', () => open(pay: true)),
                                  RowAction(Icons.history, AppColors.blue, 'Purchase History', () => open(tab: 1)),
                                  RowAction(Icons.edit, AppColors.green, 'Edit Customer', () async {
                                    if (await editCustomer(context, c)) setState(() => _v++);
                                  }),
                                  RowAction(Icons.delete_outline, AppColors.danger, 'Delete Customer', () async {
                                    if (await confirm(context, 'Delete Customer', 'Delete ${c.name}? Their bills stay in history.', danger: true, ok: 'Delete') && context.mounted) {
                                      final r = await guard(context, () => Api.instance.delete('/customers/${c.id}'));
                                      if (r != null) setState(() => _v++);
                                    }
                                  }),
                                ],
                              ]),
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

class _BalanceText extends StatelessWidget {
  final double balance;
  const _BalanceText(this.balance);
  @override
  Widget build(BuildContext context) {
    final due = balance > 0.009;
    final color = due ? AppColors.danger : AppColors.green;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(color: color.withValues(alpha: .08), borderRadius: BorderRadius.circular(6), border: Border.all(color: color.withValues(alpha: .4))),
      child: Text(
        due ? 'Due: ${money(balance)}' : balance < -0.009 ? 'Advance: ${money(-balance)}' : 'Balance: ₹0.00',
        style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12, color: color),
      ),
    );
  }
}

/// Add / edit customer dialog. Returns true when saved.
Future<bool> editCustomer(BuildContext context, [Customer? c]) async => await customerForm(context, c: c) != null;

/// Add / edit customer form; [name] / [phone] prefill a new customer (e.g. from the POS search).
/// Returns the saved customer, or null if cancelled or failed.
Future<Customer?> customerForm(BuildContext context, {Customer? c, String? name, String? phone}) async {
  final r = await showFormDialog(context, title: c == null ? 'Add Customer' : 'Edit Customer', fields: [
    FieldSpec('name', 'Customer Name (optional)', initial: c?.savedName ?? name),
    FieldSpec('phone', 'Mobile Number', initial: c?.phone ?? phone, keyboard: TextInputType.phone, validator: (v) => v.isEmpty || RegExp(r'^\d{10}$').hasMatch(v) ? null : 'Must be 10 digits'),
    FieldSpec('address', 'Address', initial: c?.address),
    FieldSpec('gstin', 'GSTIN', initial: c?.gstin),
    FieldSpec('openingBalance', c == null ? 'Opening Balance (Initial)' : 'Opening Balance (At Creation)', initial: '${c?.openingBalance ?? 0}', keyboard: TextInputType.number),
  ]);
  if (r == null || !context.mounted) return null;
  final body = {
    'name': r['name'],
    'phone': r['phone']!.isEmpty ? null : r['phone'],
    'address': r['address'],
    'gstin': r['gstin'],
    'openingBalance': double.tryParse(r['openingBalance']!) ?? 0,
  };
  final saved = await guard(context, () => c == null ? Api.instance.post('/customers', body) : Api.instance.put('/customers/${c.id}', body),
      success: c == null ? 'Customer added!' : 'Customer updated!');
  return saved == null ? null : Customer(Map<String, dynamic>.from(saved));
}

class CustomerDetail extends StatefulWidget {
  final Customer customer;
  final bool openPayment;
  final int initialTab;
  const CustomerDetail({super.key, required this.customer, this.openPayment = false, this.initialTab = 0});
  @override
  State<CustomerDetail> createState() => _CustomerDetailState();
}

class _CustomerDetailState extends State<CustomerDetail> {
  late Customer c = widget.customer;
  DateTimeRange? _range;
  int _v = 0;

  @override
  void initState() {
    super.initState();
    if (widget.openPayment) WidgetsBinding.instance.addPostFrameCallback((_) => _receivePayment());
  }

  Future<void> _reloadCustomer() async {
    c = Customer(Map<String, dynamic>.from(await Api.instance.get('/customers/${c.id}')));
    setState(() => _v++);
  }

  Future<void> _receivePayment() async {
    String method = 'CASH';
    final amount = TextEditingController(text: c.balance > 0 ? c.balance.toStringAsFixed(2) : '');
    final note = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => StatefulBuilder(
        builder: (d, set) => AlertDialog(
          title: Text('Receive Payment - ${c.name}'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            Text('Current Closing Balance: ${money(c.balance)}'),
            const SizedBox(height: 12),
            TextField(controller: amount, autofocus: true, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Amount Received (₹)')),
            const SizedBox(height: 12),
            SegmentedButton<String>(
              segments: const [ButtonSegment(value: 'CASH', label: Text('Cash')), ButtonSegment(value: 'UPI', label: Text('UPI')), ButtonSegment(value: 'CARD', label: Text('Card'))],
              selected: {method},
              onSelectionChanged: (s) => set(() => method = s.first),
            ),
            const SizedBox(height: 12),
            TextField(controller: note, decoration: const InputDecoration(labelText: 'Note (optional)')),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('Receive')),
          ],
        ),
      ),
    );
    final v = double.tryParse(amount.text);
    if (ok != true || v == null || v <= 0 || !mounted) return;
    final r = await guard(context, () => Api.instance.post('/customers/${c.id}/payments', {'amount': v, 'method': method, 'note': note.text}),
        success: 'Payment of ${money(v)} recorded via $method');
    if (r == null || !mounted) return;
    final shop = context.read<Session>().shop!;
    final opening = toDouble(r['openingBalance']);
    await _reloadCustomer();
    if (mounted && await confirm(context, 'Payment Receipt', 'Print a payment receipt?', ok: 'Print')) {
      await PrintService.printPaymentReceipt(Map<String, dynamic>.from(r['payment']), c, opening, shop);
    }
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      initialIndex: widget.initialTab,
      child: Scaffold(
        appBar: GradientAppBar(
          title: Text(c.name),
          actions: [
            IconButton(
              tooltip: 'Edit Customer',
              onPressed: () async {
                if (await editCustomer(context, c)) _reloadCustomer();
              },
              icon: const Icon(Icons.edit),
            ),
            IconButton(
              tooltip: 'Delete Customer',
              onPressed: () async {
                if (await confirm(context, 'Delete Customer', 'Delete ${c.name}? Their bills stay in history.', danger: true, ok: 'Delete') && context.mounted) {
                  final r = await guard(context, () => Api.instance.delete('/customers/${c.id}'));
                  if (r != null && context.mounted) Navigator.pop(context);
                }
              },
              icon: const Icon(Icons.delete_outline),
            ),
          ],
          bottom: const TabBar(tabs: [Tab(text: 'Ledger'), Tab(text: 'Purchase History')]),
        ),
        floatingActionButton: FloatingActionButton.extended(onPressed: _receivePayment, icon: const Icon(Icons.payments), label: const Text('Receive Payment')),
        body: Column(children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Wrap(spacing: 8, runSpacing: 8, children: [
              SizedBox(width: 200, child: StatTile(label: 'Closing Balance (Live)', value: money(c.balance), icon: Icons.account_balance_wallet, color: c.balance > 0 ? StatusColors.due : StatusColors.ok)),
              SizedBox(width: 200, child: StatTile(label: 'Opening Balance', value: money(c.openingBalance), icon: Icons.flag_outlined)),
              SizedBox(width: 200, child: StatTile(label: 'Loyalty Points', value: c.loyaltyPoints.toStringAsFixed(0), icon: Icons.star_outline, color: Colors.amber.shade800)),
              if (c.phone != null) SizedBox(width: 200, child: StatTile(label: 'Mobile', value: c.phone!, icon: Icons.phone)),
            ]),
          ),
          Expanded(
            child: TabBarView(children: [
              Column(children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Row(children: [
                    Text(_range == null ? 'Since registration' : '${dateOnly(_range!.start)} – ${dateOnly(_range!.end)}'),
                    const Spacer(),
                    TextButton.icon(
                      onPressed: () async {
                        final r = await showDateRangePicker(context: context, firstDate: DateTime(2020), lastDate: DateTime.now());
                        setState(() => _range = r);
                      },
                      icon: const Icon(Icons.date_range),
                      label: const Text('Select Dates'),
                    ),
                  ]),
                ),
                Expanded(
                  child: Loader<Map<String, dynamic>>(
                    key: ValueKey('ledger$_v$_range'),
                    load: () async => Map<String, dynamic>.from(await Api.instance.get('/customers/${c.id}/ledger', {
                      if (_range != null) 'from': _range!.start.toIso8601String(),
                      if (_range != null) 'to': DateTime(_range!.end.year, _range!.end.month, _range!.end.day, 23, 59, 59).toIso8601String(),
                    })),
                    builder: (context, l, _) {
                      final entries = List<Map<String, dynamic>>.from(l['entries']);
                      return ListView(padding: const EdgeInsets.fromLTRB(12, 0, 12, 96), children: [
                        ListTile(dense: true, title: const Text('OPENING BALANCE', style: TextStyle(fontWeight: FontWeight.w800)), trailing: Text(money(toDouble(l['opening'])))),
                        for (final e in entries)
                          Card(
                            child: ListTile(
                              dense: true,
                              onTap: e['billId'] == null
                                  ? null
                                  : () async {
                                      final b = Bill(Map<String, dynamic>.from(await Api.instance.get('/bills/${e['billId']}')));
                                      if (context.mounted) showBillDetail(context, b, () async => _reloadCustomer());
                                    },
                              title: Text('${e['ref']} • ${dateTime(DateTime.parse(e['date']))}'),
                              subtitle: Text(e['description'] ?? '', maxLines: 2, overflow: TextOverflow.ellipsis),
                              trailing: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
                                if (toDouble(e['debit']) > 0) Text('Dr ${money(toDouble(e['debit']))}', style: const TextStyle(color: StatusColors.due)),
                                if (toDouble(e['credit']) > 0) Text('Cr ${money(toDouble(e['credit']))}', style: const TextStyle(color: StatusColors.ok)),
                                Text('Bal: ${money(toDouble(e['runningBalance']))}', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12)),
                              ]),
                            ),
                          ),
                        ListTile(
                          title: const Text('TOTAL / CLOSING', style: TextStyle(fontWeight: FontWeight.w800)),
                          subtitle: Text('Debit ${money(toDouble(l['totalDebit']))} • Credit ${money(toDouble(l['totalCredit']))}'),
                          trailing: Text(money(toDouble(l['closing'])), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                        ),
                      ]);
                    },
                  ),
                ),
              ]),
              Loader<List<Bill>>(
                key: ValueKey('bills$_v'),
                load: () async => (await Api.instance.get('/customers/${c.id}/bills') as List).map((e) => Bill(Map<String, dynamic>.from(e))).toList(),
                builder: (context, bills, reload) => bills.isEmpty
                    ? ListView(children: const [SizedBox(height: 40), EmptyState(icon: Icons.receipt_long, title: 'No purchases yet')])
                    : ListView(padding: const EdgeInsets.fromLTRB(12, 0, 12, 96), children: [
                        for (final b in bills)
                          Card(
                            child: ListTile(
                              onTap: () => showBillDetail(context, b, reload),
                              title: Text('#${b.billNo}'),
                              subtitle: Text('${dateTime(b.billDate)} • ${b.items.length} items${b.isCancelled ? ' • CANCELLED' : ''}'),
                              trailing: Text(money(b.total), style: const TextStyle(fontWeight: FontWeight.w800)),
                            ),
                          ),
                      ]),
              ),
            ]),
          ),
        ]),
      ),
    );
  }
}
