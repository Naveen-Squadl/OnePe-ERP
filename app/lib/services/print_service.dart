import 'dart:typed_data';

import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/api.dart';
import '../core/format.dart';
import '../models/models.dart';
import 'device_printer.dart';
import 'printer_config.dart';

/// Receipt / KOT / payment-receipt rendering. Every slip is built as a PDF and sent to the printer
/// chosen in Printer Settings ([PrinterConfig]): the terminal's in-device printer (Nexgo), a paired
/// Bluetooth printer, or the OS / browser print dialog.
class PrintService {
  /// Paper for slips that have no sheet layout (payment receipt).
  static PaperSize get _slipPaper => PrinterConfig.bill.slipPaper;

  /// Sends a finished PDF to [target] (default: the bill printer).
  static Future<void> output(Uint8List pdf, {required String name, required PaperSize paper, PrinterTarget? target}) async {
    target ??= PrinterConfig.bill;
    switch (target.type) {
      case PrinterType.device:
        await DevicePrinter.printInDevice(pdf);
      case PrinterType.bluetooth:
        final address = target.btAddress;
        if (address == null) throw 'Select a Bluetooth printer in Printer Settings';
        await DevicePrinter.printBluetooth(address, pdf, paper.dots);
      case PrinterType.system:
        await Printing.layoutPdf(name: name, format: paper.format, onLayout: (_) async => pdf);
    }
  }

  static String _rs(num v) => 'Rs. ${v.toStringAsFixed(2)}';

  /// Label on the left, value right-aligned; a long value wraps instead of running off the paper.
  static pw.Widget _row(String l, String r, {bool bold = false, double size = 8}) {
    final style = pw.TextStyle(fontSize: size, fontWeight: bold ? pw.FontWeight.bold : null);
    return pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
      pw.Text(l, style: style),
      pw.SizedBox(width: 6),
      pw.Expanded(child: pw.Text(r, textAlign: pw.TextAlign.right, style: style)),
    ]);
  }

  /// Dashed separator across the full paper width (any roll size).
  static pw.Widget _dash() => pw.Divider(height: 8, thickness: 0.8, color: PdfColors.black, borderStyle: pw.BorderStyle.dashed);

  static Future<pw.Document> receipt(Bill b, Shop shop, {Branch? branch, PaperSize? paper}) async {
    final s = shop.settings;
    paper ??= PrinterConfig.bill.paper;
    if (paper.isSheet) return _a4Invoice(b, shop, branch: branch, format: paper.format);
    final logo = s.showLogoAndShop ? await _logo(shop) : null;
    final doc = pw.Document();
    doc.addPage(pw.Page(
      pageFormat: paper.format.copyWith(marginLeft: 6, marginRight: 6, marginTop: 8, marginBottom: 8),
      build: (_) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          if (s.showLogoAndShop) ...[
            if (logo != null) pw.Center(child: pw.Image(logo, height: 42)),
            pw.Text(shop.name, textAlign: pw.TextAlign.center, style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
            if ((branch?.address ?? shop.address) != null)
              pw.Text((branch?.address ?? shop.address)!, textAlign: pw.TextAlign.center, style: const pw.TextStyle(fontSize: 7)),
            if ((branch?.contactNumber ?? shop.contactNumber) != null)
              pw.Text('Contact: ${branch?.contactNumber ?? shop.contactNumber}', textAlign: pw.TextAlign.center, style: const pw.TextStyle(fontSize: 7)),
            if (shop.gstNumber != null) pw.Text('GSTIN: ${shop.gstNumber}', textAlign: pw.TextAlign.center, style: const pw.TextStyle(fontSize: 7)),
          ],
          pw.SizedBox(height: 4),
          pw.Text('${b.isExpense ? 'EXPENSE VOUCHER' : 'TAX INVOICE'}${b.isCancelled ? ' - CANCELLED' : ''}',
              textAlign: pw.TextAlign.center, style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),
          _dash(),
          if (s.showBillDetails) ...[
            _row('Bill No:', b.billNo),
            _row('Date:', DateFormat('dd-MM-yyyy hh:mm a').format(b.billDate.toLocal())),
            if (branch != null) _row('Branch:', branch.name),
            if (b.tableName != null) _row('Table:', b.tableName!),
            if (b.customerName != null) _row('Customer:', b.customerName!),
            if (b.customerContact != null) _row('Contact:', b.customerContact!),
            _dash(),
          ],
          pw.Row(children: [
            pw.Expanded(flex: 5, child: pw.Text('Item', style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold))),
            pw.Expanded(flex: 2, child: pw.Text('Qty', textAlign: pw.TextAlign.right, style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold))),
            pw.Expanded(flex: 3, child: pw.Text('Price', textAlign: pw.TextAlign.right, style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold))),
            pw.Expanded(flex: 3, child: pw.Text('Total', textAlign: pw.TextAlign.right, style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold))),
          ]),
          _dash(),
          for (final i in b.items) ...[
            pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
              pw.Expanded(flex: 5, child: pw.Text(i.productName, style: const pw.TextStyle(fontSize: 8))),
              pw.Expanded(flex: 2, child: pw.Text(qty(i.quantity), textAlign: pw.TextAlign.right, style: const pw.TextStyle(fontSize: 8))),
              pw.Expanded(flex: 3, child: pw.Text(i.soldPrice.toStringAsFixed(2), textAlign: pw.TextAlign.right, style: const pw.TextStyle(fontSize: 8))),
              pw.Expanded(flex: 3, child: pw.Text(i.lineTotal.toStringAsFixed(2), textAlign: pw.TextAlign.right, style: const pw.TextStyle(fontSize: 8))),
            ]),
            if (i.discount > 0) pw.Text('  (Discount: -Rs. ${i.discount.toStringAsFixed(2)})', style: const pw.TextStyle(fontSize: 7)),
          ],
          _dash(),
          _row('Subtotal:', _rs(b.subtotal)),
          if (b.totalGst > 0) _row('Total GST:', _rs(b.totalGst)),
          if (b.discount > 0) _row('Bill Discount:', '-${_rs(b.discount)}'),
          if (b.loyaltyRedeemed > 0) _row('Points Redeemed:', '-${_rs(b.loyaltyRedeemed)}'),
          if (b.roundOff != 0) _row('Round Off:', '${b.roundOff > 0 ? '+' : '-'}${_rs(b.roundOff.abs())}'),
          _row('GRAND TOTAL:', _rs(b.total), bold: true, size: 10),
          _row('Payment:', b.paymentLabel),
          for (final (label, amt) in b.splitParts) _row('  $label:', _rs(amt)),
          if (b.received > 0) _row('Received:', _rs(b.received)),
          if (b.change > 0) _row('Change:', _rs(b.change)),
          if (s.showCustomerAccount && b.customerOpening != null) ...[
            _dash(),
            pw.Text('--- Customer Account ---', textAlign: pw.TextAlign.center, style: const pw.TextStyle(fontSize: 8)),
            _row('Opening Balance:', _rs(b.customerOpening!)),
            _row('Current Bill:', _rs(b.total)),
            _row('Received:', _rs(b.received - b.change)),
            _row('New Account Balance:', _rs(b.customerClosing ?? 0), bold: true),
            if (b.loyaltyEarned > 0) _row('Points Earned (This Bill):', b.loyaltyEarned.toStringAsFixed(0)),
          ],
          _dash(),
          if (b.userName != null) pw.Text('Billed by: ${b.userName}', textAlign: pw.TextAlign.center, style: const pw.TextStyle(fontSize: 7)),
          pw.Text(shop.thanksNote ?? 'Thank you for your business!', textAlign: pw.TextAlign.center, style: const pw.TextStyle(fontSize: 8)),
          if (b.isPendingSync) pw.Text('(Saved offline – will sync)', textAlign: pw.TextAlign.center, style: const pw.TextStyle(fontSize: 6)),
        ],
      ),
    ));
    return doc;
  }

  static Future<pw.ImageProvider?> _logo(Shop shop) async {
    final url = Api.mediaUrl(shop.logoUrl);
    if (url == null) return null;
    try {
      return await networkImage(url);
    } catch (_) {
      return null; // never block printing on a missing logo
    }
  }

  static Future<pw.Document> _a4Invoice(Bill b, Shop shop, {Branch? branch, PdfPageFormat format = PdfPageFormat.a4}) async {
    final logo = await _logo(shop);
    final doc = pw.Document();
    final upi = branch?.upiId ?? shop.upiId;
    final a5 = format == PdfPageFormat.a5;
    doc.addPage(pw.MultiPage(
      pageFormat: format,
      margin: pw.EdgeInsets.all(a5 ? 20 : 32),
      theme: pw.ThemeData.withFont().copyWith(defaultTextStyle: pw.TextStyle(fontSize: a5 ? 9 : 11)),
      build: (_) => [
        pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          pw.Expanded(
            child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
              if (logo != null) pw.Image(logo, height: 48),
              pw.Text(shop.name, style: pw.TextStyle(fontSize: a5 ? 16 : 20, fontWeight: pw.FontWeight.bold)),
              if (shop.address != null) pw.Text(shop.address!),
              if (shop.contactNumber != null) pw.Text('Phone: ${shop.contactNumber}'),
              if (shop.gstNumber != null) pw.Text('GSTIN: ${shop.gstNumber}'),
            ]),
          ),
          pw.SizedBox(width: 12),
          pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
            pw.Text(b.isCancelled ? 'TAX INVOICE - CANCELLED' : 'TAX INVOICE', style: pw.TextStyle(fontSize: a5 ? 13 : 16, fontWeight: pw.FontWeight.bold)),
            pw.Text('Invoice No: ${b.billNo}'),
            pw.Text('Date: ${dateTime(b.billDate)}'),
            if (branch != null) pw.Text('Branch: ${branch.name}'),
            pw.Text('Payment Mode: ${b.paymentLabel}${b.splitParts.isEmpty ? '' : ' (${b.splitParts.map((p) => '${p.$1} ${_rs(p.$2)}').join(' + ')})'}'),
          ]),
        ]),
        pw.SizedBox(height: 16),
        pw.Text('BILLED TO:', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
        pw.Text(b.customerName ?? 'Walk-in Customer'),
        if (b.customerContact != null) pw.Text(b.customerContact!),
        pw.SizedBox(height: 12),
        pw.TableHelper.fromTextArray(
          headers: ['#', 'Item Name / Description', 'HSN', 'Qty', 'Rate (Rs.)', 'GST %', 'Amount (Rs.)'],
          data: [
            for (final (n, i) in b.items.indexed)
              [n + 1, i.productName, i.hsnCode ?? '', qty(i.quantity), i.soldPrice.toStringAsFixed(2), i.gstPercent.toStringAsFixed(0), i.lineTotal.toStringAsFixed(2)],
          ],
          headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9),
          cellStyle: const pw.TextStyle(fontSize: 9),
          headerDecoration: const pw.BoxDecoration(color: PdfColors.grey200),
        ),
        pw.SizedBox(height: 12),
        pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          pw.Expanded(
            child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
              pw.Text('Amount in Words:', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
              pw.Text(amountInWords(b.total)),
              if (upi != null && b.total > b.received) ...[
                pw.SizedBox(height: 8),
                pw.Text('Scan to Pay via UPI'),
                pw.BarcodeWidget(
                  barcode: pw.Barcode.qrCode(),
                  data: 'upi://pay?pa=$upi&pn=${Uri.encodeComponent(shop.name)}&am=${(b.total - b.received).toStringAsFixed(2)}&cu=INR',
                  width: 90,
                  height: 90,
                ),
              ],
            ]),
          ),
          pw.SizedBox(width: 16),
          pw.SizedBox(
            width: a5 ? 170 : 220,
            child: pw.Column(children: [
              _row('Subtotal', _rs(b.subtotal), size: 10),
              _row('GST', _rs(b.totalGst), size: 10),
              if (b.discount > 0) _row('Discount', '-${_rs(b.discount)}', size: 10),
              if (b.loyaltyRedeemed > 0) _row('Points Discount', '-${_rs(b.loyaltyRedeemed)}', size: 10),
              if (b.roundOff != 0) _row('Round Off', '${b.roundOff > 0 ? '+' : '-'}${_rs(b.roundOff.abs())}', size: 10),
              pw.Divider(),
              _row('Grand Total', _rs(b.total), bold: true, size: 12),
              _row('Amount Received', _rs(b.received - b.change), size: 10),
              if (b.customerClosing != null) _row('Outstanding Account Balance', _rs(b.customerClosing!), size: 10),
            ]),
          ),
        ]),
        pw.SizedBox(height: 24),
        pw.Text('Terms: Goods once sold cannot be taken back.', style: const pw.TextStyle(fontSize: 9)),
        pw.Align(alignment: pw.Alignment.centerRight, child: pw.Text('Authorised Signatory')),
      ],
    ));
    return doc;
  }

  /// The customer bill as PDF bytes, laid out for the configured paper.
  static Future<Uint8List> billPdf(Bill b, Shop shop, {Branch? branch}) async => (await receipt(b, shop, branch: branch)).save();

  static Future<void> printBill(Bill b, Shop shop, {Branch? branch, Uint8List? pdf}) async {
    await output(pdf ?? await billPdf(b, shop, branch: branch), name: 'Bill_${b.billNo}', paper: PrinterConfig.bill.paper);
  }

  /// Kitchen order ticket on the KOT printer (the bill printer unless a kitchen printer is set).
  static Future<void> printKot(Map<String, dynamic> kot) async {
    final target = PrinterConfig.kot;
    await output(await kotPdf(kot, paper: target.slipPaper), name: 'KOT_${kot['billNo']}', paper: target.slipPaper, target: target);
  }

  static Future<Uint8List> kotPdf(Map<String, dynamic> kot, {PaperSize? paper}) {
    final doc = pw.Document();
    doc.addPage(pw.Page(
      pageFormat: (paper ?? PrinterConfig.kot.slipPaper).format.copyWith(marginLeft: 6, marginRight: 6),
      build: (_) => pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.stretch, children: [
        pw.Text('KITCHEN ORDER TICKET', textAlign: pw.TextAlign.center, style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10)),
        _dash(),
        _row('Token / Bill No:', '${kot['billNo']}', bold: true, size: 9),
        if (kot['tableName'] != null) _row('Table:', '${kot['tableName']}', bold: true, size: 9),
        _row('Time:', DateFormat('hh:mm a').format(DateTime.now())),
        _dash(),
        for (final i in (kot['items'] as List)) ...[
          _row('${i['productName']}', 'x ${qty(toDouble(i['quantity']))}', bold: true, size: 10),
          if (i['note'] != null) pw.Text('  NOTE: ${i['note']}', style: const pw.TextStyle(fontSize: 8)),
        ],
        _dash(),
      ]),
    ));
    return doc.save();
  }

  static Future<void> printPaymentReceipt(Map<String, dynamic> payment, Customer c, double opening, Shop shop) async {
    await output(await paymentReceiptPdf(payment, c, opening, shop), name: 'Payment_${payment['receiptNo']}', paper: _slipPaper);
  }

  static Future<Uint8List> paymentReceiptPdf(Map<String, dynamic> payment, Customer c, double opening, Shop shop, {PaperSize? paper}) {
    final doc = pw.Document();
    final amount = toDouble(payment['amount']);
    doc.addPage(pw.Page(
      pageFormat: (paper ?? _slipPaper).format.copyWith(marginLeft: 6, marginRight: 6),
      build: (_) => pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.stretch, children: [
        pw.Text(shop.name, textAlign: pw.TextAlign.center, style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 11)),
        pw.Text('PAYMENT RECEIPT', textAlign: pw.TextAlign.center, style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9)),
        _dash(),
        _row('Receipt:', '${payment['receiptNo']}'),
        _row('Date:', dateTime(toDate(payment['createdAt']) ?? DateTime.now())),
        _row('Customer:', c.name),
        _row('Mode:', '${payment['method']}'),
        _dash(),
        _row('Opening Balance:', _rs(opening)),
        _row('Amount Received:', _rs(amount), bold: true, size: 10),
        _row('Current Balance:', _rs(opening - amount), bold: true),
        _dash(),
        pw.Text('Thank you for your payment!', textAlign: pw.TextAlign.center, style: const pw.TextStyle(fontSize: 8)),
      ]),
    ));
    return doc.save();
  }

  /// Share a bill summary via WhatsApp (wa.me deep link).
  static Future<bool> shareBillWhatsApp(Bill b, Shop shop) async {
    final phone = (b.customerContact ?? '').replaceAll(RegExp(r'\D'), '');
    final buf = StringBuffer()
      ..writeln('*${shop.name.toUpperCase()}*')
      ..writeln('---\n*TAX INVOICE*')
      ..writeln('Bill No: #${b.billNo}')
      ..writeln('Date: ${dateTime(b.billDate)}')
      ..writeln('---');
    for (final i in b.items) {
      buf.writeln('${i.productName} x ${qty(i.quantity)}  _(Rs. ${i.lineTotal.toStringAsFixed(2)})_');
    }
    buf.writeln('---');
    if (b.discount > 0) buf.writeln('Discount: Rs. ${b.discount.toStringAsFixed(2)}');
    if (b.loyaltyRedeemed > 0) buf.writeln('Points Redeemed: Rs. ${b.loyaltyRedeemed.toStringAsFixed(2)}');
    if (b.roundOff != 0) buf.writeln('Round Off: ${b.roundOff > 0 ? '+' : '-'}Rs. ${b.roundOff.abs().toStringAsFixed(2)}');
    buf.writeln('*TOTAL: Rs. ${b.total.toStringAsFixed(2)}*');
    buf.writeln('Paid: Rs. ${(b.received - b.change).toStringAsFixed(2)}');
    if (b.customerClosing != null) {
      buf
        ..writeln('---\n*CUSTOMER ACCOUNT*')
        ..writeln('Prev. Outstanding: Rs. ${(b.customerOpening ?? 0).toStringAsFixed(2)}')
        ..writeln('Current Bill: Rs. ${b.total.toStringAsFixed(2)}')
        ..writeln('*Closing Balance: Rs. ${b.customerClosing!.toStringAsFixed(2)}*');
    }
    if (b.userName != null) buf.writeln('*Billed by: ${b.userName}*');
    buf.writeln('\n_${shop.thanksNote ?? 'Thank you!'}_');
    final to = phone.length == 10 ? '91$phone' : phone;
    final uri = Uri.parse('https://wa.me/$to?text=${Uri.encodeComponent(buf.toString())}');
    return launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  /// Barcode label (CODE 128) for a product – 50×25mm sticker.
  static Future<void> printBarcodeLabel({required String name, required String code, required double price, int copies = 1}) async {
    final doc = pw.Document();
    final format = const PdfPageFormat(50 * PdfPageFormat.mm, 25 * PdfPageFormat.mm, marginAll: 2 * PdfPageFormat.mm);
    for (var i = 0; i < copies; i++) {
      doc.addPage(pw.Page(
        pageFormat: format,
        build: (_) => pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.center, children: [
          pw.Text(name, maxLines: 1, style: pw.TextStyle(fontSize: 7, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 1),
          pw.Expanded(child: pw.BarcodeWidget(barcode: pw.Barcode.code128(), data: code, drawText: true, textStyle: const pw.TextStyle(fontSize: 6))),
          pw.Text('MRP / Price: Rs. ${price.toStringAsFixed(2)}', style: const pw.TextStyle(fontSize: 6)),
        ]),
      ));
    }
    await Printing.layoutPdf(name: 'Barcode_Labels_$code', format: format, onLayout: (_) => doc.save());
  }

  /// Generic tabular report → PDF (used by Reports & Analytics "Export PDF").
  static Future<void> exportTablePdf({
    required String title,
    required String subtitle,
    required List<String> headers,
    required List<List<Object?>> rows,
    List<List<String>> summary = const [],
  }) async {
    final doc = pw.Document();
    doc.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.a4.landscape,
      margin: const pw.EdgeInsets.all(24),
      build: (_) => [
        pw.Text(title, style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
        pw.Text(subtitle, style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700)),
        pw.SizedBox(height: 10),
        if (summary.isNotEmpty)
          pw.Wrap(spacing: 16, runSpacing: 4, children: [
            for (final s in summary) pw.Text('${s[0]}: ${s[1]}', style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
          ]),
        pw.SizedBox(height: 10),
        pw.TableHelper.fromTextArray(
          headers: headers,
          data: rows.map((r) => r.map((c) => c?.toString() ?? '').toList()).toList(),
          headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8),
          cellStyle: const pw.TextStyle(fontSize: 8),
          headerDecoration: const pw.BoxDecoration(color: PdfColors.grey200),
        ),
        pw.SizedBox(height: 8),
        pw.Text('Generated: ${dateTime(DateTime.now())}', style: const pw.TextStyle(fontSize: 7, color: PdfColors.grey600)),
      ],
    ));
    await Printing.sharePdf(bytes: await doc.save(), filename: '${title.replaceAll(' ', '_')}.pdf');
  }
}
