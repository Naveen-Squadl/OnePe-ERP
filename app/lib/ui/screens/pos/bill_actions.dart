import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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

/// How a manually tracked payment was received (OnePe collection off).
class ManualPayment {
  final String method; // CASH / UPI / CARD / SPLIT
  final double cash, upi, card;
  const ManualPayment(this.method, {this.cash = 0, this.upi = 0, this.card = 0});
}

/// A plain option card of the Proceed pop-ups (no highlighted option).
Widget _optionCard(VoidCallback onTap, IconData icon, String title, String subtitle) => Padding(
  padding: const EdgeInsets.only(bottom: 10),
  child: Material(
    color: Colors.white,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(18),
      side: const BorderSide(color: AppColors.border),
    ),
    child: InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(color: AppColors.blueTint, borderRadius: BorderRadius.circular(14)),
              child: Icon(icon, color: AppColors.blue),
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
                  Text(subtitle, style: TextStyle(fontSize: 12, color: AppColors.muted)),
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

/// Title row + blue total card shared by the Proceed pop-ups.
Widget _dialogHead(BuildContext c, String title, double total, String? customer) => Column(
  crossAxisAlignment: CrossAxisAlignment.stretch,
  children: [
    Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: AppColors.navy),
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
  ],
);

Widget _dialogFrame(Widget child) => Dialog(
  insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
  child: ConstrainedBox(
    constraints: const BoxConstraints(maxWidth: 420),
    child: SingleChildScrollView(padding: const EdgeInsets.fromLTRB(18, 18, 18, 8), child: child),
  ),
);

/// OnePe collection off: the cashier confirms the [total] was received by Cash, UPI or Card, or splits
/// it across them (the split amounts must add up to the total). Returns null when cancelled.
Future<ManualPayment?> askPaymentReceived(BuildContext context, {required double total, String? customer}) {
  final fields = {for (final k in ['CASH', 'UPI', 'CARD']) k: TextEditingController()};
  var split = false;
  double amount(String k) => double.tryParse(fields[k]!.text.trim()) ?? 0;

  return showDialog<ManualPayment>(
    context: context,
    builder: (c) => StatefulBuilder(
      builder: (c, setState) {
        if (!split) {
          return _dialogFrame(
            Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _dialogHead(c, 'Payment received?', total, customer),
                _optionCard(() => Navigator.pop(c, const ManualPayment('CASH')), Icons.payments_rounded, 'Cash', 'Received ${money(total)} in cash'),
                _optionCard(() => Navigator.pop(c, const ManualPayment('UPI')), Icons.qr_code_2_rounded, 'UPI', 'Received ${money(total)} by UPI'),
                _optionCard(() => Navigator.pop(c, const ManualPayment('CARD')), Icons.credit_card_rounded, 'Card', 'Received ${money(total)} by card'),
                _optionCard(() => setState(() => split = true), Icons.call_split_rounded, 'Split', 'Part cash, UPI and / or card'),
              ],
            ),
          );
        }
        final sum = (amount('CASH') + amount('UPI') + amount('CARD')) * 100;
        final diff = (total * 100 - sum).round() / 100; // > 0 remaining, < 0 excess
        Widget field(String k, String label, IconData icon) => Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: TextField(
            controller: fields[k],
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}'))],
            decoration: InputDecoration(labelText: label, prefixIcon: Icon(icon), prefixText: '₹ '),
            onChanged: (_) => setState(() {}),
          ),
        );
        return _dialogFrame(
          Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _dialogHead(c, 'Split payment', total, customer),
              field('CASH', 'Cash', Icons.payments_rounded),
              field('UPI', 'UPI', Icons.qr_code_2_rounded),
              field('CARD', 'Card', Icons.credit_card_rounded),
              Text(
                diff == 0 ? 'Amounts match the bill total' : diff > 0 ? 'Remaining ${money(diff)}' : 'More than the bill total by ${money(-diff)}',
                style: TextStyle(fontWeight: FontWeight.w700, color: diff == 0 ? AppColors.green : AppColors.danger),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  TextButton(onPressed: () => setState(() => split = false), child: const Text('Back')),
                  const Spacer(),
                  FilledButton(
                    onPressed: diff != 0
                        ? null
                        : () => Navigator.pop(c, ManualPayment('SPLIT', cash: amount('CASH'), upi: amount('UPI'), card: amount('CARD'))),
                    child: const Text('Confirm received'),
                  ),
                ],
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    ),
  );
}

/// The Proceed pop-up: Print Bill / Collect Payment / Print + Collect / Save without printing. Collecting
/// is offered only when OnePe collection is enabled on this device, for paid sales (not credit bills or
/// expense vouchers). Returns null when cancelled (nothing is saved).
Future<BillAction?> askBillAction(BuildContext context, {required double total, required bool allowCollect, String? customer}) {
  final printer = PrinterConfig.bill.displayName;
  Widget option(BuildContext c, BillAction a, IconData icon, String title, String subtitle) =>
      _optionCard(() => Navigator.pop(c, a), icon, title, subtitle);

  return showDialog<BillAction>(
    context: context,
    builder: (c) => _dialogFrame(
      Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _dialogHead(c, 'Bill ready', total, customer),
          option(c, BillAction.print, Icons.print_rounded, 'Print Bill', printer),
          if (allowCollect) ...[
            option(c, BillAction.collect, Icons.qr_code_2_rounded, 'Collect Payment', 'Open the OnePe payment app'),
            option(c, BillAction.printAndCollect, Icons.receipt_long_rounded, 'Print + Collect', 'Print the bill and open OnePe'),
          ],
          option(c, BillAction.saveOnly, Icons.save_alt_rounded, 'Save without printing', 'Save the bill only'),
        ],
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
    if (action.prints) attempt(() => PrintService.output(pdf, name: 'Bill_$billNo', paper: PrinterConfig.bill.paper)),
    if (action.collects) attempt(() => OnePePay.collect(pdf, billNo: billNo)),
  ]);
  return errors;
}
