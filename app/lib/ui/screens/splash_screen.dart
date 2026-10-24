import 'package:flutter/material.dart';

import '../../core/config.dart';
import '../../core/theme.dart';
import '../widgets/brand.dart';

class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: AppColors.blue,
        body: Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const BrandLogo(height: 56, lime: true),
            const SizedBox(height: 28),
            const SizedBox(width: 28, height: 28, child: CircularProgressIndicator(strokeWidth: 3, color: AppColors.lime)),
            const SizedBox(height: 14),
            const Text('Connecting to cloud...', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            Text('${AppConfig.appName} v${AppConfig.version}', style: const TextStyle(color: Color(0xFFC9D6EA), fontSize: 12)),
          ]),
        ),
      );
}
