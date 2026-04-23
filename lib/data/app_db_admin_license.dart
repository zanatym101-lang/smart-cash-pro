part of 'app_db.dart';

extension AppDbAdminLicense on AppDb {
  static const String _licenseSecret = 'SCP-2026-LICENSE';
  static const String _licenseCloudAppVersion = String.fromEnvironment(
    'APP_VERSION',
    defaultValue: '1.0.0',
  );
  static const Duration _licenseStatusRefreshInterval = Duration(hours: 6);
  static const Duration _licenseTokenRefreshWindow = Duration(hours: 12);
  static const bool _allowLegacyLocalActivation =
      bool.fromEnvironment('FLUTTER_TEST', defaultValue: false) ||
      !bool.fromEnvironment('dart.vm.product');

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
    if (!license.containsKey('cloudToken')) {
      license['cloudToken'] = '';
      changed = true;
    }
    if (!license.containsKey('cloudTokenExpiresAt')) {
      license['cloudTokenExpiresAt'] = '';
      changed = true;
    }
    if (!license.containsKey('cloudLicenseExpiresAt')) {
      license['cloudLicenseExpiresAt'] = '';
      changed = true;
    }
    if (!license.containsKey('cloudDeviceId')) {
      license['cloudDeviceId'] = '';
      changed = true;
    }
    if (!license.containsKey('cloudLastCheckAt')) {
      license['cloudLastCheckAt'] = '';
      changed = true;
    }
    if (!license.containsKey('cloudLastError')) {
      license['cloudLastError'] = '';
      changed = true;
    }
    if (!license.containsKey('cloudActivatedAt')) {
      license['cloudActivatedAt'] = '';
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

  String generateActivationCodeForDeviceCode(String deviceCode) {
    final base = _normalizeCode(deviceCode);
    if (base.isEmpty) return '';
    final h = _hashHex('$_licenseSecret|$base');
    return _formatCode(h.substring(0, 12), 4);
  }

  bool _isLegacyActivationValid(
    Map<String, dynamic> license,
    String deviceCode,
  ) {
    final stored = (license['activationCode'] ?? '').toString().trim();
    if (stored.isEmpty) return false;
    final expected = generateActivationCodeForDeviceCode(deviceCode);
    return _normalizeCode(stored) == _normalizeCode(expected);
  }

  void _applyLegacyLocalActivation(
    Map<String, dynamic> license,
    String normalizedCode,
  ) {
    license['activationCode'] = normalizedCode;
    license['activatedAt'] = DateTime.now().toUtc().toIso8601String();
    license['cloudLastError'] = '';
  }

  DateTime? _parseUtcDate(dynamic raw) {
    final text = (raw ?? '').toString().trim();
    if (text.isEmpty) return null;
    return DateTime.tryParse(text)?.toUtc();
  }

  bool _isCloudLicenseLocallyValid(
    Map<String, dynamic> license,
    String deviceCode,
  ) {
    final token = (license['cloudToken'] ?? '').toString().trim();
    if (token.isEmpty) return false;

    final storedDevice = (license['cloudDeviceId'] ?? '').toString().trim();
    if (storedDevice.isNotEmpty && storedDevice != deviceCode) return false;

    final now = DateTime.now().toUtc();

    // Offline rule: once cloud activation succeeds, keep the app activated on the
    // same device until the actual license expiry is reached or the server later
    // returns a non-transient revocation/invalid state.
    final licenseExpiresAt = _parseUtcDate(license['cloudLicenseExpiresAt']);
    if (licenseExpiresAt != null && !licenseExpiresAt.isAfter(now)) {
      return false;
    }

    return true;
  }

  void _clearCloudLicense(Map<String, dynamic> license) {
    license['cloudToken'] = '';
    license['cloudTokenExpiresAt'] = '';
    license['cloudLicenseExpiresAt'] = '';
    license['cloudDeviceId'] = '';
    license['cloudLastCheckAt'] = '';
    license['cloudLastError'] = '';
    license['cloudActivatedAt'] = '';
    license['activationCode'] = '';
  }

  void _applyCloudLicense({
    required Map<String, dynamic> license,
    required LicenseCloudActivationResult result,
    required String deviceCode,
    String? activationCode,
  }) {
    license['cloudToken'] = result.token;
    license['cloudTokenExpiresAt'] =
        result.tokenExpiresAt?.toIso8601String() ?? '';
    license['cloudLicenseExpiresAt'] =
        result.licenseExpiresAt?.toIso8601String() ?? '';
    final resolvedDevice = (result.deviceId ?? '').trim();
    license['cloudDeviceId'] = resolvedDevice.isEmpty
        ? deviceCode
        : resolvedDevice;
    final nowIso = DateTime.now().toUtc().toIso8601String();
    license['cloudLastCheckAt'] = nowIso;
    license['cloudActivatedAt'] = nowIso;
    license['cloudLastError'] = '';
    if (activationCode != null && activationCode.trim().isNotEmpty) {
      license['activationCode'] = activationCode.trim();
    }
  }

  bool _isTransientCloudError(LicenseCloudException e) {
    return e.transient || e.code == 'timeout' || e.code == 'network_error';
  }

  bool _canTryCloudRefresh(String? code) {
    const blocked = <String>{
      'license_not_found',
      'license_not_active',
      'license_expired',
      'device_revoked',
      'device_limit_exceeded',
      'activation_not_found_or_revoked',
    };
    if (code == null || code.trim().isEmpty) return true;
    return !blocked.contains(code.trim());
  }

  Future<bool> _syncCloudLicense(
    Map<String, dynamic> license,
    String deviceCode,
  ) async {
    final token = (license['cloudToken'] ?? '').toString().trim();
    if (token.isEmpty) return false;

    final nowIso = DateTime.now().toUtc().toIso8601String();
    try {
      final status = await LicenseCloudService.status(
        token: token,
        deviceId: deviceCode,
      );
      if (status.licenseExpiresAt != null) {
        license['cloudLicenseExpiresAt'] = status.licenseExpiresAt!
            .toIso8601String();
      }
      license['cloudLastCheckAt'] = nowIso;
      license['cloudLastError'] = '';
      return _isCloudLicenseLocallyValid(license, deviceCode);
    } on LicenseCloudException catch (statusError) {
      if (_canTryCloudRefresh(statusError.code)) {
        try {
          final refreshed = await LicenseCloudService.refresh(
            token: token,
            deviceId: deviceCode,
            appVersion: _licenseCloudAppVersion,
          );
          _applyCloudLicense(
            license: license,
            result: refreshed,
            deviceCode: deviceCode,
          );
          return true;
        } on LicenseCloudException catch (refreshError) {
          if (_isTransientCloudError(refreshError)) {
            license['cloudLastCheckAt'] = nowIso;
            license['cloudLastError'] = refreshError.message;
            return _isCloudLicenseLocallyValid(license, deviceCode);
          }
          _clearCloudLicense(license);
          license['cloudLastCheckAt'] = nowIso;
          license['cloudLastError'] = refreshError.message;
          return false;
        }
      }

      if (_isTransientCloudError(statusError)) {
        license['cloudLastCheckAt'] = nowIso;
        license['cloudLastError'] = statusError.message;
        return _isCloudLicenseLocallyValid(license, deviceCode);
      }

      _clearCloudLicense(license);
      license['cloudLastCheckAt'] = nowIso;
      license['cloudLastError'] = statusError.message;
      return false;
    }
  }

  Future<LicenseInfo> getLicenseInfo() async {
    final m = await _readSettingsMap();
    final ensured = _ensureLicense(m);
    final license = ensured.license;
    final deviceCode = await _deviceCode();
    final before = jsonEncode(license);
    final isLegacyActivated =
        _allowLegacyLocalActivation &&
        _isLegacyActivationValid(license, deviceCode);
    var isActivated =
        isLegacyActivated || _isCloudLicenseLocallyValid(license, deviceCode);

    final token = (license['cloudToken'] ?? '').toString().trim();
    if (!isLegacyActivated && token.isNotEmpty) {
      final now = DateTime.now().toUtc();
      final lastCheck = _parseUtcDate(license['cloudLastCheckAt']);
      final tokenExpiresAt = _parseUtcDate(license['cloudTokenExpiresAt']);
      final needsSync =
          !isActivated ||
          lastCheck == null ||
          now.difference(lastCheck) >= _licenseStatusRefreshInterval ||
          (tokenExpiresAt != null &&
              tokenExpiresAt.difference(now) <= _licenseTokenRefreshWindow);
      if (needsSync) {
        isActivated = await _syncCloudLicense(license, deviceCode);
      }
    }

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

    if (ensured.changed ||
        !m.containsKey('license') ||
        jsonEncode(license) != before) {
      m['license'] = license;
      await _writeSettingsMap(m);
    }

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
    final normalizedCode = code.trim().toUpperCase();
    if (normalizedCode.isEmpty) return false;
    final deviceCode = await _deviceCode();
    final expectedLegacyCode = generateActivationCodeForDeviceCode(deviceCode);
    if (_allowLegacyLocalActivation &&
        _normalizeCode(normalizedCode) == _normalizeCode(expectedLegacyCode)) {
      _applyLegacyLocalActivation(license, normalizedCode);
      m['license'] = license;
      await _writeSettingsMap(m);
      return true;
    }
    try {
      final activation = await LicenseCloudService.activate(
        code: normalizedCode,
        deviceId: deviceCode,
        appVersion: _licenseCloudAppVersion,
      );
      _applyCloudLicense(
        license: license,
        result: activation,
        deviceCode: deviceCode,
        activationCode: normalizedCode,
      );
      m['license'] = license;
      await _writeSettingsMap(m);
      return true;
    } on LicenseCloudException catch (e) {
      if (e.code == 'license_not_found') {
        return false;
      }
      throw Exception(e.message);
    }
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
}
