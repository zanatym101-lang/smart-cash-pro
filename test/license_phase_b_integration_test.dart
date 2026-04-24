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
    expect(license['serverAuthDiagLastSource'], 'phase_b_diagnostic');
    expect(license['serverAuthDiagLastMode'], 'heartbeat');
    expect(license['serverAuthDiagLastOk'], true);
  });
}

class _FakeLicenseRpcService extends LicenseRpcService {
  _FakeLicenseRpcService({
    required this.validateResponse,
    required this.heartbeatResponse,
  }) : super(
         supabaseUrl: 'https://example.supabase.co',
         anonKey: 'anon-key',
         httpClient: MockClient((_) async {
           throw Exception('network should not be used in fake service');
         }),
       );

  final LicenseRpcResponse validateResponse;
  final LicenseRpcResponse heartbeatResponse;

  int validateCalls = 0;
  int heartbeatCalls = 0;

  @override
  Future<LicenseRpcResponse> validateLicense(
    ValidateLicenseRpcRequest request,
  ) async {
    validateCalls += 1;
    return validateResponse;
  }

  @override
  Future<LicenseRpcResponse> heartbeatLicense(
    HeartbeatLicenseRpcRequest request,
  ) async {
    heartbeatCalls += 1;
    return heartbeatResponse;
  }
}
