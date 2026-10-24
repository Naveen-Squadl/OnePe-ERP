import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'core/config.dart';
import 'core/theme.dart';
import 'services/printer_config.dart';
import 'state/cart.dart';
import 'state/catalog.dart';
import 'state/session.dart';
import 'ui/router.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  PrinterConfig.load();
  final session = Session()..restore();
  runApp(MultiProvider(
    providers: [
      ChangeNotifierProvider.value(value: session),
      ChangeNotifierProvider(create: (_) => Catalog()),
      ChangeNotifierProvider(create: (_) => Cart()),
    ],
    child: OnePeApp(session: session),
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
