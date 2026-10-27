import 'package:intl/intl.dart';

final _inr = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 2);
final _qty = NumberFormat('#,##0.###', 'en_IN');

String money(num? v) => _inr.format(v ?? 0);
String qty(num? v) => _qty.format(v ?? 0);
String dateTime(DateTime d) => DateFormat('dd MMM yyyy, hh:mm a').format(d.toLocal());
String dateOnly(DateTime d) => DateFormat('dd MMM yyyy').format(d.toLocal());
String isoDate(DateTime d) => DateFormat('yyyy-MM-dd').format(d);

double toDouble(dynamic v) => v == null ? 0 : (v is num ? v.toDouble() : double.tryParse(v.toString()) ?? 0);
DateTime? toDate(dynamic v) => v == null ? null : DateTime.tryParse(v.toString());

/// Customer balance in plain words: above zero the customer owes the shop ("₹250 due"), below zero the shop
/// holds the customer's money ("₹100 advance"), otherwise "Settled". Never shown as a negative number.
String balanceText(double v) => v > 0.009 ? '${money(v)} due' : v < -0.009 ? '${money(-v)} advance' : 'Settled';

/// Supplier balance in plain words: above zero the shop owes the supplier ("You owe ₹500"), below zero the shop
/// has paid in advance ("₹200 advance paid"), otherwise "Settled".
String supplierBalanceText(double v) => v > 0.009 ? 'You owe ${money(v)}' : v < -0.009 ? '${money(-v)} advance paid' : 'Settled';

/// "Rupees ... Only" (Indian numbering: Lakh / Crore) for A4 invoices.
String amountInWords(num amount) {
  const ones = ['', 'One', 'Two', 'Three', 'Four', 'Five', 'Six', 'Seven', 'Eight', 'Nine', 'Ten', 'Eleven', 'Twelve',
    'Thirteen', 'Fourteen', 'Fifteen', 'Sixteen', 'Seventeen', 'Eighteen', 'Nineteen'];
  const tens = ['', '', 'Twenty', 'Thirty', 'Forty', 'Fifty', 'Sixty', 'Seventy', 'Eighty', 'Ninety'];
  String two(int n) => n < 20 ? ones[n] : '${tens[n ~/ 10]}${n % 10 > 0 ? ' ${ones[n % 10]}' : ''}';
  String three(int n) => n >= 100 ? '${ones[n ~/ 100]} Hundred${n % 100 > 0 ? ' and ${two(n % 100)}' : ''}' : two(n);
  var n = amount.floor();
  if (n == 0) return 'Zero Rupees Only';
  final parts = <String>[];
  if (n >= 10000000) {
    parts.add('${three(n ~/ 10000000)} Crore');
    n %= 10000000;
  }
  if (n >= 100000) {
    parts.add('${two(n ~/ 100000)} Lakh');
    n %= 100000;
  }
  if (n >= 1000) {
    parts.add('${two(n ~/ 1000)} Thousand');
    n %= 1000;
  }
  if (n > 0) parts.add(three(n));
  return '${parts.join(' ')} Rupees Only';
}
