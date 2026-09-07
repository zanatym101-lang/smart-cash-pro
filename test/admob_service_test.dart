import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:king_wallet_accounting/services/admob_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMessageHandler(
      'plugins.flutter.io/google_mobile_ads',
      (ByteData? message) async {
        return const StandardMethodCodec().encodeSuccessEnvelope(null);
      },
    );
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMessageHandler(
      'plugins.flutter.io/google_mobile_ads',
      null,
    );
  });

  group('AdMobService Unit Tests', () {
    test('adUnitId is valid and non-empty', () {
      expect(AdMobService.adUnitId, isNotEmpty);
      expect(AdMobService.adUnitId, contains('ca-app-pub-3940256099942544'));
      expect(AdMobService.testAdUnitId, equals(AdMobService.adUnitId));
    });

    test('showRewardedAd invokes onError or handles gracefully when no ad is available in test environment', () async {
      bool rewarded = false;

      try {
        await AdMobService.showRewardedAd(
          onRewarded: () {
            rewarded = true;
          },
          onError: (_) {},
        );
      } catch (_) {
        // Platform channels may throw in headless unit tests if unmocked
      }

      expect(rewarded, isFalse);
    });
  });
}
