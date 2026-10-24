import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../core/api.dart';

/// Bills checked out while offline. Each payload already carries its client UUID,
/// so pushing is idempotent on the server.
class OfflineQueue {
  static const _key = 'pending_bills';

  static Future<List<Map<String, dynamic>>> all() async {
    final prefs = await SharedPreferences.getInstance();
    return (prefs.getStringList(_key) ?? []).map((s) => Map<String, dynamic>.from(jsonDecode(s))).toList();
  }

  static Future<void> add(Map<String, dynamic> payload) async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_key) ?? [];
    list.removeWhere((s) => jsonDecode(s)['id'] == payload['id']);
    list.add(jsonEncode(payload));
    await prefs.setStringList(_key, list);
  }

  /// Push pending bills. Returns number synced; failed bills stay queued.
  static Future<int> flush() async {
    final pending = await all();
    if (pending.isEmpty) return 0;
    final res = await Api.instance.post('/sync/push', {'bills': pending});
    final ok = <String>{
      for (final r in (res['results'] as List))
        if (r['ok'] == true) r['id'] as String,
    };
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_key, pending.where((p) => !ok.contains(p['id'])).map(jsonEncode).toList());
    return ok.length;
  }
}
