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
  static bool? debugForceServerAuthoritativeLicenseForTests;
  static LicenseRpcService Function()?
  debugServerAuthoritativeLicenseServiceFactoryForTests;

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
    if (!license.containsKey('serverAuthDiagLastCheckAt')) {
      license['serverAuthDiagLastCheckAt'] = '';
      changed = true;
    }
    if (!license.containsKey('serverAuthDiagLastMode')) {
      license['serverAuthDiagLastMode'] = '';
      changed = true;
    }
    if (!license.containsKey('serverAuthDiagLastOk')) {
      license['serverAuthDiagLastOk'] = false;
      changed = true;
    }
    if (!license.containsKey('serverAuthDiagLastError')) {
      license['serverAuthDiagLastError'] = '';
      changed = true;
    }
    if (!license.containsKey('serverAuthDiagLastErrorCode')) {
      license['serverAuthDiagLastErrorCode'] = '';
      changed = true;
    }
    if (!license.containsKey('serverAuthDiagLastSource')) {
      license['serverAuthDiagLastSource'] = '';
      changed = true;
    }
    if (!license.containsKey('serverAuthDiagKillSwitchEnabled')) {
      license['serverAuthDiagKillSwitchEnabled'] = false;
      changed = true;
    }
    if (!license.containsKey('serverAuthDiagCompromiseDetected')) {
      license['serverAuthDiagCompromiseDetected'] = false;
      changed = true;
    }
    if (!license.containsKey('serverAuthDiagCompromiseAt')) {
      license['serverAuthDiagCompromiseAt'] = '';
      changed = true;
    }
    if (!license.containsKey('serverAuthRefreshToken')) {
      license['serverAuthRefreshToken'] = '';
      changed = true;
    }
    if (!license.containsKey('serverAuthRefreshTokenExpiresAt')) {
      license['serverAuthRefreshTokenExpiresAt'] = '';
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
    license['serverAuthRefreshToken'] = '';
    license['serverAuthRefreshTokenExpiresAt'] = '';
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

  bool _isServerAuthoritativeLicenseEnabled() {
    final forced = debugForceServerAuthoritativeLicenseForTests;
    if (forced != null) return forced;
    return useServerAuthoritativeLicense;
  }

  LicenseRpcService _serverAuthoritativeLicenseService() {
    final factory = debugServerAuthoritativeLicenseServiceFactoryForTests;
    if (factory != null) return factory();
    return LicenseRpcService();
  }

  String _newLicenseIdempotencyKey(String scope) {
    final now = DateTime.now().toUtc().microsecondsSinceEpoch;
    final rand = Random().nextInt(1 << 30);
    return '$scope-$now-$rand';
  }

  bool _isServerKillSwitchEnabled(Map<String, dynamic> license) {
    return license['serverAuthDiagKillSwitchEnabled'] == true;
  }

  bool _responseHasServerKillSwitch(LicenseRpcResponse response) {
    final raw = response.raw;
    return raw['kill_switch_enabled'] == true ||
        raw['disable_server_authoritative'] == true ||
        raw['server_authoritative_enabled'] == false ||
        response.errorCode == 'kill_switch_enabled';
  }

  bool _isCompromiseErrorCode(String? code) {
    final normalized = (code ?? '').trim();
    return normalized == 'compromise_detected' ||
        normalized == 'refresh_token_reuse';
  }

  bool _shouldTryServerSessionRefresh(String? code) {
    const refreshableCodes = <String>{
      'access_token_expired',
      'token_expired',
      'invalid_token',
      'session_expired',
      'refresh_required',
    };
    return refreshableCodes.contains((code ?? '').trim());
  }

  Future<void> _markServerCompromiseDiagnostic({
    required Map<String, dynamic> license,
    required String code,
    required String message,
  }) async {
    final nowIso = DateTime.now().toUtc().toIso8601String();
    final wasDetected = license['serverAuthDiagCompromiseDetected'] == true;
    license['serverAuthDiagCompromiseDetected'] = true;
    license['serverAuthDiagCompromiseAt'] = nowIso;
    license['serverAuthDiagLastErrorCode'] = code;
    license['serverAuthDiagLastError'] = message;
    if (!wasDetected) {
      try {
        await appendAudit(
          type: 'license_compromise_detected',
          note: code,
        );
      } catch (_) {}
    }
  }

  void _applyRefreshedServerTokens(
    Map<String, dynamic> license,
    LicenseRpcResponse response,
    String nowIso,
  ) {
    final accessToken = (response.raw['access_token'] ?? '').toString().trim();
    final refreshToken = (response.raw['refresh_token'] ?? '')
        .toString()
        .trim();
    final accessExpiresAt = _parseUtcDate(response.raw['access_expires_at']);
    final refreshExpiresAt = _parseUtcDate(response.raw['refresh_expires_at']);
    final graceEndsAt = _parseUtcDate(response.raw['grace_ends_at']);

    if (accessToken.isNotEmpty) {
      license['cloudToken'] = accessToken;
      license['cloudTokenExpiresAt'] = accessExpiresAt?.toIso8601String() ?? '';
    }
    if (refreshToken.isNotEmpty) {
      license['serverAuthRefreshToken'] = refreshToken;
      license['serverAuthRefreshTokenExpiresAt'] =
          refreshExpiresAt?.toIso8601String() ?? '';
    }
    if (graceEndsAt != null) {
      license['cloudLicenseExpiresAt'] = graceEndsAt.toIso8601String();
    }
    license['cloudLastCheckAt'] = nowIso;
  }

  String _serverAuthoritativeActivationErrorMessage({
    required String? code,
    required String fallback,
  }) {
    switch ((code ?? '').trim()) {
      case 'invalid_activation_code':
        return 'كود التفعيل غير صحيح';
      case 'license_not_active':
        return 'الترخيص غير نشط حاليًا';
      case 'license_expired':
        return 'انتهت صلاحية الترخيص';
      case 'device_limit_exceeded':
        return 'تم الوصول للحد الأقصى للأجهزة لهذا الترخيص';
      case 'device_revoked':
        return 'هذا الجهاز موقوف لهذا الترخيص';
      case 'missing_supabase_config':
        return 'إعدادات خادم التفعيل غير مكتملة';
      case 'network_error':
        return 'تعذر الاتصال بخادم التفعيل';
      default:
        return fallback;
    }
  }

  Future<bool> _activateViaServerAuthoritativeRpc({
    required Map<String, dynamic> license,
    required String normalizedCode,
    required String deviceCode,
    required String deviceFingerprintHash,
  }) async {
    final service = _serverAuthoritativeLicenseService();
    final nowIso = DateTime.now().toUtc().toIso8601String();
    final result = await service.activateLicense(
      ActivateLicenseRpcRequest(
        activationCode: normalizedCode,
        deviceId: deviceCode,
        deviceFingerprintHash: deviceFingerprintHash,
        appVersion: _licenseCloudAppVersion,
        platform: Platform.operatingSystem,
        idempotencyKey: _newLicenseIdempotencyKey('activate'),
      ),
    );

    if (!result.ok) {
      if (result.errorCode == 'invalid_activation_code') return false;
      throw Exception(
        _serverAuthoritativeActivationErrorMessage(
          code: result.errorCode,
          fallback: result.message ?? 'فشل التفعيل عبر الخادم',
        ),
      );
    }

    final accessToken = (result.raw['access_token'] ?? '').toString().trim();
    final refreshToken = (result.raw['refresh_token'] ?? '').toString().trim();
    if (accessToken.isEmpty || refreshToken.isEmpty) {
      throw Exception('استجابة خادم التفعيل غير مكتملة');
    }

    final accessExpiresAt = _parseUtcDate(result.raw['access_expires_at']);
    final refreshExpiresAt = _parseUtcDate(result.raw['refresh_expires_at']);
    final graceEndsAt = _parseUtcDate(result.raw['grace_ends_at']);

    license['cloudToken'] = accessToken;
    license['cloudTokenExpiresAt'] = accessExpiresAt?.toIso8601String() ?? '';
    if (graceEndsAt != null) {
      license['cloudLicenseExpiresAt'] = graceEndsAt.toIso8601String();
    }
    license['serverAuthRefreshToken'] = refreshToken;
    license['serverAuthRefreshTokenExpiresAt'] =
        refreshExpiresAt?.toIso8601String() ?? '';
    license['cloudDeviceId'] = deviceCode;
    license['cloudActivatedAt'] = nowIso;
    license['cloudLastCheckAt'] = nowIso;
    license['cloudLastError'] = '';
    license['activationCode'] = normalizedCode;

    return true;
  }

  Future<void> _runServerAuthoritativeLicenseDiagnostics({
    required Map<String, dynamic> license,
    required String deviceCode,
  }) async {
    if (!_isServerAuthoritativeLicenseEnabled()) return;

    final nowIso = DateTime.now().toUtc().toIso8601String();
    final token = (license['cloudToken'] ?? '').toString().trim();
    var source = 'none';
    var ok = false;
    var error = '';
    var errorCode = '';

    if (_isServerKillSwitchEnabled(license)) {
      license['serverAuthDiagLastCheckAt'] = nowIso;
      license['serverAuthDiagLastMode'] = 'kill_switch_legacy';
      license['serverAuthDiagLastOk'] = false;
      license['serverAuthDiagLastError'] = 'server_authoritative_disabled';
      license['serverAuthDiagLastErrorCode'] = 'kill_switch_enabled';
      license['serverAuthDiagLastSource'] = 'phase_c5_diagnostic';
      return;
    }

    if (token.isEmpty) {
      source = 'skipped';
      error = 'missing_cloud_token';
      errorCode = 'missing_token';
    } else {
      final service = _serverAuthoritativeLicenseService();

      Future<LicenseRpcResponse> callHeartbeat() {
        return service.heartbeatLicense(
          HeartbeatLicenseRpcRequest(
            accessToken: token,
            deviceId: deviceCode,
            appVersion: _licenseCloudAppVersion,
          ),
        );
      }

      Future<LicenseRpcResponse?> callRefreshIfNeeded(String? fromCode) async {
        final refreshToken = (license['serverAuthRefreshToken'] ?? '')
            .toString()
            .trim();
        if (refreshToken.isEmpty || !_shouldTryServerSessionRefresh(fromCode)) {
          return null;
        }
        source = 'refresh';
        return service.refreshSession(
          RefreshSessionRpcRequest(
            refreshToken: refreshToken,
            deviceId: deviceCode,
            idempotencyKey: _newLicenseIdempotencyKey('refresh'),
          ),
        );
      }

      try {
        source = 'validate';
        var response = await service.validateLicense(
          ValidateLicenseRpcRequest(accessToken: token, deviceId: deviceCode),
        );
        if (_responseHasServerKillSwitch(response)) {
          license['serverAuthDiagKillSwitchEnabled'] = true;
          source = 'kill_switch_legacy';
          ok = false;
          error = 'server_authoritative_disabled';
          errorCode = 'kill_switch_enabled';
        } else if (!response.ok) {
          source = 'heartbeat';
          response = await callHeartbeat();
          if (_responseHasServerKillSwitch(response)) {
            license['serverAuthDiagKillSwitchEnabled'] = true;
            source = 'kill_switch_legacy';
            ok = false;
            error = 'server_authoritative_disabled';
            errorCode = 'kill_switch_enabled';
          } else if (!response.ok) {
            final refreshed = await callRefreshIfNeeded(response.errorCode);
            if (refreshed != null) {
              if (_responseHasServerKillSwitch(refreshed)) {
                license['serverAuthDiagKillSwitchEnabled'] = true;
                source = 'kill_switch_legacy';
                ok = false;
                error = 'server_authoritative_disabled';
                errorCode = 'kill_switch_enabled';
              } else {
                ok = refreshed.ok;
                error = refreshed.message ?? '';
                errorCode = refreshed.errorCode ?? '';
                if (ok) {
                  _applyRefreshedServerTokens(license, refreshed, nowIso);
                }
              }
            } else {
              ok = response.ok;
              error = response.message ?? '';
              errorCode = response.errorCode ?? '';
            }
          } else {
            ok = response.ok;
            error = response.message ?? '';
            errorCode = response.errorCode ?? '';
          }
        } else {
          ok = response.ok;
          error = response.message ?? '';
          errorCode = response.errorCode ?? '';
        }
      } on LicenseRpcException catch (e) {
        if (_isCompromiseErrorCode(e.code)) {
          await _markServerCompromiseDiagnostic(
            license: license,
            code: e.code ?? 'compromise_detected',
            message: e.message,
          );
        }
        source = 'legacy_fallback';
        try {
          final response = await callHeartbeat();
          if (_responseHasServerKillSwitch(response)) {
            license['serverAuthDiagKillSwitchEnabled'] = true;
            source = 'kill_switch_legacy';
            ok = false;
            error = 'server_authoritative_disabled';
            errorCode = 'kill_switch_enabled';
          } else {
            ok = response.ok;
            error = response.message ?? '';
            errorCode = response.errorCode ?? '';
            if (!ok) {
              final refreshed = await callRefreshIfNeeded(response.errorCode);
              if (refreshed != null) {
                if (_responseHasServerKillSwitch(refreshed)) {
                  license['serverAuthDiagKillSwitchEnabled'] = true;
                  source = 'kill_switch_legacy';
                  ok = false;
                  error = 'server_authoritative_disabled';
                  errorCode = 'kill_switch_enabled';
                } else {
                  ok = refreshed.ok;
                  error = refreshed.message ?? '';
                  errorCode = refreshed.errorCode ?? '';
                  if (ok) {
                    _applyRefreshedServerTokens(license, refreshed, nowIso);
                  }
                }
              }
            }
          }
        } on LicenseRpcException catch (heartbeatError) {
          if (_isCompromiseErrorCode(heartbeatError.code)) {
            await _markServerCompromiseDiagnostic(
              license: license,
              code: heartbeatError.code ?? 'compromise_detected',
              message: heartbeatError.message,
            );
          }
          ok = false;
          error = heartbeatError.message;
          errorCode =
              heartbeatError.code ??
              e.code ??
              'server_authoritative_license_error';
        }
      } catch (e) {
        ok = false;
        error = e.toString();
        errorCode = 'server_authoritative_license_error';
      }
    }

    if (_isCompromiseErrorCode(errorCode)) {
      await _markServerCompromiseDiagnostic(
        license: license,
        code: errorCode,
        message: error,
      );
    }

    license['serverAuthDiagLastCheckAt'] = nowIso;
    license['serverAuthDiagLastMode'] = source;
    license['serverAuthDiagLastOk'] = ok;
    license['serverAuthDiagLastError'] = error;
    license['serverAuthDiagLastErrorCode'] = errorCode;
    license['serverAuthDiagLastSource'] = 'phase_c5_diagnostic';
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

  Future<bool> _legacyLicenseActivationDecision(
    Map<String, dynamic> license,
    String deviceCode,
  ) async {
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

    return isActivated;
  }

  String _normalizeServerDecisionErrorCode(String? code) {
    switch ((code ?? '').trim()) {
      case 'license_not_active':
      case 'license_revoked':
        return 'license_revoked';
      case 'license_expired':
        return 'license_expired';
      case 'device_not_active':
      case 'device_revoked':
        return 'device_revoked';
      case 'session_revoked':
      case 'session_expired':
      case 'invalid_access_token':
      case 'invalid_refresh_token':
        return 'session_revoked';
      case 'refresh_token_reused':
      case 'compromise_detected':
        return 'compromise_detected';
      default:
        return (code ?? '').trim();
    }
  }

  bool _isServerTerminalNotLicensedCode(String? code) {
    const blocked = <String>{
      'license_not_active',
      'license_revoked',
      'license_expired',
      'device_not_active',
      'device_revoked',
      'session_revoked',
      'session_expired',
      'invalid_access_token',
      'invalid_refresh_token',
      'compromise_detected',
      'refresh_token_reused',
    };
    return blocked.contains((code ?? '').trim());
  }

  bool _isServerOutageCode(String? code) {
    const outage = <String>{
      'network_error',
      'timeout',
      'server_unavailable',
      'server_authoritative_license_error',
      'invalid_response',
    };
    return outage.contains((code ?? '').trim());
  }

  bool _isWithinServerGraceWindow(Map<String, dynamic> license) {
    final graceEndsAt = _parseUtcDate(license['cloudLicenseExpiresAt']);
    if (graceEndsAt == null) return false;
    return graceEndsAt.isAfter(DateTime.now().toUtc());
  }

  void _setServerDecisionDiagnostic({
    required Map<String, dynamic> license,
    required String source,
    required bool ok,
    required String errorCode,
    required String error,
    String diagSource = 'phase_d0_decision',
  }) {
    final nowIso = DateTime.now().toUtc().toIso8601String();
    license['serverAuthDiagLastCheckAt'] = nowIso;
    license['serverAuthDiagLastMode'] = source;
    license['serverAuthDiagLastOk'] = ok;
    license['serverAuthDiagLastError'] = error;
    license['serverAuthDiagLastErrorCode'] =
        _normalizeServerDecisionErrorCode(errorCode);
    license['serverAuthDiagLastSource'] = diagSource;
    license['cloudLastCheckAt'] = nowIso;
    if (error.isNotEmpty) {
      license['cloudLastError'] = error;
    } else {
      license['cloudLastError'] = '';
    }
  }

  Future<bool> _serverAuthoritativeLicenseDecision(
    Map<String, dynamic> license,
    String deviceCode,
  ) async {
    if (_isServerKillSwitchEnabled(license)) {
      final fallback = await _legacyLicenseActivationDecision(license, deviceCode);
      _setServerDecisionDiagnostic(
        license: license,
        source: 'kill_switch_legacy',
        ok: fallback,
        errorCode: 'kill_switch_enabled',
        error: 'server_authoritative_disabled',
      );
      return fallback;
    }

    final token = (license['cloudToken'] ?? '').toString().trim();
    if (token.isEmpty) {
      _setServerDecisionDiagnostic(
        license: license,
        source: 'missing_token',
        ok: false,
        errorCode: 'missing_token',
        error: 'missing_cloud_token',
      );
      return false;
    }

    final service = _serverAuthoritativeLicenseService();

    Future<LicenseRpcResponse?> refreshIfNeeded(String? fromCode) async {
      final refreshToken = (license['serverAuthRefreshToken'] ?? '')
          .toString()
          .trim();
      if (refreshToken.isEmpty || !_shouldTryServerSessionRefresh(fromCode)) {
        return null;
      }
      return service.refreshSession(
        RefreshSessionRpcRequest(
          refreshToken: refreshToken,
          deviceId: deviceCode,
          idempotencyKey: _newLicenseIdempotencyKey('refresh'),
        ),
      );
    }

    Future<bool> applySuccess({
      required LicenseRpcResponse response,
      required String source,
    }) async {
      final nowIso = DateTime.now().toUtc().toIso8601String();
      _applyRefreshedServerTokens(license, response, nowIso);
      _setServerDecisionDiagnostic(
        license: license,
        source: source,
        ok: true,
        errorCode: '',
        error: '',
      );
      return true;
    }

    try {
      final validate = await service.validateLicense(
        ValidateLicenseRpcRequest(accessToken: token, deviceId: deviceCode),
      );
      if (_responseHasServerKillSwitch(validate)) {
        license['serverAuthDiagKillSwitchEnabled'] = true;
        final fallback = await _legacyLicenseActivationDecision(license, deviceCode);
        _setServerDecisionDiagnostic(
          license: license,
          source: 'kill_switch_legacy',
          ok: fallback,
          errorCode: 'kill_switch_enabled',
          error: 'server_authoritative_disabled',
        );
        return fallback;
      }
      if (validate.ok) {
        return applySuccess(response: validate, source: 'validate');
      }
      if (_isServerTerminalNotLicensedCode(validate.errorCode)) {
        _setServerDecisionDiagnostic(
          license: license,
          source: 'validate_terminal',
          ok: false,
          errorCode: validate.errorCode ?? 'server_denied',
          error: validate.message ?? 'server denied license',
        );
        return false;
      }

      final heartbeat = await service.heartbeatLicense(
        HeartbeatLicenseRpcRequest(
          accessToken: token,
          deviceId: deviceCode,
          appVersion: _licenseCloudAppVersion,
        ),
      );
      if (_responseHasServerKillSwitch(heartbeat)) {
        license['serverAuthDiagKillSwitchEnabled'] = true;
        final fallback = await _legacyLicenseActivationDecision(license, deviceCode);
        _setServerDecisionDiagnostic(
          license: license,
          source: 'kill_switch_legacy',
          ok: fallback,
          errorCode: 'kill_switch_enabled',
          error: 'server_authoritative_disabled',
        );
        return fallback;
      }
      if (heartbeat.ok) {
        return applySuccess(response: heartbeat, source: 'heartbeat');
      }
      if (_isServerTerminalNotLicensedCode(heartbeat.errorCode)) {
        _setServerDecisionDiagnostic(
          license: license,
          source: 'heartbeat_terminal',
          ok: false,
          errorCode: heartbeat.errorCode ?? 'server_denied',
          error: heartbeat.message ?? 'server denied license',
        );
        return false;
      }

      final refreshed = await refreshIfNeeded(heartbeat.errorCode);
      if (refreshed != null) {
        if (refreshed.ok) {
          return applySuccess(response: refreshed, source: 'refresh');
        }
        if (_isServerTerminalNotLicensedCode(refreshed.errorCode)) {
          final code = refreshed.errorCode ?? 'server_denied';
          if (_isCompromiseErrorCode(code)) {
            await _markServerCompromiseDiagnostic(
              license: license,
              code: code,
              message: refreshed.message ?? 'compromise_detected',
            );
          }
          _setServerDecisionDiagnostic(
            license: license,
            source: 'refresh_terminal',
            ok: false,
            errorCode: code,
            error: refreshed.message ?? 'server denied license',
          );
          return false;
        }
      }

      _setServerDecisionDiagnostic(
        license: license,
        source: 'server_denied',
        ok: false,
        errorCode: refreshed?.errorCode ?? heartbeat.errorCode ?? validate.errorCode ?? 'server_denied',
        error: refreshed?.message ?? heartbeat.message ?? validate.message ?? 'server denied license',
      );
      return false;
    } on LicenseRpcException catch (e) {
      final code = e.code ?? 'server_authoritative_license_error';
      if (_isCompromiseErrorCode(code)) {
        await _markServerCompromiseDiagnostic(
          license: license,
          code: _normalizeServerDecisionErrorCode(code),
          message: e.message,
        );
        _setServerDecisionDiagnostic(
          license: license,
          source: 'compromise_detected',
          ok: false,
          errorCode: code,
          error: e.message,
        );
        return false;
      }
      if (code == 'kill_switch_enabled') {
        license['serverAuthDiagKillSwitchEnabled'] = true;
        final fallback = await _legacyLicenseActivationDecision(license, deviceCode);
        _setServerDecisionDiagnostic(
          license: license,
          source: 'kill_switch_legacy',
          ok: fallback,
          errorCode: 'kill_switch_enabled',
          error: 'server_authoritative_disabled',
        );
        return fallback;
      }
      if (_isServerOutageCode(code) && _isWithinServerGraceWindow(license)) {
        _setServerDecisionDiagnostic(
          license: license,
          source: 'outage_grace',
          ok: true,
          errorCode: code,
          error: e.message,
        );
        return true;
      }
      _setServerDecisionDiagnostic(
        license: license,
        source: 'server_error',
        ok: false,
        errorCode: code,
        error: e.message,
      );
      return false;
    } catch (e) {
      final message = e.toString();
      if (_isWithinServerGraceWindow(license)) {
        _setServerDecisionDiagnostic(
          license: license,
          source: 'outage_grace',
          ok: true,
          errorCode: 'server_authoritative_license_error',
          error: message,
        );
        return true;
      }
      _setServerDecisionDiagnostic(
        license: license,
        source: 'server_error',
        ok: false,
        errorCode: 'server_authoritative_license_error',
        error: message,
      );
      return false;
    }
  }

  Future<LicenseInfo> getLicenseInfo() async {
    final m = await _readSettingsMap();
    final ensured = _ensureLicense(m);
    final license = ensured.license;
    final deviceCode = await _deviceCode();
    final before = jsonEncode(license);
    final useServerDecision = _isServerAuthoritativeLicenseEnabled();
    final isActivated = useServerDecision
        ? await _serverAuthoritativeLicenseDecision(license, deviceCode)
        : await _legacyLicenseActivationDecision(license, deviceCode);

    if (!useServerDecision) {
      await _runServerAuthoritativeLicenseDiagnostics(
        license: license,
        deviceCode: deviceCode,
      );
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
    final useServerAuthoritative = _isServerAuthoritativeLicenseEnabled();
    final expectedLegacyCode = generateActivationCodeForDeviceCode(deviceCode);
    if (_allowLegacyLocalActivation &&
        _normalizeCode(normalizedCode) == _normalizeCode(expectedLegacyCode)) {
      _applyLegacyLocalActivation(license, normalizedCode);
      m['license'] = license;
      await _writeSettingsMap(m);
      return true;
    }
    if (useServerAuthoritative) {
      try {
        final deviceFingerprintHash = _hashHex(await _deviceFingerprint());
        final activated = await _activateViaServerAuthoritativeRpc(
          license: license,
          normalizedCode: normalizedCode,
          deviceCode: deviceCode,
          deviceFingerprintHash: deviceFingerprintHash,
        );
        m['license'] = license;
        await _writeSettingsMap(m);
        return activated;
      } on LicenseRpcException catch (e) {
        if (e.code == 'invalid_activation_code') {
          return false;
        }
        throw Exception(
          _serverAuthoritativeActivationErrorMessage(
            code: e.code,
            fallback: e.message,
          ),
        );
      }
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

  Future<void> runServerAuthoritativeLicenseDiagnosticsForTesting({
    required Map<String, dynamic> license,
    required String deviceCode,
  }) async {
    await _runServerAuthoritativeLicenseDiagnostics(
      license: license,
      deviceCode: deviceCode,
    );
  }

  Future<bool> activateWithCodeForTesting({
    required Map<String, dynamic> license,
    required String code,
    required String deviceCode,
    required String deviceFingerprintHash,
  }) async {
    final normalizedCode = code.trim().toUpperCase();
    if (normalizedCode.isEmpty) return false;
    final expectedLegacyCode = generateActivationCodeForDeviceCode(deviceCode);
    if (_allowLegacyLocalActivation &&
        _normalizeCode(normalizedCode) == _normalizeCode(expectedLegacyCode)) {
      _applyLegacyLocalActivation(license, normalizedCode);
      return true;
    }
    if (_isServerAuthoritativeLicenseEnabled()) {
      try {
        return await _activateViaServerAuthoritativeRpc(
          license: license,
          normalizedCode: normalizedCode,
          deviceCode: deviceCode,
          deviceFingerprintHash: deviceFingerprintHash,
        );
      } on LicenseRpcException catch (e) {
        if (e.code == 'invalid_activation_code') {
          return false;
        }
        throw Exception(
          _serverAuthoritativeActivationErrorMessage(
            code: e.code,
            fallback: e.message,
          ),
        );
      }
    }
    // Testing helper intentionally avoids network in legacy cloud mode.
    return false;
  }
}
