import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'core/config.dart';
import 'core/theme.dart';
import 'services/offline_photos.dart';
import 'services/offline_queue.dart';
import 'services/printer_config.dart';
import 'services/user_activity.dart';
import 'state/cart.dart';
import 'state/catalog.dart';
import 'state/session.dart';
import 'ui/router.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  PrinterConfig.load();
  final cart = Cart();
  // A sale in progress counts as activity: old offline bills upload only when the cart is empty and idle.
  UserActivity.busy = () => cart.lines.isNotEmpty || cart.busy;
  UserActivity.start();
  OfflineQueue.start();
  OfflinePhotos.load();
  final session = Session()..restore();
  runApp(MultiProvider(
    providers: [
      ChangeNotifierProvider.value(value: session),
      ChangeNotifierProvider(create: (_) => Catalog()),
      ChangeNotifierProvider.value(value: cart),
    ],
    child: Listener(behavior: HitTestBehavior.translucent, onPointerDown: (_) => UserActivity.touch(), child: OnePeApp(session: session)),
  ));
}

class OnePeApp extends StatefulWidget {
  final Session session;
  const OnePeApp({super.key, required this.session});

  @override
  State<OnePeApp> createState() => _OnePeAppState();
}

class _OnePeAppState extends State<OnePeApp> {
  late final router = buildRouter(widget.session);

  @override
  Widget build(BuildContext context) => MaterialApp.router(
        title: AppConfig.appName,
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light(),
        routerConfig: router,
      );
}
