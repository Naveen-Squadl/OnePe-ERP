import 'package:flutter/foundation.dart';
import 'package:pdf/pdf.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'device_printer.dart';

/// Where customer bills are printed. Stored per device (the printer is attached to this terminal),
/// not in the shop settings.
enum PrinterType {
  device('In-device printer', 'Built-in printer of the POS terminal (Nexgo N82)'),
  bluetooth('Bluetooth printer', 'Paired thermal / portable printer'),
  system('System print dialog', 'Browser or OS print dialog (PDF)');

  final String label;
  final String hint;
  const PrinterType(this.label, this.hint);
}

/// Paper sizes. [dots] is the raster width sent to thermal printers (8 dots/mm, 203 dpi).
enum PaperSize {
  in2('2"', '2 inch · 58mm roll', 384),
  in3('3"', '3 inch · 80mm roll', 576),
  in4('4"', '4 inch · 104mm roll', 832),
  a5('A5', 'A5 invoice', 1184),
  a4('A4', 'A4 tax invoice', 1680);

  final String label;
  final String hint;
  final int dots;
  const PaperSize(this.label, this.hint, this.dots);

  bool get isSheet => this == a4 || this == a5;

  PdfPageFormat get format => switch (this) {
    in2 => PdfPageFormat.roll57,
    in3 => PdfPageFormat.roll80,
    in4 => const PdfPageFormat(104 * PdfPageFormat.mm, double.infinity, marginAll: 2 * PdfPageFormat.mm),
    a5 => PdfPageFormat.a5,
    a4 => PdfPageFormat.a4,
  };
}

class PrinterConfig {
  static PrinterType type = PrinterType.system;
  static PaperSize paper = PaperSize.in2;
  static String? btName;
  static String? btAddress;

  /// Native printers exist only in the Android build.
  static bool get nativeAvailable => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  static List<PrinterType> get availableTypes => nativeAvailable ? PrinterType.values : const [PrinterType.system];

  /// The in-device printer only takes the 2" roll; Bluetooth and the print dialog take every size.
  static List<PaperSize> papersFor(PrinterType t) => t == PrinterType.device ? const [PaperSize.in2] : PaperSize.values;

  static Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    // First run: a Nexgo terminal defaults to its built-in printer, everything else to the print dialog.
    type =
        PrinterType.values.asNameMap()[p.getString('printer.type')] ??
        (nativeAvailable && await DevicePrinter.isNexgo() ? PrinterType.device : PrinterType.system);
    if (!availableTypes.contains(type)) type = PrinterType.system;
    paper = PaperSize.values.asNameMap()[p.getString('printer.paper')] ?? PaperSize.in2;
    if (!papersFor(type).contains(paper)) paper = papersFor(type).first;
    btName = p.getString('printer.btName');
    btAddress = p.getString('printer.btAddress');
  }

  static Future<void> save({PrinterType? type, PaperSize? paper, String? btName, String? btAddress}) async {
    if (type != null) PrinterConfig.type = type;
    if (paper != null) PrinterConfig.paper = paper;
    if (btAddress != null) {
      PrinterConfig.btName = btName;
      PrinterConfig.btAddress = btAddress;
    }
    if (!papersFor(PrinterConfig.type).contains(PrinterConfig.paper)) PrinterConfig.paper = papersFor(PrinterConfig.type).first;
    final p = await SharedPreferences.getInstance();
    await p.setString('printer.type', PrinterConfig.type.name);
    await p.setString('printer.paper', PrinterConfig.paper.name);
    if (PrinterConfig.btAddress != null) {
      await p.setString('printer.btAddress', PrinterConfig.btAddress!);
      await p.setString('printer.btName', PrinterConfig.btName ?? PrinterConfig.btAddress!);
    }
  }
}
