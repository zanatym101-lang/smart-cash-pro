import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

import '../data/app_db.dart';

class AdminSecurityService {
  AdminSecurityService._();

  static final AdminSecurityService instance = AdminSecurityService._();

  static const String _pinFormatPrefix = 'v2';
  static const int _pinIterations = 25000;
  static const int _adminPinMaxAttempts = 5;
  static const int _adminPinLockMinutes = 15;

  Future<Map<String, dynamic>> _readSettings() =>
      AppDb.instance.readRawSettingsMap();

  Future<void> _writeSettings(Map<String, dynamic> settings) =>
      AppDb.instance.writeRawSettingsMap(settings);

  bool _hasStoredAdminPin(Map<String, dynamic> settings) =>
      (settings['adminPin'] ?? '').toString().trim().isNotEmpty;

  String _legacyDecodePin(String stored) {
    if (!stored.startsWith('enc:')) return stored;
    try {
      final raw = stored.substring(4);
      final bytes = base64.decode(raw);
      const key = 'kw_pin_v1';
      final keyBytes = utf8.encode(key);
      final out = List<int>.generate(
        bytes.length,
        (i) => bytes[i] ^ keyBytes[i % keyBytes.length],
      );
      return utf8.decode(out);
    } catch (_) {
      return stored;
    }
  }

  String _pinSalt() {
    final rng = Random.secure();
    final bytes = List<int>.generate(16, (_) => rng.nextInt(256));
    return base64UrlEncode(bytes);
  }

  String _derivePinHash({
    required String pin,
    required String salt,
    required int iterations,
  }) {
    var bytes = sha256.convert(utf8.encode('$salt|$pin')).bytes;
    final saltBytes = utf8.encode(salt);
    for (var i = 1; i < iterations; i++) {
      bytes = sha256.convert([...bytes, ...saltBytes]).bytes;
    }
    return base64UrlEncode(bytes);
  }

  String _pinRecord(String pin) {
    final salt = _pinSalt();
    final hash = _derivePinHash(
      pin: pin,
      salt: salt,
      iterations: _pinIterations,
    );
    return '$_pinFormatPrefix:$_pinIterations:$salt:$hash';
  }

  bool _verifyPinRecord(String stored, String pin) {
    final raw = stored.trim();
    if (raw.startsWith('$_pinFormatPrefix:')) {
      final parts = raw.split(':');
      if (parts.length != 4) return false;
      final iterations = int.tryParse(parts[1]) ?? 0;
      if (iterations <= 0) return false;
      final salt = parts[2];
      final expected = parts[3];
      final actual = _derivePinHash(
        pin: pin,
        salt: salt,
        iterations: iterations,
      );
      return actual == expected;
    }
    if (raw.startsWith('enc:')) {
      return _legacyDecodePin(raw).trim() == pin.trim();
    }
    return raw == pin.trim();
  }

  String _decodeIfLegacy(String stored) {
    if (stored.startsWith('enc:')) {
      return _legacyDecodePin(stored).trim();
    }
    if (stored.startsWith('$_pinFormatPrefix:')) {
      return '';
    }
    return stored.trim();
  }

  Map<String, dynamic> _adminPinGuardMap(Map<String, dynamic> settings) {
    final raw = settings['adminPinGuard'];
    if (raw is Map) {
      return Map<String, dynamic>.from(
        raw.map((k, v) => MapEntry(k.toString(), v)),
      );
    }
    return <String, dynamic>{};
  }

  SecureRestoreStatus _adminPinStatusFromMap(Map<String, dynamic> map) {
    final failed =
        int.tryParse(
          (map['failedAttempts'] ?? '0').toString(),
        )?.clamp(0, _adminPinMaxAttempts) ??
        0;
    final lockIso = (map['lockedUntil'] ?? '').toString().trim();
    final lockTime = lockIso.isEmpty ? null : DateTime.tryParse(lockIso);
    final now = DateTime.now();
    final locked = lockTime != null && lockTime.isAfter(now);
    final remaining = locked
        ? 0
        : (_adminPinMaxAttempts - failed).clamp(0, _adminPinMaxAttempts);
    return SecureRestoreStatus(
      failedAttempts: failed,
      maxAttempts: _adminPinMaxAttempts,
      remainingAttempts: remaining,
      lockedUntil: lockTime,
      locked: locked,
    );
  }

  Future<void> _recordAdminPinFailure() async {
    final settings = await _readSettings();
    final guard = _adminPinGuardMap(settings);
    final current =
        int.tryParse((guard['failedAttempts'] ?? '0').toString()) ?? 0;
    final failed = (current + 1).clamp(1, _adminPinMaxAttempts);
    guard['failedAttempts'] = failed;
    if (failed >= _adminPinMaxAttempts) {
      guard['lockedUntil'] = DateTime.now()
          .add(const Duration(minutes: _adminPinLockMinutes))
          .toIso8601String();
    } else {
      guard['lockedUntil'] = '';
    }
    settings['adminPinGuard'] = guard;
    await _writeSettings(settings);
  }

  Future<String> getAdminPin() async {
    final settings = await _readSettings();
    final stored = (settings['adminPin'] ?? '').toString().trim();
    if (stored.isEmpty) return '';
    final decoded = _decodeIfLegacy(stored);
    if (decoded.isNotEmpty) {
      settings['adminPin'] = _pinRecord(decoded);
      await _writeSettings(settings);
      return decoded;
    }
    return '';
  }

  Future<bool> hasAdminPin() async {
    final settings = await _readSettings();
    return _hasStoredAdminPin(settings);
  }

  Future<bool> requiresPinSetup() async => !await hasAdminPin();

  Future<bool> verifyAdminPin(String pin) async {
    final settings = await _readSettings();
    if (!_hasStoredAdminPin(settings)) return false;
    final status = await getAdminPinStatus();
    if (status.locked) {
      return false;
    }
    final stored = (settings['adminPin'] ?? '').toString().trim();
    final ok = _verifyPinRecord(stored, pin);
    if (ok) {
      if (!stored.startsWith('$_pinFormatPrefix:')) {
        settings['adminPin'] = _pinRecord(pin.trim());
      }
      settings['adminPinGuard'] = <String, dynamic>{
        'failedAttempts': 0,
        'lockedUntil': '',
      };
      await _writeSettings(settings);
      return true;
    }
    await _recordAdminPinFailure();
    return false;
  }

  Future<void> setAdminPin(String newPin) async {
    final pin = newPin.trim();
    if (pin.length < 4) {
      throw Exception('PIN يجب أن يكون 4 أرقام أو أكثر');
    }
    final settings = await _readSettings();
    settings['adminPin'] = _pinRecord(pin);
    settings['adminPinGuard'] = <String, dynamic>{
      'failedAttempts': 0,
      'lockedUntil': '',
    };
    await _writeSettings(settings);
  }

  Future<SecureRestoreStatus> getAdminPinStatus() async {
    final settings = await _readSettings();
    final guard = _adminPinGuardMap(settings);
    final status = _adminPinStatusFromMap(guard);
    if (!status.locked &&
        status.lockedUntil != null &&
        status.failedAttempts >= _adminPinMaxAttempts) {
      guard['failedAttempts'] = 0;
      guard['lockedUntil'] = '';
      settings['adminPinGuard'] = guard;
      await _writeSettings(settings);
      return const SecureRestoreStatus(
        failedAttempts: 0,
        maxAttempts: _adminPinMaxAttempts,
        remainingAttempts: _adminPinMaxAttempts,
        lockedUntil: null,
        locked: false,
      );
    }
    return status;
  }

  Future<bool> getBiometricEnabled() async {
    final settings = await _readSettings();
    if (!settings.containsKey('biometricEnabled')) {
      if (!_hasStoredAdminPin(settings)) {
        return false;
      }
      settings['biometricEnabled'] = true;
      await _writeSettings(settings);
      return true;
    }
    return settings['biometricEnabled'] == true;
  }

  Future<void> setBiometricEnabled(bool enabled) async {
    final settings = await _readSettings();
    settings['biometricEnabled'] = enabled;
    await _writeSettings(settings);
  }
}
