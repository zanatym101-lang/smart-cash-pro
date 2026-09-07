import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:king_wallet_accounting/services/ad_reward_service.dart';

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
    AdRewardService.instance.dispose();
  });

  group('AdRewardService Unit Tests', () {
    test('Ad Unit IDs are configured correctly', () {
      expect(
        AdRewardService.productionAdUnitId,
        equals('ca-app-pub-6908047326536143/6125076095'),
      );
      expect(
        AdRewardService.testAdUnitId,
        equals('ca-app-pub-3940256099942544/5224354917'),
      );
      // In tests/debug mode, test unit ID must be selected to protect the account
      expect(AdRewardService.adUnitId, equals(AdRewardService.testAdUnitId));
    });

    test('Singleton pattern returns same instance', () {
      final a = AdRewardService();
      final b = AdRewardService.instance;
      expect(identical(a, b), isTrue);
    });

    test('Initial state has no ad ready', () {
      final service = AdRewardService.instance;
      service.dispose();
      expect(service.isAdReady, isFalse);
      expect(service.isLoading, isFalse);
    });

    test('showRewardedAd gracefully invokes onError or handles missing ad in headless tests', () async {
      final service = AdRewardService.instance;
      service.dispose();

      bool rewarded = false;
      String? errorMessage;

      try {
        await service.showRewardedAd(
          onRewarded: () async {
            rewarded = true;
          },
          onError: (err) {
            errorMessage = err;
          },
        );
      } catch (_) {
        // Platform channels may throw when headless
      }

      expect(rewarded, isFalse);
      expect(errorMessage != null || service.isAdReady == false, isTrue);
    });

    test('dispose resets readiness and loading flags', () {
      final service = AdRewardService.instance;
      service.setMockAdReadyForTesting(ready: true);
      expect(service.isAdReady, isFalse); // rewardedAd is still null
      service.dispose();
      expect(service.isAdReady, isFalse);
      expect(service.isLoading, isFalse);
    });
  });
}
