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
      throw Exception('هذا الإجراء متاح للأدمن فقط');
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
      throw Exception('انتهت الفترة التجريبية');
    }
    if (info.operationsLeft <= 0) {
      throw Exception(
        'تم تجاوز الحد التجريبي للعمليات (${info.maxOperations})',
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
      throw Exception('انتهت الفترة التجريبية');
    }
    if (_wallets.length >= info.maxWallets) {
      throw Exception('نسخة تجريبية: الحد الأقصى للمحافظ ${info.maxWallets}');
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
  static const int _adminPinMaxAttempts = 5;
  static const int _adminPinLockMinutes = 15;

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
      throw Exception('PIN يجب أن يكون 4 أرقام أو أكثر');
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
    final status = await getAdminPinStatus();
    if (status.locked) {
      return false;
    }
    final stored = (m['adminPin'] ?? '').toString().trim();
    final ok = _verifyPinRecord(stored, pin);
    if (ok) {
      if (!stored.startsWith('$_pinFormatPrefix:')) {
        m['adminPin'] = _pinRecord(pin.trim());
      }
      m['adminPinGuard'] = <String, dynamic>{
        'failedAttempts': 0,
        'lockedUntil': '',
      };
      await _writeSettingsMap(m);
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
    final m = await _readSettingsMap();
    m['adminPin'] = _pinRecord(pin);
    m['adminPinGuard'] = <String, dynamic>{
      'failedAttempts': 0,
      'lockedUntil': '',
    };
    await _writeSettingsMap(m);
  }

  Map<String, dynamic> _adminPinGuardMap(Map<String, dynamic> m) {
    final raw = m['adminPinGuard'];
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

  Future<SecureRestoreStatus> getAdminPinStatus() async {
    final m = await _readSettingsMap();
    final guard = _adminPinGuardMap(m);
    final status = _adminPinStatusFromMap(guard);
    if (!status.locked &&
        status.lockedUntil != null &&
        status.failedAttempts >= _adminPinMaxAttempts) {
      guard['failedAttempts'] = 0;
      guard['lockedUntil'] = '';
      m['adminPinGuard'] = guard;
      await _writeSettingsMap(m);
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

  Future<void> _recordAdminPinFailure() async {
    final m = await _readSettingsMap();
    final guard = _adminPinGuardMap(m);
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
    m['adminPinGuard'] = guard;
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
      businessName = 'النشاط';
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

    List<String> pinnedCustomers = [];
    final rawPinned = m['pinnedCustomers'];
    if (rawPinned is List) {
      pinnedCustomers = rawPinned.map((e) => e.toString()).toList();
    }
    if (!m.containsKey('pinnedCustomers')) {
      m['pinnedCustomers'] = pinnedCustomers;
      changed = true;
    }

    double customerAlertThreshold = 0;
    final rawThreshold = m['customerAlertThreshold'];
    if (rawThreshold is num) {
      customerAlertThreshold = rawThreshold.toDouble();
    } else if (rawThreshold != null) {
      customerAlertThreshold =
          double.tryParse(rawThreshold.toString().trim()) ?? 0;
    }
    if (customerAlertThreshold < 0) {
      customerAlertThreshold = 0;
      changed = true;
    }
    if (!m.containsKey('customerAlertThreshold')) {
      m['customerAlertThreshold'] = customerAlertThreshold;
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
      pinnedCustomers: pinnedCustomers,
      customerAlertThreshold: customerAlertThreshold,
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
    if (name.isEmpty) throw Exception('اسم النشاط مطلوب');
    if (currency.isEmpty) throw Exception('العملة مطلوبة');
    if (hour < 0 || hour > 23) {
      throw Exception('بداية اليوم غير صحيحة');
    }

    final m = await _readSettingsMap();
    m['businessName'] = name;
    m['currency'] = currency;
    m['dayStartHour'] = hour;
    m['quickActionsOrder'] = settings.quickActionsOrder;
    m['pinnedCustomers'] = settings.pinnedCustomers;
    m['customerAlertThreshold'] = settings.customerAlertThreshold;
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
    await _writeBackupChecksumSidecar(backup.path);
    await _markBackupMeta(type: 'db', path: backup.path);
    return backup.path;
  }

  Future<void> restoreBackup() async {
    _requireAdmin();
    final dir = await getApplicationSupportDirectory();
    final backup = File('${dir.path}/king_wallet_backup.db');
    if (!await backup.exists()) {
      throw Exception('لا توجد نسخة احتياطية');
    }
    await restoreBackupFromPath(backup.path);
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

  static const int _secureRestoreMaxAttempts = 3;
  static const int _secureRestoreLockMinutes = 15;

  void _validateBackupPassphrase(String passphrase) {
    if (passphrase.trim().length < 8) {
      throw Exception('كلمة المرور يجب أن تكون 8 أحرف على الأقل');
    }
  }

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
    return path;
  }

  Future<void> restoreBackupFromPath(String path) async {
    _requireAdmin();
    final src = File(path);
    if (!await src.exists()) {
      throw Exception('ملف النسخة الاحتياطية غير موجود');
    }
    await _verifyBackupChecksumIfPresent(path);
    final sourceDb = AppDatabase(
      customPath: src.path,
      hardenRuntimePragmas: false,
    );
    try {
      final snapshot = (
        wallets: await sourceDb.loadWallets(),
        txns: await sourceDb.loadTxns(),
        claims: await sourceDb.loadClaims(),
        dailyCloses: await sourceDb.loadDailyCloses(),
        recentNumbers: await sourceDb.loadRecentNumbers(),
        meta: await sourceDb.loadMeta(),
      );

      await _reopenSqlite();
      await _sqlite.saveSnapshot(
        walletItems: snapshot.wallets,
        txnItems: snapshot.txns,
        claimItems: snapshot.claims,
        dailyCloseItems: snapshot.dailyCloses,
        recentNumberItems: snapshot.recentNumbers,
        metaItems: snapshot.meta,
      );
    } finally {
      await sourceDb.close();
    }

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
    final j = _buildJsonBackup();
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
      payload: _buildJsonBackup(),
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
      payload: _buildJsonBackup(),
      passphrase: passphrase,
    );
    await file.writeAsString(encrypted);
    await _writeBackupChecksumSidecar(file.path);
    await _markBackupMeta(type: 'json_encrypted', path: file.path);
    return file.path;
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
    await _reopenSqlite();
    _applyJson(j);
    _autoRepairInMemoryDuplicatesAndCounters();
    await _save();
    _rebuildEngineFromTxns();
    _loaded = true;
  }
}
