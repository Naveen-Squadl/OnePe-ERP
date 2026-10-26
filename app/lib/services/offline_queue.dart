import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/api.dart';
import 'user_activity.dart';

/// Outcome of one upload of the offline queue.
class SyncResult {
  final int uploaded;
  final int alreadyOnServer;
  final int remaining;
  final String? error;
  const SyncResult({this.uploaded = 0, this.alreadyOnServer = 0, this.remaining = 0, this.error});

  String get message {
    final parts = [
      if (uploaded > 0) '$uploaded offline bill(s) uploaded',
      if (alreadyOnServer > 0) '$alreadyOnServer already on server',
      if (remaining > 0) '$remaining still waiting${error == null ? '' : ' – $error'}',
    ];
    return parts.isEmpty ? 'Everything is up to date!' : parts.join(' • ');
  }
}

/// Bills checked out while offline. Each bill carries its client UUID, so pushing is idempotent on the
/// server (re-pushing a bill that already exists just reports it as a duplicate).
///
/// Safety nets so these bills are not lost:
/// - auto-sync every 30 s while bills are pending, on app resume, after login and when the server is reachable
///   again – but only while the app is idle ([UserActivity]), in small batches that stop as soon as the user
///   is active again, so old bills never slow down the current sale (new bills go straight to the server);
/// - on Android every pending bill is also written to `Download/OnePe/OfflineBills/bill_<id>.json`, which
///   survives "Clear storage" and uninstall. Once the user grants that folder ([chooseBackupFolder], asked
///   once per install) the app reads it at start, re-queues bills found there and deletes each file when its
///   bill is on the server – also files left by an earlier install. Without the grant, Settings → Import
///   offline bills re-queues picked files.
///
/// Queue entries: `{shopId, branchId, queuedAt, bill, error?, mirrored?}`.
class OfflineQueue {
  OfflineQueue._();
  static const _key = 'pending_bills';
  static const _backup = MethodChannel('onepe/backup');
  static const backupFolder = 'Download/OnePe/OfflineBills';

  /// Number of bills waiting to be uploaded (drives the sync badges).
  static final pending = ValueNotifier<int>(0);

  /// Shop of the signed-in user. Bills of another shop stay queued until that shop signs in again.
  static String? shopId;

  static Timer? _timer;
  static Timer? _ping;
  static AppLifecycleListener? _lifecycle;
  static Future<SyncResult>? _running;
  static Future<void> _tail = Future.value();

  /// Pending bills are also written to [backupFolder] (Android only).
  static bool get hasBackupFolder => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  /// Folder the app has full access to (null: not chosen yet / declined; Android only).
  static final folderAccess = ValueNotifier<String?>(null);
  static String _id(Map<String, dynamic> e) => e['bill']['id'] as String;
  static String _file(String id) => 'bill_$id.json';

  /// Starts auto-sync (call once at app start).
  static void start() {
    _timer ??= Timer.periodic(const Duration(seconds: 30), (_) => syncQuietly());
    // While offline, check every 10 s whether the server is back (cheap request, also when the user is busy).
    _ping ??= Timer.periodic(const Duration(seconds: 10), (_) {
      if (!Api.online.value) Api.instance.ping();
    });
    Api.online.addListener(() {
      if (Api.online.value) syncQuietly();
    });
    _lifecycle ??= AppLifecycleListener(onResume: syncQuietly);
    _startup();
  }

  static Future<void> _startup() async {
    if (hasBackupFolder) {
      try {
        folderAccess.value = await _backup.invokeMethod<String>('status');
        await recoverFromFolder();
      } catch (_) {
        // No backup folder support on this device.
      }
    }
    await syncQuietly();
  }

  /// Asks the user once for the backup folder (folder chooser / storage permission), then recovers bills from it.
  /// Returns the folder name, or null if declined.
  static Future<String?> chooseBackupFolder() async {
    if (!hasBackupFolder) return null;
    final folder = await _backup.invokeMethod<String>('pickFolder');
    folderAccess.value = folder ?? folderAccess.value;
    if (folder != null) {
      await _update((l) {
        for (final e in l) {
          e.remove('mirrored'); // write them into the chosen folder too
        }
      });
      await recoverFromFolder();
      unawaited(syncQuietly());
    }
    return folder;
  }

  /// Re-queues bills found in the backup folder that are not in the queue (after reinstall / "Clear storage").
  /// Returns how many were added; they upload with the next sync and their files are deleted afterwards.
  static Future<int> recoverFromFolder() async {
    if (folderAccess.value == null) return 0;
    final files = await _backup.invokeListMethod<String>('list') ?? [];
    return files.isEmpty ? 0 : _add(_parse(files));
  }

  static Future<List<Map<String, dynamic>>> all() async {
    final prefs = await SharedPreferences.getInstance();
    final list = [for (final s in prefs.getStringList(_key) ?? <String>[]) _entry(jsonDecode(s))];
    pending.value = list.length;
    return list;
  }

  static Map<String, dynamic> _entry(dynamic raw) {
    final m = Map<String, dynamic>.from(raw as Map);
    return m['bill'] is Map ? (m..['bill'] = Map<String, dynamic>.from(m['bill'])) : {'bill': m}; // pre-envelope format
  }

  /// Serialises read-modify-write of the stored list (checkout, sync and mirroring can overlap).
  static Future<T> _locked<T>(Future<T> Function() fn) {
    final r = _tail.then((_) => fn());
    _tail = r.then((_) {}, onError: (_) {});
    return r;
  }

  static Future<void> _update(void Function(List<Map<String, dynamic>> list) change) => _locked(() async {
        final list = await all();
        change(list);
        final prefs = await SharedPreferences.getInstance();
        await prefs.setStringList(_key, list.map(jsonEncode).toList());
        pending.value = list.length;
      });

  /// Queues a bill that could not reach the server. It keeps the sale time, so the bill gets that date's number.
  static Future<void> add(Map<String, dynamic> bill) async {
    final entry = {
      'shopId': shopId,
      'branchId': Api.instance.branchId,
      'queuedAt': DateTime.now().toIso8601String(),
      'bill': {...bill, 'billDate': bill['billDate'] ?? DateTime.now().toIso8601String()},
    };
    await _update((list) => list
      ..removeWhere((e) => _id(e) == _id(entry))
      ..add(entry));
    unawaited(_mirrorPending());
  }

  /// Upload pending bills of the signed-in shop. Bills the server rejects stay queued with its error.
  /// [background]: small batches, stopping when the user becomes active (the rest goes next idle time).
  static Future<SyncResult> flush({bool background = false}) => _running ??= _flush(background).whenComplete(() => _running = null);

  static Future<SyncResult> _flush(bool background) async {
    final list = await all();
    final mine = list.where((e) => e['shopId'] == null || e['shopId'] == shopId).toList();
    if (mine.isEmpty || Api.instance.token == null) return SyncResult(remaining: list.length);
    final byBranch = <String?, List<Map<String, dynamic>>>{};
    for (final e in mine) {
      (byBranch[e['branchId'] as String?] ??= []).add(e);
    }
    final done = <String>{};
    final errors = <String, String>{};
    var duplicates = 0;
    try {
      for (final MapEntry(key: branch, value: entries) in byBranch.entries) {
        final size = background ? 25 : 200;
        for (var i = 0; i < entries.length; i += size) {
          if (background && !UserActivity.isIdle) break;
          final chunk = entries.skip(i).take(size);
          final res = await Api.instance.postForBranch(branch, '/sync/push', {'bills': [for (final e in chunk) e['bill']]});
          for (final r in res['results'] as List) {
            final id = r['id'] as String?;
            if (id == null) continue;
            if (r['ok'] == true) {
              done.add(id);
              if (r['duplicate'] == true) duplicates++;
            } else {
              errors[id] = r['error']?.toString() ?? 'Upload failed';
            }
          }
        }
      }
    } finally {
      // Record progress even if a later chunk hit a network error.
      await _update((l) {
        l.removeWhere((e) => done.contains(_id(e)));
        for (final e in l) {
          if (errors[_id(e)] != null) e['error'] = errors[_id(e)];
        }
      });
      for (final id in done) {
        unawaited(_unmirror(id));
      }
    }
    return SyncResult(
      uploaded: done.length - duplicates,
      alreadyOnServer: duplicates,
      remaining: pending.value,
      error: errors.values.firstOrNull,
    );
  }

  /// Background sync: only while the app is idle; never throws, does nothing when the queue is empty.
  static Future<void> syncQuietly() async {
    try {
      if ((await all()).isEmpty) return;
      await _mirrorPending();
      if (!UserActivity.isIdle || !Api.online.value) return;
      await flush(background: true);
    } catch (_) {
      // Still offline – the next tick retries.
    }
  }

  /// Writes not-yet-mirrored pending bills to the device's Download folder (Android).
  static Future<void> _mirrorPending() async {
    if (!hasBackupFolder) return;
    final written = <String>{};
    for (final e in (await all()).where((e) => e['mirrored'] != true)) {
      try {
        final file = {'type': 'onepe.offlineBill', 'version': 1, for (final k in ['shopId', 'branchId', 'queuedAt', 'bill']) k: e[k]};
        final ok = await _backup.invokeMethod<bool>('write', {'name': _file(_id(e)), 'json': jsonEncode(file)});
        if (ok == true) written.add(_id(e));
      } catch (_) {
        // Storage unavailable – retried on the next sync tick.
      }
    }
    if (written.isNotEmpty) {
      await _update((l) {
        for (final e in l) {
          if (written.contains(_id(e))) e['mirrored'] = true;
        }
      });
    }
  }

  static Future<void> _unmirror(String id) async {
    if (!hasBackupFolder) return;
    try {
      await _backup.invokeMethod('delete', {'name': _file(id)});
    } catch (_) {
      // A file left over from a previous install can't be deleted by this one; re-importing it is harmless.
    }
  }

  /// Re-queues bills from picked backup files. Returns how many bills were read from the files.
  static Future<int> import(List<String> contents) async {
    final entries = _parse(contents);
    if (entries.isEmpty) throw const FormatException('No OnePe offline bills found in the selected file(s)');
    await _add(entries);
    return entries.length;
  }

  static List<Map<String, dynamic>> _parse(List<String> contents) {
    final entries = <Map<String, dynamic>>[];
    for (final c in contents) {
      try {
        final data = jsonDecode(c);
        for (final raw in data is List ? data : [data]) {
          if (raw is! Map) continue;
          final e = _entry(raw)..remove('type')..remove('version');
          final bill = e['bill'] as Map;
          if (bill['id'] is! String || bill['items'] is! List) continue;
          entries.add(e..['mirrored'] = true); // the file it came from is the backup
        }
      } on FormatException {
        // Not a OnePe bill file – skip it.
      }
    }
    return entries;
  }

  /// Adds entries not yet queued; returns how many were new.
  static Future<int> _add(List<Map<String, dynamic>> entries) async {
    var added = 0;
    await _update((list) {
      final have = {for (final e in list) _id(e)};
      for (final e in entries.where((e) => have.add(_id(e)))) {
        list.add(e);
        added++;
      }
    });
    return added;
  }
}
