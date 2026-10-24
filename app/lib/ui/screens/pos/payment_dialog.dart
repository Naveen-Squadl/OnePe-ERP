import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../../core/api.dart';
import '../../../core/format.dart';
import '../../../core/theme.dart';
import '../../../models/models.dart';
import '../../../state/cart.dart';
import '../../../state/session.dart';
import 'cart_panel.dart';

/// "Payment Summary" dialog. Returns the saved bill or null if cancelled.
Future<Bill?> showPaymentDialog(BuildContext context, Cart cart) =>
    showDialog<Bill>(context: context, barrierDismissible: false, builder: (_) => _PaymentDialog(cart: cart));

class _PaymentDialog extends StatefulWidget {
  final Cart cart;
  const _PaymentDialog({required this.cart});
  @override
  State<_PaymentDialog> createState() => _PaymentDialogState();
}

class _PaymentDialogState extends State<_PaymentDialog> {
  String method = 'CASH';
  late final received = TextEditingController(text: _fmt(widget.cart.total));
  late final mobile = TextEditingController(text: widget.cart.customerPhone ?? '');
  bool giveChange = true;
  String? error;
  bool busy = false;

  static String _fmt(double v) => v.toStringAsFixed(v % 1 == 0 ? 0 : 2);
  Cart get cart => widget.cart;
  double get total => cart.total;
  double get receivedValue => double.tryParse(received.text.replaceAll('₹', '')) ?? 0;
  bool get hasCustomer => cart.customer != null || (cart.customerPhone?.length ?? 0) == 10;

  Future<void> _applyMobile(String v) async {
    if (v.isEmpty) {
      cart.setCustomer(null);
    } else if (v.length == 10) {
      try {
        cart.setCustomer(Customer(Map<String, dynamic>.from(await Api.instance.get('/customers/phone/$v'))));
      } on ApiException catch (e) {
        if (e.status == 404) cart.setCustomer(null, phone: v, name: 'New Customer');
      }
    } else {
      cart.customerPhone = v;
    }
    if (mounted) setState(() {});
  }

  Future<void> _confirm() async {
    if (mobile.text.isNotEmpty && !RegExp(r'^\d{10}$').hasMatch(mobile.text)) {
      return setState(() => error = 'Mobile number must be 10 digits');
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final bill = await cart.checkout(
        paymentMethod: cart.isExpense ? 'CASH' : method,
        received: method == 'CREDIT' ? 0 : receivedValue,
        giveChange: giveChange,
      );
      if (mounted) Navigator.pop(context, bill);
    } on ApiException catch (e) {
      setState(() => error = e.message);
    } catch (e) {
      setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = context.read<Session>();
    final upi = session.activeBranch?.upiId ?? session.shop?.upiId;
    final change = receivedValue - total;
    final quick = <double>{total, (total / 50).ceil() * 50.0, (total / 100).ceil() * 100.0, (total / 500).ceil() * 500.0}.toList()..sort();

    return Dialog(
      insetPadding: const EdgeInsets.all(20),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 380),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 26, 24, 18),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(cart.isExpense ? 'Expense Voucher' : 'Payment Summary', textAlign: TextAlign.center, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700)),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.symmetric(vertical: 18),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
              child: Column(children: [
                const Text('Bill Total', style: TextStyle(color: AppColors.muted)),
                Text(money(total).replaceAll('.00', ''), style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w700, color: AppColors.blue)),
                if (cart.billDiscount + cart.itemDiscount > 0)
                  Text('Includes ${money(cart.billDiscount + cart.itemDiscount)} Discount', style: const TextStyle(fontSize: 12, color: AppColors.green)),
              ]),
            ),
            if (!cart.isExpense)
              TextButton.icon(
                onPressed: () async {
                  await editBillDiscount(context, cart);
                  setState(() => received.text = _fmt(cart.total));
                },
                icon: const Icon(Icons.percent, size: 16, color: AppColors.green),
                label: Text(cart.billDiscount > 0 ? 'Change Bill Discount' : 'Add Bill Discount', style: const TextStyle(color: AppColors.green, fontWeight: FontWeight.w600)),
              ),
            if (!cart.isExpense) ...[
              const SizedBox(height: 4),
              TextField(
                controller: mobile,
                keyboardType: TextInputType.phone,
                maxLength: 10,
                onChanged: _applyMobile,
                decoration: InputDecoration(
                  counterText: '',
                  prefixIcon: const Icon(Icons.phone_android, color: AppColors.green),
                  hintText: 'Customer Mobile (WhatsApp / Account)',
                  helperText: cart.customer != null
                      ? '${cart.customer!.name} • Balance ${money(cart.customer!.balance)}'
                      : (cart.customerPhone?.length == 10 ? 'New customer will be created' : null),
                ),
              ),
              const SizedBox(height: 12),
              Wrap(spacing: 6, runSpacing: 6, alignment: WrapAlignment.center, children: [
                for (final m in [('CASH', 'Cash', Icons.payments_outlined), ('UPI', 'UPI', Icons.qr_code), ('CARD', 'Card', Icons.credit_card), if (hasCustomer) ('CREDIT', 'Credit', Icons.account_balance_wallet_outlined)])
                  ChoiceChip(
                    avatar: Icon(m.$3, size: 16),
                    label: Text(m.$2),
                    selected: method == m.$1,
                    onSelected: (_) => setState(() {
                      method = m.$1;
                      if (method != 'CASH') received.text = _fmt(total);
                    }),
                  ),
              ]),
              const SizedBox(height: 12),
            ],
            if (method == 'UPI' && upi != null) ...[
              Center(
                child: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
                  child: Column(children: [
                    const Text('Scan with any UPI App', style: TextStyle(fontWeight: FontWeight.w600)),
                    QrImageView(data: 'upi://pay?pa=$upi&pn=${Uri.encodeComponent(session.shop!.name)}&am=${total.toStringAsFixed(2)}&cu=INR', size: 170),
                    Text('Amount to pay: ${money(total)}', style: const TextStyle(fontSize: 12)),
                  ]),
                ),
              ),
              const SizedBox(height: 12),
            ],
            if (method != 'CREDIT') ...[
              TextField(
                controller: received,
                autofocus: true,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                onChanged: (_) => setState(() {}),
                onSubmitted: (_) => busy ? null : _confirm(),
                decoration: InputDecoration(labelText: cart.isExpense ? 'Expense Paid Amount' : 'Received Amount', prefixText: '₹'),
              ),
              if (method == 'CASH' && !cart.isExpense) ...[
                const SizedBox(height: 8),
                Wrap(spacing: 6, alignment: WrapAlignment.center, children: [
                  for (final q in quick) ActionChip(label: Text('₹${_fmt(q)}'), onPressed: () => setState(() => received.text = _fmt(q))),
                ]),
              ],
              const SizedBox(height: 14),
              Row(children: [
                Text(change < -0.005 ? (hasCustomer ? 'Balance to Account' : 'Short by') : 'Change', style: const TextStyle(fontWeight: FontWeight.w600)),
                const Spacer(),
                Text(money(change.abs()).replaceAll('.00', ''),
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 20, color: change < -0.005 ? AppColors.danger : AppColors.green)),
              ]),
              if (hasCustomer && change > 0.005 && !cart.isExpense)
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  title: const Text('Return change in cash (off = credit to account)'),
                  value: giveChange,
                  onChanged: (v) => setState(() => giveChange = v),
                ),
            ],
            if (method == 'CREDIT') Text('Full amount ${money(total)} will be added to the customer account.', style: const TextStyle(color: AppColors.danger)),
            if (error != null) Padding(padding: const EdgeInsets.only(top: 10), child: Text(error!, style: const TextStyle(color: AppColors.danger))),
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(onPressed: busy ? null : () => Navigator.pop(context), child: const Text('Cancel')),
            ),
            FilledButton(
              onPressed: busy ? null : _confirm,
              child: busy
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : Text(cart.isExpense ? 'Record Expense' : 'Confirm Amount'),
            ),
          ]),
        ),
      ),
    );
  }
}
