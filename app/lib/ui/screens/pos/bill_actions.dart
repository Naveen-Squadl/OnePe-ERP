import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../../core/format.dart';
import '../../../core/theme.dart';
import '../../../services/device_printer.dart';
import '../../../services/print_service.dart';
import '../../../services/printer_config.dart';

/// What to do with a bill after "Proceed".
enum BillAction {
  print(true, false),
  collect(false, true),
  printAndCollect(true, true),
  saveOnly(false, false);

  final bool prints, collects;
  const BillAction(this.prints, this.collects);
}

/// The Proceed pop-up: Print Bill / Collect Payment / Print + Collect. Collecting is offered only for
/// paid sales (not credit bills or expense vouchers). Returns null when cancelled (nothing is saved).
Future<BillAction?> askBillAction(BuildContext context, {required double total, required bool allowCollect, String? customer}) {
  final printer = switch (PrinterConfig.type) {
    PrinterType.device => 'In-device printer',
    PrinterType.bluetooth => PrinterConfig.btName ?? 'Bluetooth printer',
    PrinterType.system => 'Print dialog',
  };
  Widget option(BuildContext c, BillAction a, IconData icon, String title, String subtitle, {bool primary = false}) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Material(
      color: primary ? AppColors.lime : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: primary ? AppColors.lime : AppColors.border),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () => Navigator.pop(c, a),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(color: primary ? AppColors.navy : AppColors.blueTint, borderRadius: BorderRadius.circular(14)),
                child: Icon(icon, color: primary ? AppColors.lime : AppColors.blue),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: AppColors.navy),
                    ),
                    Text(subtitle, style: TextStyle(fontSize: 12, color: primary ? AppColors.navy : AppColors.muted)),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: AppColors.navy),
            ],
          ),
        ),
      ),
    ),
  );

  return showDialog<BillAction>(
    context: context,
    builder: (c) => Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Bill ready',
                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: AppColors.navy),
                    ),
                  ),
                  IconButton(tooltip: 'Back to cart', onPressed: () => Navigator.pop(c), icon: const Icon(Icons.close_rounded)),
                ],
              ),
              Container(
                margin: const EdgeInsets.only(top: 4, bottom: 14),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(color: AppColors.blue, borderRadius: BorderRadius.circular(18)),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        customer ?? 'Walk-in customer',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Color(0xFFC9D6EA), fontWeight: FontWeight.w600),
                      ),
                    ),
                    Text(
                      money(total),
                      style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w800, letterSpacing: -0.6),
                    ),
                  ],
                ),
              ),
              option(c, BillAction.print, Icons.print_rounded, 'Print Bill', printer),
              if (allowCollect) ...[
                option(c, BillAction.collect, Icons.qr_code_2_rounded, 'Collect Payment', 'Open the OnePe payment app'),
                option(c, BillAction.printAndCollect, Icons.receipt_long_rounded, 'Print + Collect', 'Print the bill and open OnePe', primary: true),
              ],
              TextButton(onPressed: () => Navigator.pop(c, BillAction.saveOnly), child: const Text('Save without printing')),
            ],
          ),
        ),
      ),
    ),
  );
}

/// Prints and/or hands the bill PDF to the OnePe app (both at once for Print + Collect).
/// Returns the error messages; an empty list means everything went through.
Future<List<String>> runBillAction(BillAction action, Uint8List pdf, {required String billNo}) async {
  final errors = <String>[];
  Future<void> attempt(Future<void> Function() f) async {
    try {
      await f();
    } catch (e) {
      errors.add('$e');
    }
  }

  await Future.wait([
    if (action.prints) attempt(() => PrintService.output(pdf, name: 'Bill_$billNo', paper: PrinterConfig.paper)),
    if (action.collects) attempt(() => OnePePay.collect(pdf, billNo: billNo)),
  ]);
  return errors;
}
