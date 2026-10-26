import '../core/format.dart';

typedef Json = Map<String, dynamic>;

class AppUser {
  final String id, name, email, role;
  final String? shopId, branchId;
  final List<String> permissions;
  AppUser.fromJson(Json j)
      : id = j['id'],
        name = j['name'],
        email = j['email'],
        role = j['role'],
        shopId = j['shopId'],
        branchId = j['branchId'],
        permissions = List<String>.from(j['permissions'] ?? const []);

  bool can(String p) => permissions.contains(p);
  bool get isSuperAdmin => role == 'SUPER_ADMIN';
  bool get isAdmin => role == 'ADMIN' || isSuperAdmin;
  bool get isAdminOrManager => isAdmin || role == 'MANAGER';
}

class ShopSettings {
  final Json raw;
  ShopSettings(this.raw);
  bool get gstInclusive => raw['gstInclusive'] == true;
  bool get enableKot => raw['enableKot'] == true;
  bool get enableLoyalty => raw['enableLoyaltyPoints'] == true;
  double get loyaltyRatio => toDouble(raw['loyaltyPointsRatio'] ?? 100);
  String get paperSize => raw['paperSize'] ?? '58mm';
  bool get showLogoAndShop => raw['showLogoAndShop'] != false;
  bool get showBillDetails => raw['showBillDetails'] != false;
  bool get showCustomerAccount => raw['showCustomerAccount'] != false;
  bool get whatsappCustomerShare => raw['whatsappCustomerShare'] == true;
  bool get enableFastPay => raw['enableFastPay'] != false;
  List<String> get storageLocations => List<String>.from(raw['storageLocations'] ?? const ['Showroom', 'Warehouse']);
  List<String> get tableNames => List<String>.from(raw['tableNames'] ?? const []);
}

class Shop {
  final String id, name, shopType, plan;
  final String? address, contactNumber, gstNumber, upiId, thanksNote, logoUrl;
  final DateTime? subscriptionExpiry;
  final ShopSettings settings;
  Shop.fromJson(Json j)
      : id = j['id'],
        name = j['name'],
        shopType = j['shopType'],
        plan = j['plan'],
        address = j['address'],
        contactNumber = j['contactNumber'],
        gstNumber = j['gstNumber'],
        upiId = j['upiId'],
        thanksNote = j['thanksNote'],
        logoUrl = j['logoUrl'],
        subscriptionExpiry = toDate(j['subscriptionExpiry']),
        settings = ShopSettings(Map<String, dynamic>.from(j['settings'] ?? {}));
  bool get isBakery => shopType == 'BAKERY';
}

class Branch {
  final String id, name, code;
  final String? address, contactNumber, upiId;
  final List<String> tableNames;
  final bool isMain, isActive;
  Branch.fromJson(Json j)
      : id = j['id'],
        name = j['name'],
        code = j['code'],
        address = j['address'],
        contactNumber = j['contactNumber'],
        upiId = j['upiId'],
        tableNames = List<String>.from(j['tableNames'] ?? const []),
        isMain = j['isMain'] == true,
        isActive = j['isActive'] != false;
}

class Category {
  final String id, name;
  final bool isStockCategory, isExpenseCategory;
  final int productCount;
  Category.fromJson(Json j)
      : id = j['id'],
        name = j['name'],
        isStockCategory = j['isStockCategory'] != false,
        isExpenseCategory = j['isExpenseCategory'] == true,
        productCount = (j['_count']?['products'] ?? 0) as int;
}

class Product {
  final Json raw;
  Product(this.raw);
  String get id => raw['id'];
  String get name => raw['name'];
  String? get categoryId => raw['categoryId'];
  String? get categoryName => raw['category']?['name'];
  bool get isExpense => raw['category']?['isExpenseCategory'] == true;
  String? get barcode => raw['barcode'];
  String? get hsnCode => raw['hsnCode'];
  String get unit => raw['unit'] ?? 'pcs';
  double get price => toDouble(raw['price'] ?? raw['basePrice']);
  double get basePrice => toDouble(raw['basePrice']);
  double? get maxPrice => raw['maxPrice'] == null ? null : toDouble(raw['maxPrice']);
  double? get purchasePrice => raw['purchasePrice'] == null ? null : toDouble(raw['purchasePrice']);
  double get gstPercent => toDouble(raw['gstPercent']);
  double get stock => toDouble(raw['stock']);
  bool get trackStock => raw['trackStock'] != false;
  bool get isLowStock => raw['isLowStock'] == true;
  bool get isPriceVariable => raw['isPriceVariable'] == true;
  bool get availableHere => raw['availableHere'] != false;
  String? get storageLocation => raw['storageLocation'];
  String? get imageUrl => raw['imageUrl'];
  double get lowStockThreshold => toDouble(raw['lowStockThreshold']);
  String get branchScope => raw['branchScope'] ?? 'ALL';
  List<Json> get branches => List<Json>.from(raw['branches'] ?? const []);
}

class Customer {
  final Json raw;
  Customer(this.raw);

  /// Mobile number picked while offline – not on the server yet; the bill creates it when it syncs.
  Customer.phoneOnly(String phone) : raw = {'phone': phone};
  bool get isNew => raw['id'] == null;
  String get id => raw['id'];
  /// Name is optional (any shop type) – falls back to the mobile number.
  String get name => (raw['name'] as String?)?.isNotEmpty == true ? raw['name'] : (raw['phone'] ?? 'Customer');
  String? get savedName => (raw['name'] as String?)?.isNotEmpty == true ? raw['name'] : null;
  String? get phone => raw['phone'];
  String? get address => raw['address'];
  String? get gstin => raw['gstin'];
  double get openingBalance => toDouble(raw['openingBalance']);
  double get balance => toDouble(raw['currentBalance']);
  double get loyaltyPoints => toDouble(raw['loyaltyPoints']);
  DateTime? get createdAt => toDate(raw['createdAt']);
}

class BillItem {
  final Json raw;
  BillItem(this.raw);
  String? get productId => raw['productId'];
  String get productName => raw['productName'];
  double get quantity => toDouble(raw['quantity']);
  double get soldPrice => toDouble(raw['soldPrice']);
  double get originalPrice => toDouble(raw['originalPrice']);
  double get discount => toDouble(raw['discount']);
  double get gstPercent => toDouble(raw['gstPercent']);
  double get gstAmount => toDouble(raw['gstAmount']);
  double get lineTotal => toDouble(raw['lineTotal']);
  String get priceType => raw['priceType'] ?? 'base';
  String? get note => raw['note'];
  double get kotPrintedQuantity => toDouble(raw['kotPrintedQuantity']);
  String? get hsnCode => raw['hsnCode'];
}

class Bill {
  final Json raw;
  Bill(this.raw);
  String get id => raw['id'];
  String get billNo => raw['billNo'];
  String get kind => raw['kind'] ?? 'SALE';
  String get status => raw['status'];
  bool get isWaiting => status == 'WAITING';
  bool get isExpense => kind == 'EXPENSE';
  String? get tableName => raw['tableName'];
  String? get customerId => raw['customerId'];
  String? get customerName => raw['customerName'];
  String? get customerContact => raw['customerContact'];
  double get subtotal => toDouble(raw['subtotal']);
  double get totalGst => toDouble(raw['totalGst']);
  double get itemDiscount => toDouble(raw['itemDiscount']);
  double get discount => toDouble(raw['discount']);
  double get loyaltyRedeemed => toDouble(raw['loyaltyPointsRedeemed']);
  double get loyaltyEarned => toDouble(raw['loyaltyPointsEarned']);
  double get roundOff => toDouble(raw['roundOff']);
  double get total => toDouble(raw['totalAmount']);
  double get received => toDouble(raw['receivedAmount']);

  /// Display name of the payment mode: Cash, UPI, Card, Split, Credit, OnePe…
  String get paymentLabel => switch (paymentMethod) {
    'ONEPE' => 'OnePe',
    'UPI' => 'UPI',
    final m => m[0] + m.substring(1).toLowerCase(),
  };

  /// Split payment parts, e.g. "Cash ₹100.00 + UPI ₹50.00" (empty unless the bill is SPLIT).
  List<(String, double)> get splitParts => paymentMethod != 'SPLIT'
      ? const []
      : [
          for (final (label, key) in const [('Cash', 'cashAmount'), ('UPI', 'upiAmount'), ('Card', 'cardAmount')])
            if (toDouble(raw[key]) > 0) (label, toDouble(raw[key])),
        ];
  double get change => toDouble(raw['changeAmount']);
  double? get customerOpening => raw['customerOpeningBal'] == null ? null : toDouble(raw['customerOpeningBal']);
  double? get customerClosing => raw['customerClosingBal'] == null ? null : toDouble(raw['customerClosingBal']);
  String get paymentMethod => raw['paymentMethod'] ?? 'CASH';
  String? get userName => raw['userName'];
  String? get note => raw['note'];
  DateTime get billDate => toDate(raw['billDate']) ?? DateTime.now();
  bool get isCancelled => raw['isCancelled'] == true;
  bool get isDeleted => raw['isDeleted'] == true;
  String? get cancelledBy => raw['cancelledByUserName'];
  String? get cancelReason => raw['cancelReason'];
  String? get deletedBy => raw['deletedByUserName'];
  List<BillItem> get items => (raw['items'] as List? ?? const []).map((e) => BillItem(Map<String, dynamic>.from(e))).toList();
  bool get isPendingSync => raw['_pending'] == true;
}
