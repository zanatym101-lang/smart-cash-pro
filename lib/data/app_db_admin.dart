part of 'app_db.dart';

const List<String> kDefaultQuickActionsOrder = [
  'help',
  'transfer',
  'receive',
  'fawry',
  'wallets',
  'treasury',
  'pending',
  'reports',
  'expenses',
  'claims',
  'wallet_funding',
];

extension AppDbAdmin on AppDb {
  // ===========================
  // Admin PIN (local settings)
  // ===========================
  static const String _licenseSecret = 'SCP-2026-LICENSE';

  void _requireAdmin() {
    if (!AppSession.isAdmin) {
      throw Exception('ظ‡ط°ط§ ط§ظ„ط¥ط¬ط±ط§ط، ظ…طھط§ط­ ظ„ظ„ط£ط¯ظ…ظ† ظپظ‚ط·');
    }
  }

  Future<File> _settingsFile() async {
    final dir = await getApplicationSupportDirectory();
    return File('${dir.path}/king_wallet_settings.json');
  }

  Future<Map<String, dynamic>> _readSettingsMap() async {
    final f = await _settingsFile();
    if (!await f.exists()) return {};
    try {
      final raw = await f.readAsString();
      final m = jsonDecode(raw);
      if (m is Map<String, dynamic>) {
        return Map<String, dynamic>.from(m);
      }
    } catch (_) {}
    return {};
  }

  Future<void> _writeSettingsMap(Map<String, dynamic> m) async {
    final f = await _settingsFile();
    await f.writeAsString(jsonEncode(m));
  }

  ({Map<String, dynamic> license, bool changed}) _ensureLicense(
    Map<String, dynamic> m,
  ) {
    bool changed = false;
    final license = Map<String, dynamic>.from(m['license'] ?? {});

    if (!license.containsKey('installDate')) {
      license['installDate'] = DateTime.now().toIso8601String();
      changed = true;
    }
    if (!license.containsKey('trialDays')) {
      license['trialDays'] = 7;
      changed = true;
    }
    if (!license.containsKey('maxOperations')) {
      license['maxOperations'] = 20;
      changed = true;
    }
    if (!license.containsKey('operationsUsed')) {
      license['operationsUsed'] = 0;
      changed = true;
    }
    if (!license.containsKey('maxWallets')) {
      license['maxWallets'] = 2;
      changed = true;
    }
    if (!license.containsKey('maxReports')) {
      license['maxReports'] = 3;
      changed = true;
    }
    if (!license.containsKey('reportsUsed')) {
      license['reportsUsed'] = 0;
      changed = true;
    }
    if (!license.containsKey('activationCode')) {
      license['activationCode'] = '';
      changed = true;
    }

    if (changed) {
      m['license'] = license;
    }
    return (license: license, changed: changed);
  }

  String _normalizeCode(String input) {
    final upper = input.toUpperCase();
    final buf = StringBuffer();
    for (final r in upper.runes) {
      final ch = String.fromCharCode(r);
      final isAlpha = ch.codeUnitAt(0) >= 65 && ch.codeUnitAt(0) <= 90;
      final isDigit = ch.codeUnitAt(0) >= 48 && ch.codeUnitAt(0) <= 57;
      if (isAlpha || isDigit) buf.write(ch);
    }
    return buf.toString();
  }

  String _formatCode(String raw, int group) {
    final clean = _normalizeCode(raw);
    final parts = <String>[];
    for (var i = 0; i < clean.length; i += group) {
      final end = (i + group > clean.length) ? clean.length : i + group;
      parts.add(clean.substring(i, end));
    }
    return parts.join('-');
  }

  String _hashHex(String input) {
    final bytes = utf8.encode(input);
    return sha256.convert(bytes).toString().toUpperCase();
  }

  Future<String> _deviceFingerprint() async {
    final info = DeviceInfoPlugin();
    try {
      if (Platform.isAndroid) {
        final a = await info.androidInfo;
        return 'android|${a.fingerprint}|${a.id}';
      }
      if (Platform.isIOS) {
        final i = await info.iosInfo;
        return 'ios|${i.identifierForVendor ?? i.name}';
      }
      if (Platform.isWindows) {
        final w = await info.windowsInfo;
        return 'windows|${w.deviceId}';
      }
      if (Platform.isMacOS) {
        final m = await info.macOsInfo;
        return 'macos|${m.systemGUID ?? m.model}';
      }
      if (Platform.isLinux) {
        final l = await info.linuxInfo;
        return 'linux|${l.machineId ?? l.id}';
      }
    } catch (_) {}
    return 'unknown|${Platform.operatingSystem}';
  }

  Future<String> _deviceCode() async {
    final fp = await _deviceFingerprint();
    final h = _hashHex(fp);
    return _formatCode(h.substring(0, 16), 4);
  }

  String _activationCodeForDeviceCode(String deviceCode) {
    final base = _normalizeCode(deviceCode);
    final h = _hashHex('$_licenseSecret|$base');
    return _formatCode(h.substring(0, 12), 4);
  }

  bool _isActivationValid(String code, String deviceCode) {
    final expected = _normalizeCode(_activationCodeForDeviceCode(deviceCode));
    final given = _normalizeCode(code);
    return given.isNotEmpty && given == expected;
  }

  String generateActivationCodeForDeviceCode(String deviceCode) {
    final base = _normalizeCode(deviceCode);
    if (base.isEmpty) return '';
    final h = _hashHex('$_licenseSecret|$base');
    return _formatCode(h.substring(0, 12), 4);
  }

  Future<LicenseInfo> getLicenseInfo() async {
    final m = await _readSettingsMap();
    final ensured = _ensureLicense(m);
    final license = ensured.license;
    if (ensured.changed || !m.containsKey('license')) {
      m['license'] = license;
      await _writeSettingsMap(m);
    }

    final deviceCode = await _deviceCode();
    final activationCode = (license['activationCode'] ?? '').toString().trim();
    final isActivated = _isActivationValid(activationCode, deviceCode);

    final installDate =
        DateTime.tryParse((license['installDate'] ?? '').toString()) ??
        DateTime.now();
    final trialDays =
        int.tryParse((license['trialDays'] ?? '7').toString()) ?? 7;
    final maxOperations =
        int.tryParse((license['maxOperations'] ?? '20').toString()) ?? 20;
    final maxWallets =
        int.tryParse((license['maxWallets'] ?? '2').toString()) ?? 2;
    final maxReports =
        int.tryParse((license['maxReports'] ?? '3').toString()) ?? 3;
    final operationsUsed =
        int.tryParse((license['operationsUsed'] ?? '0').toString()) ?? 0;
    final reportsUsed =
        int.tryParse((license['reportsUsed'] ?? '0').toString()) ?? 0;

    final daysUsed = DateTime.now().difference(installDate).inDays;
    final daysLeft = (trialDays - daysUsed).clamp(0, trialDays);
    final operationsLeft = (maxOperations - operationsUsed).clamp(
      0,
      maxOperations,
    );
    final reportsLeft = (maxReports - reportsUsed).clamp(0, maxReports);

    return LicenseInfo(
      isActivated: isActivated,
      deviceCode: deviceCode,
      trialDays: trialDays,
      daysUsed: daysUsed,
      daysLeft: daysLeft,
      maxOperations: maxOperations,
      operationsUsed: operationsUsed,
      operationsLeft: operationsLeft,
      maxWallets: maxWallets,
      maxReports: maxReports,
      reportsUsed: reportsUsed,
      reportsLeft: reportsLeft,
    );
  }

  Future<bool> activateWithCode(String code) async {
    final m = await _readSettingsMap();
    final ensured = _ensureLicense(m);
    final license = ensured.license;
    final deviceCode = await _deviceCode();
    if (!_isActivationValid(code, deviceCode)) {
      return false;
    }
    license['activationCode'] = code.trim();
    m['license'] = license;
    await _writeSettingsMap(m);
    return true;
  }

  Future<void> _ensureOperationAllowed() async {
    final info = await getLicenseInfo();
    if (info.isActivated) return;
    if (info.daysLeft <= 0) {
      throw Exception('ط§ظ†طھظ‡طھ ط§ظ„ظپطھط±ط© ط§ظ„طھط¬ط±ظٹط¨ظٹط©');
    }
    if (info.operationsLeft <= 0) {
      throw Exception(
        'طھظ… طھط¬ط§ظˆط² ط§ظ„ط­ط¯ ط§ظ„طھط¬ط±ظٹط¨ظٹ ظ„ظ„ط¹ظ…ظ„ظٹط§طھ (${info.maxOperations})',
      );
    }
  }

  Future<void> _incrementOperationUsed() async {
    final m = await _readSettingsMap();
    final ensured = _ensureLicense(m);
    final license = ensured.license;
    final used =
        int.tryParse((license['operationsUsed'] ?? '0').toString()) ?? 0;
    license['operationsUsed'] = used + 1;
    m['license'] = license;
    await _writeSettingsMap(m);
  }

  Future<void> _ensureWalletAllowed() async {
    final info = await getLicenseInfo();
    if (info.isActivated) return;
    if (info.daysLeft <= 0) {
      throw Exception('ط§ظ†طھظ‡طھ ط§ظ„ظپطھط±ط© ط§ظ„طھط¬ط±ظٹط¨ظٹط©');
    }
    if (_wallets.length >= info.maxWallets) {
      throw Exception(
        'ظ†ط³ط®ط© طھط¬ط±ظٹط¨ظٹط©: ط§ظ„ط­ط¯ ط§ظ„ط£ظ‚طµظ‰ ظ„ظ„ظ…ط­ط§ظپط¸ ${info.maxWallets}',
      );
    }
  }

  Future<bool> consumeReportView() async {
    final info = await getLicenseInfo();
    if (info.isActivated) return true;
    if (info.daysLeft <= 0) return false;
    if (info.reportsLeft <= 0) return false;

    final m = await _readSettingsMap();
    final ensured = _ensureLicense(m);
    final license = ensured.license;
    final used = int.tryParse((license['reportsUsed'] ?? '0').toString()) ?? 0;
    license['reportsUsed'] = used + 1;
    m['license'] = license;
    await _writeSettingsMap(m);
    return true;
  }

  static const String _pinFormatPrefix = 'v2';
  static const int _pinIterations = 25000;

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

  Future<String> getDeveloperPin() async {
    final m = await _readSettingsMap();
    if (!m.containsKey('devPin')) {
      m['devPin'] = _pinRecord('7777');
      await _writeSettingsMap(m);
      return '7777';
    }
    final stored = (m['devPin'] ?? '').toString().trim();
    if (stored.isEmpty) {
      m['devPin'] = _pinRecord('7777');
      await _writeSettingsMap(m);
      return '7777';
    }
    final decoded = _decodeIfLegacy(stored);
    if (decoded.isNotEmpty) {
      m['devPin'] = _pinRecord(decoded);
      await _writeSettingsMap(m);
      return decoded;
    }
    return '';
  }

  Future<bool> verifyDeveloperPin(String pin) async {
    final m = await _readSettingsMap();
    if (!m.containsKey('devPin') ||
        (m['devPin'] ?? '').toString().trim().isEmpty) {
      m['devPin'] = _pinRecord('7777');
      await _writeSettingsMap(m);
    }
    final stored = (m['devPin'] ?? '').toString().trim();
    final ok = _verifyPinRecord(stored, pin);
    if (ok && !stored.startsWith('$_pinFormatPrefix:')) {
      m['devPin'] = _pinRecord(pin.trim());
      await _writeSettingsMap(m);
    }
    return ok;
  }

  Future<void> setDeveloperPin(String newPin) async {
    final pin = newPin.trim();
    if (pin.length < 4) {
      throw Exception('PIN ظٹط¬ط¨ ط£ظ† ظٹظƒظˆظ† 4 ط£ط±ظ‚ط§ظ… ط£ظˆ ط£ظƒط«ط±');
    }
    final m = await _readSettingsMap();
    m['devPin'] = _pinRecord(pin);
    await _writeSettingsMap(m);
  }

  Future<String> getAdminPin() async {
    final m = await _readSettingsMap();
    if (!m.containsKey('adminPin')) {
      m['adminPin'] = _pinRecord('1234');
      await _writeSettingsMap(m);
      return '1234';
    }
    final stored = (m['adminPin'] ?? '').toString().trim();
    if (stored.isEmpty) {
      m['adminPin'] = _pinRecord('1234');
      await _writeSettingsMap(m);
      return '1234';
    }
    final decoded = _decodeIfLegacy(stored);
    if (decoded.isNotEmpty) {
      m['adminPin'] = _pinRecord(decoded);
      await _writeSettingsMap(m);
      return decoded;
    }
    return '';
  }

  Future<bool> verifyAdminPin(String pin) async {
    final m = await _readSettingsMap();
    if (!m.containsKey('adminPin') ||
        (m['adminPin'] ?? '').toString().trim().isEmpty) {
      m['adminPin'] = _pinRecord('1234');
      await _writeSettingsMap(m);
    }
    final stored = (m['adminPin'] ?? '').toString().trim();
    final ok = _verifyPinRecord(stored, pin);
    if (ok && !stored.startsWith('$_pinFormatPrefix:')) {
      m['adminPin'] = _pinRecord(pin.trim());
      await _writeSettingsMap(m);
    }
    return ok;
  }

  Future<void> setAdminPin(String newPin) async {
    final pin = newPin.trim();
    if (pin.length < 4) {
      throw Exception('PIN ظٹط¬ط¨ ط£ظ† ظٹظƒظˆظ† 4 ط£ط±ظ‚ط§ظ… ط£ظˆ ط£ظƒط«ط±');
    }
    final m = await _readSettingsMap();
    m['adminPin'] = _pinRecord(pin);
    await _writeSettingsMap(m);
  }

  Future<bool> getBiometricEnabled() async {
    final m = await _readSettingsMap();
    if (!m.containsKey('biometricEnabled')) {
      if (!m.containsKey('adminPin')) {
        m['adminPin'] = _pinRecord('1234');
      }
      m['biometricEnabled'] = true;
      await _writeSettingsMap(m);
      return true;
    }
    return m['biometricEnabled'] == true;
  }

  Future<void> setBiometricEnabled(bool enabled) async {
    final m = await _readSettingsMap();
    m['biometricEnabled'] = enabled;
    if (!m.containsKey('adminPin')) {
      m['adminPin'] = _pinRecord('1234');
    }
    await _writeSettingsMap(m);
  }

  Future<AppSettings> getAppSettings() async {
    final m = await _readSettingsMap();
    bool changed = false;

    String businessName = (m['businessName'] ?? '').toString().trim();
    if (businessName.isEmpty) {
      businessName = 'ط§ظ„ظ†ط´ط§ط·';
      changed = true;
    }

    String currency = (m['currency'] ?? '').toString().trim();
    if (currency.isEmpty) {
      currency = 'EGP';
      changed = true;
    }

    int dayStartHour = int.tryParse((m['dayStartHour'] ?? '0').toString()) ?? 0;
    if (dayStartHour < 0 || dayStartHour > 23) {
      dayStartHour = 0;
      changed = true;
    }

    List<String> quickActionsOrder = [];
    final rawOrder = m['quickActionsOrder'];
    if (rawOrder is List) {
      quickActionsOrder = rawOrder.map((e) => e.toString()).toList();
    }
    if (quickActionsOrder.isEmpty) {
      quickActionsOrder = List<String>.from(kDefaultQuickActionsOrder);
      changed = true;
    }

    if (changed) {
      m['businessName'] = businessName;
      m['currency'] = currency;
      m['dayStartHour'] = dayStartHour;
      m['quickActionsOrder'] = quickActionsOrder;
      if (!m.containsKey('adminPin')) {
        m['adminPin'] = _pinRecord('1234');
      }
      await _writeSettingsMap(m);
    }
    _setDayStartHourCache(dayStartHour);

    return AppSettings(
      businessName: businessName,
      currency: currency,
      dayStartHour: dayStartHour,
      quickActionsOrder: quickActionsOrder,
    );
  }

  Future<List<String>> getQuickActionsOrder() async {
    final settings = await getAppSettings();
    return settings.quickActionsOrder;
  }

  Future<void> setQuickActionsOrder(List<String> order) async {
    final settings = await getAppSettings();
    final updated = settings.copyWith(quickActionsOrder: order);
    await setAppSettings(updated);
  }

  Future<void> setAppSettings(AppSettings settings) async {
    final name = settings.businessName.trim();
    final currency = settings.currency.trim();
    final hour = settings.dayStartHour;
    if (name.isEmpty) throw Exception('ط§ط³ظ… ط§ظ„ظ†ط´ط§ط· ظ…ط·ظ„ظˆط¨');
    if (currency.isEmpty) throw Exception('ط§ظ„ط¹ظ…ظ„ط© ظ…ط·ظ„ظˆط¨ط©');
    if (hour < 0 || hour > 23) {
      throw Exception('ط¨ط¯ط§ظٹط© ط§ظ„ظٹظˆظ… ط؛ظٹط± طµط­ظٹط­ط©');
    }

    final m = await _readSettingsMap();
    m['businessName'] = name;
    m['currency'] = currency;
    m['dayStartHour'] = hour;
    m['quickActionsOrder'] = settings.quickActionsOrder;
    if (!m.containsKey('adminPin')) {
      m['adminPin'] = _pinRecord('1234');
    }
    await _writeSettingsMap(m);
    _setDayStartHourCache(hour);
  }

  Future<String> exportBackup() async {
    await _ensureLoaded();
    _requireAdmin();
    final dir = await getApplicationSupportDirectory();
    final backup = File('${dir.path}/king_wallet_backup.db');
    await _copyDatabaseSnapshotTo(backup.path);
    return backup.path;
  }

  Future<void> restoreBackup() async {
    _requireAdmin();
    final dir = await getApplicationSupportDirectory();
    final backup = File('${dir.path}/king_wallet_backup.db');
    if (!await backup.exists()) {
      throw Exception('ظ„ط§ طھظˆط¬ط¯ ظ†ط³ط®ط© ط§ط­طھظٹط§ط·ظٹط©');
    }
    await _closeSqlite();
    final dataFile = await _sqliteFile();
    if (await dataFile.exists()) {
      await dataFile.delete();
    }
    final bytes = await backup.readAsBytes();
    await dataFile.writeAsBytes(bytes, flush: true);
    await _reopenSqlite();
    _loaded = false;
    await _ensureLoaded();
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

  Map<String, dynamic> _buildJsonBackup() {
    return <String, dynamic>{
      'nextWalletId': _nextWalletId,
      'nextTxnId': _nextTxnId,
      'nextClaimId': _nextClaimId,
      'nextCloseId': _nextCloseId,
      'wallets': _wallets.map((w) => w.toJson()).toList(),
      'txns': _txns.map((t) => t.toJson()).toList(),
      'claims': _claims.map((c) => c.toJson()).toList(),
      'dailyCloses': _dailyCloses.map((c) => c.toJson()).toList(),
      'recentNumbers': _recentNumbers.map((r) => r.toJson()).toList(),
      'lastPendingAlertDate': _lastPendingAlertDate,
      'lowBalanceAlertDate': _lowBalanceAlertDate.map(
        (k, v) => MapEntry(k.toString(), v),
      ),
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
    return backup.path;
  }

  Future<String> exportBackupToPath(String directoryPath) async {
    await _ensureLoaded();
    _requireAdmin();
    final name = _backupFileName(DateTime.now());
    final path = p.join(directoryPath, name);
    await _copyDatabaseSnapshotTo(path);
    return path;
  }

  Future<void> restoreBackupFromPath(String path) async {
    _requireAdmin();
    final src = File(path);
    if (!await src.exists()) {
      throw Exception(
        'ظ…ظ„ظپ ط§ظ„ظ†ط³ط®ط© ط§ظ„ط§ط­طھظٹط§ط·ظٹط© ط؛ظٹط± ظ…ظˆط¬ظˆط¯',
      );
    }
    await _closeSqlite();
    final dataFile = await _sqliteFile();
    if (await dataFile.exists()) {
      await dataFile.delete();
    }
    final bytes = await src.readAsBytes();
    await dataFile.writeAsBytes(bytes, flush: true);
    await _reopenSqlite();
    _loaded = false;
    await _ensureLoaded();
  }

  Future<String> exportJsonBackupToDownloads() async {
    await _ensureLoaded();
    _requireAdmin();
    final downloads = await getDownloadsDirectory();
    final dir = downloads ?? await getApplicationSupportDirectory();
    final name = _backupJsonFileName(DateTime.now());
    final file = File('${dir.path}/$name');
    final j = _buildJsonBackup();
    await file.writeAsString(jsonEncode(j));
    return file.path;
  }

  Future<String> exportJsonBackupToPath(String directoryPath) async {
    await _ensureLoaded();
    _requireAdmin();
    final name = _backupJsonFileName(DateTime.now());
    final path = p.join(directoryPath, name);
    final file = File(path);
    final j = _buildJsonBackup();
    await file.writeAsString(jsonEncode(j));
    return file.path;
  }

  Future<void> restoreJsonBackupFromPath(String path) async {
    _requireAdmin();
    final src = File(path);
    if (!await src.exists()) {
      throw Exception(
        'ظ…ظ„ظپ ط§ظ„ظ†ط³ط®ط© ط§ظ„ط§ط­طھظٹط§ط·ظٹط© ط؛ظٹط± ظ…ظˆط¬ظˆط¯',
      );
    }
    final raw = await src.readAsString();
    if (raw.trim().isEmpty) {
      throw Exception('ظ…ظ„ظپ ط§ظ„ظ†ط³ط®ط© ط§ظ„ط§ط­طھظٹط§ط·ظٹط© ظپط§ط±ط؛');
    }
    final j = jsonDecode(raw) as Map<String, dynamic>;
    await _reopenSqlite();
    _applyJson(j);
    await _save();
    _rebuildEngineFromTxns();
    _loaded = true;
  }
}
