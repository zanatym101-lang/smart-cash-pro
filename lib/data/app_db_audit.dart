part of 'app_db.dart';

const String _auditMetaKey = '__audit_snapshot_json';

extension AppDbAudit on AppDb {
  List<Map<String, dynamic>> _copyAuditList(List<Map<String, dynamic>> list) {
    return list.map((e) => Map<String, dynamic>.from(e)).toList();
  }

  List<Map<String, dynamic>> _auditListFromMetaMap(Map<String, String> meta) {
    final raw = (meta[_auditMetaKey] ?? '').trim();
    if (raw.isEmpty) return <Map<String, dynamic>>[];
    try {
      final decoded = jsonDecode(raw);
      return _auditListFromRaw(decoded);
    } catch (_) {
      return <Map<String, dynamic>>[];
    }
  }

  bool _sameAuditList(
    List<Map<String, dynamic>> a,
    List<Map<String, dynamic>> b,
  ) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    return jsonEncode(a) == jsonEncode(b);
  }

  List<Map<String, dynamic>> _preferredAuditList(
    List<Map<String, dynamic>> settingsList,
    List<Map<String, dynamic>> metaList,
  ) {
    final settingsOk = settingsList.isEmpty || _hasAuditChain(settingsList);
    final metaOk = metaList.isEmpty || _hasAuditChain(metaList);

    if (settingsOk && !metaOk) return _copyAuditList(settingsList);
    if (metaOk && !settingsOk) return _copyAuditList(metaList);
    if (metaList.length > settingsList.length) return _copyAuditList(metaList);
    return _copyAuditList(settingsList);
  }

  Future<({Map<String, dynamic> settings, List<Map<String, dynamic>> list})>
  _loadAuditState({bool repairSettings = false}) async {
    final settings = await _readSettingsMap();
    final settingsList = _auditListFromRaw(settings['audit']);
    final db = await _ensureSqliteInitialized();
    final meta = await db.loadMeta();
    final metaList = _auditListFromMetaMap(meta);
    final chosen = _preferredAuditList(settingsList, metaList);

    if (repairSettings && !_sameAuditList(settingsList, chosen)) {
      settings['audit'] = _copyAuditList(chosen);
      try {
        await _writeSettingsMap(settings);
      } catch (_) {}
    }

    return (settings: settings, list: chosen);
  }

  Future<void> _writeAuditListToSqliteMeta(
    List<Map<String, dynamic>> list,
  ) async {
    final db = await _ensureSqliteInitialized();
    await db.upsertMetaValue(key: _auditMetaKey, value: jsonEncode(list));
  }

  List<Map<String, dynamic>> _auditListFromRaw(Object? raw) {
    final list = <Map<String, dynamic>>[];
    if (raw is! List) return list;
    for (final e in raw) {
      if (e is Map) {
        list.add(
          Map<String, dynamic>.from(e.map((k, v) => MapEntry(k.toString(), v))),
        );
      }
    }
    return list;
  }

  int _auditInt(Object? raw, {required int fallback}) {
    if (raw is int) return raw;
    if (raw is num) return raw.toInt();
    return int.tryParse(raw?.toString() ?? '') ?? fallback;
  }

  String _auditPayload(Map<String, dynamic> e) {
    final fields = <String>[
      'seq=${_auditInt(e['seq'], fallback: 0)}',
      'type=${(e['type'] ?? '').toString()}',
      'at=${(e['at'] ?? '').toString()}',
      'by=${(e['by'] ?? '').toString()}',
      'role=${(e['role'] ?? '').toString()}',
      'dateKey=${(e['dateKey'] ?? '').toString()}',
      'note=${(e['note'] ?? '').toString()}',
      'txnId=${(e['txnId'] ?? '').toString()}',
      'claimId=${(e['claimId'] ?? '').toString()}',
      'walletId=${(e['walletId'] ?? '').toString()}',
      'amount=${(e['amount'] ?? '').toString()}',
    ];
    return fields.join('|');
  }

  String _auditHash({
    required String prevHash,
    required Map<String, dynamic> entry,
  }) {
    final payload = _auditPayload(entry);
    return sha256
        .convert(utf8.encode('$prevHash|$payload'))
        .toString()
        .toUpperCase();
  }

  void _seedAuditChainInMemory(List<Map<String, dynamic>> list) {
    var prev = 'GENESIS';
    for (var i = 0; i < list.length; i++) {
      final e = list[i];
      e['seq'] = i + 1;
      e['prevHash'] = prev;
      final hash = _auditHash(prevHash: prev, entry: e);
      e['hash'] = hash;
      prev = hash;
    }
  }

  bool _hasAuditChain(List<Map<String, dynamic>> list) {
    if (list.isEmpty) return true;
    return list.every(
      (e) =>
          (e['hash'] ?? '').toString().trim().isNotEmpty &&
          (e['prevHash'] ?? '').toString().trim().isNotEmpty &&
          _auditInt(e['seq'], fallback: 0) > 0,
    );
  }

  Future<void> ensureAuditChainInitialized() async {
    final state = await _loadAuditState(repairSettings: true);
    final m = state.settings;
    final list = state.list;
    if (list.isEmpty || _hasAuditChain(list)) return;
    _seedAuditChainInMemory(list);
    m['audit'] = list;
    await _writeAuditListToSqliteMeta(list);
    try {
      await _writeSettingsMap(m);
    } catch (_) {}
  }

  Future<void> appendAudit({
    required String type,
    String? dateKey,
    String? note,
    int? txnId,
    int? claimId,
    int? walletId,
    double? amount,
  }) async {
    final state = await _loadAuditState(repairSettings: false);
    final m = state.settings;
    final list = state.list;
    if (!_hasAuditChain(list)) {
      _seedAuditChainInMemory(list);
    }
    final last = list.isEmpty ? null : list.last;
    final seq = (last == null)
        ? 1
        : (_auditInt(last['seq'], fallback: list.length) + 1);
    final prevHash = (last?['hash'] ?? 'GENESIS').toString();

    final entry = <String, dynamic>{
      'type': type,
      'at': DateTime.now().toIso8601String(),
      'by': _actorName(),
      'role': _actorRole(),
      'seq': seq,
      'prevHash': prevHash,
    };
    if (dateKey != null) entry['dateKey'] = dateKey;
    if (note != null && note.trim().isNotEmpty) entry['note'] = note.trim();
    if (txnId != null) entry['txnId'] = txnId;
    if (claimId != null) entry['claimId'] = claimId;
    if (walletId != null) entry['walletId'] = walletId;
    if (amount != null) entry['amount'] = amount;
    entry['hash'] = _auditHash(prevHash: prevHash, entry: entry);

    list.add(entry);
    if (list.length > 1000) {
      list.removeRange(0, list.length - 1000);
    }
    m['audit'] = list;
    await _writeAuditListToSqliteMeta(list);
    try {
      await _writeSettingsMap(m);
    } catch (_) {}
  }

  Future<List<Map<String, dynamic>>> listAudit({int limit = 200}) async {
    final state = await _loadAuditState(repairSettings: true);
    final list = state.list;
    list.sort((a, b) {
      final aAt =
          DateTime.tryParse(a['at']?.toString() ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0);
      final bAt =
          DateTime.tryParse(b['at']?.toString() ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0);
      return bAt.compareTo(aAt);
    });
    if (list.length > limit) {
      return list.sublist(0, limit);
    }
    return list;
  }

  Future<AuditChainStatus> verifyAuditChain() async {
    final state = await _loadAuditState(repairSettings: true);
    final list = state.list;
    if (list.isEmpty) {
      return const AuditChainStatus(
        ok: true,
        count: 0,
        headHash: null,
        tailHash: null,
        error: null,
        brokenIndex: null,
      );
    }

    if (!_hasAuditChain(list)) {
      return AuditChainStatus(
        ok: false,
        count: list.length,
        headHash: null,
        tailHash: null,
        error: 'audit_chain_missing_fields',
        brokenIndex: null,
      );
    }

    for (var i = 0; i < list.length; i++) {
      final current = list[i];
      final prevHash = (current['prevHash'] ?? '').toString();
      final expected = _auditHash(prevHash: prevHash, entry: current);
      final actual = (current['hash'] ?? '').toString().toUpperCase();
      if (expected != actual) {
        return AuditChainStatus(
          ok: false,
          count: list.length,
          headHash: list.first['hash']?.toString(),
          tailHash: list.last['hash']?.toString(),
          error: 'audit_hash_mismatch',
          brokenIndex: i,
        );
      }

      if (i > 0) {
        final prev = list[i - 1];
        final linked = (prev['hash'] ?? '').toString();
        if (prevHash != linked) {
          return AuditChainStatus(
            ok: false,
            count: list.length,
            headHash: list.first['hash']?.toString(),
            tailHash: list.last['hash']?.toString(),
            error: 'audit_prev_link_mismatch',
            brokenIndex: i,
          );
        }
      }
    }

    return AuditChainStatus(
      ok: true,
      count: list.length,
      headHash: list.first['hash']?.toString(),
      tailHash: list.last['hash']?.toString(),
      error: null,
      brokenIndex: null,
    );
  }

  Future<void> clearAudit() async {
    final m = await _readSettingsMap();
    m['audit'] = <Map<String, dynamic>>[];
    await _writeAuditListToSqliteMeta(const <Map<String, dynamic>>[]);
    await _writeSettingsMap(m);
  }
}
