import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/api.dart';
import '../../../core/format.dart';
import '../../../core/theme.dart';
import '../../../models/models.dart';
import '../../../services/print_service.dart';
import '../../../state/session.dart';
import '../../history_sources.dart';
import '../../widgets/app_shell.dart';
import '../../widgets/brand.dart';
import '../../widgets/common.dart';
import '../../widgets/form_dialog.dart';
import '../../widgets/history_panel.dart';
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

  /// All · Due (only with customer credit on) · Advance.
  Widget _chips(bool credit) {
    if (!credit && _filter == 'due') _filter = 'all';
    return Wrap(spacing: 6, children: [
      for (final (id, label) in [('all', 'All'), if (credit) ('due', 'Due'), ('advance', 'Advance'), ('archived', 'Archived')])
        ChoiceChip(label: Text(label), selected: _filter == id, onSelected: (_) => setState(() => _filter = id)),
    ]);
  }

  @override
  Widget build(BuildContext context) => AppScaffold(
        title: 'Customer Management',
        actions: [
          HistoryButton(tooltip: 'Customer history', onPressed: () => showCustomerActivityHistory(context)),
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
          Padding(padding: const EdgeInsets.symmetric(horizontal: 12), child: _chips(context.watch<Session>().shop?.has('credit') ?? false)),
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
                                        case 'archive':
                                          if (await archiveCustomer(context, c)) setState(() => _v++);
                                        case 'restore':
                                          if (await restoreCustomer(context, c)) setState(() => _v++);
                                      }
                                    },
                                    itemBuilder: (_) => [
                                      if (!c.isArchived) ...const [
                                        PopupMenuItem(value: 'pay', child: ListTile(leading: Icon(Icons.account_balance_wallet, color: AppColors.orange), title: Text('Receive Payment'))),
                                        PopupMenuItem(value: 'history', child: ListTile(leading: Icon(Icons.history, color: AppColors.blue), title: Text('Bill History'))),
                                        PopupMenuItem(value: 'edit', child: ListTile(leading: Icon(Icons.edit), title: Text('Edit Customer'))),
                                        PopupMenuItem(value: 'archive', child: ListTile(leading: Icon(Icons.archive_outlined, color: AppColors.danger), title: Text('Archive Customer'))),
                                      ] else ...const [
                                        PopupMenuItem(value: 'history', child: ListTile(leading: Icon(Icons.history, color: AppColors.blue), title: Text('Bill History'))),
                                        PopupMenuItem(value: 'restore', child: ListTile(leading: Icon(Icons.unarchive_outlined, color: AppColors.green), title: Text('Restore Customer'))),
                                      ],
                                    ],
                                  )
                                else if (c.isArchived) ...[
                                  RowAction(Icons.history, AppColors.blue, 'Bill History', () => open(tab: 1)),
                                  RowAction(Icons.unarchive_outlined, AppColors.green, 'Restore Customer', () async {
                                    if (await restoreCustomer(context, c)) setState(() => _v++);
                                  }),
                                ] else ...[
                                  RowAction(Icons.account_balance_wallet, AppColors.orange, 'Receive Payment', () => open(pay: true)),
                                  RowAction(Icons.history, AppColors.blue, 'Bill History', () => open(tab: 1)),
                                  RowAction(Icons.edit, AppColors.green, 'Edit Customer', () async {
                                    if (await editCustomer(context, c)) setState(() => _v++);
                                  }),
                                  RowAction(Icons.archive_outlined, AppColors.danger, 'Archive Customer', () async {
                                    if (await archiveCustomer(context, c)) setState(() => _v++);
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
    final color = due ? AppColors.danger : (balance < -0.009 ? AppColors.green : AppColors.muted);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(color: color.withValues(alpha: .08), borderRadius: BorderRadius.circular(6), border: Border.all(color: color.withValues(alpha: .4))),
      child: Text(
        balanceText(balance),
        style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12, color: color),
      ),
    );
  }
}

/// Archive instead of delete: only with a settled balance; bills, payments and history are kept.
/// Returns true when archived.
Future<bool> archiveCustomer(BuildContext context, Customer c) async {
  if (c.balance > 0.009) {
    showSnack(context, '${c.name} owes you ${money(c.balance)} – collect or settle it before archiving', error: true);
    return false;
  }
  if (c.advance > 0.009) {
    showSnack(context, '${c.name} has ${money(c.advance)} advance – refund it before archiving', error: true);
    return false;
  }
  if (!await confirm(context, 'Archive ${c.name}?',
          'They are hidden from the customer list and search. Their bills, payments and account history are kept, and reports do not change.\n\nRestore them any time from the Archived filter – adding or billing the same mobile number also brings them back.',
          ok: 'Archive') ||
      !context.mounted) {
    return false;
  }
  return await guard(context, () => Api.instance.post('/customers/${c.id}/archive'), success: '${c.name} archived') != null;
}

Future<bool> restoreCustomer(BuildContext context, Customer c) async =>
    await guard(context, () => Api.instance.post('/customers/${c.id}/restore'), success: '${c.name} restored') != null;

/// Add / edit customer dialog. Returns true when saved.
Future<bool> editCustomer(BuildContext context, [Customer? c]) async => await customerForm(context, c: c) != null;

/// Add / edit customer form; [name] / [phone] prefill a new customer (e.g. from the POS search).
/// Returns the saved customer, or null if cancelled or failed.
Future<Customer?> customerForm(BuildContext context, {Customer? c, String? name, String? phone}) async {
  final r = await showFormDialog(context, title: c == null ? 'Add Customer' : 'Edit Customer', fields: [
    FieldSpec('name', 'Customer Name', initial: c?.savedName ?? name),
    FieldSpec('phone', 'Mobile Number', initial: c?.phone ?? phone, keyboard: TextInputType.phone, validator: (v) => v.isEmpty || RegExp(r'^\d{10}$').hasMatch(v) ? null : 'Must be 10 digits'),
    FieldSpec('address', 'Address', initial: c?.address),
    FieldSpec('gstin', 'GSTIN', initial: c?.gstin),
    // Set only when creating; afterwards bills and payments change the balance.
    if (c == null) ...const [
      FieldSpec('openingBalance', 'Opening Balance', initial: '0', keyboard: TextInputType.number),
      FieldSpec('openingType', 'Opening balance is', options: [('due', 'Due'), ('advance', 'Advance')]),
    ],
  ]);
  if (r == null || !context.mounted) return null;
  final body = {
    'name': r['name'],
    'phone': r['phone']!.isEmpty ? null : r['phone'],
    'address': r['address'],
    'gstin': r['gstin'],
    if (c == null) 'openingBalance': (double.tryParse(r['openingBalance']!) ?? 0).abs() * (r['openingType'] == 'advance' ? -1 : 1),
  };
  final saved = await guard(context, () => c == null ? Api.instance.post('/customers', body) : Api.instance.put('/customers/${c.id}', body),
      success: c == null ? 'Customer added!' : 'Customer updated!');
  return saved == null ? null : Customer(Map<String, dynamic>.from(saved));
}

class CustomerDetail extends StatefulWidget {
  final Customer customer;
  final bool openPayment;
  /// 1 = open the customer's bill history on start.
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
    if (widget.openPayment && !c.isArchived) WidgetsBinding.instance.addPostFrameCallback((_) => _receivePayment());
    if (widget.initialTab == 1) WidgetsBinding.instance.addPostFrameCallback((_) => _bills());
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
          title: Text('${c.balance > 0 ? 'Receive Payment' : 'Receive Advance'} - ${c.name}'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(c.balance > 0
                ? 'Due: ${money(c.balance)} – anything above it is kept as advance'
                : c.advance > 0
                    ? 'Advance on account: ${money(c.advance)} – this adds to it'
                    : 'Nothing due – this is kept as advance for future bills'),
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
        success: v > c.balance ? '${money(v)} received via $method – ${money(v - (c.balance > 0 ? c.balance : 0))} kept as advance' : 'Payment of ${money(v)} recorded via $method');
    if (r == null || !mounted) return;
    final shop = context.read<Session>().shop!;
    final opening = toDouble(r['openingBalance']);
    await _reloadCustomer();
    if (mounted && await confirm(context, 'Payment Receipt', 'Print a payment receipt?', ok: 'Print')) {
      await PrintService.printPaymentReceipt(Map<String, dynamic>.from(r['payment']), c, opening, shop);
    }
  }

  /// Give (part of) the advance back to the customer.
  Future<void> _refundAdvance() async {
    String method = 'CASH';
    final amount = TextEditingController(text: c.advance.toStringAsFixed(2));
    final note = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => StatefulBuilder(
        builder: (d, set) => AlertDialog(
          title: Text('Refund Advance - ${c.name}'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            Text('Advance on account: ${money(c.advance)}'),
            const SizedBox(height: 12),
            TextField(controller: amount, autofocus: true, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Amount to refund (₹)')),
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
            FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('Refund')),
          ],
        ),
      ),
    );
    final v = double.tryParse(amount.text);
    if (ok != true || v == null || v <= 0 || !mounted) return;
    if (v > c.advance + 0.009) return showSnack(context, 'Only ${money(c.advance)} advance is available', error: true);
    final r = await guard(context, () => Api.instance.post('/customers/${c.id}/refunds', {'amount': v, 'method': method, 'note': note.text}),
        success: 'Advance of ${money(v)} refunded via $method');
    if (r == null || !mounted) return;
    final shop = context.read<Session>().shop!;
    final opening = toDouble(r['openingBalance']);
    await _reloadCustomer();
    if (mounted && await confirm(context, 'Refund Receipt', 'Print a refund receipt?', ok: 'Print')) {
      await PrintService.printPaymentReceipt(Map<String, dynamic>.from(r['payment']), c, opening, shop);
    }
  }

  Future<void> _bills() => showCustomerBillHistory(context, c, onChanged: _reloadCustomer);

  Future<void> _archive() async {
    if (await archiveCustomer(context, c) && mounted) Navigator.pop(context);
  }

  Future<void> _restore() async {
    if (await restoreCustomer(context, c)) _reloadCustomer();
  }

  /// Summary card: the balance in words (who owes whom), contact line and the payment actions.
  Widget _summary() {
    final due = c.balance > 0.009, advance = c.advance > 0.009;
    final color = due ? StatusColors.due : (advance ? StatusColors.advance : AppColors.navy);
    final (headline, explain) = due
        ? ('${c.name} owes you ${money(c.balance)}', 'Collect it with Receive Payment.')
        : advance
            ? ('${c.name} has ${money(c.advance)} advance with you', 'You hold this money for the customer – it is used on their next bill, or refund it.')
            : ('All settled', 'Nothing is due and there is no advance.');
    return Card(
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (c.isArchived)
            Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.fromLTRB(12, 6, 6, 6),
              decoration: BoxDecoration(color: AppColors.amber.withValues(alpha: .2), borderRadius: BorderRadius.circular(10)),
              child: Row(children: [
                const Icon(Icons.archive_outlined, size: 18, color: AppColors.navy),
                const SizedBox(width: 8),
                const Expanded(child: Text('Archived – hidden from the customer list and search', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13))),
                TextButton(onPressed: _restore, child: const Text('Restore')),
              ]),
            ),
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            IconTile(due ? Icons.call_received_rounded : (advance ? Icons.savings_outlined : Icons.check_circle_outline), color, size: 44),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(headline, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: color)),
                const SizedBox(height: 2),
                Text(explain, style: const TextStyle(color: AppColors.muted, fontSize: 13)),
              ]),
            ),
          ]),
          const SizedBox(height: 12),
          Wrap(spacing: 14, runSpacing: 6, children: [
            if (c.phone != null) _info(Icons.phone_outlined, c.phone!),
            if (c.loyaltyPoints > 0) _info(Icons.star_outline_rounded, '${c.loyaltyPoints.toStringAsFixed(0)} points'),
            _info(Icons.flag_outlined, 'Opening: ${balanceText(c.openingBalance)}'),
          ]),
          // Archived customers can't receive payments – restore them first.
          if (!c.isArchived) ...[
            const SizedBox(height: 14),
            Wrap(spacing: 8, runSpacing: 8, children: [
              FilledButton.icon(onPressed: _receivePayment, icon: const Icon(Icons.payments_outlined), label: Text(due ? 'Receive Payment' : 'Receive Advance')),
              if (advance) OutlinedButton.icon(onPressed: _refundAdvance, icon: const Icon(Icons.currency_exchange_rounded), label: const Text('Refund Advance')),
            ]),
          ],
        ]),
      ),
    );
  }

  Widget _info(IconData icon, String text) => Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 16, color: AppColors.muted),
        const SizedBox(width: 4),
        Text(text, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
      ]);

  /// Balance tag after an entry: "₹250 due" (red), "₹50 advance" (green) or "Settled".
  Widget _balanceTag(double v) {
    final color = v > 0.009 ? StatusColors.due : (v < -0.009 ? StatusColors.advance : StatusColors.muted);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(color: color.withValues(alpha: .1), borderRadius: BorderRadius.circular(6)),
      child: Text(balanceText(v), style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: color)),
    );
  }

  /// One statement row: date, what happened, the amounts in words and the balance afterwards.
  Widget _entry(Map<String, dynamic> e) {
    final date = DateTime.parse(e['date']).toLocal();
    final debit = toDouble(e['debit']), credit = toDouble(e['credit']);
    final type = e['type'] as String;
    final (icon, color, title) = switch (type) {
      'bill' => (Icons.receipt_long_rounded, AppColors.blue, 'Bill'),
      'refund' => (Icons.currency_exchange_rounded, StatusColors.due, 'Advance refunded'),
      'return' => (Icons.assignment_return_outlined, StatusColors.ok, 'Return'),
      _ => (Icons.payments_outlined, StatusColors.ok, 'Payment'),
    };
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: e['billId'] == null
            ? null
            : () async {
                final b = Bill(Map<String, dynamic>.from(await Api.instance.get('/bills/${e['billId']}')));
                if (mounted) showBillDetail(context, b, () async => _reloadCustomer());
              },
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            IconTile(icon, color, size: 36),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
                Text('${dateTime(date)}\n${e['ref']}', style: const TextStyle(fontSize: 12, color: AppColors.muted)),
                if ((e['description'] ?? '').toString().isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(e['description'], maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12)),
                  ),
              ]),
            ),
            const SizedBox(width: 8),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              if (debit > 0) Text(type == 'refund' ? 'Refunded ${money(debit)}' : 'Billed ${money(debit)}', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
              if (credit > 0) Text('Paid ${money(credit)}', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: StatusColors.ok)),
              const SizedBox(height: 4),
              _balanceTag(toDouble(e['runningBalance'])),
            ]),
          ]),
        ),
      ),
    );
  }

  /// Summary card on top; the account statement (with its own date filter) below; bills via the History button.
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: GradientAppBar(
        title: Text(c.name),
        actions: [
          HistoryButton(tooltip: 'Bills of this customer', onPressed: _bills),
          PopupMenuButton<String>(
            tooltip: 'More',
            onSelected: (v) async {
              if (v == 'edit' && await editCustomer(context, c)) _reloadCustomer();
              if (v == 'archive') _archive();
              if (v == 'restore') _restore();
            },
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'edit', child: ListTile(leading: Icon(Icons.edit_outlined), title: Text('Edit Customer'))),
              if (c.isArchived)
                const PopupMenuItem(value: 'restore', child: ListTile(leading: Icon(Icons.unarchive_outlined, color: AppColors.green), title: Text('Restore Customer')))
              else
                const PopupMenuItem(value: 'archive', child: ListTile(leading: Icon(Icons.archive_outlined, color: AppColors.danger), title: Text('Archive Customer'))),
            ],
          ),
        ],
      ),
      body: Loader<Map<String, dynamic>>(
        key: ValueKey('ledger$_v$_range'),
        load: () async => Map<String, dynamic>.from(await Api.instance.get('/customers/${c.id}/ledger', {
          if (_range != null) 'from': _range!.start.toIso8601String(),
          if (_range != null) 'to': DateTime(_range!.end.year, _range!.end.month, _range!.end.day, 23, 59, 59).toIso8601String(),
        })),
        builder: (context, l, _) {
          final entries = List<Map<String, dynamic>>.from(l['entries']);
          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 820),
              child: ListView(padding: const EdgeInsets.only(bottom: 24), children: [
                _summary(),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 8, 4),
                  child: Row(children: [
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        const Text('Account statement', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                        Text(_range == null ? 'Since registration' : '${dateOnly(_range!.start)} – ${dateOnly(_range!.end)}',
                            style: const TextStyle(fontSize: 12, color: AppColors.muted)),
                      ]),
                    ),
                    if (_range != null) IconButton(tooltip: 'All dates', onPressed: () => setState(() => _range = null), icon: const Icon(Icons.close_rounded)),
                    TextButton.icon(
                      onPressed: () async {
                        final r = await showDateRangePicker(context: context, firstDate: DateTime(2020), lastDate: DateTime.now(), initialDateRange: _range);
                        if (r != null) setState(() => _range = r);
                      },
                      icon: const Icon(Icons.date_range),
                      label: const Text('Dates'),
                    ),
                  ]),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Column(children: [
                    _statementLine(_range == null ? 'Opening balance' : 'Balance on ${dateOnly(_range!.start)}', toDouble(l['opening'])),
                    const SizedBox(height: 8),
                    if (entries.isEmpty)
                      const Padding(padding: EdgeInsets.all(24), child: Text('No bills or payments in this period', style: TextStyle(color: AppColors.muted)))
                    else
                      for (final e in entries) _entry(e),
                    _statementLine('Balance now', toDouble(l['closing']),
                        sub: 'Billed ${money(toDouble(l['totalDebit']))} • Paid ${money(toDouble(l['totalCredit']))} in this period', strong: true),
                  ]),
                ),
              ]),
            ),
          );
        },
      ),
    );
  }

  Widget _statementLine(String label, double balance, {String? sub, bool strong = false}) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
        child: Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(label, style: TextStyle(fontWeight: strong ? FontWeight.w800 : FontWeight.w700, fontSize: strong ? 15 : 13)),
              if (sub != null) Text(sub, style: const TextStyle(fontSize: 12, color: AppColors.muted)),
            ]),
          ),
          _balanceTag(balance),
        ]),
      );
}
