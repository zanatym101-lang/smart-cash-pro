import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:king_wallet_accounting/data/app_db.dart';
import 'package:king_wallet_accounting/services/license_rpc_service.dart';

void main() {
  setUp(() {
    AppDbAdminLicense.debugForceServerAuthoritativeLicenseForTests = null;
    AppDbAdminLicense.debugServerAuthoritativeLicenseServiceFactoryForTests =
        null;
  });

  tearDown(() {
    AppDbAdminLicense.debugForceServerAuthoritativeLicenseForTests = null;
    AppDbAdminLicense.debugServerAuthoritativeLicenseServiceFactoryForTests =
        null;
  });

  test('flag=false does not call server-authoritative service', () async {
    final db = AppDb.instance;
    final license = <String, dynamic>{
      'cloudToken': 'phase-b-token',
      'serverAuthDiagLastCheckAt': '',
      'serverAuthDiagLastMode': '',
      'serverAuthDiagLastOk': false,
      'serverAuthDiagLastError': '',
      'serverAuthDiagLastErrorCode': '',
      'serverAuthDiagLastSource': '',
    };

    final fake = _FakeLicenseRpcService(
      validateResponse: const LicenseRpcResponse(
        ok: true,
        errorCode: null,
        message: null,
        retriable: false,
        raw: <String, dynamic>{'ok': true},
      ),
      heartbeatResponse: const LicenseRpcResponse(
        ok: true,
        errorCode: null,
        message: null,
        retriable: false,
        raw: <String, dynamic>{'ok': true},
      ),
    );

    AppDbAdminLicense.debugForceServerAuthoritativeLicenseForTests = false;
    AppDbAdminLicense.debugServerAuthoritativeLicenseServiceFactoryForTests =
        () => fake;

    await db.runServerAuthoritativeLicenseDiagnosticsForTesting(
      license: license,
      deviceCode: 'device-code-1',
    );

    expect(fake.validateCalls, 0);
    expect(fake.heartbeatCalls, 0);
    expect((license['serverAuthDiagLastCheckAt'] ?? '').toString(), isEmpty);
  });

  test('flag=true calls validate then heartbeat and stores diagnostic only', () async {
    final db = AppDb.instance;
    final license = <String, dynamic>{
      'cloudToken': 'phase-b-token',
      'serverAuthDiagLastCheckAt': '',
      'serverAuthDiagLastMode': '',
      'serverAuthDiagLastOk': false,
      'serverAuthDiagLastError': '',
      'serverAuthDiagLastErrorCode': '',
      'serverAuthDiagLastSource': '',
    };

    final fake = _FakeLicenseRpcService(
      validateResponse: const LicenseRpcResponse(
        ok: false,
        errorCode: 'session_expired',
        message: 'expired',
        retriable: false,
        raw: <String, dynamic>{'ok': false},
      ),
      heartbeatResponse: const LicenseRpcResponse(
        ok: true,
        errorCode: null,
        message: null,
        retriable: false,
        raw: <String, dynamic>{'ok': true},
      ),
    );

    AppDbAdminLicense.debugForceServerAuthoritativeLicenseForTests = true;
    AppDbAdminLicense.debugServerAuthoritativeLicenseServiceFactoryForTests =
        () => fake;

    await db.runServerAuthoritativeLicenseDiagnosticsForTesting(
      license: license,
      deviceCode: 'device-code-1',
    );

    expect(fake.validateCalls, 1);
    expect(fake.heartbeatCalls, 1);
    expect(license['serverAuthDiagLastSource'], 'phase_c5_diagnostic');
    expect(license['serverAuthDiagLastMode'], 'heartbeat');
    expect(license['serverAuthDiagLastOk'], true);
  });

  test('kill-switch diagnostic falls back to legacy and skips future RPC calls', () async {
    final db = AppDb.instance;
    final license = <String, dynamic>{
      'cloudToken': 'phase-b-token',
      'serverAuthDiagKillSwitchEnabled': false,
      'serverAuthDiagLastCheckAt': '',
      'serverAuthDiagLastMode': '',
      'serverAuthDiagLastOk': false,
      'serverAuthDiagLastError': '',
      'serverAuthDiagLastErrorCode': '',
      'serverAuthDiagLastSource': '',
    };

    final fake = _FakeLicenseRpcService(
      validateResponse: const LicenseRpcResponse(
        ok: true,
        errorCode: null,
        message: null,
        retriable: false,
        raw: <String, dynamic>{'ok': true, 'kill_switch_enabled': true},
      ),
      heartbeatResponse: const LicenseRpcResponse(
        ok: true,
        errorCode: null,
        message: null,
        retriable: false,
        raw: <String, dynamic>{'ok': true},
      ),
    );

    AppDbAdminLicense.debugForceServerAuthoritativeLicenseForTests = true;
    AppDbAdminLicense.debugServerAuthoritativeLicenseServiceFactoryForTests =
        () => fake;

    await db.runServerAuthoritativeLicenseDiagnosticsForTesting(
      license: license,
      deviceCode: 'device-code-1',
    );
    final callsAfterFirstRun = fake.validateCalls;

    await db.runServerAuthoritativeLicenseDiagnosticsForTesting(
      license: license,
      deviceCode: 'device-code-1',
    );

    expect(license['serverAuthDiagKillSwitchEnabled'], true);
    expect(license['serverAuthDiagLastErrorCode'], 'kill_switch_enabled');
    expect(license['serverAuthDiagLastMode'], 'kill_switch_legacy');
    expect(fake.validateCalls, callsAfterFirstRun);
  });

  test('compromise detection stores diagnostic state without enforcement', () async {
    final db = AppDb.instance;
    final license = <String, dynamic>{
      'cloudToken': 'phase-b-token',
      'serverAuthRefreshToken': 'refresh-token',
      'serverAuthDiagCompromiseDetected': false,
      'serverAuthDiagCompromiseAt': '',
      'serverAuthDiagLastCheckAt': '',
      'serverAuthDiagLastMode': '',
      'serverAuthDiagLastOk': false,
      'serverAuthDiagLastError': '',
      'serverAuthDiagLastErrorCode': '',
      'serverAuthDiagLastSource': '',
    };

    final fake = _FakeLicenseRpcService(
      validateResponse: const LicenseRpcResponse(
        ok: false,
        errorCode: 'session_expired',
        message: 'expired',
        retriable: false,
        raw: <String, dynamic>{'ok': false},
      ),
      heartbeatResponse: const LicenseRpcResponse(
        ok: false,
        errorCode: 'session_expired',
        message: 'expired',
        retriable: false,
        raw: <String, dynamic>{'ok': false},
      ),
      refreshException: const LicenseRpcException(
        'refresh token reuse',
        code: 'refresh_token_reuse',
      ),
    );

    AppDbAdminLicense.debugForceServerAuthoritativeLicenseForTests = true;
    AppDbAdminLicense.debugServerAuthoritativeLicenseServiceFactoryForTests =
        () => fake;

    await db.runServerAuthoritativeLicenseDiagnosticsForTesting(
      license: license,
      deviceCode: 'device-code-1',
    );

    expect(license['serverAuthDiagCompromiseDetected'], true);
    expect((license['serverAuthDiagCompromiseAt'] ?? '').toString(), isNotEmpty);
    expect(license['serverAuthDiagLastErrorCode'], 'refresh_token_reuse');
  });

  test('network outage degrades gracefully and keeps legacy fallback path', () async {
    final db = AppDb.instance;
    final license = <String, dynamic>{
      'cloudToken': 'phase-b-token',
      'serverAuthDiagLastCheckAt': '',
      'serverAuthDiagLastMode': '',
      'serverAuthDiagLastOk': false,
      'serverAuthDiagLastError': '',
      'serverAuthDiagLastErrorCode': '',
      'serverAuthDiagLastSource': '',
    };

    final fake = _FakeLicenseRpcService(
      validateException: const LicenseRpcException(
        'network down',
        code: 'network_error',
        retriable: true,
      ),
      heartbeatException: const LicenseRpcException(
        'network down',
        code: 'network_error',
        retriable: true,
      ),
    );

    AppDbAdminLicense.debugForceServerAuthoritativeLicenseForTests = true;
    AppDbAdminLicense.debugServerAuthoritativeLicenseServiceFactoryForTests =
        () => fake;

    await db.runServerAuthoritativeLicenseDiagnosticsForTesting(
      license: license,
      deviceCode: 'device-code-1',
    );

    expect(license['serverAuthDiagLastMode'], 'legacy_fallback');
    expect(license['serverAuthDiagLastOk'], false);
    expect(license['serverAuthDiagLastErrorCode'], 'network_error');
  });
}

class _FakeLicenseRpcService extends LicenseRpcService {
  _FakeLicenseRpcService({
    this.validateResponse,
    this.heartbeatResponse,
    this.validateException,
    this.heartbeatException,
    this.refreshException,
  }) : super(
         supabaseUrl: 'https://example.supabase.co',
         anonKey: 'anon-key',
         httpClient: MockClient((_) async {
           throw Exception('network should not be used in fake service');
         }),
       );

  final LicenseRpcResponse? validateResponse;
  final LicenseRpcResponse? heartbeatResponse;
  final LicenseRpcException? validateException;
  final LicenseRpcException? heartbeatException;
  final LicenseRpcException? refreshException;

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
    if (heartbeatException != null) throw heartbeatException!;
    return heartbeatResponse ??
        const LicenseRpcResponse(
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
    if (refreshException != null) throw refreshException!;
    return const LicenseRpcResponse(
      ok: false,
      errorCode: 'refresh_failed',
      message: 'refresh failed',
      retriable: false,
      raw: <String, dynamic>{'ok': false},
    );
  }
}
