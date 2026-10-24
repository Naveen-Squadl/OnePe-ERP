import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../services/device_printer.dart';
import '../../services/print_service.dart';
import '../../services/printer_config.dart';
import '../widgets/common.dart';

/// Printers of this device (saved immediately, per terminal): the bill printer and the KOT / kitchen
/// printer, each Nexgo N82, Bluetooth or the system print dialog with the paper sizes it supports.
class PrinterSettingsCard extends StatefulWidget {
  final VoidCallback onTestPrint;
  const PrinterSettingsCard({super.key, required this.onTestPrint});

  @override
  State<PrinterSettingsCard> createState() => _PrinterSettingsCardState();
}

class _PrinterSettingsCardState extends State<PrinterSettingsCard> {
  static const _testKot = {
    'billNo': 'TEST-001',
    'tableName': 'T1',
    'items': [
      {'productName': 'Test Item 1', 'quantity': 1, 'note': 'Less spicy'},
      {'productName': 'Test Item 2', 'quantity': 2},
    ],
  };

  Widget _heading(String text) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
    child: Text(text, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
  );

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _heading('Bill Printer'),
        _PrinterPicker(target: PrinterConfig.bill, testLabel: 'Send Test Bill Print', onTest: widget.onTestPrint, onChanged: () => setState(() {})),
        const Padding(padding: EdgeInsets.fromLTRB(16, 16, 16, 0), child: Divider()),
        _heading('KOT / Kitchen Printer'),
        SwitchListTile(
          title: const Text('Same as bill printer'),
          subtitle: Text(
            PrinterConfig.kotSameAsBill
                ? 'Kitchen order tickets print on ${PrinterConfig.bill.displayName}'
                : 'Kitchen order tickets print on a separate printer',
          ),
          value: PrinterConfig.kotSameAsBill,
          onChanged: (v) async {
            await PrinterConfig.setKotSameAsBill(v);
            if (mounted) setState(() {});
          },
        ),
        if (!PrinterConfig.kotSameAsBill)
          _PrinterPicker(
            target: PrinterConfig.kitchen,
            testLabel: 'Send Test KOT Print',
            onTest: () => guard(context, () => PrintService.printKot(_testKot)),
          )
        else
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
            child: OutlinedButton.icon(
              onPressed: () => guard(context, () => PrintService.printKot(_testKot)),
              icon: const Icon(Icons.soup_kitchen_outlined),
              label: const Text('Send Test KOT Print'),
            ),
          ),
      ],
    );
  }
}

/// Printer type tiles + paper sizes + test button for one [PrinterTarget].
class _PrinterPicker extends StatefulWidget {
  final PrinterTarget target;
  final String testLabel;
  final VoidCallback onTest;
  final VoidCallback? onChanged;
  const _PrinterPicker({required this.target, required this.testLabel, required this.onTest, this.onChanged});

  @override
  State<_PrinterPicker> createState() => _PrinterPickerState();
}

class _PrinterPickerState extends State<_PrinterPicker> {
  PrinterTarget get t => widget.target;

  Future<void> _set({PrinterType? type, PaperSize? paper, String? btName, String? btAddress}) async {
    await t.save(type: type, paper: paper, btName: btName, btAddress: btAddress);
    if (mounted) setState(() {});
    widget.onChanged?.call();
  }

  Future<void> _pickBluetooth() async {
    final devices = await guard(context, DevicePrinter.pairedPrinters);
    if (devices == null || !mounted) return;
    if (devices.isEmpty) {
      return showSnack(context, 'No paired Bluetooth devices. Pair the printer in Android Bluetooth settings first.', error: true);
    }
    final picked = await showModalBottomSheet<Map<String, String>>(
      context: context,
      builder: (c) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text('Paired Bluetooth printers', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
            ),
            for (final d in devices)
              ListTile(
                leading: const Icon(Icons.print_rounded, color: AppColors.blue),
                title: Text(d['name'] ?? d['address']!, style: const TextStyle(fontWeight: FontWeight.w700)),
                subtitle: Text(d['address']!),
                trailing: d['address'] == t.btAddress ? const Icon(Icons.check_circle, color: AppColors.green) : null,
                onTap: () => Navigator.pop(c, d),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (picked != null) await _set(type: PrinterType.bluetooth, btName: picked['name'], btAddress: picked['address']);
  }

  Widget _typeTile(PrinterType type) {
    final available = PrinterConfig.availableTypes.contains(type);
    final selected = t.type == type;
    final icon = switch (type) {
      PrinterType.device => Icons.point_of_sale_rounded,
      PrinterType.bluetooth => Icons.bluetooth_rounded,
      PrinterType.system => Icons.print_rounded,
    };
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Material(
        color: selected ? AppColors.blueTint : Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: selected ? AppColors.blue : AppColors.border, width: selected ? 1.6 : 1),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: available ? () => type == PrinterType.bluetooth && t.btAddress == null ? _pickBluetooth() : _set(type: type) : null,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(color: selected ? AppColors.blue : AppColors.bg, borderRadius: BorderRadius.circular(12)),
                  child: Icon(icon, color: selected ? AppColors.lime : (available ? AppColors.navy : AppColors.muted)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        type.label,
                        style: TextStyle(fontWeight: FontWeight.w800, color: available ? AppColors.navy : AppColors.muted),
                      ),
                      Text(
                        !available
                            ? PrinterConfig.unavailableReason(type)!
                            : type == PrinterType.bluetooth && t.btAddress != null
                            ? t.btName ?? t.btAddress!
                            : type.hint,
                        style: const TextStyle(fontSize: 12, color: AppColors.muted),
                      ),
                    ],
                  ),
                ),
                if (type == PrinterType.bluetooth && available)
                  TextButton(onPressed: _pickBluetooth, child: Text(t.btAddress == null ? 'Select' : 'Change')),
                Icon(selected ? Icons.radio_button_checked : Icons.radio_button_off, color: selected ? AppColors.blue : AppColors.border),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final type in PrinterType.values) _typeTile(type),
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 12, 16, 6),
          child: Text('Paper Size', style: TextStyle(fontWeight: FontWeight.w700)),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final p in t.papers)
                ChoiceChip(
                  label: Text(p.label),
                  tooltip: p.hint,
                  selected: t.paper == p,
                  showCheckmark: false,
                  labelStyle: TextStyle(fontWeight: FontWeight.w800, color: t.paper == p ? Colors.white : AppColors.navy),
                  onSelected: (_) => _set(paper: p),
                ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
          child: Text(
            t.type == PrinterType.device ? 'The Nexgo N82 printer supports 2" (58mm) rolls only.' : t.paper.hint,
            style: const TextStyle(fontSize: 12, color: AppColors.muted),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: OutlinedButton.icon(onPressed: widget.onTest, icon: const Icon(Icons.print), label: Text(widget.testLabel)),
        ),
      ],
    );
  }
}
