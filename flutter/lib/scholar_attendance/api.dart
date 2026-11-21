import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

import 'config.dart';
import 'device_identity.dart';

class ApiException implements Exception {
  final int status;
  final String code;
  final String message;
  ApiException(this.status, this.code, this.message);
  @override
  String toString() => message;
}

/// Signed calls to the attendance service. Each request carries:
///   X-Device-Id, X-Timestamp (ms), X-Nonce, X-Signature
/// where the signature covers "METHOD\nPATH?QUERY\nTIMESTAMP\nNONCE\nsha256(body)".
class AttendanceApi {
  final AttendanceConfig config;
  final DeviceIdentity identity;
  final http.Client _http;

  AttendanceApi(this.config, this.identity, {http.Client? client}) : _http = client ?? http.Client();

  Future<dynamic> get(String path, {Map<String, String>? query}) => _send('GET', path, query: query);

  Future<dynamic> post(String path, [Object? body]) => _send('POST', path, body: body);

  Future<dynamic> put(String path, Object body) => _send('PUT', path, body: body);

  Future<Uint8List> getBytes(String path, {Map<String, String>? query}) async {
    final res = await _raw('GET', path, query: query);
    _throwIfError(res);
    return res.bodyBytes;
  }

  Future<dynamic> _send(String method, String path, {Map<String, String>? query, Object? body}) async {
    final res = await _raw(method, path, query: query, body: body);
    _throwIfError(res);
    if (res.bodyBytes.isEmpty) return null;
    return jsonDecode(utf8.decode(res.bodyBytes));
  }

  Future<http.Response> _raw(String method, String path, {Map<String, String>? query, Object? body}) async {
    await identity.ensure();
    final rel = Uri(path: path, queryParameters: (query == null || query.isEmpty) ? null : query);
    final signedPath = rel.hasQuery ? '${rel.path}?${rel.query}' : rel.path;
    final url = Uri.parse('${config.baseUrl}$signedPath');
    final bytes = body == null ? Uint8List(0) : Uint8List.fromList(utf8.encode(jsonEncode(body)));
    final ts = DateTime.now().millisecondsSinceEpoch.toString();
    final nonce = _nonce();
    final canonical = '$method\n$signedPath\n$ts\n$nonce\n${sha256.convert(bytes)}';
    final headers = {
      'Authorization': 'Bearer ${await config.getToken()}',
      'Content-Type': 'application/json',
      'X-Device-Id': identity.deviceId,
      'X-Timestamp': ts,
      'X-Nonce': nonce,
      'X-Signature': identity.sign(Uint8List.fromList(utf8.encode(canonical))),
    };
    final req = http.Request(method, url)
      ..headers.addAll(headers)
      ..bodyBytes = bytes;
    try {
      return await http.Response.fromStream(await _http.send(req).timeout(const Duration(seconds: 20)));
    } catch (_) {
      throw ApiException(0, 'NETWORK', 'Could not reach the server. Check your connection.');
    }
  }

  void _throwIfError(http.Response res) {
    if (res.statusCode < 400) return;
    var code = 'ERROR';
    var message = 'Something went wrong (${res.statusCode}).';
    try {
      final j = jsonDecode(utf8.decode(res.bodyBytes));
      final d = j['detail'];
      if (d is Map) {
        code = d['code']?.toString() ?? code;
        message = d['message']?.toString() ?? message;
      } else if (d is List && d.isNotEmpty) {
        message = d.first['msg']?.toString() ?? message;
      }
    } catch (_) {}
    throw ApiException(res.statusCode, code, message);
  }

  static String _nonce() {
    final r = Random.secure();
    return List<int>.generate(16, (_) => r.nextInt(256)).map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }
}
