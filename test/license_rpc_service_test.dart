import 'dart:convert';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:king_wallet_accounting/services/license_rpc_service.dart';

void main() {
  test('phase A flag stays disabled by default', () {
    expect(useServerAuthoritativeLicense, isFalse);
  });

  test('activateLicense posts to RPC endpoint and parses success response', () async {
    Uri? capturedUri;
    Map<String, dynamic>? capturedBody;

    final client = MockClient((request) async {
      capturedUri = request.url;
      capturedBody = Map<String, dynamic>.from(
        jsonDecode(request.body) as Map,
      );
      return http.Response(
        jsonEncode(<String, dynamic>{
          'ok': true,
          'access_token': 'acc',
          'refresh_token': 'ref',
        }),
        200,
        headers: const {'content-type': 'application/json'},
      );
    });

    final service = LicenseRpcService(
      supabaseUrl: 'https://example.supabase.co',
      anonKey: 'anon-key',
      httpClient: client,
    );

    final response = await service.activateLicense(
      const ActivateLicenseRpcRequest(
        activationCode: 'CODE-123',
        deviceId: 'device-1',
        deviceFingerprintHash: '1234567890abcdef',
        idempotencyKey: 'idem-1',
      ),
    );

    expect(response.ok, isTrue);
    expect(
      capturedUri.toString(),
      'https://example.supabase.co/rest/v1/rpc/activate_license',
    );
    expect(capturedBody?['p_activation_code'], 'CODE-123');
    expect(capturedBody?['p_device_id'], 'device-1');
    expect(capturedBody?['p_idempotency_key'], 'idem-1');
  });

  test('validateLicense throws typed exception on non-2xx RPC response', () async {
    final client = MockClient((request) async {
      return http.Response(
        jsonEncode(<String, dynamic>{
          'error_code': 'license_not_active',
          'message': 'license is not active',
        }),
        400,
        headers: const {'content-type': 'application/json'},
      );
    });

    final service = LicenseRpcService(
      supabaseUrl: 'https://example.supabase.co',
      anonKey: 'anon-key',
      httpClient: client,
    );

    await expectLater(
      service.validateLicense(
        const ValidateLicenseRpcRequest(
          accessToken: 'access-token',
          deviceId: 'device-1',
        ),
      ),
      throwsA(
        isA<LicenseRpcException>()
            .having((e) => e.code, 'code', 'license_not_active')
            .having((e) => e.statusCode, 'statusCode', 400),
      ),
    );
  });

  test('validateLicense applies retry/backoff and succeeds after transient failures', () async {
    var callCount = 0;
    final slept = <Duration>[];
    final client = MockClient((request) async {
      callCount += 1;
      if (callCount < 3) {
        return http.Response(
          jsonEncode(<String, dynamic>{
            'error_code': 'server_unavailable',
            'message': 'temporary failure',
          }),
          503,
          headers: const {'content-type': 'application/json'},
        );
      }
      return http.Response(
        jsonEncode(<String, dynamic>{'ok': true}),
        200,
        headers: const {'content-type': 'application/json'},
      );
    });

    final service = LicenseRpcService(
      supabaseUrl: 'https://example.supabase.co',
      anonKey: 'anon-key',
      httpClient: client,
      maxRetryAttempts: 3,
      baseBackoffDelay: const Duration(milliseconds: 100),
      maxBackoffDelay: const Duration(milliseconds: 500),
      sleep: (delay) async => slept.add(delay),
      random: Random(1),
    );

    final result = await service.validateLicense(
      const ValidateLicenseRpcRequest(
        accessToken: 'access-token',
        deviceId: 'device-1',
      ),
    );

    expect(result.ok, isTrue);
    expect(callCount, 3);
    expect(slept.length, 2);
    expect(slept.first.inMilliseconds, greaterThan(0));
    expect(slept.last.inMilliseconds, greaterThan(slept.first.inMilliseconds));
  });

  test('refreshSession retries are limited and throw on persistent timeout', () async {
    final client = MockClient((request) async {
      throw http.ClientException('offline');
    });

    final service = LicenseRpcService(
      supabaseUrl: 'https://example.supabase.co',
      anonKey: 'anon-key',
      httpClient: client,
      maxRetryAttempts: 2,
      sleep: (_) async {},
    );

    await expectLater(
      service.refreshSession(
        const RefreshSessionRpcRequest(
          refreshToken: 'refresh',
          deviceId: 'device-1',
          idempotencyKey: 'idem-1',
        ),
      ),
      throwsA(
        isA<LicenseRpcException>().having(
          (e) => e.code,
          'code',
          'network_error',
        ),
      ),
    );
  });
}
