import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api.dart';
import '../../core/config.dart';
import '../../models/models.dart';
import '../../services/print_service.dart';
import '../../services/printer_config.dart';
import '../../state/session.dart';
import '../widgets/app_shell.dart';
import '../widgets/brand.dart';
import '../widgets/common.dart';
import '../widgets/form_dialog.dart';
import 'offline_data_tiles.dart';
import 'printer_settings.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late Shop shop = context.read<Session>().shop!;
  late final _name = TextEditingController(text: shop.name);
  late final _address = TextEditingController(text: shop.address);
  late final _contact = TextEditingController(text: shop.contactNumber);
  late final _gst = TextEditingController(text: shop.gstNumber);
  late final _upi = TextEditingController(text: shop.upiId);
  late final _thanks = TextEditingController(text: shop.thanksNote);
  late String _type = shop.shopType;
  late String? _logo = shop.logoUrl;
  late final Map<String, dynamic> _s = Map<String, dynamic>.from(shop.settings.raw);
  bool _busy = false;

  bool get _isAdmin => context.read<Session>().user!.isAdmin;

  Future<void> _save() async {
    if (_name.text.trim().isEmpty) return showSnack(context, 'Please enter shop name', error: true);
    setState(() => _busy = true);
    final body = {
      'name': _name.text.trim(),
      'address': _address.text.trim(),
      'contactNumber': _contact.text.trim(),
      'gstNumber': _gst.text.trim().isEmpty ? null : _gst.text.trim(),
      'thanksNote': _thanks.text.trim(),
      'logoUrl': _logo,
      if (_isAdmin) 'upiId': _upi.text.trim().isEmpty ? null : _upi.text.trim(),
      if (_isAdmin) 'shopType': _type,
      'settings': Map<String, dynamic>.from(_s)..removeWhere((k, _) => !_isAdmin && k == 'printerType'),
    };
    final r = await guard(context, () => Api.instance.put('/shop', body), success: 'Settings saved');
    if (r != null && mounted) await context.read<Session>().refresh();
    if (mounted) setState(() => _busy = false);
  }

  Widget _switch(String key, String title, {String? subtitle, bool def = false}) => SwitchListTile(
        title: Text(title),
        subtitle: subtitle == null ? null : Text(subtitle),
        value: _s[key] as bool? ?? def,
        onChanged: (v) => setState(() => _s[key] = v),
      );

  Widget _section(String title, List<Widget> children) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Card(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Padding(padding: const EdgeInsets.fromLTRB(16, 8, 16, 4), child: Text(title, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800))),
              ...children,
            ]),
          ),
        ),
      );

  Widget _field(TextEditingController c, String label, {bool enabled = true, String? helper}) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        child: TextField(controller: c, enabled: enabled, decoration: InputDecoration(labelText: label, helperText: helper)),
      );

  Future<void> _editList(String key, String title, String hint) async {
    final list = List<String>.from(_s[key] ?? const []);
    final r = await showFormDialog(context, title: title, fields: [FieldSpec('v', hint, initial: list.join(', '))]);
    if (r != null) setState(() => _s[key] = r['v']!.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList());
  }

  Future<void> _testPrint() async {
    final s = context.read<Session>();
    final test = Bill({
      'id': 'test', 'billNo': 'TEST-001', 'status': 'COMPLETED', 'billDate': DateTime.now().toIso8601String(),
      'items': [
        {'productName': 'Test Item 1', 'quantity': 1, 'soldPrice': 50, 'lineTotal': 50},
        {'productName': 'Test Item 2', 'quantity': 2, 'soldPrice': 25, 'lineTotal': 50},
      ],
      'subtotal': 100, 'totalAmount': 100, 'receivedAmount': 100, 'paymentMethod': 'CASH', 'userName': s.user?.name,
    });
    await guard(context, () => PrintService.printBill(test, Shop.fromJson({...s.shop!.toJsonForPreview(), 'settings': _s}), branch: s.activeBranch));
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<Session>();
    return AppScaffold(
      title: 'Settings',
      actions: [
        Padding(
          padding: const EdgeInsets.only(right: 8),
          child: IconButton(tooltip: 'Save Settings', onPressed: _busy ? null : _save, icon: const Icon(Icons.save)),
        ),
      ],
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 820),
          child: ListView(padding: const EdgeInsets.all(12), children: [
            _section('Shop Details', [
              Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: PhotoPickerBox(url: _logo, label: 'Add Logo', onChanged: (u) => setState(() => _logo = u))),
              _field(_name, 'Shop Name *'),
              _field(_address, 'Address'),
              _field(_contact, 'Contact Number'),
              _field(_gst, 'GSTIN'),
              _field(_upi, 'UPI ID (Optional)', enabled: _isAdmin, helper: _isAdmin ? 'For UPI QR code payments' : 'Only Admins can change UPI ID'),
              _field(_thanks, 'Thank-you note on receipts'),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                child: DropdownButtonFormField<String>(
                  initialValue: _type,
                  decoration: InputDecoration(labelText: 'Shop Type', helperText: _isAdmin ? 'Changing this adjusts the POS interface' : 'Only Admins can change Shop Type'),
                  items: const [
                    DropdownMenuItem(value: 'BAKERY', child: Text('Bakery / Restaurant')),
                    DropdownMenuItem(value: 'RETAIL', child: Text('Retail Store')),
                    DropdownMenuItem(value: 'DISTRIBUTOR', child: Text('Distributor')),
                  ],
                  onChanged: _isAdmin ? (v) => setState(() => _type = v!) : null,
                ),
              ),
            ]),
            _section('Billing', [
              _switch('gstInclusive', 'Prices include GST', subtitle: 'Off: GST is added on top of the item price'),
              _switch('enableLoyaltyPoints', 'Enable loyalty points'),
              if (_s['enableLoyaltyPoints'] == true)
                ListTile(
                  title: const Text('Loyalty ratio'),
                  subtitle: Text('Earn 1 point per ₹${_s['loyaltyPointsRatio'] ?? 100} spent (1 point = ₹1 on redemption)'),
                  trailing: const Icon(Icons.edit),
                  onTap: () async {
                    final v = await askNumber(context, 'Rupees per loyalty point', initial: (_s['loyaltyPointsRatio'] as num?)?.toDouble() ?? 100);
                    if (v != null && v > 0) setState(() => _s['loyaltyPointsRatio'] = v);
                  },
                ),
              _switch('enableKot', 'Enable Kitchen Order Tickets (KOT)', subtitle: 'Shows SEND TO KITCHEN in the cart'),
              _switch('whatsappCustomerShare', 'Auto-share bill on WhatsApp after checkout'),
              ListTile(
                title: const Text('Dine-In Tables'),
                subtitle: Text((_s['tableNames'] as List?)?.join(', ') ?? 'None (set per branch in Branches)'),
                trailing: const Icon(Icons.edit),
                onTap: () => _editList('tableNames', 'Dine-In Tables', 'T1, T2, T3, T4, T5, Parcel'),
              ),
              ListTile(
                title: const Text('Storage Locations'),
                subtitle: Text((_s['storageLocations'] as List?)?.join(', ') ?? 'Showroom, Warehouse'),
                trailing: const Icon(Icons.edit),
                onTap: () => _editList('storageLocations', 'Storage Locations', 'New Storage Location (e.g. Rack B, Godown 1)'),
              ),
            ]),
            _section('Payments', [
              SwitchListTile(
                title: const Text('OnePe payment collection'),
                subtitle: Text(
                  PrinterConfig.onePeCollect
                      ? 'Collect Payment and Print + Collect are shown after Proceed'
                      : 'Off – after Proceed, confirm the amount received by Cash, UPI, Card or Split',
                ),
                value: PrinterConfig.onePeCollect,
                onChanged: (v) async {
                  await PrinterConfig.setOnePeCollect(v);
                  if (mounted) setState(() {});
                },
              ),
            ]),
            _section('Printer Settings', [
              PrinterSettingsCard(onTestPrint: _testPrint),
              const Padding(padding: EdgeInsets.fromLTRB(16, 8, 16, 0), child: Text('Print Sections', style: TextStyle(fontWeight: FontWeight.w700))),
              _switch('showLogoAndShop', '1. Logo & Shop Details', subtitle: 'Shop name, address, contact, logo', def: true),
              _switch('showBillDetails', '2. Bill & Items Table', subtitle: 'Bill number, date, cashier, itemized prices', def: true),
              _switch('showCustomerAccount', '3. Customer Account & Balances', subtitle: 'Customer name, phone, opening/closing balance', def: true),
            ]),
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: FilledButton.icon(onPressed: _busy ? null : _save, icon: const Icon(Icons.save), label: const Text('SAVE SETTINGS')),
            ),
            _section('Offline Data & Backup', const [OfflineDataTiles()]),
            _section('Data & Account', [
              ListTile(
                leading: const Icon(Icons.password),
                title: const Text('Change password'),
                onTap: () async {
                  final r = await showFormDialog(context, title: 'Change password', fields: const [
                    FieldSpec('currentPassword', 'Current password', obscure: true, required: true),
                    FieldSpec('newPassword', 'New password (min 6)', obscure: true, required: true),
                  ]);
                  if (r != null && context.mounted) await guard(context, () => Api.instance.post('/auth/change-password', r), success: 'Password changed');
                },
              ),
              ListTile(
                leading: const Icon(Icons.workspace_premium_outlined),
                title: Text('Plan: ${shop.plan}'),
                subtitle: Text(session.plan == null ? 'No expiry' : 'Status: ${session.plan!['status']} • ${session.plan!['daysLeft']} days left'),
              ),
              ListTile(leading: const Icon(Icons.info_outline), title: Text('${AppConfig.appName} v${AppConfig.version}'), subtitle: Text('API: ${AppConfig.apiUrl}')),
            ]),
          ]),
        ),
      ),
    );
  }
}

extension on Shop {
  /// Minimal JSON for the print preview (settings overridden by the unsaved form state).
  Map<String, dynamic> toJsonForPreview() => {
        'id': id, 'name': name, 'shopType': shopType, 'plan': plan, 'address': address, 'contactNumber': contactNumber,
        'gstNumber': gstNumber, 'upiId': upiId, 'thanksNote': thanksNote,
      };
}
