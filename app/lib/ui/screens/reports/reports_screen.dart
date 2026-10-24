import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/api.dart';
import '../../../core/format.dart';
import '../../../core/theme.dart';
import '../../../services/print_service.dart';
import '../../../state/session.dart';
import '../../widgets/app_shell.dart';
import '../../widgets/common.dart';
import 'report_filters.dart';

typedef ReportTable = ({List<List<String>> summary, List<String> headers, List<List<String>> rows});

/// A report tab: endpoint + how to turn its payload into a table.
class _ReportDef {
  final String title;
  final String longTitle;
  final IconData icon;
  final String endpoint;
  final bool dated;
  final ReportTable Function(dynamic) table;
  const _ReportDef(this.title, this.longTitle, this.icon, this.endpoint, this.table, {this.dated = true});
}

String _m(dynamic v) => money(toDouble(v)).replaceAll('.00', '');
String _q(dynamic v) => qty(toDouble(v));

final _reports = <_ReportDef>[
  _ReportDef('Sales Matrix', 'Sales Matrix Report', Icons.grid_on, '/reports/sales-matrix', (d) {
    final products = List<String>.from(d['products']);
    final customers = List<Map<String, dynamic>>.from(d['customers']);
    final items = {for (final i in d['items']) i['name'] as String: i};
    return (
      summary: [
        ['Active Customers', '${d['activeCustomers']}'],
        ['Unique Products', '${products.length}'],
        ['Total Items Sold', _q(d['totalQty'])],
        ['Total Sales', _m(d['totalAmount'])],
      ],
      headers: ['Customer', ...products, 'Total'],
      rows: [
        for (final c in customers)
          [
            c['customer'] as String,
            for (final p in products) c['cells'][p] == null ? '-' : '${_q(c['cells'][p]['qty'])} / ${_m(c['cells'][p]['amount'])}',
            '${_q(c['qty'])} / ${_m(c['amount'])}',
          ],
        if (customers.isNotEmpty) ['TOTAL', for (final p in products) '${_q(items[p]['qty'])} / ${_m(items[p]['amount'])}', '${_q(d['totalQty'])} / ${_m(d['totalAmount'])}'],
      ],
    );
  }),
  _ReportDef('Customer Sales', 'Customer Sales & Ledger Report', Icons.person, '/reports/customer-sales', (d) => (
        summary: [['Customers', '${(d as List).length}'], ['Total', _m(d.fold<double>(0, (s, r) => s + toDouble(r['amount'])))]],
        headers: ['Customer', 'Mobile', 'Bills', 'Amount', 'Received'],
        rows: [for (final r in d) [r['name'], r['phone'] ?? '-', '${r['bills']}', _m(r['amount']), _m(r['received'])]],
      )),
  _ReportDef('Outstanding', 'Customer Outstanding Balance Report', Icons.account_balance_wallet, '/reports/outstanding', dated: false, (d) => (
        summary: [['Total Outstanding Due', _m(d['totalDue'])], ['Total Advance', _m(d['totalAdvance'])], ['Customers', '${(d['customers'] as List).length}']],
        headers: ['Customer Name', 'Mobile', 'Opening Bal', 'Total Billed', 'Total Paid', 'Outstanding', 'Status'],
        rows: [
          for (final c in d['customers'])
            [c['name'], c['phone'] ?? '-', _m(c['openingBalance']), _m(c['totalBilled']), _m(c['totalReceived']), _m(c['outstandingBalance']), c['status']],
        ],
      )),
  _ReportDef('User Sales', 'User Wise Sales Report', Icons.badge, '/reports/user-sales', (d) => (
        summary: [['GRAND TOTAL', _m(d['grandTotal'])]],
        headers: ['User Name', 'Total Bills', 'Total Sales Amount', 'Top items'],
        rows: [
          for (final u in d['users'])
            [u['userName'], '${u['billCount']}', _m(u['total']), (u['items'] as List).take(3).map((i) => '${i['name']} ×${_q(i['qty'])}').join(', ')],
        ],
      )),
  _ReportDef('Inventory', 'Inventory & Storage Location Report', Icons.inventory_2, '/reports/inventory', dated: false, (d) => (
        summary: [
          ['Total Inventory Value', _m(d['totalValue'])],
          for (final l in d['locations']) ['📍 ${l['location']}', '${_q(l['qty'])} units • ${_m(l['value'])}'],
        ],
        headers: ['Product Name', 'Category', 'Location', 'Stock', 'Unit Price', 'Value', 'Status'],
        rows: [
          for (final i in d['items'])
            [i['name'], i['category'], i['location'], _q(i['stock']), _m(i['unitPrice']), _m(i['value']), i['isLowStock'] == true ? 'LOW STOCK' : 'OK'],
        ],
      )),
  _ReportDef('Stock History', 'Stock History Report', Icons.history, '/stock/history', (d) => (
        summary: [['Movements', '${(d as List).length}']],
        headers: ['Date & Time', 'Product', 'Type', 'Qty', 'Balance', 'Note', 'User'],
        rows: [
          for (final m in d)
            [dateTime(DateTime.parse(m['createdAt'])), m['productName'], (m['type'] as String).replaceAll('_', ' '), _q(m['quantity']), _q(m['balanceAfter']), m['note'] ?? '', m['userName'] ?? ''],
        ],
      )),
  _ReportDef('GST & Taxes', 'GST HSN Summary & Tax Rate Analysis (GSTR-1)', Icons.account_balance, '/reports/gst', (d) => (
        summary: [
          ['Total Taxable Value', _m(d['totals']['taxable'])],
          ['Total CGST', _m(d['totals']['cgst'])],
          ['Total SGST', _m(d['totals']['sgst'])],
          ['Total IGST', _m(d['totals']['igst'])],
          ['Net Output GST Liability', _m(d['totals']['totalTax'])],
        ],
        headers: ['HSN Code', 'Rate %', 'Qty', 'Taxable Val', 'CGST', 'SGST', 'IGST', 'Total Tax'],
        rows: [
          for (final h in d['hsn']) [h['hsnCode'], '${h['rate']}%', _q(h['qty']), _m(h['taxable']), _m(h['cgst']), _m(h['sgst']), _m(h['igst']), _m(h['totalTax'])],
          for (final s in d['slabs'])
            ['Slab ${s['rate']}%', '', '', _m(s['taxable']), _m(s['cgst']), _m(s['sgst']), _m(s['igst']), _m(toDouble(s['cgst']) + toDouble(s['sgst']) + toDouble(s['igst']))],
        ],
      )),
  _ReportDef('Purchase Reports', 'Purchase & Inward Stock Detailed Report', Icons.local_shipping, '/reports/purchases', (d) => (
        summary: [
          ['Total Purchase Bills', '${d['totals']['bills']}'],
          ['Total Amount', _m(d['totals']['amount'])],
          ['Total Amount Paid', _m(d['totals']['paid'])],
          ['Outstanding Balance Due', _m(d['totals']['due'])],
        ],
        headers: ['Inv #', 'Date', 'Supplier', 'Status', 'Total (₹)', 'Paid (₹)', 'Balance'],
        rows: [
          for (final p in d['purchases'])
            [p['invoiceNumber'], dateOnly(DateTime.parse(p['invoiceDate'])), p['supplierName'] ?? 'Unknown Supplier', p['status'], _m(p['totalAmount']), _m(p['amountPaid']), _m(p['balanceDue'])],
        ],
      )),
  _ReportDef('Branch-Wise', 'Branch-Wise Sales Summary', Icons.storefront, '/reports/branch-sales', (d) => (
        summary: [['Total', _m((d as List).fold<double>(0, (s, r) => s + toDouble(r['total'])))]],
        headers: ['Branch', 'Bills', 'Total'],
        rows: [for (final r in d) [r['branchName'], '${r['bills']}', _m(r['total'])]],
      )),
];

class ReportsScreen extends StatelessWidget {
  const ReportsScreen({super.key});

  @override
  Widget build(BuildContext context) => const AppScaffold(title: 'Reports & Analytics', body: ReportsView());
}

/// Filters | report tabs | quick actions. Also embedded in the POS "Reports ⇄" mode.
class ReportsView extends StatefulWidget {
  final bool embedded;
  const ReportsView({super.key, this.embedded = false});
  @override
  State<ReportsView> createState() => _ReportsViewState();
}

class _ReportsViewState extends State<ReportsView> {
  final _filter = ReportFilter();
  int _tab = 0;
  int _v = 0;
  ReportTable? _current;
  List<Map<String, dynamic>> _users = [];
  List<Map<String, dynamic>> _customers = [];

  _ReportDef get _def => _reports[_tab];

  @override
  void initState() {
    super.initState();
    final s = context.read<Session>();
    if (s.can('users.manage')) {
      Api.instance.get('/users').then((r) => mounted ? setState(() => _users = List<Map<String, dynamic>>.from(r['users'])) : null).catchError((_) => null);
    }
    Api.instance.get('/customers').then((r) => mounted ? setState(() => _customers = List<Map<String, dynamic>>.from(r)) : null).catchError((_) => null);
  }

  void _changed() => setState(() => _v++);

  Map<String, dynamic> get _query {
    final q = Map<String, dynamic>.from(_filter.query);
    if (_def.endpoint == '/stock/history') {
      final r = _filter.range;
      return {'from': r.start.toIso8601String(), 'to': DateTime(r.end.year, r.end.month, r.end.day, 23, 59, 59).toIso8601String(), 'limit': 2000};
    }
    return q;
  }

  String get _subtitle => _def.dated ? 'Period: ${_filter.periodLabel}' : 'As of ${dateTime(DateTime.now())}';

  Future<void> _pdf() async {
    final t = _current;
    if (t == null || t.rows.isEmpty) return showSnack(context, 'ℹ️ No data to export PDF.');
    await PrintService.exportTablePdf(title: _def.longTitle, subtitle: _subtitle, headers: t.headers, rows: t.rows, summary: t.summary);
  }

  Future<void> _whatsapp() async {
    final t = _current;
    if (t == null || t.rows.isEmpty) return showSnack(context, 'No sales data to share on WhatsApp');
    final shop = context.read<Session>().shop?.name ?? '';
    final buf = StringBuffer('*$shop – ${_def.longTitle}*\n$_subtitle\n\n');
    for (final s in t.summary) {
      buf.writeln('• ${s[0]}: ${s[1]}');
    }
    buf.writeln('\n_Sent via OnePe POS_');
    await launchUrl(Uri.parse('https://wa.me/?text=${Uri.encodeComponent(buf.toString())}'), mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final branch = context.watch<Session>().activeBranchId;
    return LayoutBuilder(builder: (context, box) {
      final wide = box.maxWidth >= 1000;
      final report = _reportPanel(branch);
      if (wide) {
        return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(width: 270, child: SingleChildScrollView(padding: const EdgeInsets.fromLTRB(12, 12, 6, 12), child: _filtersCard())),
          Expanded(child: report),
          SizedBox(width: 300, child: SingleChildScrollView(padding: const EdgeInsets.fromLTRB(6, 12, 12, 12), child: _actionsCard())),
        ]);
      }
      return Column(children: [
        ExpansionTile(
          title: const Text('Filters & Controls', style: TextStyle(fontWeight: FontWeight.w600)),
          subtitle: Text(_filter.label),
          leading: const Icon(Icons.filter_alt, color: AppColors.blue),
          children: [Padding(padding: const EdgeInsets.fromLTRB(12, 0, 12, 12), child: _filtersCard(flat: true))],
        ),
        Expanded(child: report),
      ]);
    });
  }

  Widget _card({required Widget child}) => Container(
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.border)),
        padding: const EdgeInsets.all(16),
        child: child,
      );

  Widget _filtersCard({bool flat = false}) {
    final body = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (!flat) ...[
        const Row(children: [
          Icon(Icons.filter_alt, color: AppColors.blue),
          SizedBox(width: 8),
          Text('Filters & Controls', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16, color: AppColors.navy)),
        ]),
        const Divider(height: 22),
      ],
      const Text('📅 Quick Date Presets', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
      const SizedBox(height: 8),
      Wrap(spacing: 6, runSpacing: 6, children: [
        for (final p in const [('today', 'Today'), ('yesterday', 'Yesterday'), ('last7', 'Last 7 Days'), ('month', 'This Month'), ('last_month', 'Last Month')])
          ChoiceChip(
            label: Text(p.$2, style: const TextStyle(fontSize: 12)),
            selected: _filter.preset == p.$1,
            showCheckmark: false,
            visualDensity: VisualDensity.compact,
            onSelected: (_) {
              _filter.preset = p.$1;
              _changed();
            },
          ),
      ]),
      const SizedBox(height: 10),
      OutlinedButton.icon(
        style: OutlinedButton.styleFrom(minimumSize: const Size(0, 40), shape: const StadiumBorder()),
        onPressed: () async {
          final r = await showDateRangePicker(context: context, firstDate: DateTime(2020), lastDate: DateTime.now(), initialDateRange: _filter.range);
          if (r == null) return;
          _filter
            ..preset = 'custom'
            ..custom = r;
          _changed();
        },
        icon: const Icon(Icons.calendar_month, size: 16),
        label: Text(_filter.label, style: const TextStyle(fontSize: 12)),
      ),
      if (context.read<Session>().branches.length > 1)
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          dense: true,
          title: const Text('🏪 All Branches'),
          value: _filter.allBranches,
          onChanged: (v) {
            _filter.allBranches = v;
            _changed();
          },
        ),
      const Divider(height: 24),
      if (_users.isNotEmpty) ...[
        const Text('👤 Line Person / Staff Filter', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
        const SizedBox(height: 8),
        DropdownButtonFormField<String?>(
          initialValue: _filter.userId,
          isExpanded: true,
          items: [const DropdownMenuItem(value: null, child: Text('All Line Persons')), for (final u in _users) DropdownMenuItem(value: u['id'] as String, child: Text(u['name']))],
          onChanged: (v) {
            _filter.userId = v;
            _changed();
          },
        ),
        const SizedBox(height: 14),
      ],
      const Text('🏢 Customer Filter', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
      const SizedBox(height: 8),
      DropdownButtonFormField<String?>(
        initialValue: _filter.customerId,
        isExpanded: true,
        items: [const DropdownMenuItem(value: null, child: Text('All Customers')), for (final c in _customers) DropdownMenuItem(value: c['id'] as String, child: Text(c['name']))],
        onChanged: (v) {
          _filter.customerId = v;
          _changed();
        },
      ),
      const SizedBox(height: 12),
      TextButton.icon(
        style: TextButton.styleFrom(foregroundColor: AppColors.danger),
        onPressed: () {
          _filter.reset();
          _changed();
        },
        icon: const Icon(Icons.filter_list_off, size: 18),
        label: const Text('Reset All Filters'),
      ),
    ]);
    return flat ? body : _card(child: body);
  }

  Widget _actionsCard() => _card(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            const Expanded(child: Text('⚡ Quick Actions & Export', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: AppColors.navy))),
            IconButton(tooltip: 'Refresh Report Data', onPressed: _changed, icon: const Icon(Icons.refresh, color: AppColors.blue)),
          ]),
          const Divider(height: 20),
          const Text('📥 Download & Export Hub', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
          const SizedBox(height: 10),
          _actionBtn('Download PDF (.pdf)', Icons.picture_as_pdf, AppColors.danger, _pdf),
          const SizedBox(height: 8),
          _actionBtn('Share Report (WhatsApp)', Icons.send, AppColors.green, _whatsapp),
          const Divider(height: 26),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: AppColors.blueTint, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.blueTintBorder)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Row(children: [
                Icon(Icons.analytics, size: 18, color: AppColors.blue),
                SizedBox(width: 6),
                Text('Report Analytics', style: TextStyle(fontWeight: FontWeight.w600, color: AppColors.navy)),
              ]),
              const SizedBox(height: 6),
              Text('Report: ${_def.longTitle}', style: const TextStyle(fontSize: 12)),
              const Text('Status: Active & Up-to-date', style: TextStyle(fontSize: 11, color: AppColors.green)),
            ]),
          ),
        ]),
      );

  Widget _actionBtn(String label, IconData icon, Color color, VoidCallback onTap) => FilledButton.icon(
        style: FilledButton.styleFrom(backgroundColor: color, minimumSize: const Size(0, 42), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
        onPressed: onTap,
        icon: Icon(icon, size: 18),
        label: Text(label, style: const TextStyle(fontSize: 13)),
      );

  Widget _reportPanel(String? branch) => Column(children: [
        Container(
          margin: const EdgeInsets.fromLTRB(6, 12, 6, 0),
          decoration: const BoxDecoration(color: Colors.white, border: Border(bottom: BorderSide(color: AppColors.border))),
          height: 68,
          child: ListView(scrollDirection: Axis.horizontal, children: [
            for (final (i, r) in _reports.indexed)
              InkWell(
                onTap: () => setState(() {
                  _tab = i;
                  _current = null;
                }),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  decoration: BoxDecoration(border: Border(bottom: BorderSide(color: i == _tab ? AppColors.blue : Colors.transparent, width: 3))),
                  child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Icon(r.icon, color: i == _tab ? AppColors.blue : AppColors.muted),
                    const SizedBox(height: 2),
                    Text(r.title, style: TextStyle(color: i == _tab ? AppColors.blue : AppColors.muted, fontWeight: FontWeight.w600, fontSize: 13)),
                  ]),
                ),
              ),
          ]),
        ),
        Expanded(
          child: Loader<dynamic>(
            key: ValueKey('${_def.endpoint}${_filter.key}$branch$_v'),
            load: () => Api.instance.get(_def.endpoint, _query),
            builder: (context, data, _) {
              final t = _def.table(data);
              _current = t;
              return ListView(padding: const EdgeInsets.fromLTRB(6, 12, 6, 24), children: [
                _card(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    Text(_subtitle, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
                    const SizedBox(height: 10),
                    FilledButton.icon(
                      style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
                      onPressed: _pdf,
                      icon: const Icon(Icons.download),
                      label: const Text('Download PDF (.pdf)'),
                    ),
                  ]),
                ),
                const SizedBox(height: 12),
                if (t.rows.isEmpty)
                  Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(color: AppColors.blueTint, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.blueTintBorder)),
                    child: Column(children: [
                      const Icon(Icons.calendar_month, size: 48, color: AppColors.blue),
                      const SizedBox(height: 8),
                      Text('No ${_def.title} Records Found', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 18, color: AppColors.navy)),
                      const SizedBox(height: 6),
                      Text(
                        _def.dated
                            ? 'No sales or stock transactions were recorded between ${dateOnly(_filter.range.start)} and ${dateOnly(_filter.range.end)}.\n\nPick another date range in Filters & Controls.'
                            : 'Nothing to show yet.',
                        textAlign: TextAlign.center,
                      ),
                    ]),
                  )
                else ...[
                  Container(
                    decoration: BoxDecoration(color: Colors.white, border: Border.all(color: const Color(0xFF9AA0AA))),
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: DataTable(
                        border: TableBorder.all(color: const Color(0xFFBDC1C6)),
                        headingTextStyle: const TextStyle(fontWeight: FontWeight.w600, color: AppColors.text, fontSize: 14),
                        columns: [for (final h in t.headers) DataColumn(label: Text(h))],
                        rows: [
                          for (final r in t.rows)
                            DataRow(
                              color: WidgetStatePropertyAll(r.first == 'TOTAL' || r.first.startsWith('Slab') ? const Color(0xFFEDEDED) : null),
                              cells: [
                                for (final c in r)
                                  DataCell(Text(c,
                                      style: TextStyle(
                                        color: c == 'DUE' || c == 'LOW STOCK' ? AppColors.danger : (c == 'ADVANCE' || c == 'SETTLED' ? AppColors.green : null),
                                        fontWeight: r.first == 'TOTAL' || c == 'DUE' ? FontWeight.w600 : null,
                                      ))),
                              ],
                            ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(color: AppColors.blueTint, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.blueTintBorder)),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('📊 ${_def.title} Summary Total', style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.blue, fontSize: 16)),
                      const SizedBox(height: 10),
                      Wrap(spacing: 8, runSpacing: 8, children: [
                        for (final s in t.summary)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10), border: Border.all(color: AppColors.border)),
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text(s[0], style: const TextStyle(fontSize: 12, color: AppColors.muted)),
                              Text(s[1], style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.blue)),
                            ]),
                          ),
                      ]),
                    ]),
                  ),
                ],
              ]);
            },
          ),
        ),
      ]);
}
