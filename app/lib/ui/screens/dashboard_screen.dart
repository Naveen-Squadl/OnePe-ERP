import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api.dart';
import '../../core/config.dart';
import '../../core/format.dart';
import '../../core/theme.dart';
import '../../state/session.dart';
import '../widgets/app_shell.dart';
import '../widgets/common.dart';
import 'reports/report_filters.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});
  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final _filter = ReportFilter();
  int _v = 0;

  @override
  Widget build(BuildContext context) {
    final branch = context.watch<Session>().activeBranchId;
    return AppScaffold(
      title: 'Dashboard',
      actions: [
        Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10)),
            child: const Text('v${AppConfig.version}', style: TextStyle(color: AppColors.blue, fontSize: 11, fontWeight: FontWeight.w700)),
          ),
        ),
        IconButton(tooltip: 'Refresh', onPressed: () => setState(() => _v++), icon: const Icon(Icons.refresh)),
      ],
      body: Loader<Map<String, dynamic>>(
        key: ValueKey('${_filter.key}$branch$_v'),
        load: () async => Map<String, dynamic>.from(await Api.instance.get('/reports/summary', _filter.query)),
        builder: (context, d, _) => ListView(padding: const EdgeInsets.all(16), children: [
          Align(
            alignment: Alignment.centerLeft,
            child: _Panel(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Period', style: TextStyle(fontWeight: FontWeight.w500)),
                const SizedBox(height: 8),
                ReportFilterBar(filter: _filter, onChanged: () => setState(() {}), showBranch: context.read<Session>().branches.length > 1),
              ]),
            ),
          ),
          const SizedBox(height: 16),
          BusinessSummaryView(data: d),
        ]),
      ),
    );
  }
}

class _Panel extends StatelessWidget {
  final Widget child;
  const _Panel({required this.child});
  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: .04), blurRadius: 10)]),
        child: child,
      );
}

class _SectionTitle extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  const _SectionTitle(this.icon, this.color, this.title, {this.subtitle, this.trailing});

  @override
  Widget build(BuildContext context) => Column(children: [
        Row(children: [
          Icon(icon, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
              if (subtitle != null) Text(subtitle!, style: const TextStyle(fontSize: 12, color: AppColors.muted)),
            ]),
          ),
          ?trailing,
        ]),
        const Divider(height: 22),
      ]);
}

/// Sales summary metrics + trend + payment split + top sellers. Reused by Reports.
class BusinessSummaryView extends StatelessWidget {
  final Map<String, dynamic> data;
  const BusinessSummaryView({super.key, required this.data});

  @override
  Widget build(BuildContext context) {
    final d = data;
    final trend = List<Map<String, dynamic>>.from(d['trend']);
    final methods = Map<String, dynamic>.from(d['byPaymentMethod']);
    final top = List<Map<String, dynamic>>.from(d['topItems']);
    final tx = (d['transactions'] as num).toInt();
    final net = toDouble(d['netSales']);
    final bucket = d['range']['bucket'] as String;
    final total = trend.fold<double>(0, (s, t) => s + toDouble(t['revenue']));
    String m(dynamic v) => money(toDouble(v)).replaceAll('.00', '');

    final metrics = [
      (Icons.storefront, AppColors.blue, m(d['grossSales']), 'Gross Sales'),
      (Icons.local_offer, AppColors.orange, m(d['discounts']), 'Discounts'),
      (Icons.point_of_sale, AppColors.navy, m(d['netSales']), 'Net Sales'),
      (Icons.money_off, AppColors.danger, m(d['expenses']), 'Expenses'),
      (Icons.account_balance_wallet, AppColors.green, m(d['netCollection']), 'Net Collection'),
      (Icons.receipt_long, AppColors.green, '$tx', 'Transactions'),
      (Icons.trending_up, AppColors.navy, m(tx == 0 ? 0 : net / tx), 'Avg. Value'),
    ];

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _Panel(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const _SectionTitle(Icons.attach_money, AppColors.green, 'Sales Summary'),
          Wrap(spacing: 28, runSpacing: 16, children: [
            for (final x in metrics)
              Column(mainAxisSize: MainAxisSize.min, children: [
                Icon(x.$1, color: x.$2, size: 30),
                const SizedBox(height: 4),
                Text(x.$3, style: TextStyle(color: x.$2, fontWeight: FontWeight.w700, fontSize: 18)),
                Text(x.$4, style: const TextStyle(color: AppColors.muted, fontSize: 12)),
              ]),
          ]),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            decoration: BoxDecoration(color: AppColors.blueTint, borderRadius: BorderRadius.circular(8), border: Border.all(color: AppColors.blueTintBorder)),
            child: Row(children: [
              const Icon(Icons.calculate_outlined, size: 18, color: AppColors.blue),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Gross (${m(d['grossSales'])}) - Discount (${m(d['discounts'])}) = Net Sales (${m(d['netSales'])}) | Net Sales - Expenses (${m(d['expenses'])}) = Net Collection (${m(d['netCollection'])})',
                  style: const TextStyle(fontSize: 12, color: AppColors.navy, fontWeight: FontWeight.w500),
                ),
              ),
            ]),
          ),
        ]),
      ),
      const SizedBox(height: 16),
      _Panel(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          _SectionTitle(
            Icons.bar_chart,
            AppColors.navy,
            'Sales Trends & Velocity',
            subtitle: bucket == 'hour' ? 'Hourly lapse breakdown (1-Hour intervals)' : 'Aggregated by $bucket',
            trailing: Chip(
              avatar: const Icon(Icons.schedule, size: 16),
              label: Text(bucket == 'hour' ? '1-Hr Slots' : '${bucket[0].toUpperCase()}${bucket.substring(1)}'),
              backgroundColor: AppColors.blueTint,
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(color: AppColors.bg, borderRadius: BorderRadius.circular(8), border: Border.all(color: AppColors.border)),
            child: Row(children: [
              const Icon(Icons.circle, size: 10, color: AppColors.blue),
              const SizedBox(width: 6),
              Text('Total: ${m(total)}', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
              if (d['peak'] != null) Text('   •   Peak: ${d['peak']['label']} (${m(d['peak']['revenue'])})', style: const TextStyle(fontSize: 12, color: AppColors.muted)),
            ]),
          ),
          const SizedBox(height: 16),
          SizedBox(height: 240, child: _TrendChart(trend: trend, bucket: bucket)),
          const Align(
            alignment: Alignment.centerRight,
            child: Text('* Excludes expense vouchers. Sales values reflect customer orders.', style: TextStyle(fontSize: 11, fontStyle: FontStyle.italic, color: AppColors.muted)),
          ),
        ]),
      ),
      const SizedBox(height: 16),
      _Panel(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const _SectionTitle(Icons.credit_card, AppColors.blue, 'Payment Methods'),
          if (methods.isEmpty)
            const Padding(padding: EdgeInsets.all(24), child: Center(child: Text('No transactions in this period')))
          else
            for (final e in methods.entries)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(children: [
                  SizedBox(width: 80, child: Text(e.key, style: const TextStyle(fontWeight: FontWeight.w500))),
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: LinearProgressIndicator(
                        value: net == 0 ? 0 : (toDouble(e.value) / net).clamp(0, 1).toDouble(),
                        minHeight: 10,
                        backgroundColor: AppColors.bg,
                        color: AppColors.blue,
                      ),
                    ),
                  ),
                  SizedBox(width: 100, child: Text(m(e.value), textAlign: TextAlign.right, style: const TextStyle(fontWeight: FontWeight.w600))),
                ]),
              ),
          if (toDouble(d['paymentsReceived']) > 0)
            Text('+ Customer payments received: ${m(d['paymentsReceived'])}', style: const TextStyle(fontSize: 12, color: AppColors.muted)),
        ]),
      ),
      const SizedBox(height: 16),
      _Panel(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const _SectionTitle(Icons.emoji_events, AppColors.amberText, 'Top Selling Products'),
          if (top.isEmpty)
            const Padding(padding: EdgeInsets.all(24), child: Center(child: Text('No products sold in this period')))
          else
            for (final (i, t) in top.indexed)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: CircleAvatar(radius: 14, backgroundColor: AppColors.forIndex(i).withValues(alpha: .15), child: Text('${i + 1}', style: TextStyle(color: AppColors.forIndex(i), fontWeight: FontWeight.w700))),
                title: Text(t['name'], style: const TextStyle(fontWeight: FontWeight.w500)),
                subtitle: Text('${qty(toDouble(t['qty']))} sold'),
                trailing: Text(m(t['amount']), style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.price)),
              ),
        ]),
      ),
    ]);
  }
}

class _TrendChart extends StatelessWidget {
  final List<Map<String, dynamic>> trend;
  final String bucket;
  const _TrendChart({required this.trend, required this.bucket});

  @override
  Widget build(BuildContext context) {
    // For hourly view always show 6 AM – 10 PM slots, like the original.
    final points = <(String, double)>[];
    if (bucket == 'hour') {
      final byHour = {for (final t in trend) int.parse((t['label'] as String).split(':').first): toDouble(t['revenue'])};
      for (var h = 6; h <= 22; h++) {
        points.add((h == 12 ? '12 PM' : h > 12 ? '${h - 12} PM' : '$h AM', byHour[h] ?? 0));
      }
    } else {
      for (final t in trend) {
        final l = t['label'] as String;
        points.add((l.length > 5 ? l.substring(l.length - 5) : l, toDouble(t['revenue'])));
      }
    }
    if (points.isEmpty) return const Center(child: Text('No sales in this period'));
    final maxY = points.map((p) => p.$2).fold<double>(0, (a, b) => a > b ? a : b);
    return BarChart(BarChartData(
      maxY: maxY == 0 ? 100 : maxY * 1.2,
      gridData: FlGridData(drawVerticalLine: false, getDrawingHorizontalLine: (_) => const FlLine(color: Color(0xFFE5E7EB), dashArray: [4, 4], strokeWidth: 1)),
      borderData: FlBorderData(show: false),
      titlesData: FlTitlesData(
        topTitles: const AxisTitles(),
        rightTitles: const AxisTitles(),
        leftTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 46,
            getTitlesWidget: (v, _) => Text(v >= 1000 ? '₹${(v / 1000).toStringAsFixed(1)}k' : '₹${v.toStringAsFixed(0)}', style: const TextStyle(fontSize: 10, color: AppColors.muted)),
          ),
        ),
        bottomTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 26,
            getTitlesWidget: (v, _) {
              final i = v.toInt();
              if (i < 0 || i >= points.length) return const SizedBox.shrink();
              final step = (points.length / 17).ceil();
              if (i % step != 0) return const SizedBox.shrink();
              return Padding(padding: const EdgeInsets.only(top: 6), child: Text(points[i].$1, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w500)));
            },
          ),
        ),
      ),
      barGroups: [
        for (final (i, p) in points.indexed)
          BarChartGroupData(x: i, barRods: [
            BarChartRodData(
              toY: p.$2,
              width: points.length > 24 ? 8 : 16,
              color: AppColors.blue,
              borderRadius: BorderRadius.circular(4),
              backDrawRodData: BackgroundBarChartRodData(show: true, toY: maxY == 0 ? 100 : maxY * 1.2, color: AppColors.bg),
            ),
          ]),
      ],
    ));
  }
}
