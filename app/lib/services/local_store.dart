import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Device storage for data too big for SharedPreferences (the offline catalog): files in the app's
/// support folder on Android / iOS / desktop, browser storage (via SharedPreferences) on the web.
/// Everything here is a cache – losing it only means the next load has to come from the server.
class LocalStore {
  LocalStore._();
  static const _prefix = 'store.';

  static Future<File> _file(String name) async => File('${(await getApplicationSupportDirectory()).path}/$name');

  static Future<String?> read(String name) async {
    try {
      if (kIsWeb) return (await SharedPreferences.getInstance()).getString('$_prefix$name');
      final f = await _file(name);
      return await f.exists() ? await f.readAsString() : null;
    } catch (_) {
      return null;
    }
  }

  static Future<void> write(String name, String data) async {
    try {
      if (kIsWeb) {
        await (await SharedPreferences.getInstance()).setString('$_prefix$name', data);
      } else {
        // Write-then-rename so a crash mid-write never leaves a half file.
        final f = await _file(name);
        final tmp = File('${f.path}.tmp');
        await tmp.writeAsString(data, flush: true);
        await tmp.rename(f.path);
      }
    } catch (_) {
      // Full disk / browser quota: keep working without the cache.
    }
  }

  /// Bytes used by the stored files whose name starts with [prefix].
  static Future<int> size(String prefix) async {
    try {
      if (kIsWeb) {
        final p = await SharedPreferences.getInstance();
        return p.getKeys().where((k) => k.startsWith('$_prefix$prefix')).fold<int>(0, (s, k) => s + (p.getString(k)?.length ?? 0));
      }
      final dir = await getApplicationSupportDirectory();
      var total = 0;
      for (final f in dir.listSync().whereType<File>()) {
        if (f.uri.pathSegments.last.startsWith(prefix)) total += f.lengthSync();
      }
      return total;
    } catch (_) {
      return 0;
    }
  }

  /// Deletes the stored files whose name starts with [prefix].
  static Future<void> clear(String prefix) async {
    try {
      if (kIsWeb) {
        final p = await SharedPreferences.getInstance();
        for (final k in p.getKeys().where((k) => k.startsWith('$_prefix$prefix')).toList()) {
          await p.remove(k);
        }
        return;
      }
      final dir = await getApplicationSupportDirectory();
      for (final f in dir.listSync().whereType<File>()) {
        if (f.uri.pathSegments.last.startsWith(prefix)) await f.delete();
      }
    } catch (_) {
      // Nothing to clear.
    }
  }
}
