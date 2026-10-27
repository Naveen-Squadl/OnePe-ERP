import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../core/api.dart';
import '../models/models.dart';
import '../services/offline_queue.dart';

double _r2(double v) => (v * 100).roundToDouble() / 100;

class CartLine {
  final String? productId;
  final String name;
  final double gstPercent;
  final double basePrice;
  /// Only variable-price products, expense items and ad-hoc lines take an entered price; everything else
  /// is sold at the item price set by the admin (the counter can only give discounts).
  final bool priceEditable;
  double quantity;
  double price;
  String priceType; // base | custom
  double discount;
  String? note;
  double kotPrinted;

  CartLine({
    required this.productId,
    required this.name,
    required this.gstPercent,
    required this.basePrice,
    this.priceEditable = false,
    this.quantity = 1,
    required this.price,
    this.priceType = 'base',
    this.discount = 0,
    this.note,
    this.kotPrinted = 0,
  });

  factory CartLine.fromProduct(Product p) => CartLine(
        productId: p.id,
        name: p.name,
        gstPercent: p.gstPercent,
        basePrice: p.price,
        price: p.price,
        priceEditable: p.isPriceVariable || p.isExpense,
      );

  /// Mirrors billing.service computeLine on the server.
  ({double taxable, double gst, double total}) compute(bool gstInclusive) {
    final gross = _r2(quantity * price - discount);
    if (gstInclusive) {
      final taxable = _r2(gross / (1 + gstPercent / 100));
      return (taxable: taxable, gst: _r2(gross - taxable), total: gross);
    }
    final gst = _r2(gross * gstPercent / 100);
    return (taxable: gross, gst: gst, total: _r2(gross + gst));
  }

  Map<String, dynamic> toJson() => {
        if (productId != null) 'productId': productId,
        'productName': name,
        'quantity': quantity,
        'soldPrice': price,
        'priceType': priceType,
        'discount': discount,
        if (note != null && note!.isNotEmpty) 'note': note,
        'kotPrintedQuantity': kotPrinted,
      };
}

/// POS cart (POSProvider in the original). Server is authoritative for totals;
/// this mirrors the maths for a live preview.
class Cart extends ChangeNotifier {
  final _api = Api.instance;
  final lines = <CartLine>[];
  String kind = 'SALE'; // SALE | EXPENSE
  Customer? customer;
  String? customerPhone;
  String? customerName;
  String? tableName;
  String discountType = 'flat';
  double discountValue = 0;
  double loyaltyRedeem = 0;
  /// Customer-selected rounding of the payable amount: 'none' | 'down' | 'up'.
  String roundMode = 'none';
  /// Record the full amount on the customer's account instead of as paid.
  bool onCredit = false;

  /// Pay (part of) this sale from the customer's advance (their balance below zero).
  bool useAdvance = false;
  double get advanceAvailable => isExpense ? 0 : (customer?.advance ?? 0);
  double get advancePart => useAdvance ? _r2(advanceAvailable < payable ? advanceAvailable : payable) : 0;

  /// What is still to be paid at the counter after the advance.
  double get toCollect => _r2(payable - advancePart);
  String? note;
  DateTime? billDate;
  bool gstInclusive = false;

  /// Set when a waiting bill or completed bill is loaded.
  String? billId;
  String? billNo;
  bool busy = false;

  bool get isEmpty => lines.isEmpty;
  bool get isExpense => kind == 'EXPENSE';
  double get itemCount => lines.fold(0, (s, l) => s + l.quantity);

  double get subtotal => _r2(lines.fold(0, (s, l) => s + l.compute(gstInclusive).taxable));
  double get totalGst => _r2(lines.fold(0, (s, l) => s + l.compute(gstInclusive).gst));
  double get itemDiscount => _r2(lines.fold(0, (s, l) => s + l.discount));
  double get gross => _r2(subtotal + totalGst);
  double get billDiscount {
    final d = discountType == 'percent' ? _r2(gross * discountValue.clamp(0, 100) / 100) : discountValue;
    return d > gross ? gross : d;
  }

  double get loyaltyDiscount {
    final max = _r2(gross - billDiscount);
    return loyaltyRedeem > max ? max : loyaltyRedeem;
  }

  double get total => _r2(gross - billDiscount - loyaltyDiscount);

  /// Payable total after rounding to a whole rupee ('none' | 'down' | 'up') – mirrors computeTotals.
  double roundedTotal(String roundMode) => switch (roundMode) {
        'down' => (total + 1e-9).floorToDouble(),
        'up' => (total - 1e-9).ceilToDouble(),
        _ => total,
      };

  bool get hasPaise => (total - total.roundToDouble()).abs() > 0.005;
  double get payable => roundedTotal(roundMode);
  double get roundOff => _r2(payable - total);
  bool get hasCustomer => customer != null || (customerPhone?.length ?? 0) == 10;

  /// Adds a product. Throws a user-facing message if mixing sales & expense items.
  void add(Product p, {double qty = 1, double? price, String? priceType}) {
    if (lines.isNotEmpty && p.isExpense != isExpense) {
      throw p.isExpense
          ? 'Cannot mix expense items with customer sales. Please complete or clear current cart first.'
          : 'Cannot mix sales items with an expense voucher. Please complete or clear current cart first.';
    }
    kind = p.isExpense ? 'EXPENSE' : 'SALE';
    final existing = lines.where((l) => l.productId == p.id && price == null).firstOrNull;
    if (existing != null) {
      existing.quantity += qty;
    } else {
      final line = CartLine.fromProduct(p)..quantity = qty;
      if (price != null) {
        line.price = price;
        line.priceType = priceType ?? 'custom';
      }
      lines.add(line);
    }
    notifyListeners();
  }

  void setQty(CartLine l, double q) {
    if (q <= 0) {
      lines.remove(l);
    } else {
      l.quantity = q;
    }
    if (lines.isEmpty) kind = 'SALE';
    notifyListeners();
  }

  /// Entered price for variable-price / expense / ad-hoc lines (ignored by the server for other items).
  void setPrice(CartLine l, double price) {
    if (!l.priceEditable) return;
    l.price = price;
    l.priceType = 'custom';
    notifyListeners();
  }

  void setItemDiscount(CartLine l, double d) {
    l.discount = d;
    notifyListeners();
  }

  /// [c] may be a mobile-only customer picked offline ([Customer.isNew]) – created by the server on sync.
  void setCustomer(Customer? c, {String? phone, String? name}) {
    customer = c != null && c.isNew ? null : c;
    customerPhone = c?.phone ?? phone;
    customerName = c?.savedName ?? name;
    loyaltyRedeem = 0;
    if (!hasCustomer) onCredit = false;
    useAdvance = advanceAvailable > 0; // a customer with an advance pays from it by default
    notifyListeners();
  }

  void setTable(String? t) {
    tableName = t;
    notifyListeners();
  }

  void setDiscount(String type, double value) {
    discountType = type;
    discountValue = value;
    notifyListeners();
  }

  void setLoyalty(double points) {
    loyaltyRedeem = points;
    notifyListeners();
  }

  /// Tapping the selected option again clears it (back to the exact amount).
  void setRoundMode(String mode) {
    roundMode = roundMode == mode ? 'none' : mode;
    notifyListeners();
  }

  void setOnCredit(bool v) {
    onCredit = v;
    if (v) useAdvance = false;
    notifyListeners();
  }

  void setUseAdvance(bool v) {
    useAdvance = v && advanceAvailable > 0;
    if (useAdvance) onCredit = false;
    notifyListeners();
  }

  void setBillDate(DateTime? d) {
    billDate = d;
    notifyListeners();
  }

  void clear() {
    lines.clear();
    kind = 'SALE';
    customer = null;
    customerPhone = null;
    customerName = null;
    tableName = null;
    discountType = 'flat';
    discountValue = 0;
    loyaltyRedeem = 0;
    roundMode = 'none';
    onCredit = false;
    useAdvance = false;
    note = null;
    billDate = null;
    billId = null;
    billNo = null;
    notifyListeners();
  }

  /// Load a waiting order to continue it (same bill, paid through the normal Proceed flow), or with
  /// [asNew] copy a cancelled bill's items into a brand-new bill (completed bills are never edited).
  void loadBill(Bill b, {Customer? customerObj, bool asNew = false}) {
    clear();
    if (!asNew) {
      billId = b.id;
      billNo = b.billNo;
    }
    kind = b.kind;
    tableName = b.tableName;
    customer = customerObj;
    customerPhone = b.customerContact;
    customerName = b.customerName;
    note = b.note;
    if (b.discount > 0) {
      discountType = 'flat';
      discountValue = b.discount;
    }
    for (final i in b.items) {
      // Entered prices stay; other items go back to the item price (the server applies the current one).
      final entered = i.productId == null || i.priceType == 'custom';
      lines.add(CartLine(
        productId: i.productId,
        name: i.productName,
        gstPercent: i.gstPercent,
        basePrice: i.originalPrice,
        priceEditable: entered,
        quantity: i.quantity,
        price: entered ? i.soldPrice : i.originalPrice,
        priceType: entered ? 'custom' : 'base',
        discount: i.discount,
        note: i.note,
        kotPrinted: asNew ? 0 : i.kotPrintedQuantity,
      ));
    }
    notifyListeners();
  }

  Map<String, dynamic> _payload({
    required String status,
    String paymentMethod = 'CASH',
    double? received,
    double cash = 0,
    double upi = 0,
    double card = 0,
    bool giveChange = true,
  }) =>
      {
        'id': billId ?? const Uuid().v4(),
        'kind': kind,
        'status': status,
        if (tableName != null) 'tableName': tableName,
        if (customer != null) 'customerId': customer!.id,
        if (customer == null && customerPhone != null && customerPhone!.isNotEmpty) 'customerPhone': customerPhone,
        if (customerName != null) 'customerName': customerName,
        'items': lines.map((l) => l.toJson()).toList(),
        'discountType': discountType,
        'discountValue': discountValue,
        'loyaltyPointsToRedeem': loyaltyRedeem,
        'roundMode': roundMode,
        'paymentMethod': paymentMethod,
        'receivedAmount': ?received,
        'cashAmount': cash,
        'upiAmount': upi,
        'cardAmount': card,
        'giveChange': giveChange,
        if (note != null) 'note': note,
        if (billDate != null) 'billDate': billDate!.toIso8601String(),
      };

  /// Park the order (table / waiting list). Returns the saved bill.
  Future<Bill> saveWaiting() async {
    final payload = _payload(status: 'WAITING');
    final res = await _api.post('/bills/checkout', payload);
    final bill = Bill(Map<String, dynamic>.from(res));
    billId = bill.id;
    billNo = bill.billNo;
    notifyListeners();
    return bill;
  }

  /// Send unsent quantities to the kitchen. Parks the bill first if needed.
  Future<Map<String, dynamic>> sendKot() async {
    if (lines.every((l) => l.quantity <= l.kotPrinted)) throw 'All items already printed to KOT.';
    final bill = await saveWaiting();
    final kot = Map<String, dynamic>.from(await _api.post('/bills/${bill.id}/kot'));
    for (final l in lines) {
      l.kotPrinted = l.quantity;
    }
    notifyListeners();
    return kot;
  }

  /// Complete the sale. Goes straight to the server when it is reachable (giving up after
  /// [checkoutTimeout]); when the app already knows it is offline, or the request fails, the bill is
  /// saved to the offline queue at once – no waiting. A bill that reached the server after all is
  /// reported as a duplicate when the queue syncs (same bill id), so it is never billed twice.
  static const checkoutTimeout = Duration(seconds: 10);

  Future<Bill> checkout({
    required String paymentMethod,
    double? received,
    double cash = 0,
    double upi = 0,
    double card = 0,
    bool giveChange = true,
  }) async {
    if (busy) throw 'Checkout blocked: already processing';
    if (lines.isEmpty) throw 'Checkout failed: Cart is empty';
    busy = true;
    notifyListeners();
    final payload = _payload(
      status: 'COMPLETED',
      paymentMethod: paymentMethod,
      received: received,
      cash: cash,
      upi: upi,
      card: card,
      giveChange: giveChange,
    );
    final payable = this.payable;
    final advanceUsed = advancePart;
    try {
      if (!Api.online.value) throw ApiException(0, 'offline');
      final res = await _api.postWithin(checkoutTimeout, '/bills/checkout', payload);
      final bill = Bill(Map<String, dynamic>.from(res));
      clear();
      return bill;
    } on ApiException catch (e) {
      if (!e.isNetwork) rethrow;
      await OfflineQueue.add(payload);
      final local = Bill({
        ...payload,
        'billNo': billNo ?? 'OFFLINE',
        'totalAmount': payable,
        'roundOff': _r2(payable - total),
        'advanceUsed': advanceUsed,
        'subtotal': subtotal,
        'totalGst': totalGst,
        'discount': billDiscount,
        'receivedAmount': received ?? payable,
        'changeAmount': ((received ?? payable) - payable).clamp(0, double.infinity),
        'billDate': DateTime.now().toIso8601String(),
        'items': lines
            .map((l) => {
                  ...l.toJson(),
                  'originalPrice': l.basePrice,
                  'gstPercent': l.gstPercent,
                  'gstAmount': l.compute(gstInclusive).gst,
                  'lineTotal': l.compute(gstInclusive).total,
                })
            .toList(),
        '_pending': true,
      });
      clear();
      return local;
    } finally {
      busy = false;
      notifyListeners();
    }
  }
}
