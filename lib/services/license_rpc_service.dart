import 'dart:convert';

import 'package:http/http.dart' as http;

/// Phase A guard: keep server-authoritative licensing disabled by default.
const bool useServerAuthoritativeLicense = false;

class LicenseRpcException implements Exception {
  final String message;
  final String? code;
  final int? statusCode;
  final bool retriable;

  const LicenseRpcException(
    this.message, {
    this.code,
    this.statusCode,
    this.retriable = false,
  });

  @override
  String toString() => message;
}

class LicenseRpcResponse {
  final bool ok;
  final String? errorCode;
  final String? message;
  final bool retriable;
  final Map<String, dynamic> raw;

  const LicenseRpcResponse({
    required this.ok,
    required this.errorCode,
    required this.message,
    required this.retriable,
    required this.raw,
  });

  factory LicenseRpcResponse.fromJson(Map<String, dynamic> json) {
    return LicenseRpcResponse(
      ok: json['ok'] == true,
      errorCode: (json['error_code'] ?? '').toString().trim().isEmpty
          ? null
          : (json['error_code'] ?? '').toString().trim(),
      message: (json['message'] ?? '').toString().trim().isEmpty
          ? null
          : (json['message'] ?? '').toString().trim(),
      retriable: json['retriable'] == true,
      raw: json,
    );
  }
}

class ActivateLicenseRpcRequest {
  final String activationCode;
  final String deviceId;
  final String deviceFingerprintHash;
  final String? platform;
  final String? appVersion;
  final String idempotencyKey;
  final String? requestIp;
  final String? userAgent;

  const ActivateLicenseRpcRequest({
    required this.activationCode,
    required this.deviceId,
    required this.deviceFingerprintHash,
    required this.idempotencyKey,
    this.platform,
    this.appVersion,
    this.requestIp,
    this.userAgent,
  });

  Map<String, dynamic> toJson() => {
    'p_activation_code': activationCode,
    'p_device_id': deviceId,
    'p_device_fingerprint_hash': deviceFingerprintHash,
    'p_platform': platform,
    'p_app_version': appVersion,
    'p_idempotency_key': idempotencyKey,
    'p_request_ip': requestIp,
    'p_user_agent': userAgent,
  };
}

class ValidateLicenseRpcRequest {
  final String accessToken;
  final String deviceId;

  const ValidateLicenseRpcRequest({
    required this.accessToken,
    required this.deviceId,
  });

  Map<String, dynamic> toJson() => {
    'p_access_token': accessToken,
    'p_device_id': deviceId,
  };
}

class HeartbeatLicenseRpcRequest {
  final String accessToken;
  final String deviceId;
  final String? appVersion;

  const HeartbeatLicenseRpcRequest({
    required this.accessToken,
    required this.deviceId,
    this.appVersion,
  });

  Map<String, dynamic> toJson() => {
    'p_access_token': accessToken,
    'p_device_id': deviceId,
    'p_app_version': appVersion,
  };
}

class RefreshSessionRpcRequest {
  final String refreshToken;
  final String deviceId;
  final String idempotencyKey;
  final String? requestIp;
  final String? userAgent;

  const RefreshSessionRpcRequest({
    required this.refreshToken,
    required this.deviceId,
    required this.idempotencyKey,
    this.requestIp,
    this.userAgent,
  });

  Map<String, dynamic> toJson() => {
    'p_refresh_token': refreshToken,
    'p_device_id': deviceId,
    'p_idempotency_key': idempotencyKey,
    'p_request_ip': requestIp,
    'p_user_agent': userAgent,
  };
}

class LicenseRpcService {
  static const String _defaultSupabaseUrl = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: '',
  );
  static const String _defaultAnonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue: '',
  );

  final String supabaseUrl;
  final String anonKey;
  final http.Client _httpClient;

  LicenseRpcService({
    String? supabaseUrl,
    String? anonKey,
    http.Client? httpClient,
  }) : supabaseUrl = (supabaseUrl ?? _defaultSupabaseUrl).trim(),
       anonKey = (anonKey ?? _defaultAnonKey).trim(),
       _httpClient = httpClient ?? http.Client();

  Future<LicenseRpcResponse> activateLicense(
    ActivateLicenseRpcRequest request,
  ) {
    return _callRpc('activate_license', request.toJson());
  }

  Future<LicenseRpcResponse> validateLicense(
    ValidateLicenseRpcRequest request,
  ) {
    return _callRpc('validate_license', request.toJson());
  }

  Future<LicenseRpcResponse> heartbeatLicense(
    HeartbeatLicenseRpcRequest request,
  ) {
    return _callRpc('heartbeat_license', request.toJson());
  }

  Future<LicenseRpcResponse> refreshSession(
    RefreshSessionRpcRequest request,
  ) {
    return _callRpc('refresh_session', request.toJson());
  }

  Future<LicenseRpcResponse> _callRpc(
    String rpcName,
    Map<String, dynamic> body,
  ) async {
    if (supabaseUrl.isEmpty || anonKey.isEmpty) {
      throw const LicenseRpcException(
        'Missing Supabase licensing RPC configuration',
        code: 'missing_supabase_config',
      );
    }

    final base = supabaseUrl.endsWith('/')
        ? supabaseUrl.substring(0, supabaseUrl.length - 1)
        : supabaseUrl;
    final uri = Uri.parse('$base/rest/v1/rpc/$rpcName');

    http.Response response;
    try {
      response = await _httpClient.post(
        uri,
        headers: {
          'Content-Type': 'application/json',
          'apikey': anonKey,
          'Authorization': 'Bearer $anonKey',
        },
        body: jsonEncode(body),
      );
    } on Exception {
      throw const LicenseRpcException(
        'License RPC network error',
        code: 'network_error',
        retriable: true,
      );
    }

    final payload = _decodeResponse(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw LicenseRpcException(
        _extractErrorMessage(payload) ?? 'License RPC failed',
        code: _extractErrorCode(payload),
        statusCode: response.statusCode,
        retriable: response.statusCode >= 500,
      );
    }
    return LicenseRpcResponse.fromJson(payload);
  }

  static Map<String, dynamic> _decodeResponse(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map<String, dynamic>) return decoded;
      if (decoded is Map) {
        return Map<String, dynamic>.from(decoded);
      }
    } catch (_) {}
    throw const LicenseRpcException(
      'Invalid RPC response format',
      code: 'invalid_response',
    );
  }

  static String? _extractErrorCode(Map<String, dynamic> payload) {
    final code = (payload['error_code'] ?? payload['code'] ?? '')
        .toString()
        .trim();
    return code.isEmpty ? null : code;
  }

  static String? _extractErrorMessage(Map<String, dynamic> payload) {
    final message = (payload['message'] ?? payload['error'] ?? '')
        .toString()
        .trim();
    return message.isEmpty ? null : message;
  }
}
