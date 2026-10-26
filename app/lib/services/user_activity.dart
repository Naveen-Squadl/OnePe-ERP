import 'package:flutter/services.dart';

/// When the user last touched the screen or typed (barcode scanners type too). Background work – uploading
/// old offline bills, downloading photos – waits until the app has been idle for [idleAfter], so it never
/// slows down the sale in progress.
class UserActivity {
  UserActivity._();
  static const idleAfter = Duration(seconds: 20);
  static DateTime _last = DateTime.now();

  /// Extra "busy" signal, e.g. items in the cart (set in main.dart).
  static bool Function() busy = () => false;

  static void touch() => _last = DateTime.now();
  static bool get isIdle => !busy() && DateTime.now().difference(_last) >= idleAfter;

  /// Starts listening to keyboard input; pointer input comes from the Listener in main.dart.
  static void start() => HardwareKeyboard.instance.addHandler((_) {
        touch();
        return false;
      });

  /// Completes once the app is idle.
  static Future<void> waitForIdle() async {
    while (!isIdle) {
      await Future<void>.delayed(const Duration(seconds: 5));
    }
  }
}
