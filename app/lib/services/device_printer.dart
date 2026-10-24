import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

/// Bridge to the Android side (MainActivity → PrinterChannel): Nexgo in-device printer,
/// Bluetooth ESC/POS printers and PDF → bitmap rendering.
class DevicePrinter {
  static const _ch = MethodChannel('onepe/printer');

  static Future<String> _call(String method, [Map<String, Object?>? args]) async {
    try {
      return await _ch.invokeMethod<String>(method, args) ?? 'ok';
    } on PlatformException catch (e) {
      throw e.message ?? e.code;
    } on MissingPluginException {
      throw 'Printing on this device needs the Android app';
    }
  }

  /// True on Nexgo terminals (built-in printer available).
  static Future<bool> isNexgo() async {
    try {
      return await _ch.invokeMethod<bool>('isNexgo') ?? false;
    } on Object {
      return false;
    }
  }

  /// Prints a PDF on the terminal's built-in printer (Nexgo N82, 2" roll / 384 dots).
  static Future<void> printInDevice(Uint8List pdf) => _call('printNexgo', {'pdf': pdf, 'width': 384});

  /// Prints a PDF as an ESC/POS raster image on a paired Bluetooth printer.
  static Future<void> printBluetooth(String address, Uint8List pdf, int widthDots) =>
      _call('printBluetooth', {'address': address, 'pdf': pdf, 'width': widthDots});

  /// Paired (bonded) Bluetooth devices as {name, address}.
  static Future<List<Map<String, String>>> pairedPrinters() async {
    try {
      final list = await _ch.invokeListMethod<Map>('pairedDevices') ?? const [];
      return [for (final m in list) m.map((k, v) => MapEntry('$k', '$v'))];
    } on PlatformException catch (e) {
      throw e.message ?? e.code;
    } on MissingPluginException {
      throw 'Bluetooth printers need the Android app';
    }
  }

  /// PNG pages of the PDF scaled to [width] px (what the OnePe app shows / prints).
  static Future<List<Uint8List>> renderPages(Uint8List pdf, int width) async {
    try {
      return await _ch.invokeListMethod<Uint8List>('renderPdf', {'pdf': pdf, 'width': width}) ?? const [];
    } on Object {
      return const []; // web / iOS: the OnePe app only gets the PDF
    }
  }
}

/// Hands the bill to the OnePe payment app running on the same terminal. It listens on
/// http://127.0.0.1:8080/ and takes the bill as multipart form data (`pdf`, plus rendered `images`).
class OnePePay {
  static final endpoint = Uri.parse('http://127.0.0.1:8080/');

  static Future<void> collect(Uint8List pdf, {required String billNo}) async {
    final images = await DevicePrinter.renderPages(pdf, 384);
    final req = http.MultipartRequest('POST', endpoint)
      ..files.add(http.MultipartFile.fromBytes('pdf', pdf, filename: 'Bill_$billNo.pdf', contentType: MediaType('application', 'pdf')));
    for (final (i, img) in images.indexed) {
      req.files.add(http.MultipartFile.fromBytes('images', img, filename: 'bill_page_${i + 1}.png', contentType: MediaType('image', 'png')));
    }
    final http.Response res;
    try {
      res = await http.Response.fromStream(await req.send().timeout(const Duration(seconds: 20)));
    } on Object {
      throw 'OnePe app not installed or not configured properly.';
    }
    if (res.statusCode >= 300) throw 'OnePe app error (${res.statusCode})';
    if (res.body.toLowerCase().contains('txn in progress')) {
      throw 'A transaction is already in progress. QR was not generated for this bill.';
    }
  }
}
