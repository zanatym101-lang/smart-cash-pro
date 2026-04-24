part of 'app_db.dart';

extension AppDbAdminBackup on AppDb {
  Future<String> exportBackup() async {
    await _ensureLoaded();
    _requireAdmin();
    final dir = await getApplicationSupportDirectory();
    final backup = File('${dir.path}/king_wallet_backup.db');
    await _copyDatabaseSnapshotTo(backup.path);
    await _writeBackupChecksumSidecar(backup.path);
    await _markBackupMeta(type: 'db', path: backup.path);
    return backup.path;
  }

  String _backupFileName(DateTime now) {
    final y = now.year.toString().padLeft(4, '0');
    final m = now.month.toString().padLeft(2, '0');
    final d = now.day.toString().padLeft(2, '0');
    final h = now.hour.toString().padLeft(2, '0');
    final min = now.minute.toString().padLeft(2, '0');
    final s = now.second.toString().padLeft(2, '0');
    return 'smart_cash_backup_$y$m${d}_$h$min$s.db';
  }

  String _backupJsonFileName(DateTime now) {
    final y = now.year.toString().padLeft(4, '0');
    final m = now.month.toString().padLeft(2, '0');
    final d = now.day.toString().padLeft(2, '0');
    final h = now.hour.toString().padLeft(2, '0');
    final min = now.minute.toString().padLeft(2, '0');
    final s = now.second.toString().padLeft(2, '0');
    return 'smart_cash_backup_$y$m${d}_$h$min$s.json';
  }

  String _backupEncryptedFileName(DateTime now) {
    final y = now.year.toString().padLeft(4, '0');
    final m = now.month.toString().padLeft(2, '0');
    final d = now.day.toString().padLeft(2, '0');
    final h = now.hour.toString().padLeft(2, '0');
    final min = now.minute.toString().padLeft(2, '0');
    final s = now.second.toString().padLeft(2, '0');
    return 'smart_cash_backup_$y$m${d}_$h$min$s.scpb';
  }

  String _backupChecksumSidecarPath(String path) => '$path.sha256';

  Future<void> _writeBackupChecksumSidecar(String path) async {
    final file = File(path);
    if (!await file.exists()) return;
    final bytes = await file.readAsBytes();
    final digest = sha256.convert(bytes).toString().toLowerCase();
    final sidecar = File(_backupChecksumSidecarPath(path));
    final payload = <String, dynamic>{
      'algo': 'sha256',
      'digest': digest,
      'size': bytes.length,
      'createdAt': DateTime.now().toIso8601String(),
    };
    await sidecar.writeAsString(jsonEncode(payload), flush: true);
  }

  Future<void> _verifyBackupChecksumIfPresent(String path) async {
    final file = File(path);
    if (!await file.exists()) return;
    final sidecar = File(_backupChecksumSidecarPath(path));
    if (!await sidecar.exists()) return;

    final raw = await sidecar.readAsString();
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return;

    String expectedDigest = '';
    int? expectedSize;
    try {
      final decoded = jsonDecode(trimmed);
      if (decoded is Map<String, dynamic>) {
        expectedDigest = (decoded['digest'] ?? '').toString().trim();
        expectedSize = int.tryParse((decoded['size'] ?? '').toString());
      } else {
        expectedDigest = trimmed;
      }
    } catch (_) {
      expectedDigest = trimmed;
    }

    if (expectedDigest.isEmpty) return;

    final bytes = await file.readAsBytes();
    final actualDigest = sha256.convert(bytes).toString().toLowerCase();
    if (expectedSize != null && expectedSize != bytes.length) {
      throw Exception(
        'فشل التحقق من سلامة النسخة الاحتياطية (حجم الملف غير مطابق)',
      );
    }
    if (expectedDigest.toLowerCase() != actualDigest) {
      throw Exception(
        'فشل التحقق من سلامة النسخة الاحتياطية (تلف أو تعديل غير متوقع)',
      );
    }
  }

  void _validateBackupPassphrase(String passphrase) {
    if (passphrase.trim().length < 8) {
      throw Exception('كلمة المرور يجب أن تكون 8 أحرف على الأقل');
    }
  }

  Future<crypt.SecretKey> _deriveBackupKey({
    required String passphrase,
    required List<int> salt,
    required int iterations,
  }) async {
    final kdf = crypt.Pbkdf2(
      macAlgorithm: crypt.Hmac.sha256(),
      iterations: iterations,
      bits: 256,
    );
    return kdf.deriveKey(
      secretKey: crypt.SecretKey(utf8.encode(passphrase)),
      nonce: salt,
    );
  }

  Future<String> _encryptBackupJson({
    required Map<String, dynamic> payload,
    required String passphrase,
  }) async {
    _validateBackupPassphrase(passphrase);
    const iterations = 150000;
    final rnd = Random.secure();
    final salt = List<int>.generate(16, (_) => rnd.nextInt(256));
    final nonce = List<int>.generate(12, (_) => rnd.nextInt(256));
    final key = await _deriveBackupKey(
      passphrase: passphrase,
      salt: salt,
      iterations: iterations,
    );
    final algorithm = crypt.AesGcm.with256bits();
    final clear = utf8.encode(jsonEncode(payload));
    final box = await algorithm.encrypt(clear, secretKey: key, nonce: nonce);
    final packed = <int>[...box.cipherText, ...box.mac.bytes];
    final envelope = <String, dynamic>{
      'format': 'smart_cash_secure_backup_v1',
      'cipher': 'aes_gcm_256',
      'kdf': 'pbkdf2_hmac_sha256',
      'iterations': iterations,
      'salt': base64Encode(salt),
      'nonce': base64Encode(nonce),
      'data': base64Encode(packed),
      'createdAt': DateTime.now().toIso8601String(),
    };
    return jsonEncode(envelope);
  }

  Future<Map<String, dynamic>> _decryptBackupJson({
    required String envelopeJson,
    required String passphrase,
  }) async {
    _validateBackupPassphrase(passphrase);
    final envelope = jsonDecode(envelopeJson) as Map<String, dynamic>;
    if ((envelope['format'] ?? '').toString() !=
        'smart_cash_secure_backup_v1') {
      throw Exception('صيغة النسخة المشفرة غير مدعومة');
    }
    final iterations =
        int.tryParse((envelope['iterations'] ?? '150000').toString()) ?? 150000;
    final saltRaw = (envelope['salt'] ?? '').toString();
    final nonceRaw = (envelope['nonce'] ?? '').toString();
    final dataRaw = (envelope['data'] ?? '').toString();
    if (saltRaw.isEmpty || nonceRaw.isEmpty || dataRaw.isEmpty) {
      throw Exception('ملف النسخة المشفرة غير مكتمل');
    }
    final salt = base64Decode(saltRaw);
    final nonce = base64Decode(nonceRaw);
    final packed = base64Decode(dataRaw);
    if (packed.length <= 16) {
      throw Exception('بيانات النسخة المشفرة تالفة');
    }

    final key = await _deriveBackupKey(
      passphrase: passphrase,
      salt: salt,
      iterations: iterations,
    );
    final cipher = packed.sublist(0, packed.length - 16);
    final mac = packed.sublist(packed.length - 16);
    final box = crypt.SecretBox(cipher, nonce: nonce, mac: crypt.Mac(mac));
    final algorithm = crypt.AesGcm.with256bits();

    List<int> clear;
    try {
      clear = await algorithm.decrypt(box, secretKey: key);
    } on crypt.SecretBoxAuthenticationError {
      throw const SecureBackupAuthException(
        'Invalid passphrase or tampered file',
      );
    }
    final decoded = utf8.decode(clear);
    final payload = jsonDecode(decoded);
    if (payload is! Map<String, dynamic>) {
      throw Exception('بيانات النسخة غير صالحة');
    }
    return payload;
  }

  Future<void> _markBackupMeta({
    required String type,
    required String path,
  }) async {
    final m = await _readSettingsMap();
    m['backupMeta'] = <String, dynamic>{
      'lastAt': DateTime.now().toIso8601String(),
      'type': type,
      'path': path,
    };
    await _writeSettingsMap(m);
  }

  static const Set<String> _localOnlySettingsKeys = <String>{
    'backupMeta',
    'secureRestoreGuard',
    'adminPinGuard',
  };

  static const Set<String> _sensitiveLicenseSettingsKeys = <String>{
    'activationCode',
    'cloudToken',
    'cloudTokenExpiresAt',
    'cloudLicenseExpiresAt',
    'cloudDeviceId',
    'cloudLastCheckAt',
    'cloudLastError',
    'cloudActivatedAt',
    'serverAuthRefreshToken',
    'serverAuthRefreshTokenExpiresAt',
  };

  Map<String, dynamic> _sanitizeLicenseSettings(Map<String, dynamic> settings) {
    final copy = Map<String, dynamic>.from(settings);
    final rawLicense = copy['license'];
    if (rawLicense is Map) {
      final license = Map<String, dynamic>.from(
        rawLicense.map((k, v) => MapEntry(k.toString(), v)),
      );
      final keys = List<String>.from(license.keys);
      for (final key in keys) {
        if (_sensitiveLicenseSettingsKeys.contains(key) ||
            key.startsWith('serverAuthDiag')) {
          license.remove(key);
        }
      }
      copy['license'] = license;
    }
    return copy;
  }

  Map<String, dynamic> _backupableSettingsMap(Map<String, dynamic> settings) {
    final copy = Map<String, dynamic>.from(settings);
    for (final key in _localOnlySettingsKeys) {
      copy.remove(key);
    }
    return _sanitizeLicenseSettings(copy);
  }

  Map<String, dynamic> _mergeRestoredSettingsWithLocal({
    required Map<String, dynamic> restored,
    required Map<String, dynamic> current,
  }) {
    final merged = _sanitizeLicenseSettings(restored);
    for (final key in _localOnlySettingsKeys) {
      if (current.containsKey(key)) {
        merged[key] = current[key];
      }
    }

    final currentLicenseRaw = current['license'];
    final mergedLicenseRaw = merged['license'];
    if (currentLicenseRaw is Map) {
      final currentLicense = Map<String, dynamic>.from(
        currentLicenseRaw.map((k, v) => MapEntry(k.toString(), v)),
      );
      final mergedLicense = mergedLicenseRaw is Map
          ? Map<String, dynamic>.from(
              mergedLicenseRaw.map((k, v) => MapEntry(k.toString(), v)),
            )
          : <String, dynamic>{};

      for (final entry in currentLicense.entries) {
        final key = entry.key;
        if (_sensitiveLicenseSettingsKeys.contains(key) ||
            key.startsWith('serverAuthDiag')) {
          mergedLicense[key] = entry.value;
        }
      }
      merged['license'] = mergedLicense;
    }
    return merged;
  }

  String _backupSettingsSidecarPath(String path) => '$path.settings.json';

  Future<void> _writeBackupSettingsSidecar(String path) async {
    final file = File(_backupSettingsSidecarPath(path));
    final settings = _backupableSettingsMap(await _readSettingsMap());
    final payload = <String, dynamic>{
      'format': 'king_wallet_settings_backup_v1',
      'settings': settings,
    };
    await file.writeAsString(jsonEncode(payload), flush: true);
  }

  Future<Map<String, dynamic>?> _readBackupSettingsSidecar(String path) async {
    final file = File(_backupSettingsSidecarPath(path));
    if (!await file.exists()) return null;
    try {
      final raw = await file.readAsString();
      if (raw.trim().isEmpty) return null;
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return null;
      final wrapped = decoded['settings'];
      if (wrapped is! Map) return null;
      return Map<String, dynamic>.from(
        wrapped.map((k, v) => MapEntry(k.toString(), v)),
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> _restoreSettingsFromBackup(
    Map<String, dynamic>? restoredSettings,
  ) async {
    if (restoredSettings == null) return;
    final current = await _readSettingsMap();
    final merged = _mergeRestoredSettingsWithLocal(
      restored: restoredSettings,
      current: current,
    );
    await _writeSettingsMap(merged);
    final hour = int.tryParse((merged['dayStartHour'] ?? '0').toString()) ?? 0;
    _setDayStartHourCache(hour);
  }

  Future<void> _copyDatabaseSnapshotTo(String destinationPath) async {
    final dataFile = await _sqliteFile();
    if (!await dataFile.exists()) {
      await _save();
    }
    await _closeSqlite();
    try {
      final bytes = await dataFile.readAsBytes();
      final out = File(destinationPath);
      if (await out.exists()) {
        await out.delete();
      }
      await out.writeAsBytes(bytes, flush: true);
    } finally {
      await _reopenSqlite();
    }
  }

  Future<Map<String, dynamic>> _buildJsonBackup() async {
    return <String, dynamic>{
      'nextWalletId': _nextWalletId,
      'nextTxnId': _nextTxnId,
      'nextClaimId': _nextClaimId,
      'nextCloseId': _nextCloseId,
      'nextAttachmentId': _nextAttachmentId,
      'wallets': _wallets.map((w) => w.toJson()).toList(),
      'txns': _txns.map((t) => t.toJson()).toList(),
      'claims': _claims.map((c) => c.toJson()).toList(),
      'dailyCloses': _dailyCloses.map((c) => c.toJson()).toList(),
      'recentNumbers': _recentNumbers.map((r) => r.toJson()).toList(),
      'customerAttachments': _customerAttachments
          .map((a) => a.toJson())
          .toList(),
      'lastPendingAlertDate': _lastPendingAlertDate,
      'lowBalanceAlertDate': _lowBalanceAlertDate.map(
        (k, v) => MapEntry(k.toString(), v),
      ),
      'dailyUsageResetAt': _dailyUsageResetAt.map(
        (k, v) => MapEntry(k.toString(), v.toIso8601String()),
      ),
      'monthlyUsageResetAt': _monthlyUsageResetAt.map(
        (k, v) => MapEntry(k.toString(), v.toIso8601String()),
      ),
      'settings': _backupableSettingsMap(await _readSettingsMap()),
    };
  }

  Future<String> exportBackupToDownloads() async {
    await _ensureLoaded();
    _requireAdmin();
    final downloads = await getDownloadsDirectory();
    final dir = downloads ?? await getApplicationSupportDirectory();
    final name = _backupFileName(DateTime.now());
    final backup = File('${dir.path}/$name');
    await _copyDatabaseSnapshotTo(backup.path);
    await _writeBackupChecksumSidecar(backup.path);
    await _markBackupMeta(type: 'db', path: backup.path);
    await _writeBackupSettingsSidecar(backup.path);
    return backup.path;
  }

  Future<String> exportBackupToPath(String directoryPath) async {
    await _ensureLoaded();
    _requireAdmin();
    final name = _backupFileName(DateTime.now());
    final path = p.join(directoryPath, name);
    await _copyDatabaseSnapshotTo(path);
    await _writeBackupChecksumSidecar(path);
    await _markBackupMeta(type: 'db', path: path);
    await _writeBackupSettingsSidecar(path);
    return path;
  }

  Future<String> exportJsonBackupToDownloads() async {
    await _ensureLoaded();
    _requireAdmin();
    final downloads = await getDownloadsDirectory();
    final dir = downloads ?? await getApplicationSupportDirectory();
    final name = _backupJsonFileName(DateTime.now());
    final file = File('${dir.path}/$name');
    final j = await _buildJsonBackup();
    await file.writeAsString(jsonEncode(j));
    await _writeBackupChecksumSidecar(file.path);
    await _markBackupMeta(type: 'json', path: file.path);
    return file.path;
  }

  Future<String> exportJsonBackupToPath(String directoryPath) async {
    await _ensureLoaded();
    _requireAdmin();
    final name = _backupJsonFileName(DateTime.now());
    final path = p.join(directoryPath, name);
    final file = File(path);
    final j = await _buildJsonBackup();
    await file.writeAsString(jsonEncode(j));
    await _writeBackupChecksumSidecar(file.path);
    await _markBackupMeta(type: 'json', path: file.path);
    return file.path;
  }

  Future<String> exportEncryptedJsonBackupToDownloads({
    required String passphrase,
  }) async {
    await _ensureLoaded();
    _requireAdmin();
    final downloads = await getDownloadsDirectory();
    final dir = downloads ?? await getApplicationSupportDirectory();
    final name = _backupEncryptedFileName(DateTime.now());
    final file = File('${dir.path}/$name');
    final encrypted = await _encryptBackupJson(
      payload: await _buildJsonBackup(),
      passphrase: passphrase,
    );
    await file.writeAsString(encrypted);
    await _writeBackupChecksumSidecar(file.path);
    await _markBackupMeta(type: 'json_encrypted', path: file.path);
    return file.path;
  }

  Future<String> exportEncryptedJsonBackupToPath({
    required String directoryPath,
    required String passphrase,
  }) async {
    await _ensureLoaded();
    _requireAdmin();
    final name = _backupEncryptedFileName(DateTime.now());
    final path = p.join(directoryPath, name);
    final file = File(path);
    final encrypted = await _encryptBackupJson(
      payload: await _buildJsonBackup(),
      passphrase: passphrase,
    );
    await file.writeAsString(encrypted);
    await _writeBackupChecksumSidecar(file.path);
    await _markBackupMeta(type: 'json_encrypted', path: file.path);
    return file.path;
  }
}
