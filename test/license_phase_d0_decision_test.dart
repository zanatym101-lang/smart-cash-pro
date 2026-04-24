import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:king_wallet_accounting/data/app_db.dart';
import 'package:king_wallet_accounting/services/license_rpc_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const pathProviderChannel = MethodChannel('plugins.flutter.io/path_provider');
  final supportDir = Directory.systemTemp.createTempSync('kw_license_d0_');

  setUpAll(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProviderChannel, (call) async {
          if (call.method.endsWith('Paths')) {
            return <String>[supportDir.path];
          }
          return supportDir.path;
        });
  });

  setUp(() async {
    AppDbAdminLicense.debugForceServerAuthoritativeLicenseForTests = null;
    AppDbAdminLicense.debugServerAuthoritativeLicenseServiceFactoryForTests =
        null;
    await AppDb.instance.writeRawSettingsMap(<String, dynamic>{});
  });

  tearDown(() {
    AppDbAdminLicense.debugForceServerAuthoritativeLicenseForTests = null;
    AppDbAdminLicense.debugServerAuthoritativeLicenseServiceFactoryForTests =
        null;
  });

  tearDownAll(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProviderChannel, null);
    try {
      if (supportDir.existsSync()) {
        supportDir.deleteSync(recursive: true);
      }
    } catch (_) {}
  });

  test('D0: flag=false keeps legacy behavior unchanged', () async {
    final db = AppDb.instance;
    final firstInfo = await db.getLicenseInfo();
    final legacyCode = db.generateActivationCodeForDeviceCode(firstInfo.deviceCode);
    final fake = _FakeDecisionRpcService(
      validateException: const LicenseRpcException(
        'server should not be called',
        code: 'network_error',
        retriable: true,
      ),
    );

    AppDbAdminLicense.debugForceServerAuthoritativeLicenseForTests = false;
    AppDbAdminLicense.debugServerAuthoritativeLicenseServiceFactoryForTests =
        () => fake;

    final activated = await db.activateWithCode(legacyCode);
    final info = await db.getLicenseInfo();

    expect(activated, isTrue);
    expect(info.isActivated, isTrue);
    expect(fake.validateCalls, 0);
    expect(fake.heartbeatCalls, 0);
    expect(fake.refreshCalls, 0);
  });

  test('D0: flag=true + valid RPC => activated', () async {
    final db = AppDb.instance;
    await db.writeRawSettingsMap(<String, dynamic>{
      'license': <String, dynamic>{
        'cloudToken': 'access-token',
        'serverAuthRefreshToken': 'refresh-token',
      },
    });

    final fake = _FakeDecisionRpcService(
      validateResponse: const LicenseRpcResponse(
        ok: true,
        errorCode: null,
        message: null,
        retriable: false,
        raw: <String, dynamic>{
          'ok': true,
          'grace_ends_at': '2035-01-01T00:00:00Z',
        },
      ),
    );
    AppDbAdminLicense.debugForceServerAuthoritativeLicenseForTests = true;
    AppDbAdminLicense.debugServerAuthoritativeLicenseServiceFactoryForTests =
        () => fake;

    final info = await db.getLicenseInfo();
    final settings = await db.readRawSettingsMap();
    final license = Map<String, dynamic>.from(
      (settings['license'] as Map?)?.map((k, v) => MapEntry(k.toString(), v)) ??
          <String, dynamic>{},
    );

    expect(info.isActivated, isTrue);
    expect(license['serverAuthDiagLastMode'], 'validate');
    expect(license['serverAuthDiagLastSource'], 'phase_d0_decision');
  });

  test('D0: flag=true + revoked RPC => not activated', () async {
    final db = AppDb.instance;
    await db.writeRawSettingsMap(<String, dynamic>{
      'license': <String, dynamic>{
        'cloudToken': 'access-token',
        'serverAuthRefreshToken': 'refresh-token',
      },
    });

    final fake = _FakeDecisionRpcService(
      validateResponse: const LicenseRpcResponse(
        ok: false,
        errorCode: 'license_not_active',
        message: 'revoked',
        retriable: false,
        raw: <String, dynamic>{'ok': false},
      ),
    );
    AppDbAdminLicense.debugForceServerAuthoritativeLicenseForTests = true;
    AppDbAdminLicense.debugServerAuthoritativeLicenseServiceFactoryForTests =
        () => fake;

    final info = await db.getLicenseInfo();
    final settings = await db.readRawSettingsMap();
    final license = Map<String, dynamic>.from(
      (settings['license'] as Map?)?.map((k, v) => MapEntry(k.toString(), v)) ??
          <String, dynamic>{},
    );

    expect(info.isActivated, isFalse);
    expect(license['serverAuthDiagLastErrorCode'], 'license_revoked');
  });

  test('D0: flag=true + outage within server grace => activated', () async {
    final db = AppDb.instance;
    await db.writeRawSettingsMap(<String, dynamic>{
      'license': <String, dynamic>{
        'cloudToken': 'access-token',
        'serverAuthRefreshToken': 'refresh-token',
        'cloudLicenseExpiresAt': DateTime.now()
            .toUtc()
            .add(const Duration(hours: 2))
            .toIso8601String(),
      },
    });

    final fake = _FakeDecisionRpcService(
      validateException: const LicenseRpcException(
        'network down',
        code: 'network_error',
        retriable: true,
      ),
    );
    AppDbAdminLicense.debugForceServerAuthoritativeLicenseForTests = true;
    AppDbAdminLicense.debugServerAuthoritativeLicenseServiceFactoryForTests =
        () => fake;

    final info = await db.getLicenseInfo();
    final settings = await db.readRawSettingsMap();
    final license = Map<String, dynamic>.from(
      (settings['license'] as Map?)?.map((k, v) => MapEntry(k.toString(), v)) ??
          <String, dynamic>{},
    );

    expect(info.isActivated, isTrue);
    expect(license['serverAuthDiagLastMode'], 'outage_grace');
  });

  test('D0: flag=true + outage after server grace => not activated', () async {
    final db = AppDb.instance;
    await db.writeRawSettingsMap(<String, dynamic>{
      'license': <String, dynamic>{
        'cloudToken': 'access-token',
        'serverAuthRefreshToken': 'refresh-token',
        'cloudLicenseExpiresAt': DateTime.now()
            .toUtc()
            .subtract(const Duration(hours: 2))
            .toIso8601String(),
      },
    });

    final fake = _FakeDecisionRpcService(
      validateException: const LicenseRpcException(
        'network down',
        code: 'network_error',
        retriable: true,
      ),
    );
    AppDbAdminLicense.debugForceServerAuthoritativeLicenseForTests = true;
    AppDbAdminLicense.debugServerAuthoritativeLicenseServiceFactoryForTests =
        () => fake;

    final info = await db.getLicenseInfo();
    final settings = await db.readRawSettingsMap();
    final license = Map<String, dynamic>.from(
      (settings['license'] as Map?)?.map((k, v) => MapEntry(k.toString(), v)) ??
          <String, dynamic>{},
    );

    expect(info.isActivated, isFalse);
    expect(license['serverAuthDiagLastMode'], 'server_error');
  });
}

class _FakeDecisionRpcService extends LicenseRpcService {
  _FakeDecisionRpcService({
    this.validateResponse,
    this.validateException,
  }) : super(
         supabaseUrl: 'https://example.supabase.co',
         anonKey: 'anon-key',
         httpClient: MockClient((_) async {
           throw Exception('network should not be used in fake service');
         }),
       );

  final LicenseRpcResponse? validateResponse;
  final LicenseRpcException? validateException;

  int validateCalls = 0;
  int heartbeatCalls = 0;
  int refreshCalls = 0;

  @override
  Future<LicenseRpcResponse> validateLicense(
    ValidateLicenseRpcRequest request,
  ) async {
    validateCalls += 1;
    if (validateException != null) throw validateException!;
    return validateResponse ??
        const LicenseRpcResponse(
          ok: false,
          errorCode: 'validate_failed',
          message: 'validate failed',
          retriable: false,
          raw: <String, dynamic>{'ok': false},
        );
  }

  @override
  Future<LicenseRpcResponse> heartbeatLicense(
    HeartbeatLicenseRpcRequest request,
  ) async {
    heartbeatCalls += 1;
    return const LicenseRpcResponse(
      ok: false,
      errorCode: 'heartbeat_failed',
      message: 'heartbeat failed',
      retriable: false,
      raw: <String, dynamic>{'ok': false},
    );
  }

  @override
  Future<LicenseRpcResponse> refreshSession(
    RefreshSessionRpcRequest request,
  ) async {
    refreshCalls += 1;
    return const LicenseRpcResponse(
      ok: false,
      errorCode: 'refresh_failed',
      message: 'refresh failed',
      retriable: false,
      raw: <String, dynamic>{'ok': false},
    );
  }
}
