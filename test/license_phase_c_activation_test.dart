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

  test('legacy activation still works when flag=false', () async {
    final db = AppDb.instance;
    final license = <String, dynamic>{};
    const deviceCode = 'ABCD-EFGH-IJKL-MNOP';
    const deviceFingerprintHash =
        'abcdefabcdefabcdefabcdefabcdefabcdefabcdefabcdefabcdefabcdef';
    final legacyCode = db.generateActivationCodeForDeviceCode(deviceCode);

    final fake = _FakeActivationRpcService(
      activateResult: const LicenseRpcResponse(
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

    final ok = await db.activateWithCodeForTesting(
      license: license,
      code: legacyCode,
      deviceCode: deviceCode,
      deviceFingerprintHash: deviceFingerprintHash,
    );

    expect(ok, isTrue);
    expect(fake.activateCalls, 0);
    expect((license['activationCode'] ?? '').toString().isNotEmpty, isTrue);
  });

  test('RPC activation path is used only when flag=true', () async {
    final db = AppDb.instance;
    final license = <String, dynamic>{};
    const deviceCode = 'ABCD-EFGH-IJKL-MNOP';
    const deviceFingerprintHash =
        'abcdefabcdefabcdefabcdefabcdefabcdefabcdefabcdefabcdefabcdef';

    final fake = _FakeActivationRpcService(
      activateResult: const LicenseRpcResponse(
        ok: true,
        errorCode: null,
        message: null,
        retriable: false,
        raw: <String, dynamic>{
          'ok': true,
          'access_token': 'access-token-1',
          'refresh_token': 'refresh-token-1',
          'access_expires_at': '2030-01-01T00:00:00Z',
          'refresh_expires_at': '2030-02-01T00:00:00Z',
        },
      ),
    );
    AppDbAdminLicense.debugForceServerAuthoritativeLicenseForTests = true;
    AppDbAdminLicense.debugServerAuthoritativeLicenseServiceFactoryForTests =
        () => fake;

    final ok = await db.activateWithCodeForTesting(
      license: license,
      code: 'NON-LEGACY-CODE',
      deviceCode: deviceCode,
      deviceFingerprintHash: deviceFingerprintHash,
    );

    expect(ok, isTrue);
    expect(fake.activateCalls, 1);
    expect(license['cloudToken'], 'access-token-1');
    expect(license['serverAuthRefreshToken'], 'refresh-token-1');
    expect(license['cloudDeviceId'], deviceCode);
  });

  test('RPC failure does not break legacy activation path when flag=false', () async {
    final db = AppDb.instance;
    final license = <String, dynamic>{};
    const deviceCode = 'ABCD-EFGH-IJKL-MNOP';
    const deviceFingerprintHash =
        'abcdefabcdefabcdefabcdefabcdefabcdefabcdefabcdefabcdefabcdef';
    final legacyCode = db.generateActivationCodeForDeviceCode(deviceCode);

    final fake = _FakeActivationRpcService(
      activateException: const LicenseRpcException(
        'network down',
        code: 'network_error',
        retriable: true,
      ),
    );
    AppDbAdminLicense.debugForceServerAuthoritativeLicenseForTests = false;
    AppDbAdminLicense.debugServerAuthoritativeLicenseServiceFactoryForTests =
        () => fake;

    final ok = await db.activateWithCodeForTesting(
      license: license,
      code: legacyCode,
      deviceCode: deviceCode,
      deviceFingerprintHash: deviceFingerprintHash,
    );

    expect(ok, isTrue);
    expect(fake.activateCalls, 0);
  });
}

class _FakeActivationRpcService extends LicenseRpcService {
  _FakeActivationRpcService({this.activateResult, this.activateException})
    : super(
        supabaseUrl: 'https://example.supabase.co',
        anonKey: 'anon-key',
        httpClient: MockClient((_) async {
          throw Exception('network should not be used in fake service');
        }),
      );

  final LicenseRpcResponse? activateResult;
  final LicenseRpcException? activateException;

  int activateCalls = 0;

  @override
  Future<LicenseRpcResponse> activateLicense(
    ActivateLicenseRpcRequest request,
  ) async {
    activateCalls += 1;
    if (activateException != null) throw activateException!;
    return activateResult ??
        const LicenseRpcResponse(
          ok: false,
          errorCode: 'activation_failed',
          message: 'activation failed',
          retriable: false,
          raw: <String, dynamic>{'ok': false},
        );
  }
}
