part of 'app_db.dart';

extension AppDbAdminMaintenance on AppDb {
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
      throw Exception('PIN يجب أن يكون 4 أرقام أو أكثر');
    }
    final m = await _readSettingsMap();
    m['devPin'] = _pinRecord(pin);
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

    List<String> archivedCustomers = [];
    final rawArchived = m['archivedCustomers'];
    if (rawArchived is List) {
      archivedCustomers = rawArchived.map((e) => e.toString()).toList();
    }
    if (!m.containsKey('archivedCustomers')) {
      m['archivedCustomers'] = archivedCustomers;
      changed = true;
    }

    Map<String, String> customerNameOverrides = {};
    final rawOverrides = m['customerNameOverrides'];
    if (rawOverrides is Map) {
      customerNameOverrides = rawOverrides.map(
        (key, value) => MapEntry(key.toString(), value.toString()),
      );
    }
    if (!m.containsKey('customerNameOverrides')) {
      m['customerNameOverrides'] = customerNameOverrides;
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
      await _writeSettingsMap(m);
    }
    _setDayStartHourCache(dayStartHour);

    return AppSettings(
      businessName: businessName,
      currency: currency,
      dayStartHour: dayStartHour,
      quickActionsOrder: quickActionsOrder,
      pinnedCustomers: pinnedCustomers,
      archivedCustomers: archivedCustomers,
      customerNameOverrides: customerNameOverrides,
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
    m['archivedCustomers'] = settings.archivedCustomers;
    m['customerNameOverrides'] = settings.customerNameOverrides;
    m['customerAlertThreshold'] = settings.customerAlertThreshold;
    await _writeSettingsMap(m);
    _setDayStartHourCache(hour);
  }

  String _normalizeProviderKey(String provider) {
    final p = provider.trim().toLowerCase();
    return p.isEmpty ? 'unknown' : p;
  }

  Map<String, double> _readDoubleMap(dynamic raw) {
    final out = <String, double>{};
    if (raw is Map) {
      for (final entry in raw.entries) {
        final key = entry.key.toString();
        final val = entry.value;
        if (val is num) {
          out[key] = val.toDouble();
        } else if (val != null) {
          final parsed = double.tryParse(val.toString());
          if (parsed != null) out[key] = parsed;
        }
      }
    }
    return out;
  }

  Future<double> getDefaultNetworkFee(String provider) async {
    final m = await _readSettingsMap();
    final map = _readDoubleMap(m['defaultNetworkFeeByProvider']);
    final key = _normalizeProviderKey(provider);
    if (map.containsKey(key)) return map[key]!;
    if (map.containsKey('default')) return map['default']!;
    return 0;
  }

  Future<void> setDefaultNetworkFee(String provider, double value) async {
    final m = await _readSettingsMap();
    final map = _readDoubleMap(m['defaultNetworkFeeByProvider']);
    map[_normalizeProviderKey(provider)] = value;
    m['defaultNetworkFeeByProvider'] = map;
    await _writeSettingsMap(m);
  }

  Future<double> getDefaultReceiveFee(String provider) async {
    final m = await _readSettingsMap();
    final map = _readDoubleMap(m['defaultReceiveFeeByProvider']);
    final key = _normalizeProviderKey(provider);
    if (map.containsKey(key)) return map[key]!;
    if (map.containsKey('default')) return map['default']!;
    return 0;
  }

  Future<void> setDefaultReceiveFee(String provider, double value) async {
    final m = await _readSettingsMap();
    final map = _readDoubleMap(m['defaultReceiveFeeByProvider']);
    map[_normalizeProviderKey(provider)] = value;
    m['defaultReceiveFeeByProvider'] = map;
    await _writeSettingsMap(m);
  }
}
