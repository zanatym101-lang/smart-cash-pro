import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import '../data/app_db.dart';

class AdRewardService {
  AdRewardService._();
  static final AdRewardService instance = AdRewardService._();
  factory AdRewardService() => instance;

  static const String productionAdUnitId =
      'ca-app-pub-6908047326536143/6125076095';
  static const String testAdUnitId =
      'ca-app-pub-3940256099942544/5224354917';

  /// Selects test ID in debug mode to protect the AdMob account, and production ID in release mode.
  static String get adUnitId => kDebugMode ? testAdUnitId : productionAdUnitId;

  RewardedAd? _rewardedAd;
  bool _isAdLoaded = false;
  bool _isLoading = false;

  bool get isAdReady => _isAdLoaded && _rewardedAd != null;
  bool get isLoading => _isLoading;

  /// Preloads a rewarded ad in the background.
  Future<void> loadRewardedAd({
    VoidCallback? onLoaded,
    void Function(String error)? onFailed,
  }) async {
    if (isAdReady) {
      onLoaded?.call();
      return;
    }
    if (_isLoading) return;

    _isLoading = true;

    try {
      await RewardedAd.load(
        adUnitId: adUnitId,
        request: const AdRequest(),
        rewardedAdLoadCallback: RewardedAdLoadCallback(
          onAdLoaded: (RewardedAd ad) {
            _rewardedAd = ad;
            _isAdLoaded = true;
            _isLoading = false;

            ad.fullScreenContentCallback = FullScreenContentCallback(
              onAdDismissedFullScreenContent: (RewardedAd ad) {
                ad.dispose();
                _rewardedAd = null;
                _isAdLoaded = false;
                // Automatically preload next rewarded ad in background
                loadRewardedAd();
              },
              onAdFailedToShowFullScreenContent: (RewardedAd ad, AdError error) {
                ad.dispose();
                _rewardedAd = null;
                _isAdLoaded = false;
                debugPrint('Ad failed to show full screen: ');
              },
            );

            onLoaded?.call();
          },
          onAdFailedToLoad: (LoadAdError error) {
            _rewardedAd = null;
            _isAdLoaded = false;
            _isLoading = false;
            debugPrint('Failed to load rewarded ad: ');
            onFailed?.call(error.message);
          },
        ),
      );
    } catch (e) {
      _rewardedAd = null;
      _isAdLoaded = false;
      _isLoading = false;
      debugPrint('Exception while loading rewarded ad: ');
      onFailed?.call(e.toString());
    }
  }

  /// Presents the rewarded ad to the user.
  Future<void> showRewardedAd({
    required Future<void> Function() onRewarded,
    required void Function(String error) onError,
    VoidCallback? onClosed,
  }) async {
    if (!isAdReady) {
      // Attempt on-demand load if ad is not already ready
      await loadRewardedAd(
        onLoaded: () async {
          await _presentLoadedAd(
            onRewarded: onRewarded,
            onError: onError,
            onClosed: onClosed,
          );
        },
        onFailed: (err) {
          onError('لا يوجد إعلان متوفر حالياً. يرجى المحاولة لاحقاً.');
        },
      );
      return;
    }

    await _presentLoadedAd(
      onRewarded: onRewarded,
      onError: onError,
      onClosed: onClosed,
    );
  }

  Future<void> _presentLoadedAd({
    required Future<void> Function() onRewarded,
    required void Function(String error) onError,
    VoidCallback? onClosed,
  }) async {
    final ad = _rewardedAd;
    if (ad == null) {
      onError('تعذر عرض الإعلان. يرجى المحاولة لاحقاً.');
      return;
    }

    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (RewardedAd ad) {
        ad.dispose();
        _rewardedAd = null;
        _isAdLoaded = false;
        onClosed?.call();
        // Background preload next ad
        loadRewardedAd();
      },
      onAdFailedToShowFullScreenContent: (RewardedAd ad, AdError error) {
        ad.dispose();
        _rewardedAd = null;
        _isAdLoaded = false;
        onError('فشل عرض الإعلان: ');
      },
    );

    try {
      await ad.show(
        onUserEarnedReward: (AdWithoutView ad, RewardItem reward) async {
          try {
            await onRewarded();
          } catch (e) {
            onError('حدث خطأ أثناء تمديد الفترة التجريبية: ');
          }
        },
      );
    } catch (e) {
      onError('فشل عرض الإعلان: ');
    }
  }

  /// Convenience method to show ad and extend trial by [days] days.
  Future<void> showAdAndExtendTrial({
    required BuildContext context,
    int days = 3,
    VoidCallback? onSuccess,
    void Function(String error)? onError,
  }) async {
    await showRewardedAd(
      onRewarded: () async {
        await AppDb.instance.extendByAd(days: days);
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('🎉 تم بنجاح تمديد فترتك التجريبية لمدة يوم إضافية!'),
            ),
          );
        }
        onSuccess?.call();
      },
      onError: (err) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(err)),
          );
        }
        onError?.call(err);
      },
    );
  }

  @visibleForTesting
  void setMockAdReadyForTesting({bool ready = true}) {
    _isAdLoaded = ready;
  }

  void dispose() {
    _rewardedAd?.dispose();
    _rewardedAd = null;
    _isAdLoaded = false;
    _isLoading = false;
  }
}
