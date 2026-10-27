import 'package:flutter/material.dart';

import '../core/api.dart';
import '../core/format.dart';
import '../core/theme.dart';
import '../models/models.dart';
import 'screens/bills/bills_screen.dart';
import 'widgets/history_panel.dart';

/// What each page's History button shows (see [showHistory]).
String _iso(DateTime d) => d.toIso8601String();

String _label(String s) => s.replaceAll('_', ' ').toLowerCase().replaceFirstMapped(RegExp(r'^\w'), (m) => m[0]!.toUpperCase());

/// Inventory: stock movements (sales, inwards, adjustments, purchases, returns), optionally of one product.
Future<void> showStockHistory(BuildContext context, {String? productId, String? productName}) => showHistory(
      context,
      title: productName == null ? 'Stock history' : 'Stock history • $productName',
      exportHeaders: const ['Product', 'Movement', 'Qty', 'Balance', 'Note', 'User'],
      load: (from, to) async {
        final list = await Api.instance.get('/stock/history', {'from': _iso(from), 'to': _iso(to), 'productId': productId, 'limit': 1000}) as List;
        return [
          for (final m in list)
            () {
              final q = toDouble(m['quantity']);
              final type = _label(m['type'] as String);
              return HistoryEntry(
                at: DateTime.parse(m['createdAt']).toLocal(),
                icon: q >= 0 ? Icons.south_west_rounded : Icons.north_east_rounded,
                color: q >= 0 ? StatusColors.ok : StatusColors.due,
                title: productName == null ? '${m['productName']} • $type' : type,
                subtitle: [m['note'], m['userName']].whereType<String>().join(' • '),
                value: '${q >= 0 ? '+' : ''}${qty(q)}',
                valueColor: q >= 0 ? StatusColors.ok : StatusColors.due,
                detail: 'Bal ${qty(toDouble(m['balanceAfter']))}',
                exportRow: [m['productName'] ?? '', type, qty(q), qty(toDouble(m['balanceAfter'])), m['note'] ?? '', m['userName'] ?? ''],
              );
            }(),
        ];
      },
    );

/// Purchases: received purchase bills and supplier payments.
Future<void> showPurchaseHistory(BuildContext context) => showHistory(
      context,
      title: 'Purchase history',
      exportHeaders: const ['Type', 'Invoice / Supplier', 'Items', 'Amount', 'Due'],
      load: (from, to) async {
        final r = await Future.wait([
          Api.instance.get('/purchases', {'status': 'RECEIVED', 'from': _iso(from), 'to': _iso(to)}),
          Api.instance.get('/suppliers/payments', {'from': _iso(from), 'to': _iso(to)}),
        ]);
        final entries = <HistoryEntry>[
          for (final p in r[0] as List)
            () {
              final items = List<Map<String, dynamic>>.from(p['items']);
              final due = toDouble(p['balanceDue']);
              return HistoryEntry(
                at: DateTime.parse(p['invoiceDate']).toLocal(),
                icon: Icons.move_to_inbox_rounded,
                color: AppColors.blue,
                title: '${p['invoiceNumber']} • ${p['supplierName'] ?? 'Unknown supplier'}',
                subtitle: '${items.length} item(s)${p['location'] != null ? ' • ${p['location']}' : ''}',
                value: money(toDouble(p['totalAmount'])),
                detail: due > 0 ? 'Due ${money(due)}' : 'Paid',
                onTap: () => _purchaseItems(context, Map<String, dynamic>.from(p)),
                exportRow: ['Purchase', '${p['invoiceNumber']} • ${p['supplierName'] ?? ''}', '${items.length}', money(toDouble(p['totalAmount'])), money(due)],
              );
            }(),
          for (final s in r[1] as List)
            HistoryEntry(
              at: DateTime.parse(s['createdAt']).toLocal(),
              icon: Icons.payments_outlined,
              color: StatusColors.ok,
              title: 'Paid to ${s['supplier']?['name'] ?? 'supplier'}',
              subtitle: [_label(s['method'] as String), s['note']].whereType<String>().join(' • '),
              value: money(toDouble(s['amount'])),
              valueColor: StatusColors.ok,
              exportRow: ['Supplier payment', s['supplier']?['name'] ?? '', '', money(toDouble(s['amount'])), ''],
            ),
        ];
        return entries..sort((a, b) => b.at.compareTo(a.at));
      },
    );

Future<void> _purchaseItems(BuildContext context, Map<String, dynamic> p) => showDialog(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('${p['invoiceNumber']} • ${p['supplierName'] ?? ''}'),
        content: SizedBox(
          width: 420,
          child: ListView(shrinkWrap: true, children: [
            for (final it in List<Map<String, dynamic>>.from(p['items']))
              ListTile(
                dense: true,
                title: Text(it['productName']),
                subtitle: Text('${qty(toDouble(it['quantity']))} × ${money(toDouble(it['unitPrice']))}'
                    '${it['batchNumber'] != null ? ' • Batch: ${it['batchNumber']}' : ''}'
                    '${it['expiryDate'] != null ? ' • Exp: ${dateOnly(DateTime.parse(it['expiryDate']))}' : ''}'),
                trailing: Text(money(toDouble(it['total']))),
              ),
          ]),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(c), child: const Text('Close'))],
      ),
    );

/// New Bill (POS): bills of this outlet – today by default.
Future<void> showBillHistory(BuildContext context) => showHistory(
      context,
      title: 'Bills',
      preset: 'today',
      exportHeaders: const ['Bill', 'Items', 'Payment', 'Amount', 'Status'],
      load: (from, to) async {
        final open = _billOpener(context, null);
        final list = await Api.instance.get('/bills', {'status': 'completed', 'from': _iso(from), 'to': _iso(to), 'limit': 1000}) as List;
        return [for (final e in list) _billEntry(Bill(Map<String, dynamic>.from(e)), open)];
      },
    );

/// Tapping a bill opens its details (cancel / reprint …) on the page under the panel.
void Function(Bill) _billOpener(BuildContext context, Future<void> Function()? onChanged) => (b) {
      if (context.mounted) showBillDetail(context, b, onChanged ?? () async {});
    };

HistoryEntry _billEntry(Bill b, void Function(Bill) open) => HistoryEntry(
      at: b.billDate.toLocal(),
      icon: b.isCancelled ? Icons.block_rounded : (b.isExpense ? Icons.money_off_rounded : Icons.receipt_long_rounded),
      color: b.isCancelled ? StatusColors.due : AppColors.blue,
      title: '#${b.billNo}${b.customerName != null ? ' • ${b.customerName}' : ''}',
      subtitle: '${b.items.length} item(s) • ${b.paymentLabel}${b.isCancelled ? ' • CANCELLED' : ''}',
      value: money(b.total),
      valueColor: b.isCancelled ? AppColors.muted : null,
      onTap: () => open(b),
      exportRow: [b.billNo, '${b.items.length}', b.paymentLabel, money(b.total), b.isCancelled ? 'Cancelled' : 'Completed'],
    );

/// Settings: shop activity log (who changed settings, cancelled / restored bills …).
Future<void> showActivityHistory(BuildContext context) => showHistory(
      context,
      title: 'Activity log',
      exportHeaders: const ['Action', 'Details', 'User'],
      load: (from, to) async {
        final list = await Api.instance.get('/shop/activity', {'from': _iso(from), 'to': _iso(to), 'limit': 1000}) as List;
        return [
          for (final a in list)
            HistoryEntry(
              at: DateTime.parse(a['createdAt']).toLocal(),
              icon: _activityIcon(a['action'] as String),
              color: (a['action'] as String).contains('cancel') || (a['action'] as String).contains('delete') ? StatusColors.due : AppColors.navy,
              title: a['description'],
              subtitle: [_label(a['action'] as String), a['userName']].whereType<String>().join(' • '),
              exportRow: [_label(a['action'] as String), a['description'], a['userName'] ?? ''],
            ),
        ];
      },
    );

IconData _activityIcon(String action) => action.startsWith('bill_')
    ? Icons.receipt_long_rounded
    : action.startsWith('shop_')
        ? Icons.settings_rounded
        : action.startsWith('payment')
            ? Icons.payments_outlined
            : action.startsWith('customer')
                ? Icons.person_outline_rounded
                : action.startsWith('offline')
                    ? Icons.cloud_off_rounded
                    : Icons.history_rounded;
