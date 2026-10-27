import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../state/session.dart';
import 'screens/admin/admin_screen.dart';
import 'screens/bills/bills_screen.dart';
import 'screens/customers/customers_screen.dart';
import 'screens/inventory/inventory_screen.dart';
import 'screens/login_screen.dart';
import 'screens/pos/pos_screen.dart';
import 'screens/purchases/purchases_screen.dart';
import 'screens/reports/reports_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/splash_screen.dart';
import 'widgets/app_shell.dart';

GoRouter buildRouter(Session session) {
  String home() {
    final u = session.user!;
    if (u.isSuperAdmin) return '/admin';
    if (u.can('bills.create')) return '/pos';
    return navItems.firstWhere((n) => n.permissions.isNotEmpty && n.allowedFor(session), orElse: () => navItems.first).path;
  }

  return GoRouter(
    refreshListenable: session,
    initialLocation: '/',
    redirect: (context, state) {
      final loc = state.matchedLocation;
      if (session.booting) return loc == '/' ? null : '/';
      if (!session.isLoggedIn) return loc == '/login' ? null : '/login';
      if (loc == '/' || loc == '/login') return home();
      final item = navItems.where((n) => n.path == loc).firstOrNull;
      if (item != null && !item.allowedFor(session)) return home();
      if (loc.startsWith('/admin') && !session.user!.isSuperAdmin) return home();
      return null;
    },
    routes: [
      GoRoute(path: '/', builder: (_, _) => const SplashScreen()),
      GoRoute(path: '/login', builder: (_, _) => const LoginScreen()),
      GoRoute(path: '/pos', builder: (_, _) => const PosScreen()),
      GoRoute(path: '/bills', builder: (_, _) => const BillsScreen()),
      GoRoute(path: '/inventory', builder: (_, s) => InventoryScreen(tab: s.uri.queryParameters['tab'])),
      GoRoute(path: '/purchases', builder: (_, s) => PurchasesScreen(tab: s.uri.queryParameters['tab'])),
      GoRoute(path: '/customers', builder: (_, _) => const CustomersScreen()),
      GoRoute(path: '/reports', builder: (_, s) => ReportsScreen(tab: s.uri.queryParameters['tab'])),
      GoRoute(
        path: '/settings',
        redirect: (_, s) => s.uri.queryParameters['section'] == 'printer' ? '/settings?tab=printer' : null,
        builder: (_, s) => SettingsScreen(tab: s.uri.queryParameters['tab']),
      ),
      // Old menu entries, now tabs of the areas above.
      for (final (from, to) in const [
        ('/products', '/inventory?tab=products'),
        ('/categories', '/inventory?tab=categories'),
        ('/stock', '/inventory?tab=batches'),
        ('/suppliers', '/purchases?tab=suppliers'),
        ('/dashboard', '/reports?tab=overview'),
        ('/users', '/settings?tab=users'),
        ('/branches', '/settings?tab=branches'),
      ])
        GoRoute(path: from, redirect: (_, _) => to),
      GoRoute(path: '/admin', builder: (_, _) => const AdminScreen()),
    ],
    errorBuilder: (_, s) => Scaffold(body: Center(child: Text('Page not found: ${s.uri}'))),
  );
}
