import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/format.dart';
import '../../../core/theme.dart';
import '../../../models/models.dart';
import '../../../services/print_service.dart';
import '../../../state/cart.dart';
import '../../../state/catalog.dart';
import '../../../state/session.dart';
import '../../widgets/brand.dart';
import '../../widgets/common.dart';
import '../../widgets/pickers.dart';
import 'payment_dialog.dart';

class CartPanel extends StatelessWidget {
  final VoidCallback? onCheckedOut;
  final bool popOnDone;
  const CartPanel({super.key, this.onCheckedOut, this.popOnDone = false});

  @override
  Widget build(BuildContext context) {
    final cart = context.watch<Cart>();
    final session = context.watch<Session>();
    return ColoredBox(
      color: Colors.white,
      child: Column(children: [
        if (cart.billNo != null || cart.isExpense)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            color: cart.isExpense ? const Color(0xFFFFF3E0) : const Color(0xFFFFF8E1),
            child: Text(
              cart.isExpense
                  ? 'EXPENSE VOUCHER (Outflow)'
                  : cart.editingCompleted
                      ? 'Editing Bill #${cart.billNo}'
                      : 'Waiting Bill #${cart.billNo}${cart.tableName != null ? ' • ${cart.tableName}' : ''}',
              style: TextStyle(fontWeight: FontWeight.w600, color: cart.editingCompleted ? AppColors.danger : StatusColors.waiting),
            ),
          ),
        if (popOnDone) _MobileCustomerRow(cart: cart),
        if (cart.isExpense) _ExpenseDateRow(cart: cart),
        Expanded(
          child: cart.isEmpty
              ? const Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Icon(Icons.shopping_cart_outlined, size: 84, color: Color(0xFFC4C8CF)),
                  SizedBox(height: 10),
                  Text('Your cart is empty', style: TextStyle(fontSize: 18, color: AppColors.muted)),
                ])
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
                  itemCount: cart.lines.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 10),
                  itemBuilder: (_, i) => _LineCard(line: cart.lines[i]),
                ),
        ),
        _Summary(cart: cart, session: session),
      ]),
    );
  }
}

class _MobileCustomerRow extends StatelessWidget {
  final Cart cart;
  const _MobileCustomerRow({required this.cart});

  @override
  Widget build(BuildContext context) => ListTile(
        dense: true,
        leading: const IconTile(Icons.person, AppColors.green, size: 32),
        title: Text(cart.customer?.name ?? (cart.customerPhone != null ? 'New Customer (${cart.customerPhone})' : 'Walk-in')),
        subtitle: Text(cart.tableName == null ? 'Storage / Counter: Not Selected' : 'Storage / Counter: ${cart.tableName}'),
        trailing: TextButton(
          onPressed: () async {
            final c = await pickCustomer(context);
            if (c != null) cart.setCustomer(c);
          },
          child: const Text('Change'),
        ),
      );
}

class _ExpenseDateRow extends StatelessWidget {
  final Cart cart;
  const _ExpenseDateRow({required this.cart});

  @override
  Widget build(BuildContext context) => ListTile(
        dense: true,
        leading: const Icon(Icons.event),
        title: Text('Expense Date: ${dateOnly(cart.billDate ?? DateTime.now())}'),
        trailing: TextButton(
          onPressed: () async {
            final d = await showDatePicker(context: context, initialDate: cart.billDate ?? DateTime.now(), firstDate: DateTime(2020), lastDate: DateTime.now());
            if (d != null) cart.setBillDate(d);
          },
          child: const Text('Change Date'),
        ),
      );
}

/// Cart line: name + line total, price option dropdown, qty stepper, "Add Discount".
class _LineCard extends StatelessWidget {
  final CartLine line;
  const _LineCard({required this.line});

  Future<void> _onPriceOption(BuildContext context, String v) async {
    final cart = context.read<Cart>();
    switch (v) {
      case 'base':
        cart.setPrice(line, line.basePrice, 'base');
      case 'max':
        cart.setPrice(line, line.maxPrice!, 'max');
      case 'last':
        cart.setPrice(line, line.price, 'last'); // server resolves the customer's last price
        showSnack(context, 'Last price will be applied at checkout');
      case 'custom':
        final p = await askNumber(context, 'Enter Price for ${line.name}', label: 'Price (₹)', initial: line.price);
        if (p != null) cart.setPrice(line, p, 'custom');
    }
  }

  @override
  Widget build(BuildContext context) {
    final cart = context.read<Cart>();
    final t = line.compute(cart.gstInclusive);
    final options = <String, String>{
      'base': 'Basic: ${money(line.basePrice).replaceAll('.00', '')}',
      if (line.maxPrice != null) 'max': 'Max: ${money(line.maxPrice).replaceAll('.00', '')}',
      if (cart.customer != null) 'last': 'Last price',
      'custom': line.priceType == 'custom' ? 'Custom: ${money(line.price).replaceAll('.00', '')}' : 'Custom / Edit',
    };
    final current = options.containsKey(line.priceType) ? line.priceType : 'custom';
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 10, 10),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.border)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text(line.name, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15))),
          Text(money(t.total).replaceAll('.00', ''), style: const TextStyle(color: AppColors.blue, fontWeight: FontWeight.w700, fontSize: 15)),
        ]),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(
            child: Container(
              height: 38,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(color: const Color(0xFFF1F3F7), borderRadius: BorderRadius.circular(8)),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: current,
                  isExpanded: true,
                  style: const TextStyle(fontSize: 13, color: AppColors.text),
                  items: [for (final e in options.entries) DropdownMenuItem(value: e.key, child: Text(e.value, overflow: TextOverflow.ellipsis))],
                  onChanged: (v) => v == null ? null : _onPriceOption(context, v),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          _square(Icons.remove, () => cart.setQty(line, line.quantity - 1)),
          InkWell(
            onTap: () async {
              final v = await askNumber(context, 'Set Quantity (${line.name})', label: 'Quantity', initial: line.quantity);
              if (v != null) cart.setQty(line, v);
            },
            child: Container(
              height: 34,
              constraints: const BoxConstraints(minWidth: 42),
              margin: const EdgeInsets.symmetric(horizontal: 6),
              padding: const EdgeInsets.symmetric(horizontal: 6),
              decoration: BoxDecoration(color: const Color(0xFFEAF2FE), borderRadius: BorderRadius.circular(8), border: Border.all(color: AppColors.blue)),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Text(qty(line.quantity), style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.blue, fontSize: 15)),
                const Icon(Icons.edit, size: 11, color: AppColors.blue),
              ]),
            ),
          ),
          _square(Icons.add, () => cart.setQty(line, line.quantity + 1)),
        ]),
        const SizedBox(height: 6),
        Row(children: [
          InkWell(
            onTap: () async {
              final v = await askNumber(context, 'Apply Item Discount', label: 'Discount Amount (₹)', initial: line.discount, helper: 'Original Total: ${money(line.price * line.quantity)}');
              if (v != null) cart.setItemDiscount(line, v);
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.local_offer, size: 15, color: AppColors.green),
                const SizedBox(width: 6),
                Text(line.discount > 0 ? 'Discount: -${money(line.discount)}' : 'Add Discount', style: const TextStyle(color: AppColors.green, fontWeight: FontWeight.w600, fontSize: 13)),
              ]),
            ),
          ),
          const Spacer(),
          if (line.gstPercent > 0) Text('GST ${line.gstPercent.toStringAsFixed(0)}%', style: const TextStyle(fontSize: 11, color: AppColors.muted)),
          IconButton(
            tooltip: 'Add note (kitchen)',
            visualDensity: VisualDensity.compact,
            onPressed: () async {
              final ctrl = TextEditingController(text: line.note);
              final note = await showDialog<String>(
                context: context,
                builder: (c) => AlertDialog(
                  title: const Text('Item note'),
                  content: TextField(controller: ctrl, autofocus: true, decoration: const InputDecoration(hintText: 'e.g. Extra Crispy')),
                  actions: [FilledButton(onPressed: () => Navigator.pop(c, ctrl.text), child: const Text('Save'))],
                ),
              );
              if (note != null) {
                line.note = note;
                cart.setQty(line, line.quantity);
              }
            },
            icon: Icon(Icons.sticky_note_2_outlined, size: 18, color: line.note?.isNotEmpty == true ? AppColors.blue : AppColors.muted),
          ),
        ]),
        if (line.note?.isNotEmpty == true) Text('Note: ${line.note}', style: const TextStyle(fontSize: 11, fontStyle: FontStyle.italic)),
      ]),
    );
  }

  Widget _square(IconData icon, VoidCallback onTap) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(8), border: Border.all(color: AppColors.border)),
          child: Icon(icon, size: 18),
        ),
      );
}

/// Opens the bill-discount dialog (shared with the payment dialog).
Future<void> editBillDiscount(BuildContext context, Cart cart) async {
  String type = cart.discountType;
  final ctrl = TextEditingController(text: cart.discountValue == 0 ? '' : cart.discountValue.toString());
  final ok = await showDialog<bool>(
    context: context,
    builder: (c) => StatefulBuilder(
      builder: (c, set) => AlertDialog(
        title: const Text('Apply Bill Discount'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('Original Bill Total: ${money(cart.gross)}'),
          const SizedBox(height: 12),
          SegmentedButton<String>(
            segments: const [ButtonSegment(value: 'flat', label: Text('₹ Flat')), ButtonSegment(value: 'percent', label: Text('% Percent'))],
            selected: {type},
            onSelectionChanged: (s) => set(() => type = s.first),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: ctrl,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(labelText: type == 'flat' ? 'Discount Amount' : 'Discount Percentage'),
          ),
        ]),
        actions: [
          if (cart.discountValue > 0)
            TextButton(
              onPressed: () {
                ctrl.text = '0';
                Navigator.pop(c, true);
              },
              child: const Text('Remove'),
            ),
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Apply')),
        ],
      ),
    ),
  );
  if (ok == true) cart.setDiscount(type, double.tryParse(ctrl.text) ?? 0);
}

class _Summary extends StatelessWidget {
  final Cart cart;
  final Session session;
  const _Summary({required this.cart, required this.session});

  Widget _row(String l, String r, {Color? color}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(children: [
          Expanded(child: Text(l, style: const TextStyle(color: Color(0xFF5F6368), fontSize: 15))),
          Text(r, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500, color: color)),
        ]),
      );

  Future<void> _loyalty(BuildContext context) async {
    final available = cart.customer?.loyaltyPoints ?? 0;
    final v = await askNumber(context, 'Redeem Loyalty Points', label: 'Points to Redeem', initial: cart.loyaltyRedeem, helper: 'Available Points: ${available.toStringAsFixed(0)} (1 pt = ₹1)');
    if (v != null) cart.setLoyalty(v.clamp(0, available).toDouble());
  }

  Future<void> _kot(BuildContext context) async {
    final kot = await guard(context, cart.sendKot);
    if (kot == null || !context.mounted) return;
    showSnack(context, '✅ KOT sent for #${kot['billNo']}');
    await PrintService.printKot(kot, session.shop!);
  }

  Future<void> _saveWaiting(BuildContext context) async {
    final b = await guard(context, cart.saveWaiting);
    if (b != null && context.mounted) {
      cart.clear();
      showSnack(context, 'Saved to waiting list: ${b.tableName ?? '#${b.billNo}'}');
    }
  }

  Future<void> _pay(BuildContext context) async {
    if (cart.isEmpty) return showSnack(context, 'Your cart is empty', error: true);
    final bill = await showPaymentDialog(context, cart);
    if (bill == null || !context.mounted) return;
    context.read<Catalog>().load(); // refresh stock
    final panel = context.findAncestorWidgetOfExactType<CartPanel>();
    panel?.onCheckedOut?.call();
    // The navigator's own context outlives this panel when the mobile cart page is popped.
    final hostContext = Navigator.of(context).context;
    if (panel?.popOnDone == true) Navigator.of(context).pop();
    if (hostContext.mounted) await showBillDoneDialog(hostContext, bill, session);
  }

  @override
  Widget build(BuildContext context) {
    final s = session.shop?.settings;
    final showKot = (s?.enableKot ?? false) && !cart.isExpense && !cart.isEmpty;
    final showLoyalty = !cart.isExpense && (s?.enableLoyalty ?? false) && (cart.customer?.loyaltyPoints ?? 0) > 0;
    return Container(
      padding: const EdgeInsets.fromLTRB(22, 18, 22, 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: .06), blurRadius: 16, offset: const Offset(0, -4))],
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        _row('Subtotal', money(cart.subtotal).replaceAll('.00', '')),
        if (cart.totalGst > 0) _row('Tax (GST)', money(cart.totalGst).replaceAll('.00', '')),
        if (cart.itemDiscount > 0) _row('Item Discounts', '-${money(cart.itemDiscount)}', color: AppColors.green),
        if (cart.billDiscount > 0) _row('Bill Discount', '-${money(cart.billDiscount)}', color: AppColors.green),
        if (cart.loyaltyDiscount > 0) _row('Loyalty Discount', '-${money(cart.loyaltyDiscount)}', color: AppColors.green),
        const Divider(height: 22),
        Row(children: [
          const Expanded(child: Text('TOTAL', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 20))),
          Text(money(cart.total).replaceAll('.00', ''), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 28, color: AppColors.blue)),
        ]),
        const SizedBox(height: 12),
        if (!cart.isExpense) GreenOutlineButton(label: cart.billDiscount > 0 ? 'Change Bill Discount' : 'Apply Bill Discount', icon: Icons.percent, onPressed: cart.isEmpty ? null : () => editBillDiscount(context, cart)),
        if (showLoyalty) ...[
          const SizedBox(height: 8),
          GreenOutlineButton(label: 'Redeem Points (Available: ${cart.customer!.loyaltyPoints.toStringAsFixed(0)})', icon: Icons.stars_rounded, onPressed: () => _loyalty(context)),
        ],
        if (!cart.isEmpty && !cart.isExpense) ...[
          const SizedBox(height: 8),
          Row(children: [
            Expanded(child: OutlinedButton.icon(onPressed: () => _saveWaiting(context), icon: const Icon(Icons.pending_actions, size: 18), label: const Text('Hold'))),
            if (showKot) ...[
              const SizedBox(width: 8),
              Expanded(child: OutlinedButton.icon(onPressed: () => _kot(context), icon: const Icon(Icons.soup_kitchen_outlined, size: 18), label: const Text('KOT'))),
            ],
          ]),
        ],
        const SizedBox(height: 12),
        GreenButton(
          label: cart.isExpense ? 'Record Expense Voucher' : 'Proceed to Payment',
          icon: Icons.payments_outlined,
          busy: cart.busy,
          onPressed: () => _pay(context),
        ),
      ]),
    );
  }
}

/// Post-checkout dialog: print / WhatsApp / new order.
Future<void> showBillDoneDialog(BuildContext context, Bill bill, Session session) async {
  final shop = session.shop!;
  if (shop.settings.whatsappCustomerShare && bill.customerContact != null && !bill.isExpense) {
    PrintService.shareBillWhatsApp(bill, shop);
  }
  await showDialog(
    context: context,
    builder: (c) => AlertDialog(
      icon: Icon(bill.isPendingSync ? Icons.cloud_off : Icons.check_circle, color: bill.isPendingSync ? StatusColors.waiting : AppColors.green, size: 56),
      title: Text(bill.isPendingSync ? 'Saved offline' : (bill.isExpense ? 'Expense Recorded' : 'Bill Saved (${bill.paymentMethod})')),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        Text('Bill #${bill.billNo}', style: const TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 4),
        Text(money(bill.total), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 30, color: AppColors.blue)),
        if (bill.change > 0) Text('Change Returned: ${money(bill.change)}', style: const TextStyle(color: AppColors.green, fontWeight: FontWeight.w700)),
        if (bill.customerClosing != null) Text('New Account Balance: ${money(bill.customerClosing)}'),
        if (bill.loyaltyEarned > 0) Text('Points Earned: ${bill.loyaltyEarned.toStringAsFixed(0)}'),
        if (bill.isPendingSync) const Text('Device is offline. The bill is saved safely and will sync automatically.', textAlign: TextAlign.center),
      ]),
      actions: [
        if (bill.customerContact != null) TextButton.icon(onPressed: () => PrintService.shareBillWhatsApp(bill, shop), icon: const Icon(Icons.chat), label: const Text('WhatsApp')),
        TextButton.icon(onPressed: () => PrintService.printBill(bill, shop, branch: session.activeBranch), icon: const Icon(Icons.print), label: const Text('Print')),
        FilledButton(onPressed: () => Navigator.pop(c), child: const Text('New Order')),
      ],
    ),
  );
}
