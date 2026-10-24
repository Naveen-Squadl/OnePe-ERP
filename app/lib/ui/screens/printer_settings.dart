import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../services/device_printer.dart';
import '../../services/printer_config.dart';
import '../widgets/common.dart';

/// Printer choice for this device (saved immediately, per terminal): in-device (Nexgo), Bluetooth or
/// the system print dialog, and the paper sizes each one supports.
class PrinterSettingsCard extends StatefulWidget {
  final VoidCallback onTestPrint;
  const PrinterSettingsCard({super.key, required this.onTestPrint});

  @override
  State<PrinterSettingsCard> createState() => _PrinterSettingsCardState();
}

class _PrinterSettingsCardState extends State<PrinterSettingsCard> {
  Future<void> _set({PrinterType? type, PaperSize? paper, String? btName, String? btAddress}) async {
    await PrinterConfig.save(type: type, paper: paper, btName: btName, btAddress: btAddress);
    if (mounted) setState(() {});
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
                trailing: d['address'] == PrinterConfig.btAddress ? const Icon(Icons.check_circle, color: AppColors.green) : null,
                onTap: () => Navigator.pop(c, d),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (picked != null) await _set(type: PrinterType.bluetooth, btName: picked['name'], btAddress: picked['address']);
  }

  Widget _typeTile(PrinterType t) {
    final available = PrinterConfig.availableTypes.contains(t);
    final selected = PrinterConfig.type == t;
    final icon = switch (t) {
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
          onTap: available ? () => t == PrinterType.bluetooth && PrinterConfig.btAddress == null ? _pickBluetooth() : _set(type: t) : null,
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
                        t.label,
                        style: TextStyle(fontWeight: FontWeight.w800, color: available ? AppColors.navy : AppColors.muted),
                      ),
                      Text(
                        !available
                            ? 'Available in the Android app'
                            : t == PrinterType.bluetooth && PrinterConfig.btAddress != null
                            ? PrinterConfig.btName ?? PrinterConfig.btAddress!
                            : t.hint,
                        style: const TextStyle(fontSize: 12, color: AppColors.muted),
                      ),
                    ],
                  ),
                ),
                if (t == PrinterType.bluetooth && available)
                  TextButton(onPressed: _pickBluetooth, child: Text(PrinterConfig.btAddress == null ? 'Select' : 'Change')),
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
    final papers = PrinterConfig.papersFor(PrinterConfig.type);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 4, 16, 4),
          child: Text('Bill Printer (this device)', style: TextStyle(fontWeight: FontWeight.w700)),
        ),
        for (final t in PrinterType.values) _typeTile(t),
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
              for (final p in PaperSize.values)
                if (papers.contains(p))
                  ChoiceChip(
                    label: Text(p.label),
                    tooltip: p.hint,
                    selected: PrinterConfig.paper == p,
                    showCheckmark: false,
                    labelStyle: TextStyle(fontWeight: FontWeight.w800, color: PrinterConfig.paper == p ? Colors.white : AppColors.navy),
                    onSelected: (_) => _set(paper: p),
                  ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
          child: Text(
            PrinterConfig.type == PrinterType.device ? 'The in-device printer supports 2" (58mm) rolls only.' : PrinterConfig.paper.hint,
            style: const TextStyle(fontSize: 12, color: AppColors.muted),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: OutlinedButton.icon(onPressed: widget.onTestPrint, icon: const Icon(Icons.print), label: const Text('Send Test Bill Print')),
        ),
      ],
    );
  }
}
