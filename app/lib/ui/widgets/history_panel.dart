import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../core/theme.dart';
import '../../services/print_service.dart';
import 'brand.dart';
import 'common.dart';

/// One row of a History panel.
class HistoryEntry {
  final DateTime at;
  final IconData icon;
  final Color color;
  final String title;
  final String? subtitle;

  /// Right-hand value (amount / quantity) and an optional small line under it.
  final String? value;
  final Color? valueColor;
  final String? detail;
  final VoidCallback? onTap;

  /// Cells for the PDF export (same order as the panel's export headers).
  final List<String> exportRow;
  const HistoryEntry({
    required this.at,
    required this.icon,
    required this.color,
    required this.title,
    this.subtitle,
    this.value,
    this.valueColor,
    this.detail,
    this.onTap,
    this.exportRow = const [],
  });
}

typedef HistoryLoader = Future<List<HistoryEntry>> Function(DateTime from, DateTime to);

/// History button for the top of a page.
class HistoryButton extends StatelessWidget {
  final VoidCallback onPressed;
  final String tooltip;
  const HistoryButton({super.key, required this.onPressed, this.tooltip = 'History'});

  @override
  Widget build(BuildContext context) => IconButton(tooltip: tooltip, onPressed: onPressed, icon: const Icon(Icons.history_rounded));
}

/// Opens the History panel: date shortcuts (Today · Yesterday · 7 days · This month) or a calendar range, search,
/// entries grouped by day, PDF export. Phones get a full-height sheet, wide screens a side panel.
Future<void> showHistory(
  BuildContext context, {
  required String title,
  required HistoryLoader load,
  List<String> exportHeaders = const [],
  String preset = 'week',
}) {
  final panel = _HistoryPanel(title: title, load: load, exportHeaders: exportHeaders, preset: preset);
  if (MediaQuery.of(context).size.width >= 900) {
    return showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: title,
      pageBuilder: (_, _, _) => Align(
        alignment: Alignment.centerRight,
        child: Material(
          elevation: 12,
          color: AppColors.bg,
          borderRadius: const BorderRadius.horizontal(left: Radius.circular(24)),
          clipBehavior: Clip.antiAlias,
          child: SizedBox(width: 520, height: double.infinity, child: SafeArea(child: panel)),
        ),
      ),
    );
  }
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: AppColors.bg,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    builder: (_) => FractionallySizedBox(heightFactor: .92, child: panel),
  );
}

class _HistoryPanel extends StatefulWidget {
  final String title;
  final HistoryLoader load;
  final List<String> exportHeaders;
  final String preset;
  const _HistoryPanel({required this.title, required this.load, required this.exportHeaders, required this.preset});

  @override
  State<_HistoryPanel> createState() => _HistoryPanelState();
}

class _HistoryPanelState extends State<_HistoryPanel> {
  static const _presets = [('today', 'Today'), ('yesterday', 'Yesterday'), ('week', 'Last 7 days'), ('month', 'This month')];
  late String _preset = widget.preset;
  DateTimeRange? _custom;
  String _q = '';
  List<HistoryEntry> _shown = const [];

  static DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);

  DateTimeRange get _range {
    final today = _day(DateTime.now());
    return switch (_preset) {
      'today' => DateTimeRange(start: today, end: today),
      'yesterday' => DateTimeRange(start: today.subtract(const Duration(days: 1)), end: today.subtract(const Duration(days: 1))),
      'month' => DateTimeRange(start: DateTime(today.year, today.month), end: today),
      'custom' => _custom!,
      _ => DateTimeRange(start: today.subtract(const Duration(days: 6)), end: today),
    };
  }

  String get _rangeLabel {
    final r = _range;
    return r.start == r.end ? dateOnly(r.start) : '${dateOnly(r.start)} – ${dateOnly(r.end)}';
  }

  Future<void> _pickDates() async {
    final r = await showDateRangePicker(context: context, firstDate: DateTime(2020), lastDate: DateTime.now(), initialDateRange: _range);
    if (r != null) {
      setState(() {
        _custom = DateTimeRange(start: _day(r.start), end: _day(r.end));
        _preset = 'custom';
      });
    }
  }

  Future<List<HistoryEntry>> _load() {
    final r = _range;
    return widget.load(r.start, DateTime(r.end.year, r.end.month, r.end.day, 23, 59, 59));
  }

  String _dayLabel(DateTime d) {
    final diff = _day(DateTime.now()).difference(_day(d)).inDays;
    return diff == 0 ? 'Today' : diff == 1 ? 'Yesterday' : dateOnly(d);
  }

  Future<void> _export() async {
    if (_shown.isEmpty) return showSnack(context, 'Nothing to export for these dates');
    await PrintService.exportTablePdf(
      title: widget.title,
      subtitle: _rangeLabel,
      headers: ['Date & time', ...widget.exportHeaders],
      rows: [for (final e in _shown) [dateTime(e.at), ...e.exportRow]],
    );
  }

  @override
  Widget build(BuildContext context) => Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 8, 4),
          child: Row(children: [
            const Icon(Icons.history_rounded, color: AppColors.blue),
            const SizedBox(width: 10),
            Expanded(child: Text(widget.title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800))),
            if (widget.exportHeaders.isNotEmpty) IconButton(tooltip: 'Export PDF', onPressed: _export, icon: const Icon(Icons.picture_as_pdf_outlined)),
            IconButton(tooltip: 'Close', onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close)),
          ]),
        ),
        // Wraps on phones so the calendar chip is always visible.
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Wrap(spacing: 6, runSpacing: 4, children: [
            for (final (id, label) in _presets)
              ChoiceChip(label: Text(label), selected: _preset == id, onSelected: (_) => setState(() => _preset = id)),
            ActionChip(
              avatar: const Icon(Icons.calendar_month_rounded, size: 18),
              label: Text(_preset == 'custom' ? _rangeLabel : 'Pick dates'),
              backgroundColor: _preset == 'custom' ? AppColors.lime : null,
              onPressed: _pickDates,
            ),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 6),
          child: SearchField(hint: 'Search in this period…', onChanged: (v) => setState(() => _q = v.trim().toLowerCase())),
        ),
        Expanded(
          child: Loader<List<HistoryEntry>>(
            key: ValueKey('$_preset${_custom?.start}${_custom?.end}'),
            load: _load,
            builder: (context, all, _) {
              final list = _q.isEmpty
                  ? all
                  : all.where((e) => '${e.title} ${e.subtitle ?? ''} ${e.value ?? ''}'.toLowerCase().contains(_q)).toList();
              _shown = list;
              if (list.isEmpty) {
                return ListView(children: [const SizedBox(height: 40), EmptyState(icon: Icons.history_toggle_off, title: 'Nothing recorded for $_rangeLabel')]);
              }
              final rows = <Widget>[
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 0, 4, 6),
                  child: Text('${list.length} record(s) • $_rangeLabel', style: const TextStyle(fontSize: 12, color: AppColors.muted, fontWeight: FontWeight.w600)),
                ),
              ];
              DateTime? day;
              for (final e in list) {
                if (day == null || _day(e.at) != day) {
                  day = _day(e.at);
                  rows.add(Padding(
                    padding: const EdgeInsets.fromLTRB(4, 10, 4, 4),
                    child: Text(_dayLabel(e.at), style: const TextStyle(fontWeight: FontWeight.w800, color: AppColors.navy)),
                  ));
                }
                rows.add(Card(
                  margin: const EdgeInsets.only(bottom: 6),
                  child: ListTile(
                    dense: true,
                    onTap: e.onTap,
                    leading: IconTile(e.icon, e.color, size: 36),
                    title: Text(e.title, style: const TextStyle(fontWeight: FontWeight.w700)),
                    subtitle: Text([TimeOfDay.fromDateTime(e.at).format(context), if (e.subtitle != null && e.subtitle!.isNotEmpty) e.subtitle].join(' • '),
                        maxLines: 2, overflow: TextOverflow.ellipsis),
                    trailing: e.value == null
                        ? (e.onTap == null ? null : const Icon(Icons.chevron_right))
                        : Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
                            Text(e.value!, style: TextStyle(fontWeight: FontWeight.w800, color: e.valueColor)),
                            if (e.detail != null) Text(e.detail!, style: const TextStyle(fontSize: 11, color: AppColors.muted)),
                          ]),
                  ),
                ));
              }
              return ListView(padding: const EdgeInsets.fromLTRB(12, 0, 12, 24), children: rows);
            },
          ),
        ),
      ]);
}
