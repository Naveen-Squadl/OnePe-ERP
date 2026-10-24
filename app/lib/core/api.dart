import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

import 'config.dart';

class ApiException implements Exception {
  final int status;
  final String message;
  ApiException(this.status, this.message);

  bool get isNetwork => status == 0;
  @override
  String toString() => message;
}

/// Thin JSON client. Adds auth + active-branch headers and maps errors to [ApiException].
class Api {
  Api._();
  static final Api instance = Api._();

  String? token;
  String? branchId;
  String? shopId; // super admin acting on a shop
  void Function()? onUnauthorized;

  Map<String, String> get _headers => {
        'content-type': 'application/json',
        if (token != null) 'authorization': 'Bearer $token',
        'x-branch-id': ?branchId,
        'x-shop-id': ?shopId,
      };

  Uri _uri(String path, [Map<String, dynamic>? query]) {
    final q = <String, String>{};
    query?.forEach((k, v) {
      if (v != null && v.toString().isNotEmpty) q[k] = v.toString();
    });
    return Uri.parse('${AppConfig.apiUrl}/api$path').replace(queryParameters: q.isEmpty ? null : q);
  }

  Future<dynamic> get(String path, [Map<String, dynamic>? query]) => _send(() => http.get(_uri(path, query), headers: _headers));
  Future<dynamic> post(String path, [Object? body]) =>
      _send(() => http.post(_uri(path), headers: _headers, body: jsonEncode(body ?? {})));
  Future<dynamic> put(String path, [Object? body]) =>
      _send(() => http.put(_uri(path), headers: _headers, body: jsonEncode(body ?? {})));
  Future<dynamic> delete(String path) => _send(() => http.delete(_uri(path), headers: _headers));

  /// Multipart image upload; returns the stored URL path (e.g. `/uploads/{shop}/{id}.jpg`).
  Future<String> uploadImage(List<int> bytes, String filename) async {
    final ext = filename.split('.').last.toLowerCase();
    final mime = ext == 'png' ? 'png' : ext == 'webp' ? 'webp' : 'jpeg';
    final res = await _send(() async {
      final req = http.MultipartRequest('POST', _uri('/uploads'))
        ..headers.addAll(Map.of(_headers)..remove('content-type'))
        ..files.add(http.MultipartFile.fromBytes('file', bytes, filename: filename, contentType: MediaType('image', mime)));
      return http.Response.fromStream(await req.send());
    });
    return res['url'] as String;
  }

  /// Absolute URL for a server-relative media path.
  static String? mediaUrl(String? path) {
    if (path == null || path.isEmpty) return null;
    return path.startsWith('http') ? path : '${AppConfig.apiUrl}$path';
  }

  Future<dynamic> _send(Future<http.Response> Function() call) async {
    http.Response res;
    try {
      res = await call().timeout(const Duration(seconds: 25));
    } on TimeoutException {
      throw ApiException(0, 'Slow connection detected. Please check your internet and try again.');
    } catch (_) {
      throw ApiException(0, 'Network error. Please check your internet connection.');
    }
    final body = res.body.isEmpty ? null : jsonDecode(res.body);
    if (res.statusCode >= 200 && res.statusCode < 300) return body;
    if (res.statusCode == 401 && token != null) onUnauthorized?.call();
    final msg = body is Map && body['error'] != null ? body['error'].toString() : 'Request failed (${res.statusCode})';
    throw ApiException(res.statusCode, msg);
  }
}
