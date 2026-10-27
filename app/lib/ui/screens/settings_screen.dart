import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api.dart';
import '../../core/config.dart';
import '../../core/features.dart';
import '../../core/theme.dart';
import '../../models/models.dart';
import '../../services/print_service.dart';
import '../../services/printer_config.dart';
import '../../state/catalog.dart';
import '../../state/session.dart';
import '../widgets/app_shell.dart';
import '../widgets/brand.dart';
import '../widgets/common.dart';
import '../widgets/form_dialog.dart';
import 'branches_screen.dart';
import 'offline_data_tiles.dart';
import 'printer_settings.dart';
import 'users_screen.dart';

/// Settings: Business | Features | Billing & Receipt (whole shop) | Printers (this device) | Users | Branches |
/// Device & Account (this device). Tabs by permission; business type and features are admin-only.
class SettingsScreen extends StatefulWidget {
  final String? tab;
  const SettingsScreen({super.key, this.tab});
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

  /// Feature switches the admin chose (missing = business-type default).
  late final Map<String, dynamic> _features = Map<String, dynamic>.from(_s['features'] ?? const {});
  bool _busy = false;

  bool get _isAdmin => context.read<Session>().user!.isAdmin;
  Map<String, bool> get _on => effectiveFeatures(_type, _features);

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
      'settings': {
        for (final k in const ['gstInclusive', 'showLogoAndShop', 'showBillDetails', 'showCustomerAccount', 'loyaltyPointsRatio', 'whatsappCustomerShare', 'storageLocations', 'tableNames', 'expiryReminderDays'])
          if (_s[k] != null) k: _s[k],
        if (_isAdmin) 'features': _features,
      },
    };
    final r = await guard(context, () => Api.instance.put('/shop', body), success: 'Settings saved');
    if (r != null && mounted) {
      await context.read<Session>().refresh();
      if (mounted) context.read<Catalog>().load();
    }
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

  Widget _page(String scope, List<Widget> children) => Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 820),
          child: ListView(padding: const EdgeInsets.all(12), children: [
            // Whole shop vs this device, so it is clear why a printer set on one counter doesn't change others.
            Padding(
              padding: const EdgeInsets.only(bottom: 10, left: 4),
              child: Row(children: [
                Icon(scope == 'device' ? Icons.phone_android_rounded : Icons.storefront_rounded, size: 16, color: AppColors.muted),
                const SizedBox(width: 6),
                Text(scope == 'device' ? 'Applies to this device only' : 'Applies to the whole shop (all devices)',
                    style: const TextStyle(fontSize: 12, color: AppColors.muted, fontWeight: FontWeight.w600)),
              ]),
            ),
            ...children,
          ]),
        ),
      );

  Widget get _saveButton => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: FilledButton.icon(onPressed: _busy ? null : _save, icon: const Icon(Icons.save), label: const Text('SAVE SETTINGS')),
      );

  Widget _business() => AppScaffold(
        title: 'Business',
        body: _page('shop', [
          _section('Business Type', [
            RadioGroup<String>(
              groupValue: _type,
              onChanged: (v) => setState(() {
                _type = v!;
                _features.clear(); // start from the new type's recommended features
              }),
              child: Column(children: [
                for (final t in businessTypes)
                  RadioListTile<String>(
                    value: t.id,
                    enabled: _isAdmin,
                    title: Text(t.label, style: const TextStyle(fontWeight: FontWeight.w700)),
                    subtitle: Text(t.hint),
                  ),
              ]),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text(_isAdmin ? 'Changing it resets Features to that type\'s recommended set.' : 'Only Admins can change the business type.',
                  style: const TextStyle(fontSize: 12, color: AppColors.muted)),
            ),
          ]),
          _section('Shop Details', [
            Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: PhotoPickerBox(url: _logo, label: 'Add Logo', onChanged: (u) => setState(() => _logo = u))),
            _field(_name, 'Shop Name *'),
            _field(_address, 'Address'),
            _field(_contact, 'Contact Number'),
            _field(_gst, 'GSTIN'),
            _field(_upi, 'UPI ID (Optional)', enabled: _isAdmin, helper: _isAdmin ? 'For UPI QR code payments' : 'Only Admins can change UPI ID'),
          ]),
          _saveButton,
        ]),
      );

  /// Extra options shown under a switched-on feature.
  List<Widget> _featureDetails(String key) => switch (key) {
        'tables' => [
            ListTile(
              contentPadding: const EdgeInsets.fromLTRB(32, 0, 16, 0),
              title: const Text('Dine-in tables'),
              subtitle: Text((_s['tableNames'] as List?)?.join(', ') ?? 'None (add per branch in Branches)'),
              trailing: const Icon(Icons.edit),
              onTap: () => _editList('tableNames', 'Dine-In Tables', 'T1, T2, T3, T4, T5, Parcel'),
            ),
          ],
        'loyalty' => [
            ListTile(
              contentPadding: const EdgeInsets.fromLTRB(32, 0, 16, 0),
              title: const Text('Loyalty ratio'),
              subtitle: Text('Earn 1 point per ₹${_s['loyaltyPointsRatio'] ?? 100} spent (1 point = ₹1 on redemption)'),
              trailing: const Icon(Icons.edit),
              onTap: () async {
                final v = await askNumber(context, 'Rupees per loyalty point', initial: (_s['loyaltyPointsRatio'] as num?)?.toDouble() ?? 100);
                if (v != null && v > 0) setState(() => _s['loyaltyPointsRatio'] = v);
              },
            ),
          ],
        'batches' => [
            ListTile(
              contentPadding: const EdgeInsets.fromLTRB(32, 0, 16, 0),
              title: const Text('Expiry reminder'),
              subtitle: Text('Batches expiring within ${_s['expiryReminderDays'] ?? 3} day(s) are flagged'),
              trailing: const Icon(Icons.edit),
              onTap: () async {
                final v = await askNumber(context, 'Expiry reminder (days)', initial: ((_s['expiryReminderDays'] as num?) ?? 3).toDouble());
                if (v != null && v >= 0) setState(() => _s['expiryReminderDays'] = v.toInt());
              },
            ),
          ],
        'locations' => [
            ListTile(
              contentPadding: const EdgeInsets.fromLTRB(32, 0, 16, 0),
              title: const Text('Locations'),
              subtitle: Text((_s['storageLocations'] as List?)?.join(', ') ?? 'Showroom, Warehouse'),
              trailing: const Icon(Icons.edit),
              onTap: () => _editList('storageLocations', 'Storage Locations', 'New Storage Location (e.g. Rack B, Godown 1)'),
            ),
          ],
        _ => const [],
      };

  Widget _featuresTab() {
    final on = _on;
    final available = featureInfo.where((f) => featureAvailable(_type, f.key)).toList();
    return AppScaffold(
      title: 'Features',
      body: _page('shop', [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 0, 4, 12),
          child: Text(
            '${businessTypeLabel(_type)}: switch on what this shop uses. Menus, the cart and forms show only what is on.'
            '${_isAdmin ? '' : ' Only Admins can change features.'}',
            style: const TextStyle(color: AppColors.muted),
          ),
        ),
        for (final group in const ['Selling', 'Inventory', 'Purchases'])
          if (available.any((f) => f.group == group))
            _section(group, [
              for (final f in available.where((f) => f.group == group)) ...[
                SwitchListTile(
                  title: Row(children: [
                    Flexible(child: Text(f.label)),
                    if (featureDefaults[_type]![f.key] == true) ...[
                      const SizedBox(width: 6),
                      const Pill('Recommended', AppColors.green),
                    ],
                  ]),
                  subtitle: Text(f.key == 'batches' && !on['stock']! ? 'Needs stock tracking' : f.description),
                  value: on[f.key]!,
                  onChanged: !_isAdmin || (f.key == 'batches' && !on['stock']!) ? null : (v) => setState(() => _features[f.key] = v),
                ),
                if (on[f.key]!) ..._featureDetails(f.key),
              ],
            ]),
        _saveButton,
      ]),
    );
  }

  Widget _billing() => AppScaffold(
        title: 'Billing & Receipt',
        body: _page('shop', [
          _section('Tax', [
            _switch('gstInclusive', 'Prices include GST', subtitle: 'Off: GST is added on top of the item price'),
          ]),
          _section('Receipt', [
            _field(_thanks, 'Thank-you note on receipts'),
            const Padding(padding: EdgeInsets.fromLTRB(16, 8, 16, 0), child: Text('Print sections', style: TextStyle(fontWeight: FontWeight.w700))),
            _switch('showLogoAndShop', '1. Logo & Shop Details', subtitle: 'Shop name, address, contact, logo', def: true),
            _switch('showBillDetails', '2. Bill & Items Table', subtitle: 'Bill number, date, cashier, itemized prices', def: true),
            _switch('showCustomerAccount', '3. Customer Account & Balances', subtitle: 'Customer name, phone, opening/closing balance', def: true),
          ]),
          _section('Sharing', [
            _switch('whatsappCustomerShare', 'Auto-share bill on WhatsApp after checkout', subtitle: 'For bills with a customer mobile number'),
          ]),
          _saveButton,
        ]),
      );

  Widget _printers() => AppScaffold(
        title: 'Printers',
        body: _page('device', [
          _section('Printers', [PrinterSettingsCard(onTestPrint: _testPrint, kot: shop.has('kot'))]),
        ]),
      );

  Widget _device(Session session) => AppScaffold(
        title: 'Device & Account',
        body: _page('device', [
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
          _section('Offline Data & Backup', const [OfflineDataTiles()]),
          _section('Account', [
            ListTile(
              leading: const Icon(Icons.password),
              title: const Text('Change password'),
              onTap: () async {
                final r = await showFormDialog(context, title: 'Change password', fields: const [
                  FieldSpec('currentPassword', 'Current password', obscure: true, required: true),
                  FieldSpec('newPassword', 'New password (min 6)', obscure: true, required: true),
                ]);
                if (r != null && mounted) await guard(context, () => Api.instance.post('/auth/change-password', r), success: 'Password changed');
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
      );

  @override
  Widget build(BuildContext context) {
    final session = context.watch<Session>();
    shop = session.shop ?? shop;
    return HubScaffold(
      title: 'Settings',
      initial: widget.tab,
      tabs: [
        HubTab('business', 'Business', (_) => _business(), permissions: const ['settings.manage']),
        HubTab('features', 'Features', (_) => _featuresTab(), permissions: const ['settings.manage']),
        HubTab('billing', 'Billing & Receipt', (_) => _billing(), permissions: const ['settings.manage']),
        HubTab('printers', 'Printers', (_) => _printers(), permissions: const ['settings.manage']),
        HubTab('users', 'Users', (_) => const UsersScreen(), permissions: const ['users.manage']),
        HubTab('branches', 'Branches', (_) => const BranchesScreen(), permissions: const ['branches.manage']),
        HubTab('device', 'Device & Account', (_) => _device(session)),
      ],
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
