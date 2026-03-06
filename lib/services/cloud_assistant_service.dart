import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

class CloudAssistantService {
  static const String _endpoint = String.fromEnvironment(
    'CLOUD_ASSISTANT_ENDPOINT',
    defaultValue: 'https://smart-cash-pro-six.vercel.app/api/assistant',
  );
  static const String _clientToken = String.fromEnvironment(
    'CLOUD_ASSISTANT_CLIENT_TOKEN',
    defaultValue: '',
  );

  static final Random _rng = _createRandom();

  static Future<String> ask(Map<String, dynamic> payload) async {
    final bodyText = _canonicalJson(payload);
    final ts = DateTime.now().millisecondsSinceEpoch.toString();
    final nonce = _nonce();
    final clientId = _extractClientId(payload);

    final headers = <String, String>{
      'Content-Type': 'application/json',
      'X-SCP-TS': ts,
      'X-SCP-Nonce': nonce,
      if (clientId.isNotEmpty) 'X-SCP-Client-Id': clientId,
      if (_clientToken.isNotEmpty) ...{
        'X-SCP-Client-Token': _clientToken,
        'X-SCP-Signature': _signature(ts: ts, nonce: nonce),
      },
    };

    final res = await http.post(
      Uri.parse(_endpoint),
      headers: headers,
      body: bodyText,
    );

    if (res.statusCode < 200 || res.statusCode >= 300) {
      String details = '';
      try {
        final data = jsonDecode(res.body);
        if (data is Map) {
          details = (data['details'] ?? data['error'] ?? '').toString();
        }
      } catch (_) {
        details = '';
      }
      final suffix = details.trim().isEmpty ? '' : ': $details';
      throw Exception(
        'فشل الاتصال بالمساعد السحابي (${res.statusCode})$suffix',
      );
    }

    final data = jsonDecode(res.body);
    final answer = data is Map ? data['answer']?.toString() : null;
    if (answer == null || answer.trim().isEmpty) {
      throw Exception('لم يتم استلام رد من المساعد');
    }
    return answer.trim();
  }

  static String _extractClientId(Map<String, dynamic> payload) {
    final meta = payload['meta'];
    if (meta is Map) {
      final raw = meta['deviceCode'] ?? meta['deviceId'] ?? meta['device_code'];
      return (raw ?? '').toString().trim();
    }
    return '';
  }

  static String _nonce() {
    final bytes = List<int>.generate(16, (_) => _rng.nextInt(256));
    return base64UrlEncode(bytes).replaceAll('=', '');
  }

  static Random _createRandom() {
    try {
      return Random.secure();
    } catch (_) {
      return Random();
    }
  }

  static String _signature({required String ts, required String nonce}) {
    final key = utf8.encode(_clientToken);
    final message = utf8.encode('$ts.$nonce');
    return Hmac(sha256, key).convert(message).toString();
  }

  static String _canonicalJson(Map<String, dynamic> payload) {
    dynamic normalize(dynamic value) {
      if (value is Map) {
        final entries = value.entries.toList()
          ..sort((a, b) => a.key.toString().compareTo(b.key.toString()));
        return {for (final e in entries) e.key.toString(): normalize(e.value)};
      }
      if (value is List) {
        return value.map(normalize).toList();
      }
      return value;
    }

    return jsonEncode(normalize(payload));
  }
}
