import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/format.dart';
import '../../../core/theme.dart';
import '../../../models/models.dart';
import '../../../services/print_service.dart';
import '../../../services/printer_config.dart';
import '../../../state/cart.dart';
import '../../../state/catalog.dart';
import '../../../state/session.dart';
import '../../widgets/brand.dart';
import '../../widgets/common.dart';
import '../../widgets/pickers.dart';
import 'bill_actions.dart';

class CartPanel extends StatelessWidget {
  final VoidCallback? onCheckedOut;
  final bool popOnDone;
  const CartPanel({super.key, this.onCheckedOut, this.popOnDone = false});

  @override
  Widget build(BuildContext context) {
    final cart = context.watch<Cart>();
    final session = context.watch<Session>();
    final banner = cart.isExpense
        ? ('EXPENSE VOUCHER (Outflow)', AppColors.amber, AppColors.navy)
        : cart.billNo != null
            ? ('Waiting Bill #${cart.billNo}${cart.tableName != null ? ' • ${cart.tableName}' : ''}', AppColors.amber, AppColors.navy)
            : null;
    return ColoredBox(
      color: popOnDone ? AppColors.bg : Colors.white,
      child: SafeArea(
        bottom: false,
        child: Column(children: [
          Padding(
            padding: EdgeInsets.fromLTRB(popOnDone ? 8 : 20, 12, 14, 10),
            child: Row(children: [
              if (popOnDone) ...[
                IconButton(
                  tooltip: 'Back to catalog',
                  onPressed: () => Navigator.of(context).pop(),
                  style: IconButton.styleFrom(backgroundColor: Colors.white, fixedSize: const Size(44, 44)),
                  icon: const Icon(Icons.arrow_back_rounded),
                ),
                const SizedBox(width: 8),
              ],
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(cart.isExpense ? 'Expense voucher' : 'Current order', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, letterSpacing: -0.3)),
                  Text('${qty(cart.itemCount)} item(s)${session.activeBranch != null ? ' · ${session.activeBranch!.name}' : ''}',
                      style: const TextStyle(fontSize: 12, color: AppColors.muted, fontWeight: FontWeight.w600)),
                ]),
              ),
              TextButton.icon(
                onPressed: () {
                  cart.clear();
                  showSnack(context, 'New order started.');
                },
                style: TextButton.styleFrom(
                  backgroundColor: AppColors.lime,
                  foregroundColor: AppColors.navy,
                  minimumSize: const Size(0, 40),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(13)),
                ),
                icon: const Icon(Icons.add_rounded, size: 18),
                label: const Text('New order'),
              ),
            ]),
          ),
          if (banner != null)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.fromLTRB(16, 0, 16, 10),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(color: banner.$2, borderRadius: BorderRadius.circular(12)),
              child: Text(banner.$1, style: TextStyle(fontWeight: FontWeight.w800, color: banner.$3, fontSize: 13)),
            ),
          if (!cart.isExpense) _OrderContextRow(cart: cart, onCard: popOnDone),
          if (cart.isExpense) _ExpenseDateRow(cart: cart),
          Expanded(
            child: cart.isEmpty
                ? Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Container(
                      width: 96,
                      height: 96,
                      decoration: const BoxDecoration(color: AppColors.cream, shape: BoxShape.circle),
                      child: const Icon(Icons.shopping_basket_rounded, size: 44, color: Color(0xFF8C8A5E)),
                    ),
                    const SizedBox(height: 14),
                    const Text('Your cart is empty', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 4),
                    const Text('Tap a product to add it to this order', style: TextStyle(color: AppColors.muted, fontWeight: FontWeight.w500)),
                  ])
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 2, 16, 12),
                    itemCount: cart.lines.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (_, i) => _LineCard(line: cart.lines[i], onCard: popOnDone),
                  ),
          ),
          _Summary(cart: cart, session: session),
        ]),
      ),
    );
  }
}

/// Table / counter picker shared by the POS header and the cart.
Future<void> pickTable(BuildContext context, Cart cart) async {
  final s = context.read<Session>();
  final tables = {...?s.activeBranch?.tableNames, ...?s.shop?.settings.tableNames}.toList();
  final t = await showModalBottomSheet<String>(
    context: context,
    builder: (c) => SafeArea(
      child: ListView(shrinkWrap: true, children: [
        const ListTile(title: Text('Table / Counter', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18))),
        ListTile(leading: const Icon(Icons.block), title: const Text('Not Selected'), onTap: () => Navigator.pop(c, '')),
        if (tables.isEmpty) const ListTile(title: Text('Add tables / counters in Settings or Branches')),
        for (final t in tables) ListTile(leading: const Icon(Icons.table_restaurant_outlined), title: Text(t), selected: cart.tableName == t, onTap: () => Navigator.pop(c, t)),
      ]),
    ),
  );
  if (t != null) cart.setTable(t.isEmpty ? null : t);
}

/// Customer ("Walk-in · Search / Add customer") and table cards above the order lines.
class _OrderContextRow extends StatelessWidget {
  final Cart cart;
  final bool onCard; // true on the phone cart page (grey ground → white cards)
  const _OrderContextRow({required this.cart, required this.onCard});

  @override
  Widget build(BuildContext context) {
    final bg = onCard ? Colors.white : AppColors.bg;
    final name = cart.customer?.name ?? (cart.customerPhone != null ? (cart.customerName ?? cart.customerPhone!) : 'Walk-in');
    final sub = cart.customer != null
        ? '${balanceText(cart.customer!.balance)}${cart.customer!.loyaltyPoints > 0 ? ' · ★ ${cart.customer!.loyaltyPoints.toStringAsFixed(0)}' : ''} · Change'
        : 'Search / Add customer';
    Widget card({required Widget child, required VoidCallback onTap, double? width}) => SizedBox(
          width: width,
          height: 54,
          child: Material(
            color: bg,
            borderRadius: BorderRadius.circular(16),
            child: InkWell(borderRadius: BorderRadius.circular(16), onTap: onTap, child: child),
          ),
        );
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Row(children: [
        Expanded(
          child: card(
            onTap: () async {
              final c = await pickCustomer(context);
              if (c != null) cart.setCustomer(c);
            },
            child: Row(children: [
              const SizedBox(width: 10),
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(color: AppColors.blue, borderRadius: BorderRadius.circular(11)),
                child: const Icon(Icons.person_rounded, color: Colors.white, size: 19),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
                  Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 11, color: AppColors.blue)),
                ]),
              ),
            ]),
          ),
        ),
        if (context.watch<Session>().shop?.has('tables') ?? false) ...[
          const SizedBox(width: 8),
          card(
            width: 86,
            onTap: () => pickTable(context, cart),
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              const Text('Table', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.muted)),
              Text(cart.tableName ?? 'None', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800)),
            ]),
          ),
        ],
      ]),
    );
  }
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

/// Cart line: name + line total, item price, qty stepper, "Add Discount".
class _LineCard extends StatelessWidget {
  final CartLine line;
  final bool onCard;
  const _LineCard({required this.line, this.onCard = false});

  Future<void> _enterPrice(BuildContext context) async {
    final cart = context.read<Cart>();
    final p = await askNumber(context, 'Enter Price for ${line.name}', label: 'Price (₹)', initial: line.price);
    if (p != null) cart.setPrice(line, p);
  }

  @override
  Widget build(BuildContext context) {
    final cart = context.read<Cart>();
    final t = line.compute(cart.gstInclusive);
    final fieldBg = onCard ? AppColors.bg : Colors.white;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 10, 8),
      decoration: BoxDecoration(color: onCard ? Colors.white : AppColors.bg, borderRadius: BorderRadius.circular(18)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text(line.name, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14))),
          Text(money(t.total).replaceAll('.00', ''), style: const TextStyle(color: AppColors.blue, fontWeight: FontWeight.w800, fontSize: 15)),
        ]),
        const SizedBox(height: 8),
        Row(children: [
          // Item price from Products (admin); only variable-price / expense lines can be changed here.
          Expanded(
            child: InkWell(
              onTap: line.priceEditable ? () => _enterPrice(context) : null,
              borderRadius: BorderRadius.circular(12),
              child: Container(
                height: 38,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                decoration: BoxDecoration(color: fieldBg, borderRadius: BorderRadius.circular(12)),
                child: Row(children: [
                  Expanded(
                    child: Text('Price: ${money(line.price).replaceAll('.00', '')}',
                        overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, color: AppColors.text, fontWeight: FontWeight.w600)),
                  ),
                  if (line.priceEditable) const Icon(Icons.edit_rounded, size: 16, color: AppColors.blue),
                ]),
              ),
            ),
          ),
          const SizedBox(width: 8),
          _square(Icons.remove_rounded, fieldBg, () => cart.setQty(line, line.quantity - 1)),
          InkWell(
            onTap: () async {
              final v = await askNumber(context, 'Set Quantity (${line.name})', label: 'Quantity', initial: line.quantity);
              if (v != null) cart.setQty(line, v);
            },
            child: Container(
              height: 36,
              constraints: const BoxConstraints(minWidth: 36),
              alignment: Alignment.center,
              margin: const EdgeInsets.symmetric(horizontal: 4),
              child: Text(qty(line.quantity), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
            ),
          ),
          _square(Icons.add_rounded, fieldBg, () => cart.setQty(line, line.quantity + 1)),
        ]),
        const SizedBox(height: 6),
        Row(children: [
          InkWell(
            onTap: () async {
              final v = await askNumber(context, 'Apply Item Discount', label: 'Discount Amount (₹)', initial: line.discount);
              if (v != null) cart.setItemDiscount(line, v);
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.local_offer_rounded, size: 15, color: line.discount > 0 ? AppColors.green : AppColors.blue),
                const SizedBox(width: 6),
                Text(line.discount > 0 ? 'Discount: -${money(line.discount)}' : 'Add Discount',
                    style: TextStyle(color: line.discount > 0 ? AppColors.green : AppColors.blue, fontWeight: FontWeight.w700, fontSize: 12)),
              ]),
            ),
          ),
          const Spacer(),
          if (line.gstPercent > 0) Text('GST ${line.gstPercent.toStringAsFixed(0)}%', style: const TextStyle(fontSize: 11, color: AppColors.muted, fontWeight: FontWeight.w600)),
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

  Widget _square(IconData icon, Color bg, VoidCallback onTap) => Material(
        color: bg,
        borderRadius: BorderRadius.circular(11),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(11),
          child: SizedBox(width: 36, height: 36, child: Icon(icon, size: 18, color: AppColors.navy)),
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

class _Summary extends StatefulWidget {
  final Cart cart;
  final Session session;
  const _Summary({required this.cart, required this.session});

  @override
  State<_Summary> createState() => _SummaryState();
}

/// Compact checkout footer: one-line total (breakdown on tap), round off, a single row of
/// small actions and the pay button – so the item list keeps most of a phone screen.
class _SummaryState extends State<_Summary> {
  bool showDetails = false;
  Cart get cart => widget.cart;
  Session get session => widget.session;

  static String _signed(double v) => '${v > 0 ? '+' : '-'}${v.abs().toStringAsFixed(2)}';

  Widget _row(String l, String r, {Color? color}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(children: [
          Expanded(child: Text(l, style: const TextStyle(color: Color(0xFFC9D6EA), fontSize: 13, fontWeight: FontWeight.w600))),
          Text(r, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: color ?? Colors.white)),
        ]),
      );

  Future<void> _loyalty(BuildContext context) async {
    final available = cart.customer?.loyaltyPoints ?? 0;
    final v = await askNumber(context, 'Redeem Loyalty Points · ${available.toStringAsFixed(0)} available', label: 'Points to Redeem', initial: cart.loyaltyRedeem);
    if (v != null) cart.setLoyalty(v.clamp(0, available).toDouble());
  }

  Future<void> _kot(BuildContext context) async {
    final kot = await guard(context, cart.sendKot);
    if (kot == null || !context.mounted) return;
    showSnack(context, '✅ KOT sent for #${kot['billNo']}');
    await PrintService.printKot(kot);
  }

  Future<void> _saveWaiting(BuildContext context) async {
    final b = await guard(context, cart.saveWaiting);
    if (b != null && context.mounted) {
      cart.clear();
      showSnack(context, 'Saved to waiting list: ${b.tableName ?? '#${b.billNo}'}');
    }
  }

  /// Proceed: ask Print / Collect / Print + Collect / Save, confirm the payment mode when OnePe collection
  /// is off, save the bill (OnePe when collecting, else the confirmed mode or credit), build its PDF and hand it to the printer and/or the OnePe payment app.
  Future<void> _pay(BuildContext context) async {
    if (cart.isEmpty) return showSnack(context, 'Your cart is empty', error: true);
    final credit = cart.onCredit && cart.hasCustomer && !cart.isExpense;
    // Advance: the customer's advance pays first; only the rest is collected (no OnePe hand-off then, since
    // the bill PDF shows the full total).
    final advance = cart.isExpense ? 0.0 : cart.advancePart;
    final toCollect = cart.toCollect;
    final fromAdvanceOnly = advance > 0 && toCollect <= 0;
    final collect = PrinterConfig.onePeCollect && advance == 0;
    final action = await askBillAction(context, total: cart.payable, allowCollect: collect && !credit && !cart.isExpense, customer: cart.customer?.name);
    if (action == null || !context.mounted) return;
    // OnePe collection off: the cashier confirms how the money was received (paid sales only).
    ManualPayment? paid;
    if (!collect && !credit && !cart.isExpense && !fromAdvanceOnly) {
      paid = await askPaymentReceived(context, total: toCollect, customer: cart.customer?.name, keepChangeOption: cart.customer != null);
      if (paid == null || !context.mounted) return;
    }
    final method = credit ? 'CREDIT' : fromAdvanceOnly ? 'ADVANCE' : (action.collects ? 'ONEPE' : paid?.method ?? 'CASH');
    final bill = await guard(
      context,
      () => cart.checkout(
        paymentMethod: method,
        received: credit || fromAdvanceOnly ? 0 : (paid?.received ?? toCollect),
        cash: paid?.cash ?? 0,
        upi: paid?.upi ?? 0,
        card: paid?.card ?? 0,
        giveChange: !(paid?.keepChange ?? false),
      ),
    );
    if (bill == null || !context.mounted) return;
    context.read<Catalog>().load(); // refresh stock
    final panel = context.findAncestorWidgetOfExactType<CartPanel>();
    panel?.onCheckedOut?.call();
    // The navigator's own context outlives this panel when the mobile cart page is popped.
    final hostContext = Navigator.of(context).context;
    if (panel?.popOnDone == true) Navigator.of(context).pop();
    if (hostContext.mounted) await finishBill(hostContext, bill, session, action);
  }

  /// Outlined action on the blue payment card (lime when toggled on).
  Widget _action(IconData icon, String label, VoidCallback? onTap, {bool selected = false}) => Expanded(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 3),
          child: Material(
            color: selected ? AppColors.lime : Colors.transparent,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: selected ? AppColors.lime : Colors.white.withValues(alpha: .3)),
            ),
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: onTap,
              child: SizedBox(
                height: 46,
                child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Icon(icon, size: 17, color: selected ? AppColors.navy : Colors.white),
                  const SizedBox(height: 2),
                  Text(label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: selected ? AppColors.navy : Colors.white)),
                ]),
              ),
            ),
          ),
        ),
      );

  Widget _roundOption(String mode, String label, String sub) {
    final on = cart.roundMode == mode;
    return Expanded(
      child: Material(
        color: on ? AppColors.lime : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => cart.setRoundMode(mode == cart.roundMode ? 'none' : mode),
          child: SizedBox(
            height: 44,
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              Text(label, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: on ? AppColors.navy : Colors.white)),
              Text(sub, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: on ? AppColors.navy : const Color(0xFFB9C4D8))),
            ]),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final shop = session.shop;
    final showKot = (shop?.has('kot') ?? false) && !cart.isExpense && !cart.isEmpty;
    final showLoyalty = !cart.isExpense && (shop?.has('loyalty') ?? false) && (cart.customer?.loyaltyPoints ?? 0) > 0;
    final showCredit = cart.hasCustomer && (shop?.has('credit') ?? false);
    const light = Color(0xFFC9D6EA);
    final payable = money(cart.payable).replaceAll('.00', '');
    return Padding(
      padding: EdgeInsets.fromLTRB(8, 10, 8, 8 + MediaQuery.of(context).padding.bottom),
      child: Stack(children: [
        // Brand element: lime step behind the payment card's upper-left edge.
        Positioned(
          left: 0,
          top: 0,
          width: 210,
          height: 60,
          child: Container(decoration: const BoxDecoration(color: AppColors.lime, borderRadius: BorderRadius.only(topLeft: Radius.circular(24), topRight: Radius.circular(18)))),
        ),
        Container(
          margin: const EdgeInsets.only(top: 9),
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
          decoration: BoxDecoration(color: AppColors.blue, borderRadius: BorderRadius.circular(24)),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            InkWell(
              onTap: () => setState(() => showDetails = !showDetails),
              borderRadius: BorderRadius.circular(10),
              child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(cart.isExpense ? 'Expense total' : 'Total payable', style: const TextStyle(color: AppColors.lime, fontSize: 12, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 2),
                    Row(children: [
                      Flexible(
                        child: Text(
                          cart.totalGst > 0
                              ? 'Subtotal ${money(cart.subtotal).replaceAll('.00', '')} · GST ${money(cart.totalGst).replaceAll('.00', '')}'
                              : (cart.itemDiscount + cart.billDiscount + cart.loyaltyDiscount > 0 ? 'View breakdown' : 'Subtotal ${money(cart.subtotal).replaceAll('.00', '')}'),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: light, fontSize: 12, fontWeight: FontWeight.w600),
                        ),
                      ),
                      Icon(showDetails ? Icons.expand_more_rounded : Icons.expand_less_rounded, size: 16, color: light),
                    ]),
                  ]),
                ),
                Text(money(cart.total).replaceAll('.00', ''), style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w800, letterSpacing: -0.8)),
              ]),
            ),
            if (showDetails) ...[
              const SizedBox(height: 8),
              _row('Subtotal', money(cart.subtotal).replaceAll('.00', '')),
              if (cart.totalGst > 0) _row('Tax (GST)', money(cart.totalGst).replaceAll('.00', '')),
              if (cart.itemDiscount > 0) _row('Item Discounts', '-${money(cart.itemDiscount)}', color: AppColors.lime),
              if (cart.billDiscount > 0) _row('Bill Discount', '-${money(cart.billDiscount)}', color: AppColors.lime),
              if (cart.loyaltyDiscount > 0) _row('Loyalty Discount', '-${money(cart.loyaltyDiscount)}', color: AppColors.lime),
              if (cart.roundMode != 'none') _row('Round Off', _signed(cart.roundOff)),
            ],
            if (cart.advancePart > 0) ...[
              const SizedBox(height: 6),
              _row('From advance (${money(cart.advanceAvailable).replaceAll('.00', '')} available)', '-${money(cart.advancePart)}', color: AppColors.lime),
            ],
            if (!cart.isEmpty && cart.hasPaise) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(color: AppColors.navy, borderRadius: BorderRadius.circular(16)),
                child: Row(children: [
                  _roundOption('none', 'Exact', money(cart.total)),
                  const SizedBox(width: 4),
                  _roundOption('down', money(cart.roundedTotal('down')).replaceAll('.00', ''), _signed(cart.roundedTotal('down') - cart.total)),
                  const SizedBox(width: 4),
                  _roundOption('up', money(cart.roundedTotal('up')).replaceAll('.00', ''), _signed(cart.roundedTotal('up') - cart.total)),
                ]),
              ),
            ],
            if (!cart.isEmpty && !cart.isExpense) ...[
              const SizedBox(height: 10),
              Row(children: [
                _action(Icons.percent_rounded, cart.billDiscount > 0 ? 'Discount ✓' : 'Discount', () => editBillDiscount(context, cart), selected: cart.billDiscount > 0),
                if (showLoyalty) _action(Icons.stars_rounded, 'Points ${cart.customer!.loyaltyPoints.toStringAsFixed(0)}', () => _loyalty(context), selected: cart.loyaltyRedeem > 0),
                _action(Icons.pause_circle_outline_rounded, 'Hold', () => _saveWaiting(context)),
                if (showKot) _action(Icons.soup_kitchen_outlined, 'KOT', () => _kot(context)),
                if (cart.advanceAvailable > 0) _action(Icons.savings_outlined, 'Advance', () => cart.setUseAdvance(!cart.useAdvance), selected: cart.useAdvance),
                if (showCredit) _action(Icons.account_balance_wallet_outlined, 'Credit', () => cart.setOnCredit(!cart.onCredit), selected: cart.onCredit),
              ]),
            ],
            const SizedBox(height: 12),
            GreenButton(
              height: 54,
              label: cart.isExpense
                  ? 'Record Expense Voucher'
                  : cart.isEmpty
                      ? 'Proceed'
                      : cart.onCredit
                          ? 'Proceed on Credit · $payable'
                          : cart.advancePart > 0
                              ? (cart.toCollect > 0 ? 'Proceed · pay ${money(cart.toCollect).replaceAll('.00', '')}' : 'Proceed · from advance')
                              : 'Proceed · $payable',
              icon: cart.isExpense ? Icons.receipt_long_rounded : Icons.arrow_forward_rounded,
              busy: cart.busy,
              onPressed: () => _pay(context),
            ),
          ]),
        ),
      ]),
    );
  }
}

/// After checkout: build the bill PDF, then print and/or collect as chosen in the Proceed pop-up.
Future<void> finishBill(BuildContext context, Bill bill, Session session, BillAction action) async {
  final shop = session.shop!;
  if (shop.settings.whatsappCustomerShare && bill.customerContact != null && !bill.isExpense) {
    PrintService.shareBillWhatsApp(bill, shop);
  }
  final saved = bill.isPendingSync ? 'Saved offline – will sync' : (bill.isExpense ? 'Expense recorded' : 'Bill #${bill.billNo} saved');
  if (action == BillAction.saveOnly) return showSnack(context, '✅ $saved');
  final nav = Navigator.of(context, rootNavigator: true);
  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (_) => PopScope(
      canPop: false,
      child: AlertDialog(
        content: Row(children: [
          const SizedBox(width: 28, height: 28, child: CircularProgressIndicator(strokeWidth: 3)),
          const SizedBox(width: 18),
          Expanded(
            child: Text(
              action == BillAction.printAndCollect ? 'Printing & opening OnePe…' : (action.prints ? 'Printing bill…' : 'Opening OnePe…'),
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ]),
      ),
    ),
  );
  var errors = <String>[];
  try {
    final pdf = await PrintService.billPdf(bill, shop, branch: session.activeBranch);
    errors = await runBillAction(action, pdf, billNo: bill.billNo);
  } catch (e) {
    errors = ['$e'];
  } finally {
    nav.pop();
  }
  if (!context.mounted) return;
  if (errors.isEmpty) {
    showSnack(context, '✅ $saved${action.collects ? ' · sent to OnePe' : ''}');
  } else {
    showSnack(context, '$saved, but: ${errors.join('; ')}', error: true);
  }
}
