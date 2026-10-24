import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

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
  final String? permission;
  const NavItem(this.label, this.icon, this.color, this.path, [this.permission]);
}

/// Drawer order mirrors the original "Navigation Menu".
const navItems = [
  NavItem('Dashboard', Icons.dashboard_rounded, Color(0xFF2F80ED), '/dashboard', 'reports.view'),
  NavItem('Manage Products', Icons.inventory_2_rounded, Color(0xFFF2994A), '/products', 'products.manage'),
  NavItem('Manage Categories', Icons.category_rounded, Color(0xFFE53958), '/categories', 'products.manage'),
  NavItem('Manage Customers', Icons.people_alt_rounded, Color(0xFF12A46A), '/customers', 'customers.manage'),
  NavItem('Manage Suppliers', Icons.local_shipping_rounded, Color(0xFF00A3BF), '/suppliers', 'suppliers.manage'),
  NavItem('Purchase History', Icons.add_shopping_cart_rounded, Color(0xFFEB5757), '/purchases', 'purchases.manage'),
  NavItem('Settings', Icons.settings_rounded, Color(0xFF5B6BD6), '/settings', 'settings.manage'),
  NavItem('Printer Settings', Icons.print_rounded, Color(0xFF12A46A), '/settings?section=printer', 'settings.manage'),
  NavItem('Sync Cloud Data', Icons.sync_rounded, Color(0xFF2D9CDB), '#sync'),
  NavItem('Bills History', Icons.receipt_long_rounded, Color(0xFF9B51E0), '/bills', 'bills.view'),
  NavItem('Reports & Analytics', Icons.bar_chart_rounded, Color(0xFFD4A017), '/reports', 'reports.view'),
  NavItem('Stock Management', Icons.fact_check_rounded, Color(0xFFE53958), '/stock', 'inventory.view'),
  NavItem('User Management', Icons.badge_rounded, Color(0xFF5B6BD6), '/users', 'users.manage'),
  NavItem('Branches', Icons.storefront_rounded, Color(0xFF2D9CDB), '/branches', 'branches.manage'),
];

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
          backgroundColor: Colors.white24,
          side: BorderSide.none,
          avatar: const Icon(Icons.storefront, size: 18, color: Colors.white),
          label: Text(s.activeBranch?.name ?? 'Branch', style: const TextStyle(color: Colors.white)),
        ),
      ),
    );
  }
}

Future<void> syncCloudData(BuildContext context) async {
  final n = await guard(context, OfflineQueue.flush);
  if (n == null || !context.mounted) return;
  await context.read<Catalog>().load();
  if (context.mounted) {
    showSnack(context, n > 0 ? '✅ Sync Complete: $n offline bill(s) uploaded! All data is up to date.' : '✅ Everything is up to date!');
  }
}

class AppDrawer extends StatelessWidget {
  const AppDrawer({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<Session>();
    final productCount = context.watch<Catalog>().products.length;
    final items = navItems.where((n) => n.permission == null || s.can(n.permission!)).toList();
    final exp = s.shop?.subscriptionExpiry;
    final expired = s.plan?['status'] == 'expired';
    return Drawer(
      width: 300,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.horizontal(right: Radius.circular(24))),
      child: Column(children: [
        // Gradient shop header
        Container(
          width: double.infinity,
          padding: EdgeInsets.fromLTRB(20, MediaQuery.of(context).padding.top + 28, 16, 18),
          decoration: const BoxDecoration(gradient: AppColors.headerGradient, borderRadius: BorderRadius.only(topRight: Radius.circular(24))),
          child: Row(children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(12)),
              clipBehavior: Clip.antiAlias,
              child: s.shop?.logoUrl != null ? ProductImage(url: s.shop!.logoUrl) : const Icon(Icons.storefront, color: Colors.white, size: 28),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(s.shop?.name ?? AppConfig.appName,
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 18), maxLines: 1, overflow: TextOverflow.ellipsis),
                const Text('OnePe POS System', style: TextStyle(color: Colors.white, fontSize: 12)),
                if (exp != null)
                  Container(
                    margin: const EdgeInsets.only(top: 4),
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(color: expired ? AppColors.danger : Colors.white24, borderRadius: BorderRadius.circular(4)),
                    child: Text('${expired ? 'Expired' : 'Exp'}: ${dateOnly(exp)}', style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w600)),
                  ),
              ]),
            ),
          ]),
        ),
        Expanded(
          child: ListView(padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10), children: [
            for (final n in items)
              ListTile(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                leading: IconTile(n.icon, n.color, size: 34),
                title: Text(n.label, style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 14)),
                trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                  if (n.path == '/products' && productCount > 0)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
                      decoration: BoxDecoration(color: AppColors.orange.withValues(alpha: .15), borderRadius: BorderRadius.circular(10)),
                      child: Text('$productCount', style: const TextStyle(color: AppColors.orange, fontSize: 11, fontWeight: FontWeight.w700)),
                    ),
                  const Icon(Icons.chevron_right, color: AppColors.muted),
                ]),
                onTap: () {
                  Navigator.pop(context);
                  if (n.path == '#sync') {
                    syncCloudData(context);
                  } else {
                    context.go(n.path);
                  }
                },
              ),
          ]),
        ),
        const Divider(height: 1),
        ListTile(
          contentPadding: const EdgeInsets.fromLTRB(16, 6, 8, 0),
          leading: const CircleAvatar(backgroundColor: Color(0xFFE8F0FE), child: Icon(Icons.person, color: AppColors.blue)),
          title: Text(s.user?.name ?? '', style: const TextStyle(fontWeight: FontWeight.w600)),
          subtitle: Text(s.user?.role.replaceAll('_', ' ') ?? '', style: const TextStyle(fontSize: 11)),
          trailing: IconButton(tooltip: 'Logout', onPressed: s.logout, icon: const Icon(Icons.logout, color: AppColors.danger)),
        ),
        Padding(
          padding: const EdgeInsets.only(bottom: 14, top: 4),
          child: Text('${AppConfig.appName} v${AppConfig.version}', style: const TextStyle(fontSize: 11, color: AppColors.muted)),
        ),
      ]),
    );
  }
}
