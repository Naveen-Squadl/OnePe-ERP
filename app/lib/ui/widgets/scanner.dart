import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

/// Full-screen camera barcode / QR scanner. Returns the first code read.
Future<String?> scanBarcode(BuildContext context) => Navigator.of(context).push<String>(
      MaterialPageRoute(fullscreenDialog: true, builder: (_) => const _ScannerPage()),
    );

class _ScannerPage extends StatefulWidget {
  const _ScannerPage();
  @override
  State<_ScannerPage> createState() => _ScannerPageState();
}

class _ScannerPageState extends State<_ScannerPage> {
  final _ctrl = MobileScannerController();
  final _manual = TextEditingController();
  bool _done = false;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _finish(String code) {
    if (_done || code.isEmpty) return;
    _done = true;
    Navigator.pop(context, code);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: const Text('Scan QR / Barcode'),
          actions: [
            IconButton(tooltip: 'Toggle Flashlight', onPressed: () => _ctrl.toggleTorch(), icon: const Icon(Icons.flash_on)),
            IconButton(tooltip: 'Switch Camera', onPressed: () => _ctrl.switchCamera(), icon: const Icon(Icons.cameraswitch)),
          ],
        ),
        body: Column(children: [
          Expanded(
            child: MobileScanner(
              controller: _ctrl,
              onDetect: (c) {
                final v = c.barcodes.firstOrNull?.rawValue;
                if (v != null) _finish(v);
              },
              errorBuilder: (_, e) => Center(child: Text('Camera unavailable: ${e.errorCode.name}\nType the code below.', textAlign: TextAlign.center)),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              controller: _manual,
              decoration: InputDecoration(
                labelText: 'Type Barcode / Product Code',
                suffixIcon: IconButton(icon: const Icon(Icons.check), onPressed: () => _finish(_manual.text.trim())),
              ),
              onSubmitted: (v) => _finish(v.trim()),
            ),
          ),
        ]),
      );
}
