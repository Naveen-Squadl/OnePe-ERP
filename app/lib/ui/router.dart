import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../state/session.dart';
import 'screens/admin/admin_screen.dart';
import 'screens/bills/bills_screen.dart';
import 'screens/branches_screen.dart';
import 'screens/categories_screen.dart';
import 'screens/customers/customers_screen.dart';
import 'screens/dashboard_screen.dart';
import 'screens/login_screen.dart';
import 'screens/pos/pos_screen.dart';
import 'screens/products/products_screen.dart';
import 'screens/purchases/purchases_screen.dart';
import 'screens/reports/reports_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/splash_screen.dart';
import 'screens/stock/stock_screen.dart';
import 'screens/suppliers_screen.dart';
import 'screens/users_screen.dart';
import 'widgets/app_shell.dart';

GoRouter buildRouter(Session session) {
  String home() {
    final u = session.user!;
    if (u.isSuperAdmin) return '/admin';
    if (u.can('bills.create')) return '/pos';
    return navItems.firstWhere((n) => n.permission != null && u.can(n.permission!), orElse: () => navItems.first).path;
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
      if (loc == '/pos' && !session.can('bills.create')) return home();
      if (item?.permission != null && !session.can(item!.permission!)) return home();
      if (loc.startsWith('/admin') && !session.user!.isSuperAdmin) return home();
      return null;
    },
    routes: [
      GoRoute(path: '/', builder: (_, _) => const SplashScreen()),
      GoRoute(path: '/login', builder: (_, _) => const LoginScreen()),
      GoRoute(path: '/pos', builder: (_, _) => const PosScreen()),
      GoRoute(path: '/dashboard', builder: (_, _) => const DashboardScreen()),
      GoRoute(path: '/bills', builder: (_, _) => const BillsScreen()),
      GoRoute(path: '/products', builder: (_, _) => const ProductsScreen()),
      GoRoute(path: '/categories', builder: (_, _) => const CategoriesScreen()),
      GoRoute(path: '/customers', builder: (_, _) => const CustomersScreen()),
      GoRoute(path: '/suppliers', builder: (_, _) => const SuppliersScreen()),
      GoRoute(path: '/stock', builder: (_, _) => const StockScreen()),
      GoRoute(path: '/purchases', builder: (_, _) => const PurchasesScreen()),
      GoRoute(path: '/reports', builder: (_, _) => const ReportsScreen()),
      GoRoute(path: '/users', builder: (_, _) => const UsersScreen()),
      GoRoute(path: '/branches', builder: (_, _) => const BranchesScreen()),
      GoRoute(path: '/settings', builder: (_, _) => const SettingsScreen()),
      GoRoute(path: '/admin', builder: (_, _) => const AdminScreen()),
    ],
    errorBuilder: (_, s) => Scaffold(body: Center(child: Text('Page not found: ${s.uri}'))),
  );
}
