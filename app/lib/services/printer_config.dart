import 'package:flutter/foundation.dart';
import 'package:pdf/pdf.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'device_printer.dart';

/// Where customer bills are printed. Stored per device (the printer is attached to this terminal),
/// not in the shop settings.
enum PrinterType {
  device('Nexgo N82 Printer', 'Built-in printer of the Nexgo N82 terminal'),
  bluetooth('Bluetooth printer', 'Paired thermal / portable printer'),
  system('System print dialog', 'Browser, AirPrint or Android print dialog (PDF)');

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

/// One configured printer (the bill printer or the kitchen / KOT printer), stored under [key] in
/// SharedPreferences.
class PrinterTarget {
  final String key;

  /// Bill printers also take A5 / A4 sheets; KOT printers are rolls only.
  final bool sheets;
  PrinterType type = PrinterType.system;
  PaperSize paper = PaperSize.in2;
  String? btName;
  String? btAddress;
  PrinterTarget(this.key, {required this.sheets});

  /// Nexgo N82 takes the 2" roll only; Bluetooth and the print dialog take every size.
  List<PaperSize> get papers => type == PrinterType.device
      ? const [PaperSize.in2]
      : [for (final p in PaperSize.values) if (sheets || !p.isSheet) p];

  /// Paper for slips without a sheet layout (KOT, payment receipt).
  PaperSize get slipPaper => paper.isSheet ? PaperSize.in3 : paper;

  /// Short name shown on buttons, e.g. "Nexgo N82 Printer" or the Bluetooth device name.
  String get displayName => switch (type) {
    PrinterType.device => type.label,
    PrinterType.bluetooth => btName ?? type.label,
    PrinterType.system => 'Print dialog',
  };

  void _load(SharedPreferences p, PrinterType fallback) {
    type = PrinterType.values.asNameMap()[p.getString('$key.type')] ?? fallback;
    if (!PrinterConfig.availableTypes.contains(type)) type = PrinterType.system;
    paper = PaperSize.values.asNameMap()[p.getString('$key.paper')] ?? PaperSize.in2;
    if (!papers.contains(paper)) paper = papers.first;
    btName = p.getString('$key.btName');
    btAddress = p.getString('$key.btAddress');
  }

  Future<void> save({PrinterType? type, PaperSize? paper, String? btName, String? btAddress}) async {
    if (type != null) this.type = type;
    if (paper != null) this.paper = paper;
    if (btAddress != null) {
      this.btName = btName;
      this.btAddress = btAddress;
    }
    if (!papers.contains(this.paper)) this.paper = papers.first;
    final p = await SharedPreferences.getInstance();
    await p.setString('$key.type', this.type.name);
    await p.setString('$key.paper', this.paper.name);
    if (this.btAddress != null) {
      await p.setString('$key.btAddress', this.btAddress!);
      await p.setString('$key.btName', this.btName ?? this.btAddress!);
    }
  }
}

/// Printers of this device (per terminal, not shop settings).
class PrinterConfig {
  static final bill = PrinterTarget('printer', sheets: true);
  static final kitchen = PrinterTarget('kotPrinter', sheets: false);

  /// KOTs print on the bill printer unless a separate kitchen printer is set up.
  static bool kotSameAsBill = true;
  static PrinterTarget get kot => kotSameAsBill ? bill : kitchen;

  /// Native printers exist only in the Android build.
  static bool get nativeAvailable => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  static List<PrinterType> get availableTypes => nativeAvailable ? PrinterType.values : const [PrinterType.system];

  /// Why a printer type can't be used here (null when it can).
  static String? unavailableReason(PrinterType t) {
    if (availableTypes.contains(t)) return null;
    final ios = !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;
    return switch (t) {
      PrinterType.device => 'Only in the app installed on the Nexgo N82',
      PrinterType.bluetooth => ios ? 'Not supported on iPhone / iPad – use the print dialog (AirPrint)' : 'Not supported in the browser – use the Android app',
      PrinterType.system => null,
    };
  }

  static Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    // First run: a Nexgo terminal defaults to its built-in printer, everything else to the print dialog.
    final fallback = nativeAvailable && await DevicePrinter.isNexgo() ? PrinterType.device : PrinterType.system;
    bill._load(p, fallback);
    kitchen._load(p, PrinterType.system);
    kotSameAsBill = p.getBool('kotPrinter.sameAsBill') ?? true;
  }

  static Future<void> setKotSameAsBill(bool v) async {
    kotSameAsBill = v;
    await (await SharedPreferences.getInstance()).setBool('kotPrinter.sameAsBill', v);
  }
}
