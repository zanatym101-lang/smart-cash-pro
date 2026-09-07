import 'package:flutter/material.dart';
import 'ad_reward_service.dart';

class AdMobService {
  static const String testAdUnitId = AdRewardService.testAdUnitId;
  static String get adUnitId => AdRewardService.adUnitId;

  static Future<void> showRewardedAd({
    required VoidCallback onRewarded,
    required Function(String error) onError,
  }) async {
    await AdRewardService.instance.showRewardedAd(
      onRewarded: () async {
        onRewarded();
      },
      onError: onError,
    );
  }
}
