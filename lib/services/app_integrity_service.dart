import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Service that verifies APK signature integrity against legitimate release certificates.
/// Prevents running tampered, re-signed, or cracked builds on Android.
class AppIntegrityService {
  static const String channelName = 'com.smartcashpro.app/app_integrity';
  static const MethodChannel _channel = MethodChannel(channelName);

  /// The legitimate Release Certificate SHA-256 fingerprint for Smart Cash Pro.
  static const String expectedReleaseFingerprint =
      '83:4B:1E:56:08:21:F1:9F:EC:21:5D:FA:33:46:8F:9A:4D:27:BA:65:C7:4B:A8:4C:EB:10:9E:1B:CF:21:E4:75';

  /// Normalizes fingerprints by stripping colons, spaces, and converting to uppercase.
  static String normalizeFingerprint(String fp) =>
      fp.replaceAll(':', '').replaceAll(' ', '').trim().toUpperCase();

  /// Retrieves the active APK signing certificate SHA-256 fingerprint from Android.
  static Future<String?> getSignatureFingerprint() async {
    if (!Platform.isAndroid) return null;
    try {
      final fp = await _channel.invokeMethod<String>('getSignatureFingerprint');
      return fp;
    } catch (e) {
      debugPrint('[AppIntegrityService] Failed to retrieve fingerprint: $e');
      return null;
    }
  }

  /// Verifies the application signature integrity.
  /// - Non-Android platforms (Windows, macOS, iOS, Web) always pass.
  /// - Debug mode always passes (emits log message with active fingerprint).
  /// - Release mode on Android strictly validates against [expectedReleaseFingerprint].
  static Future<bool> verifyAppIntegrity({
    bool? isDebugOverride,
    String? testFingerprint,
    bool? isAndroidOverride,
  }) async {
    final isAndroid = isAndroidOverride ?? Platform.isAndroid;
    if (!isAndroid) {
      return true;
    }

    final isDebug = isDebugOverride ?? kDebugMode;
    if (isDebug) {
      final fp = testFingerprint ?? await getSignatureFingerprint();
      debugPrint(
        '[AppIntegrityService] Debug mode: Active signature SHA-256 = $fp',
      );
      return true;
    }

    final activeFp = testFingerprint ?? await getSignatureFingerprint();
    if (activeFp == null || activeFp.trim().isEmpty) {
      debugPrint(
        '[AppIntegrityService] TAMPER DETECTED: Unable to read APK signature.',
      );
      return false;
    }

    final normalizedActive = normalizeFingerprint(activeFp);
    final normalizedExpected = normalizeFingerprint(expectedReleaseFingerprint);

    final isValid = normalizedActive == normalizedExpected;
    if (!isValid) {
      debugPrint(
        '[AppIntegrityService] TAMPER DETECTED: Signature mismatch!',
      );
      debugPrint('Expected: $normalizedExpected');
      debugPrint('Actual:   $normalizedActive');
    }
    return isValid;
  }
}

/// Screen displayed when unauthorized tampering or re-signing is detected.
class TamperAlertScreen extends StatelessWidget {
  const TamperAlertScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.redAccent.withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: Colors.redAccent.withValues(alpha: 0.4),
                      width: 2,
                    ),
                  ),
                  child: const Icon(
                    Icons.gpp_bad_rounded,
                    size: 72,
                    color: Colors.redAccent,
                  ),
                ),
                const SizedBox(height: 24),
                const Text(
                  'تنبيه أمني عالي الخطورة',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.red.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text(
                    'App Signature Tamper Detected',
                    style: TextStyle(
                      color: Colors.redAccent,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                const Text(
                  'تم اكتشاف تعديل غير مصرح به أو إعادة توقيع لحزمة التطبيق بمفتاح غير شرعي.\n\n'
                  'لحماية أموالك وبياناتك المحاسبية وسجلات الخزينة من التلاعب والسرقة، تم تعطيل الوصول إلى التطبيق فوراً.\n\n'
                  'يُرجى تنزيل النسخة الأصلية المعتمدة من القنوات الرسمية فقط.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Color(0xFF94A3B8),
                    fontSize: 14,
                    height: 1.6,
                  ),
                ),
                const SizedBox(height: 36),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () {
                      SystemNavigator.pop();
                    },
                    icon: const Icon(Icons.exit_to_app_rounded),
                    label: const Text(
                      'إغلاق التطبيق',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.redAccent,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
