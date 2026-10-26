import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/api.dart';
import 'user_activity.dart';

/// Product photo thumbnails kept on the device so the POS grid shows them offline.
/// Bounded: at most [maxPhotos] files (≈10–20 KB each, oldest-used dropped first), removed after
/// [keepFor] without use. Switchable per device (Settings → Offline data). Mobile only – the web
/// build relies on the browser's own cache.
class OfflinePhotos {
  OfflinePhotos._();
  static const _pref = 'offline.photos';
  static const _key = 'onepe_photos';
  static const maxPhotos = 400;
  static const keepFor = Duration(days: 60);

  static const supported = !kIsWeb;
  static bool enabled = true;
  static final cache = CacheManager(Config(_key, stalePeriod: keepFor, maxNrOfCacheObjects: maxPhotos));

  static bool get active => supported && enabled;

  static Future<void> load() async {
    enabled = (await SharedPreferences.getInstance()).getBool(_pref) ?? true;
  }

  static Future<void> setEnabled(bool v) async {
    enabled = v;
    await (await SharedPreferences.getInstance()).setBool(_pref, v);
    if (!v) await clear();
  }

  static Future<void> clear() async {
    if (supported) await cache.emptyCache();
  }

  /// Bytes used on the device.
  static Future<int> size() async {
    if (!supported) return 0;
    try {
      final dir = Directory('${(await getTemporaryDirectory()).path}/$_key');
      if (!await dir.exists()) return 0;
      return dir.listSync(recursive: true).whereType<File>().fold<int>(0, (s, f) => s + f.lengthSync());
    } catch (_) {
      return 0;
    }
  }

  /// Downloads missing thumbnails in the background (after the catalog loads, while the app is idle) so they
  /// are there offline.
  static Future<void> prefetch(Iterable<String?> imagePaths) async {
    if (!active || _prefetching) return;
    _prefetching = true;
    var failures = 0;
    try {
      for (final path in imagePaths.whereType<String>().toSet().take(maxPhotos)) {
        final url = Api.thumbUrl(path)!;
        await UserActivity.waitForIdle(); // never compete with the sale in progress
        try {
          if (await cache.getFileFromCache(url) == null) await cache.downloadFile(url);
          failures = 0;
        } catch (_) {
          // Missing photo → placeholder; several failures in a row → offline, try again next load.
          if (++failures >= 3) break;
        }
      }
    } finally {
      _prefetching = false;
    }
  }

  static bool _prefetching = false;
}
