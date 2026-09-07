import 'package:flutter_test/flutter_test.dart';
import 'package:king_wallet_accounting/services/license_cloud_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('LicenseCloudService and Data Model Tests', () {
    test('LicenseCloudException properties and formatting', () {
      const ex = LicenseCloudException(
        'خطأ تجريبي',
        code: 'test_code',
        statusCode: 400,
        transient: true,
      );

      expect(ex.message, 'خطأ تجريبي');
      expect(ex.code, 'test_code');
      expect(ex.statusCode, 400);
      expect(ex.transient, isTrue);
      expect(ex.toString(), 'خطأ تجريبي');
    });

    test('LicenseCloudActivationResult constructs valid object', () {
      final now = DateTime.now();
      final res = LicenseCloudActivationResult(
        token: 'token-123',
        licenseExpiresAt: now.add(const Duration(days: 30)),
        tokenExpiresAt: now.add(const Duration(days: 60)),
        deviceId: 'device-abc',
      );

      expect(res.token, 'token-123');
      expect(res.deviceId, 'device-abc');
      expect(res.licenseExpiresAt!.isAfter(now), isTrue);
    });

    test('LicenseCloudService operations require authentication or complete safely', () async {
      // Without initialized Firebase / signed in user, activate & status throw LicenseCloudException
      expect(
        () => LicenseCloudService.activate(
          code: 'TEST1234',
          deviceId: 'device-1',
          appVersion: '1.8.1',
        ),
        throwsA(isA<LicenseCloudException>()),
      );

      expect(
        () => LicenseCloudService.status(
          token: 'token-1',
          deviceId: 'device-1',
        ),
        throwsA(isA<LicenseCloudException>()),
      );

      // extendByAd safely exits without crashing when user is not signed in
      await expectLater(LicenseCloudService.extendByAd(), completes);
    });
  });
}
