import 'package:flutter/material.dart';

import '../../core/config.dart';

class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
        body: Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.storefront_rounded, size: 96, color: Theme.of(context).colorScheme.primary),
            const SizedBox(height: 16),
            const CircularProgressIndicator(),
            const SizedBox(height: 12),
            const Text('Connecting to cloud...'),
            const SizedBox(height: 8),
            Text('${AppConfig.appName} v${AppConfig.version}', style: Theme.of(context).textTheme.bodySmall),
          ]),
        ),
      );
}
