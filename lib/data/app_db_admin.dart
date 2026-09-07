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

const String kTransferUseCasePilotFlagKey = 'useNewTransferUseCasePilot';
const String kTransferUseCasePilotMetricsKey = 'transferUseCasePilotMetrics';
const String kTransferUseCasePilotAutoDisabledReasonKey =
    'transferUseCasePilotAutoDisabledReason';
const String kTransferUseCasePilotMismatchThresholdKey =
    'transferUseCasePilotMismatchThreshold';
const int kDefaultTransferUseCasePilotMismatchThreshold = 3;
const String kReceiveUseCasePilotFlagKey = 'useNewReceiveUseCasePilot';
const String kReceiveUseCasePilotMetricsKey = 'receiveUseCasePilotMetrics';
const String kReceiveUseCasePilotAutoDisabledReasonKey =
    'receiveUseCasePilotAutoDisabledReason';
const String kReceiveUseCasePilotMismatchThresholdKey =
    'receiveUseCasePilotMismatchThreshold';
const int kDefaultReceiveUseCasePilotMismatchThreshold = 3;
const String kClaimsUseCasePilotFlagKey = 'useNewClaimsUseCasePilot';
const String kClaimsUseCasePilotMetricsKey = 'claimsUseCasePilotMetrics';
const String kClaimsUseCasePilotAutoDisabledReasonKey =
    'claimsUseCasePilotAutoDisabledReason';
const String kClaimsUseCasePilotMismatchThresholdKey =
    'claimsUseCasePilotMismatchThreshold';
const int kDefaultClaimsUseCasePilotMismatchThreshold = 3;
const String kWebSettingsMetaKey = '__web_settings_json';

extension AppDbAdmin on AppDb {
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
    if (kIsWeb) {
      final db = await _ensureSqliteInitialized();
      final meta = await db.loadMeta();
      final raw = (meta[kWebSettingsMetaKey] ?? '').trim();
      if (raw.isEmpty) return {};
      try {
        final m = jsonDecode(raw);
        if (m is Map<String, dynamic>) {
          return Map<String, dynamic>.from(m);
        }
      } catch (_) {}
      return {};
    }
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
    if (kIsWeb) {
      final db = await _ensureSqliteInitialized();
      await db.upsertMetaValue(key: kWebSettingsMetaKey, value: jsonEncode(m));
      return;
    }
    final f = await _settingsFile();
    await f.writeAsString(jsonEncode(m));
  }

  Future<Map<String, dynamic>> readRawSettingsMap() async => _readSettingsMap();

  Future<void> writeRawSettingsMap(Map<String, dynamic> settings) async {
    await _writeSettingsMap(settings);
  }

  Future<bool> getTransferUseCasePilotEnabled() async {
    final settings = await _readSettingsMap();
    return settings[kTransferUseCasePilotFlagKey] == true;
  }

  Future<void> setTransferUseCasePilotEnabled(bool enabled) async {
    final settings = await _readSettingsMap();
    settings[kTransferUseCasePilotFlagKey] = enabled;
    if (enabled) {
      settings.remove(kTransferUseCasePilotAutoDisabledReasonKey);
    }
    await _writeSettingsMap(settings);
  }

  Future<String?> getTransferUseCasePilotAutoDisabledReason() async {
    final settings = await _readSettingsMap();
    final value = settings[kTransferUseCasePilotAutoDisabledReasonKey];
    return value is String && value.trim().isNotEmpty ? value : null;
  }

  Future<int> getTransferUseCasePilotMismatchThreshold() async {
    final settings = await _readSettingsMap();
    final value = settings[kTransferUseCasePilotMismatchThresholdKey];
    if (value is int && value > 0) return value;
    if (value is num && value.toInt() > 0) return value.toInt();
    return kDefaultTransferUseCasePilotMismatchThreshold;
  }

  Future<Map<String, int>> getTransferUseCasePilotMetrics() async {
    final settings = await _readSettingsMap();
    final raw = settings[kTransferUseCasePilotMetricsKey];
    final map = raw is Map ? Map<String, dynamic>.from(raw) : <String, dynamic>{};
    int readInt(String key) {
      final value = map[key];
      if (value is int) return value;
      if (value is num) return value.toInt();
      return 0;
    }

    return <String, int>{
      'pilot_runs': readInt('pilot_runs'),
      'pilot_success': readInt('pilot_success'),
      'pilot_mismatch': readInt('pilot_mismatch'),
    };
  }

  Future<void> recordTransferUseCasePilotRun({
    required bool success,
    required bool mismatch,
  }) async {
    final settings = await _readSettingsMap();
    final current = await getTransferUseCasePilotMetrics();
    settings[kTransferUseCasePilotMetricsKey] = <String, int>{
      'pilot_runs': current['pilot_runs']! + 1,
      'pilot_success': current['pilot_success']! + (success ? 1 : 0),
      'pilot_mismatch': current['pilot_mismatch']! + (mismatch ? 1 : 0),
    };
    await _writeSettingsMap(settings);
  }

  Future<bool> checkPilotHealth() async {
    final settings = await _readSettingsMap();
    final enabled = settings[kTransferUseCasePilotFlagKey] == true;
    if (!enabled) return false;

    final metrics = await getTransferUseCasePilotMetrics();
    final threshold = await getTransferUseCasePilotMismatchThreshold();
    final mismatchCount = metrics['pilot_mismatch'] ?? 0;
    if (mismatchCount < threshold) return true;

    settings[kTransferUseCasePilotFlagKey] = false;
    settings[kTransferUseCasePilotAutoDisabledReasonKey] =
        'too_many_mismatches';
    await _writeSettingsMap(settings);

    // ignore: avoid_print
    print(
      jsonEncode({
        'type': 'pilot_auto_disabled',
        'reason': 'too_many_mismatches',
        'threshold': threshold,
        'metrics': metrics,
      }),
    );

    return false;
  }

  Future<bool> getReceiveUseCasePilotEnabled() async {
    final settings = await _readSettingsMap();
    return settings[kReceiveUseCasePilotFlagKey] == true;
  }

  Future<void> setReceiveUseCasePilotEnabled(bool enabled) async {
    final settings = await _readSettingsMap();
    settings[kReceiveUseCasePilotFlagKey] = enabled;
    if (enabled) {
      settings.remove(kReceiveUseCasePilotAutoDisabledReasonKey);
    }
    await _writeSettingsMap(settings);
  }

  Future<String?> getReceiveUseCasePilotAutoDisabledReason() async {
    final settings = await _readSettingsMap();
    final value = settings[kReceiveUseCasePilotAutoDisabledReasonKey];
    return value is String && value.trim().isNotEmpty ? value : null;
  }

  Future<int> getReceiveUseCasePilotMismatchThreshold() async {
    final settings = await _readSettingsMap();
    final value = settings[kReceiveUseCasePilotMismatchThresholdKey];
    if (value is int && value > 0) return value;
    if (value is num && value.toInt() > 0) return value.toInt();
    return kDefaultReceiveUseCasePilotMismatchThreshold;
  }

  Future<Map<String, int>> getReceiveUseCasePilotMetrics() async {
    final settings = await _readSettingsMap();
    final raw = settings[kReceiveUseCasePilotMetricsKey];
    final map = raw is Map ? Map<String, dynamic>.from(raw) : <String, dynamic>{};
    int readInt(String key) {
      final value = map[key];
      if (value is int) return value;
      if (value is num) return value.toInt();
      return 0;
    }

    return <String, int>{
      'pilot_runs': readInt('pilot_runs'),
      'pilot_success': readInt('pilot_success'),
      'pilot_mismatch': readInt('pilot_mismatch'),
    };
  }

  Future<void> recordReceiveUseCasePilotRun({
    required bool success,
    required bool mismatch,
  }) async {
    final settings = await _readSettingsMap();
    final current = await getReceiveUseCasePilotMetrics();
    settings[kReceiveUseCasePilotMetricsKey] = <String, int>{
      'pilot_runs': current['pilot_runs']! + 1,
      'pilot_success': current['pilot_success']! + (success ? 1 : 0),
      'pilot_mismatch': current['pilot_mismatch']! + (mismatch ? 1 : 0),
    };
    await _writeSettingsMap(settings);
  }

  Future<bool> checkReceivePilotHealth() async {
    final settings = await _readSettingsMap();
    final enabled = settings[kReceiveUseCasePilotFlagKey] == true;
    if (!enabled) return false;

    final metrics = await getReceiveUseCasePilotMetrics();
    final threshold = await getReceiveUseCasePilotMismatchThreshold();
    final mismatchCount = metrics['pilot_mismatch'] ?? 0;
    if (mismatchCount < threshold) return true;

    settings[kReceiveUseCasePilotFlagKey] = false;
    settings[kReceiveUseCasePilotAutoDisabledReasonKey] =
        'too_many_mismatches';
    await _writeSettingsMap(settings);

    // ignore: avoid_print
    print(
      jsonEncode({
        'type': 'pilot_auto_disabled',
        'pilot': 'receive_use_case',
        'reason': 'too_many_mismatches',
        'threshold': threshold,
        'metrics': metrics,
      }),
    );

    return false;
  }

  Future<bool> getClaimsUseCasePilotEnabled() async {
    final settings = await _readSettingsMap();
    return settings[kClaimsUseCasePilotFlagKey] == true;
  }

  Future<void> setClaimsUseCasePilotEnabled(bool enabled) async {
    final settings = await _readSettingsMap();
    settings[kClaimsUseCasePilotFlagKey] = enabled;
    if (enabled) {
      settings.remove(kClaimsUseCasePilotAutoDisabledReasonKey);
    }
    await _writeSettingsMap(settings);
  }

  Future<String?> getClaimsUseCasePilotAutoDisabledReason() async {
    final settings = await _readSettingsMap();
    final value = settings[kClaimsUseCasePilotAutoDisabledReasonKey];
    return value is String && value.trim().isNotEmpty ? value : null;
  }

  Future<int> getClaimsUseCasePilotMismatchThreshold() async {
    final settings = await _readSettingsMap();
    final value = settings[kClaimsUseCasePilotMismatchThresholdKey];
    if (value is int && value > 0) return value;
    if (value is num && value.toInt() > 0) return value.toInt();
    return kDefaultClaimsUseCasePilotMismatchThreshold;
  }

  Future<Map<String, int>> getClaimsUseCasePilotMetrics() async {
    final settings = await _readSettingsMap();
    final raw = settings[kClaimsUseCasePilotMetricsKey];
    final map = raw is Map ? Map<String, dynamic>.from(raw) : <String, dynamic>{};
    int readInt(String key) {
      final value = map[key];
      if (value is int) return value;
      if (value is num) return value.toInt();
      return 0;
    }

    return <String, int>{
      'pilot_runs': readInt('pilot_runs'),
      'pilot_success': readInt('pilot_success'),
      'pilot_mismatch': readInt('pilot_mismatch'),
    };
  }

  Future<void> recordClaimsUseCasePilotRun({
    required bool success,
    required bool mismatch,
  }) async {
    final settings = await _readSettingsMap();
    final current = await getClaimsUseCasePilotMetrics();
    settings[kClaimsUseCasePilotMetricsKey] = <String, int>{
      'pilot_runs': current['pilot_runs']! + 1,
      'pilot_success': current['pilot_success']! + (success ? 1 : 0),
      'pilot_mismatch': current['pilot_mismatch']! + (mismatch ? 1 : 0),
    };
    await _writeSettingsMap(settings);
  }

  Future<bool> checkClaimsPilotHealth() async {
    final settings = await _readSettingsMap();
    final enabled = settings[kClaimsUseCasePilotFlagKey] == true;
    if (!enabled) return false;

    final metrics = await getClaimsUseCasePilotMetrics();
    final threshold = await getClaimsUseCasePilotMismatchThreshold();
    final mismatchCount = metrics['pilot_mismatch'] ?? 0;
    if (mismatchCount < threshold) return true;

    settings[kClaimsUseCasePilotFlagKey] = false;
    settings[kClaimsUseCasePilotAutoDisabledReasonKey] =
        'too_many_mismatches';
    await _writeSettingsMap(settings);

    // ignore: avoid_print
    print(
      jsonEncode({
        'type': 'pilot_auto_disabled',
        'pilot': 'claims_use_case',
        'reason': 'too_many_mismatches',
        'threshold': threshold,
        'metrics': metrics,
      }),
    );

    return false;
  }

  Future<AppDatabase> getAdapterDatabase() async {
    await _ensureLoaded();
    return _ensureSqliteInitialized();
  }
}
