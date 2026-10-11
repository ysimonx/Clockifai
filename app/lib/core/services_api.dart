import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config.dart';

class ServicesException implements Exception {
  ServicesException(this.status, this.message);
  final int status;
  final String message;
  @override
  String toString() => message;
}

/// Client du service Flask (exports, invitations). Nécessite le réseau.
class ServicesApi {
  static Uri _uri(String path, [Map<String, String>? query]) {
    final base = AppConfig.servicesUrl.isEmpty && kIsWeb ? Uri.base.origin : AppConfig.servicesUrl;
    return Uri.parse('$base$path').replace(queryParameters: query);
  }

  static Map<String, String> _headers() {
    final token = Supabase.instance.client.auth.currentSession?.accessToken;
    return {
      if (token != null) 'Authorization': 'Bearer $token',
      'Content-Type': 'application/json',
    };
  }

  static Future<Uint8List> download(String path, Map<String, String> query) async {
    final res = await http.get(_uri(path, query), headers: _headers());
    if (res.statusCode != 200) throw ServicesException(res.statusCode, _error(res));
    return res.bodyBytes;
  }

  static Future<Map<String, dynamic>> post(String path, Map<String, dynamic> body) async {
    final res = await http.post(_uri(path), headers: _headers(), body: jsonEncode(body));
    if (res.statusCode >= 300) throw ServicesException(res.statusCode, _error(res));
    return res.body.isEmpty ? const {} : jsonDecode(res.body) as Map<String, dynamic>;
  }

  /// Appels du mode kiosque : authentifiés par le jeton de l'appareil, sans session utilisateur.
  static Future<Map<String, dynamic>> kiosk(String method, String path, String token, [Map<String, dynamic>? body]) async {
    final headers = {'X-Kiosk-Token': token, 'Content-Type': 'application/json'};
    final res = method == 'GET'
        ? await http.get(_uri(path), headers: headers)
        : await http.post(_uri(path), headers: headers, body: jsonEncode(body ?? const {}));
    if (res.statusCode >= 300) throw ServicesException(res.statusCode, _error(res));
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  static Future<void> delete(String path, Map<String, String> query) async {
    final res = await http.delete(_uri(path, query), headers: _headers());
    if (res.statusCode >= 300) throw ServicesException(res.statusCode, _error(res));
  }

  static Future<Map<String, dynamic>> get(String path, Map<String, String> query) async {
    final res = await http.get(_uri(path, query), headers: _headers());
    if (res.statusCode >= 300) throw ServicesException(res.statusCode, _error(res));
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  static String _error(http.Response res) {
    try {
      return (jsonDecode(res.body) as Map<String, dynamic>)['error']?.toString() ?? 'HTTP ${res.statusCode}';
    } catch (_) {
      return 'HTTP ${res.statusCode}';
    }
  }
}
