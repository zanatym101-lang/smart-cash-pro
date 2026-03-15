import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

class LicenseCloudException implements Exception {
  final String message;
  final String? code;
  final int? statusCode;
  final bool transient;

  const LicenseCloudException(
    this.message, {
    this.code,
    this.statusCode,
    this.transient = false,
  });

  @override
  String toString() => message;
}

class LicenseCloudActivationResult {
  final String token;
  final DateTime? licenseExpiresAt;
  final DateTime? tokenExpiresAt;
  final String? deviceId;

  const LicenseCloudActivationResult({
    required this.token,
    required this.licenseExpiresAt,
    required this.tokenExpiresAt,
    required this.deviceId,
  });
}

class LicenseCloudStatusResult {
  final DateTime? licenseExpiresAt;

  const LicenseCloudStatusResult({required this.licenseExpiresAt});
}

class LicenseCloudService {
  static const String _baseUrl = String.fromEnvironment(
    'LICENSE_API_BASE_URL',
    defaultValue: 'https://smart-cash-pro-six.vercel.app',
  );

  static Future<LicenseCloudActivationResult> activate({
    required String code,
    required String deviceId,
    required String appVersion,
  }) async {
    final payload = await _post('/api/license/activate', {
      'code': code,
      'deviceId': deviceId,
      'appVersion': appVersion,
    });

    final token = (payload['token'] ?? '').toString().trim();
    if (token.isEmpty) {
      throw const LicenseCloudException('استجابة خادم التفعيل غير مكتملة');
    }

    final activation = payload['activation'];
    String? activationDeviceId;
    if (activation is Map) {
      activationDeviceId = (activation['deviceId'] ?? '').toString().trim();
      if (activationDeviceId.isEmpty) activationDeviceId = null;
    }

    final licenseExpiresAt = _parseDate(payload['expiresAt']);
    return LicenseCloudActivationResult(
      token: token,
      tokenExpiresAt: _tokenExpiry(token),
      licenseExpiresAt: licenseExpiresAt,
      deviceId: activationDeviceId,
    );
  }

  static Future<LicenseCloudStatusResult> status({
    required String token,
    required String deviceId,
  }) async {
    final payload = await _post('/api/license/status', {
      'token': token,
      'deviceId': deviceId,
    });

    final license = payload['license'];
    DateTime? licenseExpiresAt;
    if (license is Map) {
      licenseExpiresAt = _parseDate(license['expiresAt']);
    }
    return LicenseCloudStatusResult(licenseExpiresAt: licenseExpiresAt);
  }

  static Future<LicenseCloudActivationResult> refresh({
    required String token,
    required String deviceId,
    required String appVersion,
  }) async {
    final payload = await _post('/api/license/refresh', {
      'token': token,
      'deviceId': deviceId,
      'appVersion': appVersion,
    });

    final nextToken = (payload['token'] ?? '').toString().trim();
    if (nextToken.isEmpty) {
      throw const LicenseCloudException('تعذر تجديد جلسة الترخيص');
    }

    return LicenseCloudActivationResult(
      token: nextToken,
      tokenExpiresAt: _tokenExpiry(nextToken),
      licenseExpiresAt: _parseDate(payload['expiresAt']),
      deviceId: deviceId,
    );
  }

  static Future<Map<String, dynamic>> _post(
    String path,
    Map<String, dynamic> body,
  ) async {
    final url = Uri.parse('$_baseUrl$path');
    http.Response res;
    try {
      res = await http
          .post(
            url,
            headers: const {'Content-Type': 'application/json'},
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 20));
    } on TimeoutException {
      throw const LicenseCloudException(
        'انتهت مهلة الاتصال بخادم الترخيص',
        code: 'timeout',
        transient: true,
      );
    } on Exception {
      throw const LicenseCloudException(
        'تعذر الاتصال بخادم الترخيص',
        code: 'network_error',
        transient: true,
      );
    }

    dynamic decoded;
    try {
      decoded = jsonDecode(res.body);
    } catch (_) {
      decoded = null;
    }

    if (res.statusCode < 200 || res.statusCode >= 300) {
      final errorCode = decoded is Map
          ? (decoded['error'] ?? '').toString().trim()
          : '';
      final details = decoded is Map
          ? (decoded['details'] ?? '').toString().trim()
          : '';
      throw LicenseCloudException(
        _mapErrorMessage(errorCode, details, res.statusCode),
        code: errorCode.isEmpty ? null : errorCode,
        statusCode: res.statusCode,
        transient: res.statusCode >= 500,
      );
    }

    if (decoded is! Map) {
      throw const LicenseCloudException('استجابة خادم الترخيص غير صالحة');
    }
    return Map<String, dynamic>.from(decoded);
  }

  static DateTime? _tokenExpiry(String token) {
    try {
      final parts = token.split('.');
      if (parts.length < 2) return null;
      final payloadPart = parts[1];
      final normalized = base64Url.normalize(payloadPart);
      final payload = utf8.decode(base64Url.decode(normalized));
      final data = jsonDecode(payload);
      if (data is! Map) return null;
      final expRaw = data['exp'];
      int? exp;
      if (expRaw is int) {
        exp = expRaw;
      } else if (expRaw is num) {
        exp = expRaw.toInt();
      } else {
        exp = int.tryParse(expRaw?.toString() ?? '');
      }
      if (exp == null || exp <= 0) return null;
      return DateTime.fromMillisecondsSinceEpoch(exp * 1000, isUtc: true);
    } catch (_) {
      return null;
    }
  }

  static DateTime? _parseDate(dynamic raw) {
    final text = (raw ?? '').toString().trim();
    if (text.isEmpty) return null;
    return DateTime.tryParse(text)?.toUtc();
  }

  static String _mapErrorMessage(String code, String details, int statusCode) {
    final c = code.trim();
    switch (c) {
      case 'license_not_found':
        return 'كود التفعيل غير صحيح';
      case 'license_not_active':
        return 'هذا الترخيص غير نشط حاليا';
      case 'license_expired':
        return 'انتهت صلاحية هذا الترخيص';
      case 'device_limit_exceeded':
        return 'تم الوصول للحد الأقصى للأجهزة لهذا الترخيص';
      case 'device_revoked':
        return 'هذا الجهاز تم إيقافه لهذا الترخيص';
      case 'missing_token':
      case 'invalid_token':
      case 'invalid_token_format':
      case 'activation_not_found_or_revoked':
        return 'جلسة الترخيص على هذا الجهاز غير صالحة';
      case 'missing_license_token_secret':
        return 'خادم الترخيص غير مهيأ';
      default:
        final suffix = details.isEmpty ? '' : ': $details';
        return 'فشل التحقق من الترخيص ($statusCode)$suffix';
    }
  }
}
