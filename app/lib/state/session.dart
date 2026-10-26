import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/api.dart';
import '../models/models.dart';
import '../services/customer_cache.dart';
import '../services/local_store.dart';
import '../services/offline_queue.dart';
import 'catalog.dart';

/// Auth + tenant context (user, shop, branches, active outlet, plan status).
class Session extends ChangeNotifier {
  final _api = Api.instance;
  AppUser? user;
  Shop? shop;
  List<Branch> branches = [];
  String? activeBranchId;
  Map<String, dynamic>? plan;
  bool booting = true;

  bool get isLoggedIn => user != null;
  Branch? get activeBranch =>
      branches.where((b) => b.id == activeBranchId).firstOrNull ?? (branches.isNotEmpty ? branches.first : null);
  bool can(String p) => user?.can(p) ?? false;

  Session() {
    _api.onUnauthorized = logout;
  }

  Future<void> restore() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token');
    if (token != null) {
      _api.token = token;
      activeBranchId = prefs.getString('branchId');
      _api.branchId = activeBranchId;
      try {
        _apply(await _api.get('/auth/me'));
      } on ApiException catch (e) {
        if (e.isNetwork) {
          // Offline boot: use the cached session.
          final cached = prefs.getString('session');
          if (cached != null) _apply(jsonDecode(cached));
        } else {
          await logout();
        }
      }
    }
    booting = false;
    notifyListeners();
  }

  Future<void> login(String email, String password) async {
    final res = await _api.post('/auth/login', {'email': email.trim(), 'password': password});
    _api.token = res['token'];
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('token', res['token']);
    _apply(res);
    notifyListeners();
  }

  void _apply(Map<String, dynamic> res) {
    user = AppUser.fromJson(res['user']);
    shop = res['shop'] == null ? null : Shop.fromJson(res['shop']);
    branches = (res['branches'] as List? ?? []).map((b) => Branch.fromJson(b)).toList();
    plan = res['plan'];
    final valid = branches.any((b) => b.id == activeBranchId);
    if (!valid) activeBranchId = user!.branchId ?? (branches.isNotEmpty ? branches.first.id : null);
    _api.branchId = activeBranchId;
    OfflineQueue.shopId = shop?.id;
    OfflineQueue.syncQuietly();
    SharedPreferences.getInstance().then((p) {
      p.setString('session', jsonEncode(res..remove('token')));
      if (activeBranchId != null) p.setString('branchId', activeBranchId!);
    });
  }

  Future<void> refresh() async {
    _apply(await _api.get('/auth/me'));
    notifyListeners();
  }

  Future<void> switchBranch(String id) async {
    activeBranchId = id;
    _api.branchId = id;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('branchId', id);
    notifyListeners();
  }

  Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('token');
    await prefs.remove('session');
    _api.token = null;
    _api.shopId = null;
    OfflineQueue.shopId = null;
    await LocalStore.clear(Catalog.filePrefix); // saved products & customers of this shop
    await LocalStore.clear(CustomerCache.filePrefix);
    user = null;
    shop = null;
    branches = [];
    notifyListeners();
  }
}
