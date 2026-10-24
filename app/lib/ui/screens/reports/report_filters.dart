import 'package:flutter/material.dart';

import '../../../core/format.dart';

/// Date preset / custom range, branch scope and staff/customer filters shared by Dashboard and Reports.
class ReportFilter {
  String preset; // today | yesterday | last7 | week | month | last_month | custom
  DateTimeRange? custom;
  bool allBranches;
  String? userId;
  String? customerId;
  ReportFilter({this.preset = 'today', this.custom, this.allBranches = false});

  DateTimeRange get range {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    return switch (preset) {
      'yesterday' => DateTimeRange(start: today.subtract(const Duration(days: 1)), end: today.subtract(const Duration(days: 1))),
      'last7' => DateTimeRange(start: today.subtract(const Duration(days: 6)), end: today),
      'week' => DateTimeRange(start: today.subtract(Duration(days: now.weekday - 1)), end: today),
      'month' => DateTimeRange(start: DateTime(now.year, now.month, 1), end: today),
      'last_month' => DateTimeRange(start: DateTime(now.year, now.month - 1, 1), end: DateTime(now.year, now.month, 0)),
      'custom' => custom ?? DateTimeRange(start: today, end: today),
      _ => DateTimeRange(start: today, end: today),
    };
  }

  Map<String, dynamic> get query => {
        if (preset != 'custom') 'preset': preset,
        if (preset == 'custom' && custom != null) 'from': isoDate(custom!.start),
        if (preset == 'custom' && custom != null) 'to': isoDate(custom!.end),
        if (allBranches) 'branch': 'all',
        'userId': userId,
        'customerId': customerId,
      };

  String get label => '${dateOnly(range.start)} - ${dateOnly(range.end)}';
  String get periodLabel {
    String d(DateTime x) => '${x.day.toString().padLeft(2, '0')}-${x.month.toString().padLeft(2, '0')}-${x.year}';
    return '${d(range.start)} to ${d(range.end)}';
  }

  String get key => '$preset${custom?.start}${custom?.end}$allBranches$userId$customerId';

  void reset() {
    preset = 'today';
    custom = null;
    allBranches = false;
    userId = null;
    customerId = null;
  }
}

/// Horizontal preset bar (Dashboard "Period" card).
class ReportFilterBar extends StatelessWidget {
  final ReportFilter filter;
  final VoidCallback onChanged;
  final bool showBranch;
  const ReportFilterBar({super.key, required this.filter, required this.onChanged, this.showBranch = true});

  @override
  Widget build(BuildContext context) => Wrap(spacing: 6, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
        for (final p in const [('today', 'Today'), ('week', 'This Week'), ('month', 'This Month'), ('last_month', 'Last Month')])
          ChoiceChip(
            label: Text(p.$2),
            selected: filter.preset == p.$1,
            onSelected: (_) {
              filter.preset = p.$1;
              onChanged();
            },
          ),
        ChoiceChip(
          label: Text(filter.preset == 'custom' ? filter.label : 'Custom'),
          selected: filter.preset == 'custom',
          onSelected: (_) async {
            final r = await showDateRangePicker(context: context, firstDate: DateTime(2020), lastDate: DateTime.now(), initialDateRange: filter.custom);
            if (r == null) return;
            filter
              ..preset = 'custom'
              ..custom = r;
            onChanged();
          },
        ),
        if (showBranch)
          FilterChip(
            label: const Text('All Branches'),
            selected: filter.allBranches,
            onSelected: (v) {
              filter.allBranches = v;
              onChanged();
            },
          ),
      ]);
}
