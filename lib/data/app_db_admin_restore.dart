part of 'app_db.dart';

extension AppDbAdminRestore on AppDb {
  Future<void> restoreBackup() async {
    _requireAdmin();
    final dir = await getApplicationSupportDirectory();
    final backup = File('${dir.path}/king_wallet_backup.db');
    if (!await backup.exists()) {
      throw Exception('لا توجد نسخة احتياطية');
    }
    await restoreBackupFromPath(backup.path);
  }

  static const int _secureRestoreMaxAttempts = 3;
  static const int _secureRestoreLockMinutes = 15;

  Map<String, dynamic> _secureRestoreMap(Map<String, dynamic> m) {
    final raw = m['secureRestoreGuard'];
    if (raw is Map) {
      return Map<String, dynamic>.from(
        raw.map((k, v) => MapEntry(k.toString(), v)),
      );
    }
    return <String, dynamic>{};
  }

  SecureRestoreStatus _secureRestoreStatusFromMap(Map<String, dynamic> map) {
    final failed =
        int.tryParse(
          (map['failedAttempts'] ?? '0').toString(),
        )?.clamp(0, _secureRestoreMaxAttempts) ??
        0;
    final lockIso = (map['lockedUntil'] ?? '').toString().trim();
    final lockTime = lockIso.isEmpty ? null : DateTime.tryParse(lockIso);
    final now = DateTime.now();
    final locked = lockTime != null && lockTime.isAfter(now);
    final remaining = locked
        ? 0
        : (_secureRestoreMaxAttempts - failed).clamp(
            0,
            _secureRestoreMaxAttempts,
          );
    return SecureRestoreStatus(
      failedAttempts: failed,
      maxAttempts: _secureRestoreMaxAttempts,
      remainingAttempts: remaining,
      lockedUntil: lockTime,
      locked: locked,
    );
  }

  Future<SecureRestoreStatus> getEncryptedRestoreStatus() async {
    final m = await _readSettingsMap();
    final guard = _secureRestoreMap(m);
    final status = _secureRestoreStatusFromMap(guard);
    if (!status.locked &&
        status.lockedUntil != null &&
        status.failedAttempts >= _secureRestoreMaxAttempts) {
      guard['failedAttempts'] = 0;
      guard['lockedUntil'] = '';
      m['secureRestoreGuard'] = guard;
      await _writeSettingsMap(m);
      return const SecureRestoreStatus(
        failedAttempts: 0,
        maxAttempts: _secureRestoreMaxAttempts,
        remainingAttempts: _secureRestoreMaxAttempts,
        lockedUntil: null,
        locked: false,
      );
    }
    return status;
  }

  Future<void> _clearEncryptedRestoreGuard() async {
    final m = await _readSettingsMap();
    m['secureRestoreGuard'] = <String, dynamic>{
      'failedAttempts': 0,
      'lockedUntil': '',
    };
    await _writeSettingsMap(m);
  }

  Future<void> resetEncryptedRestoreGuard() async {
    _requireAdmin();
    await _clearEncryptedRestoreGuard();
  }

  String _minutesLabel(Duration d) {
    final mins = d.inMinutes + ((d.inSeconds % 60) > 0 ? 1 : 0);
    return mins <= 0 ? '1' : mins.toString();
  }

  Future<void> _recordEncryptedRestoreFailure() async {
    final m = await _readSettingsMap();
    final guard = _secureRestoreMap(m);
    final current =
        int.tryParse((guard['failedAttempts'] ?? '0').toString()) ?? 0;
    final failed = (current + 1).clamp(1, _secureRestoreMaxAttempts);
    guard['failedAttempts'] = failed;
    if (failed >= _secureRestoreMaxAttempts) {
      guard['lockedUntil'] = DateTime.now()
          .add(const Duration(minutes: _secureRestoreLockMinutes))
          .toIso8601String();
    } else {
      guard['lockedUntil'] = '';
    }
    m['secureRestoreGuard'] = guard;
    await _writeSettingsMap(m);
  }

  Future<void> restoreBackupFromPath(String path) async {
    _requireAdmin();
    final src = File(path);
    if (!await src.exists()) {
      throw Exception('ملف النسخة الاحتياطية غير موجود');
    }
    await _verifyBackupChecksumIfPresent(path);
    final settingsSnapshot = await _readBackupSettingsSidecar(path);
    await _closeSqlite();
    final sourceDb = AppDatabase(
      customPath: src.path,
      hardenRuntimePragmas: false,
    );
    late final ({
      List<Wallet> wallets,
      List<Txn> txns,
      List<Claim> claims,
      List<DailyClose> dailyCloses,
      List<RecentNumber> recentNumbers,
      Map<String, String> meta,
    }) snapshot;
    try {
      snapshot = (
        wallets: await sourceDb.loadWallets(),
        txns: await sourceDb.loadTxns(),
        claims: await sourceDb.loadClaims(),
        dailyCloses: await sourceDb.loadDailyCloses(),
        recentNumbers: await sourceDb.loadRecentNumbers(),
        meta: await sourceDb.loadMeta(),
      );
    } finally {
      await sourceDb.close();
    }

    final db = await _ensureSqliteInitialized();
    await db.saveSnapshot(
      walletItems: snapshot.wallets,
      txnItems: snapshot.txns,
      claimItems: snapshot.claims,
      dailyCloseItems: snapshot.dailyCloses,
      recentNumberItems: snapshot.recentNumbers,
      metaItems: snapshot.meta,
      clearSyncOutbox: true,
    );

    await _restoreSettingsFromBackup(settingsSnapshot);
    _loaded = false;
    await _ensureLoaded();
  }

  Future<void> restoreJsonBackupFromPath(String path) async {
    _requireAdmin();
    final src = File(path);
    if (!await src.exists()) {
      throw Exception('ملف النسخة الاحتياطية غير موجود');
    }
    await _verifyBackupChecksumIfPresent(path);
    final raw = await src.readAsString();
    if (raw.trim().isEmpty) {
      throw Exception('ملف النسخة الاحتياطية فارغ');
    }
    final j = jsonDecode(raw) as Map<String, dynamic>;
    await _restoreFromJsonMap(j);
  }

  Future<void> restoreEncryptedJsonBackupFromPath({
    required String path,
    required String passphrase,
  }) async {
    _requireAdmin();
    final status = await getEncryptedRestoreStatus();
    if (status.locked && status.lockedUntil != null) {
      final left = status.lockedUntil!.difference(DateTime.now());
      throw Exception(
        'Secure restore is temporarily locked. Try again in ${_minutesLabel(left)} minute(s).',
      );
    }

    final src = File(path);
    if (!await src.exists()) {
      throw Exception('ملف النسخة المشفرة غير موجود');
    }
    await _verifyBackupChecksumIfPresent(path);
    final raw = await src.readAsString();
    if (raw.trim().isEmpty) {
      throw Exception('ملف النسخة المشفرة فارغ');
    }
    Map<String, dynamic> j;
    try {
      j = await _decryptBackupJson(envelopeJson: raw, passphrase: passphrase);
    } on SecureBackupAuthException {
      await _recordEncryptedRestoreFailure();
      final nowStatus = await getEncryptedRestoreStatus();
      if (nowStatus.locked && nowStatus.lockedUntil != null) {
        final left = nowStatus.lockedUntil!.difference(DateTime.now());
        throw Exception(
          'Invalid passphrase. Secure restore is locked for ${_minutesLabel(left)} minute(s).',
        );
      }
      throw Exception(
        'Invalid passphrase. Remaining attempts: ${nowStatus.remainingAttempts}.',
      );
    }
    await _restoreFromJsonMap(j);
    await _clearEncryptedRestoreGuard();
  }

  Future<void> _restoreFromJsonMap(Map<String, dynamic> j) async {
    final rawSettings = j['settings'];
    Map<String, dynamic>? settingsSnapshot;
    if (rawSettings is Map) {
      settingsSnapshot = Map<String, dynamic>.from(
        rawSettings.map((k, v) => MapEntry(k.toString(), v)),
      );
    }
    await _restoreSettingsFromBackup(settingsSnapshot);
    await _reopenSqlite();
    _applyJson(j);
    _autoRepairInMemoryDuplicatesAndCounters();
    await _save(clearSyncOutbox: true);
    _rebuildEngineFromTxns();
    _loaded = true;
  }
}
