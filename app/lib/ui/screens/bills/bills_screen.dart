import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../core/api.dart';
import '../../../core/format.dart';
import '../../../core/theme.dart';
import '../../../models/models.dart';
import '../../../services/print_service.dart';
import '../../../state/cart.dart';
import '../../../state/session.dart';
import '../../widgets/app_shell.dart';
import '../../widgets/brand.dart';
import '../../widgets/common.dart';

class BillsScreen extends StatefulWidget {
  const BillsScreen({super.key});
  @override
  State<BillsScreen> createState() => _BillsScreenState();
}

class _BillsScreenState extends State<BillsScreen> with SingleTickerProviderStateMixin {
  late final _tabs = TabController(length: 2, vsync: this, initialIndex: 0);
  String _q = '';
  bool _deleted = false;
  DateTimeRange? _range;
  int _version = 0;

  Future<List<Bill>> _load(String status) async {
    final res = await Api.instance.get('/bills', {
      'status': _deleted ? null : status,
      'deleted': _deleted ? 'true' : null,
      'q': _q,
      if (_range != null) 'from': _range!.start.toIso8601String(),
      if (_range != null) 'to': DateTime(_range!.end.year, _range!.end.month, _range!.end.day, 23, 59, 59).toIso8601String(),
    });
    return (res as List).map((e) => Bill(Map<String, dynamic>.from(e))).toList();
  }

  void _reload() => setState(() => _version++);

  Future<void> _export() async {
    final status = _tabs.index == 0 ? 'waiting' : 'completed';
    final bills = await guard(context, () => _load(status));
    if (bills == null || bills.isEmpty) {
      if (mounted) showSnack(context, 'No $status bills to export');
      return;
    }
    await PrintService.exportTablePdf(
      title: status == 'waiting' ? 'Waiting List Bills Report' : 'Completed Bills Report',
      subtitle: _range == null ? 'All dates' : '${dateOnly(_range!.start)} – ${dateOnly(_range!.end)}',
      headers: ['Bill #', 'Date', 'Table', 'Customer', 'Billed By', 'Items', 'Subtotal', 'GST', 'Total', 'Status'],
      rows: [
        for (final b in bills)
          [b.billNo, dateTime(b.billDate), b.tableName ?? '-', b.customerName ?? 'Walk-in', b.userName ?? '-', b.items.length, b.subtotal.toStringAsFixed(2), b.totalGst.toStringAsFixed(2), b.total.toStringAsFixed(2),
            b.isDeleted ? 'Deleted by ${b.deletedBy}' : b.isCancelled ? 'Cancelled by ${b.cancelledBy}' : 'Active'],
      ],
      summary: [
        ['Total Bills', '${bills.length}'],
        ['Grand Total', money(bills.where((b) => !b.isCancelled).fold<double>(0, (s, b) => s + b.total))],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final canDelete = context.read<Session>().can('bills.delete');
    return Scaffold(
      drawer: const AppDrawer(),
      appBar: GradientAppBar(
        title: Text(_deleted ? 'Deleted Bills' : 'Bills History'),
        leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => context.go('/pos')),
        actions: [
          IconButton(tooltip: 'Export', onPressed: _export, icon: const Icon(Icons.download_rounded)),
          if (canDelete)
            IconButton(
              tooltip: _deleted ? 'Show Active Bills' : 'Show Deleted Bills',
              onPressed: () => setState(() => _deleted = !_deleted),
              icon: Icon(_deleted ? Icons.restore_from_trash : Icons.delete_outline),
            ),
          IconButton(
            tooltip: _range == null ? 'Filter by Date' : 'Clear Date Filter',
            onPressed: () async {
              if (_range != null) return setState(() => _range = null);
              final r = await showDateRangePicker(context: context, firstDate: DateTime(2020), lastDate: DateTime.now());
              if (r != null) setState(() => _range = r);
            },
            icon: Icon(_range == null ? Icons.calendar_today : Icons.event_busy),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(110),
          child: Column(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: TextField(
                style: const TextStyle(color: Colors.white),
                cursorColor: Colors.white,
                onChanged: (v) {
                  _q = v;
                  _reload();
                },
                decoration: InputDecoration(
                  hintText: 'Search bill ID, name or phone...',
                  hintStyle: const TextStyle(color: Colors.white70),
                  prefixIcon: const Icon(Icons.search, color: Colors.white),
                  fillColor: Colors.white.withValues(alpha: .18),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                  isDense: true,
                ),
              ),
            ),
            TabBar(controller: _tabs, tabs: const [
              Tab(icon: Icon(Icons.pending_actions, size: 18), iconMargin: EdgeInsets.zero, height: 46, text: 'Waiting'),
              Tab(icon: Icon(Icons.check_circle, size: 18), iconMargin: EdgeInsets.zero, height: 46, text: 'Completed'),
            ]),
          ]),
        ),
      ),
      body: Column(children: [
        if (_range != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: InputChip(label: Text('Date Selected: ${dateOnly(_range!.start)} – ${dateOnly(_range!.end)}'), onDeleted: () => setState(() => _range = null)),
          ),
        Expanded(
          child: TabBarView(controller: _tabs, children: [
            for (final status in ['waiting', 'completed'])
              Loader<List<Bill>>(
                key: ValueKey('$status$_version$_deleted$_range'),
                load: () => _load(status),
                builder: (context, bills, reload) => bills.isEmpty
                    ? ListView(children: [
                        const SizedBox(height: 90),
                        Center(
                          child: Container(
                            width: 110,
                            height: 110,
                            decoration: BoxDecoration(color: Colors.white, shape: BoxShape.circle, boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: .06), blurRadius: 12)]),
                            child: Icon(status == 'waiting' ? Icons.pending_actions : Icons.receipt_long, size: 52, color: AppColors.blueTintBorder),
                          ),
                        ),
                        const SizedBox(height: 18),
                        Text(status == 'waiting' ? 'No waiting list bills' : 'No completed bills', textAlign: TextAlign.center, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
                        Text(status == 'waiting' ? 'Active orders will appear here' : 'Processed sales records will appear here', textAlign: TextAlign.center, style: const TextStyle(color: AppColors.muted)),
                      ])
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
                        itemCount: bills.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 12),
                        itemBuilder: (_, i) => _BillCard(bill: bills[i], onChanged: reload),
                      ),
              ),
          ]),
        ),
      ]),
    );
  }
}

/// Short serial shown on cards ("002" from "GS-MAIN-20261013-002").
String shortBillNo(String billNo) => billNo.split('-').last;

class _StatusPill extends StatelessWidget {
  final Bill b;
  const _StatusPill(this.b);
  @override
  Widget build(BuildContext context) {
    final (label, color, icon) = b.isDeleted
        ? ('DELETED', AppColors.danger, Icons.delete)
        : b.isCancelled
            ? ('CANCELLED', AppColors.danger, Icons.block)
            : b.isWaiting
                ? ('WAITING', StatusColors.waiting, Icons.schedule)
                : b.isExpense
                    ? ('EXPENSE', AppColors.orange, Icons.money_off)
                    : ('COMPLETED', AppColors.green, Icons.check_circle);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: color.withValues(alpha: .1), borderRadius: BorderRadius.circular(20)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 4),
        Text(label, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: .4)),
      ]),
    );
  }
}

class _BillCard extends StatelessWidget {
  final Bill bill;
  final Future<void> Function() onChanged;
  const _BillCard({required this.bill, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final b = bill;
    final session = context.read<Session>();
    Widget meta(IconData i, String t, {Color? color}) => Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(i, size: 14, color: color ?? AppColors.muted),
            const SizedBox(width: 6),
            Text(t, style: TextStyle(fontSize: 13, color: color ?? AppColors.muted)),
          ]),
        );
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => showBillDetail(context, b, onChanged),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(b.customerName ?? (b.tableName != null ? b.tableName! : 'Walk-in Customer'), style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
                  const SizedBox(height: 2),
                  Row(children: [
                    const Icon(Icons.tag, size: 13, color: AppColors.muted),
                    Text(' ${shortBillNo(b.billNo)}   ', style: const TextStyle(fontSize: 12, color: AppColors.muted)),
                    const Icon(Icons.schedule, size: 13, color: AppColors.muted),
                    Text(' ${DateFormat('hh:mm a').format(b.billDate.toLocal())}', style: const TextStyle(fontSize: 12, color: AppColors.muted)),
                    if (b.tableName != null && b.customerName != null) Text('   •  ${b.tableName}', style: const TextStyle(fontSize: 12, color: AppColors.muted)),
                    Text('   •  ${dateOnly(b.billDate)}', style: const TextStyle(fontSize: 12, color: AppColors.muted)),
                  ]),
                ]),
              ),
              _StatusPill(b),
            ]),
            const Divider(height: 22),
            Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  meta(Icons.person_outline, b.customerContact ?? 'Guest'),
                  Row(children: [
                    meta(Icons.shopping_bag_outlined, '${b.items.length} Items'),
                    const SizedBox(width: 14),
                    meta(Icons.payments_outlined, b.paymentLabel),
                  ]),
                  if (b.userName != null) meta(Icons.badge_outlined, 'Billed by: ${b.userName}', color: AppColors.blue),
                  if (b.isDeleted && b.deletedBy != null) meta(Icons.delete_outline, 'Deleted by: ${b.deletedBy}', color: AppColors.danger),
                  if (b.isCancelled && b.cancelledBy != null) meta(Icons.block, 'Cancelled by: ${b.cancelledBy}${b.cancelReason != null ? ' – ${b.cancelReason}' : ''}', color: AppColors.danger),
                ]),
              ),
              Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Text(money(b.total).replaceAll('.00', ''),
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: AppColors.blue, decoration: b.isCancelled ? TextDecoration.lineThrough : null)),
                const SizedBox(height: 8),
                Row(mainAxisSize: MainAxisSize.min, children: [
                  // Waiting orders (not billed yet): continue or delete.
                  if (b.isWaiting && !b.isDeleted && session.can('bills.create')) RowAction(Icons.edit, AppColors.blue, 'Continue Order', () => _continueOrder(context, b)),
                  if (b.isWaiting && !b.isDeleted && session.can('bills.delete')) RowAction(Icons.delete_outline, AppColors.danger, 'Delete Order', () => _delete(context, b, onChanged)),
                  // Completed bills are issued invoices: cancel only (restore is for the shop admin).
                  if (!b.isWaiting && !b.isDeleted && !b.isCancelled && session.can('bills.cancel')) RowAction(Icons.block, AppColors.orange, 'Cancel Bill', () => _cancel(context, b, onChanged)),
                  if (b.isCancelled && !b.isDeleted && (session.user?.isAdmin ?? false)) RowAction(Icons.restore, AppColors.green, 'Restore', () => _restore(context, b, onChanged)),
                  if (b.isDeleted && session.can('bills.delete')) RowAction(Icons.restore, AppColors.green, 'Restore', () => _restore(context, b, onChanged)),
                  if (b.isDeleted && b.isWaiting && session.can('bills.delete')) RowAction(Icons.delete_forever, AppColors.danger, 'Delete Forever', () => _purge(context, b, onChanged)),
                ]),
              ]),
            ]),
          ]),
        ),
      ),
    );
  }
}

Future<void> _act(BuildContext context, Future<dynamic> Function() f, String ok, Future<void> Function() onChanged) async {
  final r = await guard(context, f, success: ok);
  if (r != null) await onChanged();
}

Future<void> _continueOrder(BuildContext context, Bill b, {bool asNew = false}) async {
  Customer? cu;
  if (b.customerId != null) cu = Customer(Map<String, dynamic>.from(await Api.instance.get('/customers/${b.customerId}')));
  if (!context.mounted) return;
  context.read<Cart>().loadBill(b, customerObj: cu, asNew: asNew);
  context.go('/pos');
  showSnack(context, asNew ? 'Items of #${b.billNo} loaded into a new bill' : 'Loaded waiting bill for ${b.tableName ?? b.billNo}');
}

/// Cancel a completed bill: a reason is required; optionally load its items into a new bill (re-bill).
Future<void> _cancel(BuildContext context, Bill b, Future<void> Function() onChanged) async {
  final reason = TextEditingController();
  var rebill = false;
  final ok = await showDialog<bool>(
    context: context,
    builder: (c) => StatefulBuilder(
      builder: (c, setState) => AlertDialog(
        title: const Text('Cancel Bill'),
        content: SizedBox(
          width: 420,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Bill #${b.billNo} (${money(b.total)}) will be marked cancelled. Its number is kept; stock and balances are reverted.'),
            const SizedBox(height: 14),
            TextField(
              controller: reason,
              autofocus: true,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(labelText: 'Reason *', hintText: 'e.g. Wrong item, customer returned'),
              onChanged: (_) => setState(() {}),
            ),
            if (context.read<Session>().can('bills.create'))
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                value: rebill,
                onChanged: (v) => setState(() => rebill = v ?? false),
                title: const Text('Load items into a new bill'),
                subtitle: const Text('To correct and re-bill'),
              ),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Keep Bill')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Theme.of(c).colorScheme.error),
            onPressed: reason.text.trim().isEmpty ? null : () => Navigator.pop(c, true),
            child: const Text('Cancel Bill'),
          ),
        ],
      ),
    ),
  );
  if (ok != true || !context.mounted) return;
  final r = await guard(context, () => Api.instance.post('/bills/${b.id}/cancel', {'reason': reason.text.trim()}), success: 'Bill cancelled');
  if (r == null || !context.mounted) return;
  await onChanged();
  if (rebill && context.mounted) await _continueOrder(context, b, asNew: true);
}

Future<void> _delete(BuildContext context, Bill b, Future<void> Function() onChanged) async {
  if (await confirm(context, 'Delete Order', 'Delete waiting order ${b.tableName ?? '#${b.billNo}'}? It has not been billed yet.', ok: 'Delete', danger: true) && context.mounted) {
    await _act(context, () => Api.instance.delete('/bills/${b.id}'), 'Order deleted', onChanged);
  }
}

Future<void> _restore(BuildContext context, Bill b, Future<void> Function() onChanged) async {
  if (await confirm(context, 'Restore Bill', b.isCancelled
          ? 'Restore cancelled Bill #${b.billNo}? Stock and balances will be applied again.'
          : 'Restore order #${b.billNo} to the waiting list?') && context.mounted) {
    await _act(context, () => Api.instance.post('/bills/${b.id}/restore'), 'Bill restored', onChanged);
  }
}

Future<void> _purge(BuildContext context, Bill b, Future<void> Function() onChanged) async {
  if (await confirm(context, 'Permanently Delete', 'Permanently delete waiting order #${b.billNo}? This cannot be undone.', ok: 'Delete Forever', danger: true) &&
      context.mounted) {
    await _act(context, () => Api.instance.delete('/bills/${b.id}/permanent'), 'Bill permanently deleted', onChanged);
  }
}

/// "Bill Details" dialog with Preview / Continue (waiting) or Cancel (completed) / Print.
Future<void> showBillDetail(BuildContext context, Bill b, Future<void> Function() onChanged) async {
  final session = context.read<Session>();
  Widget kv(String k, String v) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(k, style: const TextStyle(fontSize: 12, color: AppColors.muted)),
        Text(v, style: const TextStyle(fontWeight: FontWeight.w600)),
      ]);
  Widget sum(String k, String v, {bool big = false}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(children: [
          Expanded(child: Text(k, style: TextStyle(color: big ? AppColors.text : AppColors.muted, fontWeight: big ? FontWeight.w700 : null, fontSize: big ? 18 : 14))),
          Text(v, style: TextStyle(fontWeight: FontWeight.w700, fontSize: big ? 22 : 14, color: big ? AppColors.blue : null)),
        ]),
      );
  // Equal-size footer buttons: icon above the label so all three fit on a 2" terminal screen.
  Widget action(IconData icon, String label, VoidCallback onPressed, {bool filled = true}) {
    final child = Column(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, size: 20),
      const SizedBox(height: 2),
      Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
    ]);
    final style = ButtonStyle(
      minimumSize: const WidgetStatePropertyAll(Size(0, 58)),
      padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 6, vertical: 8)),
      shape: WidgetStatePropertyAll(RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
    );
    return Expanded(
      child: filled
          ? FilledButton(style: style, onPressed: onPressed, child: child)
          : OutlinedButton(style: style, onPressed: onPressed, child: child),
    );
  }

  await showDialog(
    context: context,
    builder: (c) => Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 500, maxHeight: 680),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 8, 0),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('Bill Details', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
                  Text('#${b.billNo}', style: const TextStyle(fontSize: 12, color: AppColors.muted)),
                  const SizedBox(height: 10),
                  _StatusPill(b),
                ]),
              ),
              IconButton(onPressed: () => Navigator.pop(c), icon: const Icon(Icons.close)),
            ]),
          ),
          Flexible(
            child: ListView(shrinkWrap: true, padding: const EdgeInsets.fromLTRB(20, 16, 20, 8), children: [
              Row(children: [
                Expanded(child: kv('Date', dateOnly(b.billDate))),
                Expanded(child: kv('Time', DateFormat('hh:mm a').format(b.billDate.toLocal()))),
                kv('Table', b.tableName ?? 'N/A'),
              ]),
              const SizedBox(height: 12),
              kv('Customer', b.customerName == null ? 'Guest' : '${b.customerName}${b.customerContact != null ? ' (${b.customerContact})' : ''}'),
              const SizedBox(height: 18),
              const Text('Order Summary', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
              const SizedBox(height: 6),
              for (final i in b.items)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(children: [
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(i.productName, style: const TextStyle(fontWeight: FontWeight.w500)),
                        Text('${qty(i.quantity)} x ${money(i.soldPrice).replaceAll('.00', '')}${i.discount > 0 ? '  (Discount: -${money(i.discount)})' : ''}',
                            style: const TextStyle(fontSize: 12, color: AppColors.muted)),
                      ]),
                    ),
                    Text(money(i.lineTotal).replaceAll('.00', ''), style: const TextStyle(fontWeight: FontWeight.w600)),
                  ]),
                ),
              const Divider(height: 24),
              sum('Subtotal', money(b.subtotal).replaceAll('.00', '')),
              if (b.totalGst > 0) sum('GST', money(b.totalGst).replaceAll('.00', '')),
              if (b.discount > 0) sum('Discount', '-${money(b.discount)}'),
              if (b.loyaltyRedeemed > 0) sum('Points Discount', '-${money(b.loyaltyRedeemed)}'),
              if (b.roundOff != 0) sum('Round Off', '${b.roundOff > 0 ? '+' : '-'}${money(b.roundOff.abs())}'),
              sum('Grand Total', money(b.total).replaceAll('.00', ''), big: true),
              sum('Payment', '${b.paymentLabel} • ${money(b.received - b.change)}'),
              for (final (label, amt) in b.splitParts) sum('   $label', money(amt)),
              if (b.change > 0) sum('Change returned', money(b.change)),
              if (b.customerClosing != null) sum('Customer Balance', '${money(b.customerOpening)} → ${money(b.customerClosing)}'),
              if (b.userName != null) sum('Billed by', b.userName!),
              if (b.isCancelled) sum('Cancelled by', b.cancelledBy ?? '-'),
              if (b.isCancelled && b.cancelReason != null) sum('Reason', b.cancelReason!),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
            child: Row(children: [
              action(Icons.preview, 'Preview', () => showReceiptPreview(c, b, session), filled: false),
              if (b.isWaiting && !b.isDeleted && session.can('bills.create')) ...[
                const SizedBox(width: 10),
                action(Icons.edit, 'Continue', () {
                  Navigator.pop(c);
                  _continueOrder(context, b);
                }, filled: false),
              ],
              if (!b.isWaiting && !b.isDeleted && !b.isCancelled && session.can('bills.cancel')) ...[
                const SizedBox(width: 10),
                action(Icons.block, 'Cancel', () {
                  Navigator.pop(c);
                  _cancel(context, b, onChanged);
                }, filled: false),
              ],
              const SizedBox(width: 10),
              action(Icons.print, 'Print', () => guard(c, () => PrintService.printBill(b, session.shop!, branch: session.activeBranch))),
            ]),
          ),
          if (b.customerContact != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: TextButton.icon(onPressed: () => PrintService.shareBillWhatsApp(b, session.shop!), icon: const Icon(Icons.chat, color: AppColors.green), label: const Text('Share on WhatsApp')),
            ),
        ]),
      ),
    ),
  );
}

/// On-screen thermal receipt ("Print Preview").
Future<void> showReceiptPreview(BuildContext context, Bill b, Session session) {
  final shop = session.shop!;
  const mono = TextStyle(fontSize: 12, color: Colors.black87);
  Widget line(String l, String r, {bool bold = false, double size = 13}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 1),
        child: Row(children: [
          Expanded(child: Text(l, style: TextStyle(fontWeight: bold ? FontWeight.w700 : null, fontSize: size))),
          Text(r, style: TextStyle(fontWeight: bold ? FontWeight.w700 : null, fontSize: size)),
        ]),
      );
  return showDialog(
    context: context,
    builder: (c) => Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 400, maxHeight: 680),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 18, 12, 6),
            child: Row(children: [
              const Expanded(child: Text('Print Preview', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600))),
              IconButton(onPressed: () => Navigator.pop(c), icon: const Icon(Icons.close)),
            ]),
          ),
          const Divider(height: 1),
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(12),
              child: Container(
                color: Colors.white,
                padding: const EdgeInsets.all(16),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Text(shop.name, textAlign: TextAlign.center, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
                  if (shop.address != null) Text(shop.address!, textAlign: TextAlign.center, style: mono),
                  if (shop.contactNumber != null) Text('Tel: ${shop.contactNumber}', textAlign: TextAlign.center, style: mono),
                  if (shop.gstNumber != null) Text('GSTIN: ${shop.gstNumber}', textAlign: TextAlign.center, style: mono),
                  const SizedBox(height: 12),
                  Text(b.isCancelled ? 'TAX INVOICE – CANCELLED' : 'TAX INVOICE', textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15, color: b.isCancelled ? AppColors.danger : null)),
                  const Divider(),
                  line('Bill No:', b.billNo),
                  line('Date:', DateFormat('dd-MM-yyyy HH:mm').format(b.billDate.toLocal())),
                  if (b.customerName != null) line('Customer: ${b.customerName}', b.customerContact ?? ''),
                  const Divider(),
                  Row(children: const [
                    Expanded(child: Text('Item', style: TextStyle(fontWeight: FontWeight.w600))),
                    SizedBox(width: 34, child: Text('Qty', textAlign: TextAlign.right, style: TextStyle(fontWeight: FontWeight.w600))),
                    SizedBox(width: 50, child: Text('Price', textAlign: TextAlign.right, style: TextStyle(fontWeight: FontWeight.w600))),
                    SizedBox(width: 56, child: Text('Total', textAlign: TextAlign.right, style: TextStyle(fontWeight: FontWeight.w600))),
                  ]),
                  const Divider(),
                  for (final i in b.items)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 3),
                      child: Row(children: [
                        Expanded(child: Text(i.productName, style: mono)),
                        SizedBox(width: 34, child: Text(qty(i.quantity), textAlign: TextAlign.right, style: mono)),
                        SizedBox(width: 50, child: Text(i.soldPrice.toStringAsFixed(0), textAlign: TextAlign.right, style: mono)),
                        SizedBox(width: 56, child: Text(i.lineTotal.toStringAsFixed(0), textAlign: TextAlign.right, style: mono)),
                      ]),
                    ),
                  const Divider(),
                  line('Subtotal:', money(b.subtotal)),
                  if (b.totalGst > 0) line('Total GST:', money(b.totalGst)),
                  if (b.discount > 0) line('Bill Discount:', '-${money(b.discount)}'),
                  if (b.roundOff != 0) line('Round Off:', '${b.roundOff > 0 ? '+' : '-'}${money(b.roundOff.abs())}'),
                  const Divider(),
                  line('GRAND TOTAL:', money(b.total), bold: true, size: 16),
                  const Divider(),
                  line('Payment:', b.paymentLabel),
                  for (final (label, amt) in b.splitParts) line('  $label:', money(amt)),
                  if (b.received > 0) line('Received:', money(b.received)),
                  if (b.change > 0) line('Change:', money(b.change)),
                  const Divider(),
                  if (b.userName != null) Text('Billed by: ${b.userName}', textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
                  Text(shop.thanksNote ?? 'Thank you for visiting!', textAlign: TextAlign.center, style: const TextStyle(fontStyle: FontStyle.italic, fontSize: 12)),
                ]),
              ),
            ),
          ),
        ]),
      ),
    ),
  );
}
