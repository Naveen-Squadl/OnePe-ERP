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
  final double? maxPrice;
  double quantity;
  double price;
  String priceType; // base | last | max | custom
  double discount;
  String? note;
  double kotPrinted;

  CartLine({
    required this.productId,
    required this.name,
    required this.gstPercent,
    required this.basePrice,
    this.maxPrice,
    this.quantity = 1,
    required this.price,
    this.priceType = 'base',
    this.discount = 0,
    this.note,
    this.kotPrinted = 0,
  });

  factory CartLine.fromProduct(Product p, {String priceOption = 'base'}) {
    final usesMax = priceOption == 'max' && p.maxPrice != null;
    return CartLine(
      productId: p.id,
      name: p.name,
      gstPercent: p.gstPercent,
      basePrice: p.price,
      maxPrice: p.maxPrice,
      price: usesMax ? p.maxPrice! : p.price,
      priceType: usesMax ? 'max' : (priceOption == 'last' ? 'last' : 'base'),
    );
  }

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
  String? note;
  DateTime? billDate;
  bool gstInclusive = false;
  String defaultPriceOption = 'base';

  /// Set when a waiting bill or completed bill is loaded.
  String? billId;
  String? billNo;
  bool editingCompleted = false;
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
      final line = CartLine.fromProduct(p, priceOption: defaultPriceOption)..quantity = qty;
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

  void setPrice(CartLine l, double price, String type) {
    l.price = price;
    l.priceType = type;
    notifyListeners();
  }

  void setItemDiscount(CartLine l, double d) {
    l.discount = d;
    notifyListeners();
  }

  void setCustomer(Customer? c, {String? phone, String? name}) {
    customer = c;
    customerPhone = c?.phone ?? phone;
    customerName = c?.name ?? name;
    loyaltyRedeem = 0;
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
    note = null;
    billDate = null;
    billId = null;
    billNo = null;
    editingCompleted = false;
    notifyListeners();
  }

  /// Load a waiting bill (to continue) or a completed bill (to edit — server reverts on checkout).
  void loadBill(Bill b, {Customer? customerObj}) {
    clear();
    billId = b.id;
    billNo = b.billNo;
    editingCompleted = !b.isWaiting;
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
      lines.add(CartLine(
        productId: i.productId,
        name: i.productName,
        gstPercent: i.gstPercent,
        basePrice: i.originalPrice,
        quantity: i.quantity,
        price: i.soldPrice,
        priceType: i.priceType == 'last' ? 'custom' : i.priceType,
        discount: i.discount,
        note: i.note,
        kotPrinted: i.kotPrintedQuantity,
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
        'editing': editingCompleted,
        if (tableName != null) 'tableName': tableName,
        if (customer != null) 'customerId': customer!.id,
        if (customer == null && customerPhone != null && customerPhone!.isNotEmpty) 'customerPhone': customerPhone,
        if (customerName != null) 'customerName': customerName,
        'items': lines.map((l) => l.toJson()).toList(),
        'discountType': discountType,
        'discountValue': discountValue,
        'loyaltyPointsToRedeem': loyaltyRedeem,
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

  /// Complete the sale. Falls back to the offline queue on network failure.
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
    try {
      final res = await _api.post('/bills/checkout', payload);
      final bill = Bill(Map<String, dynamic>.from(res));
      clear();
      return bill;
    } on ApiException catch (e) {
      if (!e.isNetwork) rethrow;
      await OfflineQueue.add(payload);
      final local = Bill({
        ...payload,
        'billNo': billNo ?? 'OFFLINE',
        'totalAmount': total,
        'subtotal': subtotal,
        'totalGst': totalGst,
        'discount': billDiscount,
        'receivedAmount': received ?? total,
        'changeAmount': ((received ?? total) - total).clamp(0, double.infinity),
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
