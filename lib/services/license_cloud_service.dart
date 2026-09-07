import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';

class LicenseCloudException implements Exception {
  final String message;
  final String? code;
  final int? statusCode;
  final bool transient;

  const LicenseCloudException(
    this.message, {
    this.code,
    this.statusCode,
    this.transient = false,
  });

  @override
  String toString() => message;
}

class LicenseCloudActivationResult {
  final String token;
  final DateTime? licenseExpiresAt;
  final DateTime? tokenExpiresAt;
  final String? deviceId;

  const LicenseCloudActivationResult({
    required this.token,
    required this.licenseExpiresAt,
    required this.tokenExpiresAt,
    required this.deviceId,
  });
}

class LicenseCloudStatusResult {
  final DateTime? licenseExpiresAt;
  const LicenseCloudStatusResult({required this.licenseExpiresAt});
}

class LicenseCloudService {
  static Future<String> _ensureSignedIn() async {
    if (Firebase.apps.isEmpty) {
      throw const LicenseCloudException('يجب تسجيل الدخول أولاً');
    }
    try {
      var user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        final cred = await FirebaseAuth.instance.signInAnonymously();
        user = cred.user;
      }
      if (user == null || user.uid.isEmpty) {
        throw const LicenseCloudException('يجب تسجيل الدخول أولاً');
      }
      return user.uid;
    } on FirebaseAuthException catch (e) {
      throw LicenseCloudException('فشل تسجيل الدخول: ${e.message ?? e.code}');
    } catch (e) {
      if (e is LicenseCloudException) rethrow;
      throw LicenseCloudException('فشل تسجيل الدخول: $e');
    }
  }

  static Future<LicenseCloudActivationResult> activate({
    required String code,
    required String deviceId,
    required String appVersion,
  }) async {
    final uid = await _ensureSignedIn();

    int daysToAdd = 0;
    final String cleanCode = code.trim().toUpperCase();

    try {
      // Check activation code in Firestore
      final codeRef = FirebaseFirestore.instance.collection('activation_codes').doc(cleanCode);
      final codeSnap = await codeRef.get();

      if (!codeSnap.exists) {
        if (cleanCode == 'TRIAL7') {
          daysToAdd = 7;
        } else {
          throw const LicenseCloudException(
            'الكود غير صحيح أو غير موجود.',
            code: 'license_not_found',
          );
        }
      } else {
        final data = codeSnap.data()!;
        final ownerUid = (data['ownerUid'] ?? data['usedBy']) as String?;

        // Security check: If claimed by a different user account, block it!
        if (ownerUid != null && ownerUid != uid) {
          throw const LicenseCloudException('هذا الكود مرتبط بحساب مستخدم آخر ولا يمكن استخدامه.');
        }

        final maxDevices = (data['maxDevices'] as num?)?.toInt() ?? 1;
        final rawDevices = data['usedDevices'] as List<dynamic>? ?? [];
        final usedDevices = rawDevices.map((e) => e.toString()).toList();

        if (!usedDevices.contains(deviceId)) {
          if (usedDevices.length >= maxDevices) {
            throw LicenseCloudException(
              'تم استنفاد الحد الأقصى للأجهزة لهذا الكود ($maxDevices أجهزة).',
            );
          }
          usedDevices.add(deviceId);
        }

        daysToAdd = (data['days'] as num?)?.toInt() ?? 30;
        final isNowFullyUsed = usedDevices.length >= maxDevices;

        // Update code in Firestore
        await codeRef.update({
          'ownerUid': uid,
          'usedBy': uid,
          'usedDevices': usedDevices,
          'usedCount': usedDevices.length,
          'maxDevices': maxDevices,
          'isUsed': isNowFullyUsed,
          'usedAt': FieldValue.serverTimestamp(),
        });
      }

      final docRef = FirebaseFirestore.instance
          .collection('workspaces')
          .doc(uid)
          .collection('subscription')
          .doc('status');

      final snap = await docRef.get();
      DateTime newExpiry;
      if (snap.exists && snap.data()!.containsKey('licenseExpiresAt')) {
        final current = DateTime.tryParse(snap.data()!['licenseExpiresAt'] as String);
        if (current != null && current.isAfter(DateTime.now())) {
          newExpiry = current.add(Duration(days: daysToAdd));
        } else {
          newExpiry = DateTime.now().add(Duration(days: daysToAdd));
        }
      } else {
        newExpiry = DateTime.now().add(Duration(days: daysToAdd));
      }

      await docRef.set({
        'licenseExpiresAt': newExpiry.toIso8601String(),
        'deviceId': deviceId,
        'appVersion': appVersion,
      });

      return LicenseCloudActivationResult(
        token: 'firebase-token-$uid',
        licenseExpiresAt: newExpiry,
        tokenExpiresAt: DateTime.now().add(const Duration(days: 30)),
        deviceId: deviceId,
      );
    } on FirebaseException catch (e) {
      if (e.code == 'permission-denied') {
        throw const LicenseCloudException(
          'تم رفض الإذن أثناء تفعيل الترخيص. يرجى التحقق من الاتصال والمصادقة.',
          code: 'permission-denied',
        );
      }
      throw LicenseCloudException(
        e.message ?? 'حدث خطأ في الاتصال بقاعدة البيانات السحابية',
        code: e.code,
      );
    }
  }

  static Future<LicenseCloudStatusResult> status({
    required String token,
    required String deviceId,
  }) async {
    final uid = await _ensureSignedIn();

    try {
      final docRef = FirebaseFirestore.instance
          .collection('workspaces')
          .doc(uid)
          .collection('subscription')
          .doc('status');
      final snap = await docRef.get();

      if (!snap.exists) {
        return const LicenseCloudStatusResult(licenseExpiresAt: null);
      }

      final data = snap.data()!;
      final expiresStr = data['licenseExpiresAt'] as String?;
      DateTime? expires;
      if (expiresStr != null) {
        expires = DateTime.tryParse(expiresStr);
      }

      return LicenseCloudStatusResult(licenseExpiresAt: expires);
    } on FirebaseException catch (e) {
      throw LicenseCloudException(
        e.message ?? 'فشل الاستعلام عن حالة الترخيص',
        code: e.code,
      );
    }
  }

  static Future<LicenseCloudActivationResult> refresh({
    required String token,
    required String deviceId,
    required String appVersion,
  }) async {
    final s = await status(token: token, deviceId: deviceId);
    return LicenseCloudActivationResult(
      token: token,
      licenseExpiresAt: s.licenseExpiresAt,
      tokenExpiresAt: DateTime.now().add(const Duration(days: 30)),
      deviceId: deviceId,
    );
  }

  static Future<void> extendByAd({int days = 3}) async {
    if (Firebase.apps.isEmpty) return;
    try {
      final uid = await _ensureSignedIn();
      final docRef = FirebaseFirestore.instance
          .collection('workspaces')
          .doc(uid)
          .collection('subscription')
          .doc('status');

      final snap = await docRef.get();
      DateTime newExpiry;
      if (snap.exists && snap.data()!.containsKey('licenseExpiresAt')) {
        final current = DateTime.tryParse(snap.data()!['licenseExpiresAt'] as String);
        if (current != null && current.isAfter(DateTime.now())) {
          newExpiry = current.add(Duration(days: days));
        } else {
          newExpiry = DateTime.now().add(Duration(days: days));
        }
      } else {
        newExpiry = DateTime.now().add(Duration(days: days));
      }

      await docRef.set({
        'licenseExpiresAt': newExpiry.toIso8601String(),
      }, SetOptions(merge: true));
    } catch (_) {
      // Safe fallback for extendByAd
    }
  }

  static Future<LicenseCloudActivationResult?> tryAutoActivateAssignedLicense({
    required String deviceId,
    required String appVersion,
  }) async {
    if (Firebase.apps.isEmpty) return null;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || user.uid.isEmpty) return null;
    final uid = user.uid;
    final email = user.email?.trim().toLowerCase();

    try {
      // 1. Check workspace subscription status
      final docRef = FirebaseFirestore.instance
          .collection('workspaces')
          .doc(uid)
          .collection('subscription')
          .doc('status');
      final snap = await docRef.get();
      if (snap.exists) {
        final data = snap.data()!;
        final expiresStr = data['licenseExpiresAt'] as String?;
        if (expiresStr != null) {
          final expires = DateTime.tryParse(expiresStr);
          if (expires != null && expires.isAfter(DateTime.now())) {
            // Valid active subscription, bind device
            await docRef.set({
              'deviceId': deviceId,
              'appVersion': appVersion,
            }, SetOptions(merge: true));

            return LicenseCloudActivationResult(
              token: 'firebase-token-$uid',
              licenseExpiresAt: expires,
              tokenExpiresAt: DateTime.now().add(const Duration(days: 30)),
              deviceId: deviceId,
            );
          }
        }
      }

      // 2. Query activation_codes assigned to this account or email
      QuerySnapshot<Map<String, dynamic>> codesSnap;
      if (email != null && email.isNotEmpty) {
        codesSnap = await FirebaseFirestore.instance
            .collection('activation_codes')
            .where('assignedEmail', isEqualTo: email)
            .get();
      } else {
        codesSnap = await FirebaseFirestore.instance
            .collection('activation_codes')
            .where('ownerUid', isEqualTo: uid)
            .get();
      }

      for (final doc in codesSnap.docs) {
        final data = doc.data();
        final maxDevices = (data['maxDevices'] as num?)?.toInt() ?? 1;
        final rawDevices = data['usedDevices'] as List<dynamic>? ?? [];
        final usedDevices = rawDevices.map((e) => e.toString()).toList();

        if (usedDevices.contains(deviceId) || usedDevices.length < maxDevices) {
          return await activate(
            code: doc.id,
            deviceId: deviceId,
            appVersion: appVersion,
          );
        }
      }
    } catch (_) {
      // Best-effort auto-activation
    }
    return null;
  }
}
