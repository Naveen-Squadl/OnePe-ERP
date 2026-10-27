import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/config.dart';
import '../../core/format.dart';
import '../../core/theme.dart';
import '../../services/offline_queue.dart';
import '../../state/catalog.dart';
import '../../state/session.dart';
import 'brand.dart';
import 'common.dart';

class NavItem {
  final String label;
  final IconData icon;
  final Color color;
  final String path;

  /// Shown to users with any of these permissions (empty = everyone) …
  final List<String> permissions;

  /// … when this shop feature is on (Settings → Features).
  final String? feature;
  const NavItem(this.label, this.icon, this.color, this.path, [this.permissions = const [], this.feature]);

  bool allowedFor(Session s) => (permissions.isEmpty || permissions.any(s.can)) && (feature == null || (s.shop?.has(feature!) ?? false));
}

/// Main menu: one entry per area; related screens are tabs inside it ([HubScaffold]).
const navItems = [
  NavItem('New Bill', Icons.point_of_sale_rounded, AppColors.blue, '/pos', ['bills.create']),
  NavItem('Bills', Icons.receipt_long_rounded, AppColors.blue, '/bills', ['bills.view']),
  NavItem('Inventory', Icons.inventory_2_rounded, Color(0xFFE09A00), '/inventory', ['products.manage', 'products.edit_limited', 'inventory.view']),
  NavItem('Purchases', Icons.add_shopping_cart_rounded, AppColors.danger, '/purchases', ['purchases.manage', 'suppliers.manage'], 'purchases'),
  NavItem('Customers', Icons.people_alt_rounded, Color(0xFF3E7D16), '/customers', ['customers.manage']),
  NavItem('Reports', Icons.bar_chart_rounded, Color(0xFFE09A00), '/reports', ['reports.view']),
  NavItem('Settings', Icons.settings_rounded, AppColors.navy, '/settings', ['settings.manage', 'users.manage', 'branches.manage']),
];

/// One tab of a [HubScaffold]; hidden unless the user has any of [permissions] (empty = everyone) and the
/// shop has [feature] on.
class HubTab {
  final String id;
  final String label;
  final List<String> permissions;
  final String? feature;
  final WidgetBuilder builder;
  const HubTab(this.id, this.label, this.builder, {this.permissions = const [], this.feature});

  bool allowedFor(Session s) => (permissions.isEmpty || permissions.any(s.can)) && (feature == null || (s.shop?.has(feature!) ?? false));
}

/// A menu area with tabs (Inventory, Purchases, Reports, Settings). Screens inside a tab keep using
/// [AppScaffold], which then renders without its own app bar. [initial] is the tab id (`?tab=` in the URL);
/// [embedded] shows just the tab bar + content (Reports inside the POS).
class HubScaffold extends StatelessWidget {
  final String title;
  final List<HubTab> tabs;
  final String? initial;
  final bool embedded;

  /// App-bar buttons of the whole area, e.g. its History button.
  final List<Widget> actions;
  const HubScaffold({super.key, required this.title, required this.tabs, this.initial, this.embedded = false, this.actions = const []});

  @override
  Widget build(BuildContext context) {
    final session = context.watch<Session>();
    final visible = tabs.where((t) => t.allowedFor(session)).toList();
    if (visible.isEmpty) return AppScaffold(title: title, body: const EmptyState(icon: Icons.lock_outline, title: 'You do not have access to this area.'));
    final index = visible.indexWhere((t) => t.id == initial).clamp(0, visible.length - 1);
    final scroll = visible.length > 3;
    TabBar bar({Color? label, Color? unselected, Color? indicator}) => TabBar(
          isScrollable: scroll,
          tabAlignment: scroll ? TabAlignment.start : null,
          labelColor: label,
          unselectedLabelColor: unselected,
          indicatorColor: indicator,
          tabs: [for (final t in visible) Tab(text: t.label)],
        );
    final view = TabBarView(children: [for (final t in visible) _HubScope(child: Builder(builder: t.builder))]);
    return DefaultTabController(
      key: ValueKey('${visible.length}$initial'),
      length: visible.length,
      initialIndex: index,
      child: embedded
          ? Column(children: [
              Material(color: Colors.white, child: bar(label: AppColors.blue, unselected: AppColors.muted, indicator: AppColors.blue)),
              Expanded(child: view),
            ])
          : AppScaffold(title: title, actions: actions, bottom: bar(), body: view),
    );
  }
}

/// Marks content shown inside a [HubScaffold] tab.
class _HubScope extends InheritedWidget {
  const _HubScope({required super.child});
  static bool inside(BuildContext context) => context.getInheritedWidgetOfExactType<_HubScope>() != null;
  @override
  bool updateShouldNotify(_HubScope oldWidget) => false;
}

/// Inner-page scaffold: gradient bar, back arrow to the POS, optional actions/tabs.
class AppScaffold extends StatelessWidget {
  final String title;
  final Widget body;
  final List<Widget> actions;
  final Widget? fab;
  final PreferredSizeWidget? bottom;
  const AppScaffold({super.key, required this.title, required this.body, this.actions = const [], this.fab, this.bottom});

  @override
  Widget build(BuildContext context) {
    // Inside a hub tab: the hub owns the app bar; keep this screen's FAB and show its actions in a slim row.
    if (_HubScope.inside(context)) {
      return Scaffold(
        backgroundColor: Colors.transparent,
        floatingActionButton: fab,
        body: actions.isEmpty
            ? body
            : Column(children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 2, 8, 0),
                  child: IconTheme(data: const IconThemeData(color: AppColors.navy), child: Row(mainAxisAlignment: MainAxisAlignment.end, children: actions)),
                ),
                Expanded(child: body),
              ]),
      );
    }
    return Scaffold(
      appBar: GradientAppBar(
        title: Text(title),
        leading: IconButton(
          tooltip: 'Back',
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.canPop() ? context.pop() : context.go('/pos'),
        ),
        actions: [...actions, const BranchSwitcher(), const SizedBox(width: 4)],
        bottom: bottom,
      ),
      drawer: const AppDrawer(),
      body: body,
      floatingActionButton: fab,
    );
  }
}

class BranchSwitcher extends StatelessWidget {
  const BranchSwitcher({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<Session>();
    if (s.branches.length < 2 || !(s.user?.isAdminOrManager ?? false)) return const SizedBox.shrink();
    return PopupMenuButton<String>(
      tooltip: 'Switch outlet',
      onSelected: (id) => s.switchBranch(id),
      itemBuilder: (_) => [
        for (final b in s.branches) CheckedPopupMenuItem(value: b.id, checked: b.id == s.activeBranchId, child: Text(b.name)),
      ],
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Chip(
          backgroundColor: Colors.white.withValues(alpha: .14),
          side: BorderSide.none,
          avatar: const Icon(Icons.storefront, size: 18, color: AppColors.lime),
          label: Text(s.activeBranch?.name ?? 'Branch', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
        ),
      ),
    );
  }
}

Future<void> syncCloudData(BuildContext context) async {
  final r = await guard(context, OfflineQueue.flush);
  if (r == null || !context.mounted) return;
  await context.read<Catalog>().load();
  if (context.mounted) showSnack(context, '${r.remaining > 0 ? '⚠️' : '✅'} ${r.message}', error: r.remaining > 0);
}

/// Asks once per install (Android) for the backup folder that protects offline bills; Settings can change it later.
Future<void> offerBackupFolder(BuildContext context) async {
  if (!OfflineQueue.hasBackupFolder || OfflineQueue.folderAccess.value != null) return;
  final prefs = await SharedPreferences.getInstance();
  if (prefs.getBool('backupFolder.asked') == true) return;
  await prefs.setBool('backupFolder.asked', true);
  if (!context.mounted) return;
  final ok = await confirm(
    context,
    'Protect offline bills',
    'Bills made without internet are also saved in ${OfflineQueue.backupFolder}, so they survive reinstalling the app or clearing its data.\n\n'
        'Allow OnePe to use that folder: on the next screen tap "Use this folder", then "Allow".',
    ok: 'Choose folder',
  );
  if (ok && context.mounted) await chooseBackupFolder(context);
}

Future<void> chooseBackupFolder(BuildContext context) async {
  final folder = await guard(context, OfflineQueue.chooseBackupFolder);
  if (!context.mounted) return;
  if (folder == null) return showSnack(context, 'Backup folder not set – you can choose it later in Settings', error: true);
  final n = OfflineQueue.pending.value;
  showSnack(context, '✅ Offline bills are backed up in $folder${n > 0 ? ' • $n bill(s) waiting to upload' : ''}');
}

/// Logout, but first upload offline bills – and warn if some exist only on this device.
Future<void> safeLogout(BuildContext context) async {
  final session = context.read<Session>();
  if (OfflineQueue.pending.value > 0) {
    try {
      await OfflineQueue.flush();
    } catch (_) {
      // Still offline – warn below.
    }
    if (!context.mounted) return;
    final n = OfflineQueue.pending.value;
    if (n > 0 &&
        !await confirm(
          context,
          '$n bill(s) not uploaded',
          'These bills are saved only on this device${OfflineQueue.hasBackupFolder ? ' (backup copy in ${OfflineQueue.backupFolder})' : ''}. '
              'They upload automatically after the next login once the internet is back.\n\n'
              'Do NOT clear app data or uninstall the app until they are uploaded.',
          ok: 'Logout anyway',
          danger: true,
        )) {
      return;
    }
  }
  await session.logout();
}

class AppDrawer extends StatelessWidget {
  const AppDrawer({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<Session>();
    final productCount = context.watch<Catalog>().products.length;
    final items = navItems.where((n) => n.allowedFor(s)).toList();
    final exp = s.shop?.subscriptionExpiry;
    final expired = s.plan?['status'] == 'expired';
    return Drawer(
      width: 300,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.horizontal(right: Radius.circular(24))),
      child: Column(children: [
        // OnePe Blue shop header on the brand's lime stepped edge.
        Stack(children: [
          Positioned(
            left: 0,
            right: 110,
            bottom: 0,
            height: 40,
            child: Container(decoration: const BoxDecoration(color: AppColors.lime, borderRadius: BorderRadius.only(bottomRight: Radius.circular(22)))),
          ),
          Container(
            width: double.infinity,
            margin: const EdgeInsets.only(bottom: 7),
            padding: EdgeInsets.fromLTRB(20, MediaQuery.of(context).padding.top + 18, 16, 18),
            decoration: const BoxDecoration(
              color: AppColors.blue,
              borderRadius: BorderRadius.only(topRight: Radius.circular(24), bottomLeft: Radius.circular(22), bottomRight: Radius.circular(22)),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const BrandLogo(height: 30, lime: true),
              const SizedBox(height: 16),
              Row(children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(color: Colors.white.withValues(alpha: .14), borderRadius: BorderRadius.circular(14)),
                  clipBehavior: Clip.antiAlias,
                  child: s.shop?.logoUrl != null ? ProductImage(url: s.shop!.logoUrl) : const Icon(Icons.storefront, color: AppColors.lime, size: 24),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(s.shop?.name ?? AppConfig.appName,
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 17), maxLines: 1, overflow: TextOverflow.ellipsis),
                    Text(s.activeBranch?.name ?? 'POS System', style: const TextStyle(color: AppColors.lime, fontSize: 12, fontWeight: FontWeight.w600)),
                    if (exp != null)
                      Container(
                        margin: const EdgeInsets.only(top: 4),
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                        decoration: BoxDecoration(color: expired ? AppColors.coral : Colors.white.withValues(alpha: .16), borderRadius: BorderRadius.circular(6)),
                        child: Text('${expired ? 'Expired' : 'Exp'}: ${dateOnly(exp)}', style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w700)),
                      ),
                  ]),
                ),
              ]),
            ]),
          ),
        ]),
        Expanded(
          child: ListView(padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10), children: [
            for (final n in items)
              ListTile(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                leading: IconTile(n.icon, n.color, size: 34),
                title: Text(n.label, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                  if (n.path == '/inventory' && productCount > 0)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
                      decoration: BoxDecoration(color: AppColors.lime, borderRadius: BorderRadius.circular(8)),
                      child: Text('$productCount', style: const TextStyle(color: AppColors.navy, fontSize: 11, fontWeight: FontWeight.w800)),
                    ),
                  const Icon(Icons.chevron_right, color: AppColors.muted),
                ]),
                onTap: () {
                  Navigator.pop(context);
                  context.go(n.path);
                },
              ),
          ]),
        ),
        // Offline bills waiting to upload (only while there are some).
        ValueListenableBuilder<int>(
          valueListenable: OfflineQueue.pending,
          builder: (_, pending, _) => pending == 0
              ? const SizedBox.shrink()
              : ListTile(
                  tileColor: AppColors.amber.withValues(alpha: .18),
                  leading: const Icon(Icons.cloud_upload_outlined, color: AppColors.navy),
                  title: Text('$pending bill(s) waiting to sync', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                  subtitle: const Text('Tap to upload now', style: TextStyle(fontSize: 11)),
                  onTap: () {
                    Navigator.pop(context);
                    syncCloudData(context);
                  },
                ),
        ),
        const Divider(height: 1),
        ListTile(
          contentPadding: const EdgeInsets.fromLTRB(16, 6, 8, 0),
          leading: CircleAvatar(
            backgroundColor: AppColors.lime,
            child: Text(initials(s.user?.name), style: const TextStyle(color: AppColors.navy, fontWeight: FontWeight.w800, fontSize: 13)),
          ),
          title: Text(s.user?.name ?? '', style: const TextStyle(fontWeight: FontWeight.w700)),
          subtitle: Text(s.user?.role.replaceAll('_', ' ') ?? '', style: const TextStyle(fontSize: 11)),
          trailing: IconButton(tooltip: 'Logout', onPressed: () => safeLogout(context), icon: const Icon(Icons.logout, color: AppColors.danger)),
        ),
        Padding(
          padding: const EdgeInsets.only(bottom: 14, top: 4),
          child: Text('${AppConfig.appName} v${AppConfig.version}', style: const TextStyle(fontSize: 11, color: AppColors.muted)),
        ),
      ]),
    );
  }
}

/// Up to two initials for avatars ("Demo Owner" → "DO").
String initials(String? name) {
  final parts = (name ?? '').trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
  if (parts.isEmpty) return '?';
  return (parts.first[0] + (parts.length > 1 ? parts.last[0] : '')).toUpperCase();
}
