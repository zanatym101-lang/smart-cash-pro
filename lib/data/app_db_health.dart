part of 'app_db.dart';

extension AppDbHealth on AppDb {
  static const Set<String> _autoRepairSupportedCodes = {
    'wallet_duplicate_id',
    'txn_duplicate_id',
    'claim_duplicate_id',
    'daily_close_duplicate_date',
    'next_wallet_id_invalid',
    'next_txn_id_invalid',
    'next_claim_id_invalid',
    'next_close_id_invalid',
  };

  IntegrityIssue _issue(String code, String message) {
    return IntegrityIssue(code: code, message: message);
  }

  int _maxId<T>(Iterable<T> items, int Function(T item) selector) {
    var maxValue = 0;
    for (final item in items) {
      final value = selector(item);
      if (value > maxValue) maxValue = value;
    }
    return maxValue;
  }

  DateTime? _parseIsoOrNull(Object? raw) {
    final s = (raw ?? '').toString().trim();
    if (s.isEmpty) return null;
    return DateTime.tryParse(s);
  }

  Iterable<List<T>> _duplicateGroupsById<T>(
    Iterable<T> items,
    int Function(T item) selector,
  ) sync* {
    final groups = <int, List<T>>{};
    for (final item in items) {
      groups.putIfAbsent(selector(item), () => <T>[]).add(item);
    }
    for (final group in groups.values) {
      if (group.length > 1) {
        yield group;
      }
    }
  }

  String _todayBusinessKey() => _businessDateKeyFromDateTime(DateTime.now());

  Map<String, dynamic> _readHealthMap(Map<String, dynamic> m) {
    final raw = m['health'];
    if (raw is Map) {
      return Map<String, dynamic>.from(
        raw.map((k, v) => MapEntry(k.toString(), v)),
      );
    }
    return <String, dynamic>{};
  }

  Future<void> _writeHealthResult(IntegrityCheckResult result) async {
    final m = await _readSettingsMap();
    final health = _readHealthMap(m);
    health['lastRunAt'] = result.checkedAt.toIso8601String();
    health['lastRunDateKey'] = _todayBusinessKey();
    health['ok'] = result.ok;
    health['issuesCount'] = result.issues.length;
    health['error'] = result.ok
        ? ''
        : result.issues.map((e) => '${e.code}:${e.message}').join(' || ');
    health['auditEntries'] = result.auditEntries;
    health['auditChainOk'] = result.auditChainOk;
    health['auditHeadHash'] = result.auditHeadHash ?? '';
    health['auditTailHash'] = result.auditTailHash ?? '';
    m['health'] = health;
    await _writeSettingsMap(m);
  }

  IntegrityCheckResult _integrityFromCore({
    required DateTime checkedAt,
    required List<IntegrityIssue> issues,
    required AuditChainStatus audit,
  }) {
    final ok = issues.isEmpty && audit.ok;
    return IntegrityCheckResult(
      ok: ok,
      checkedAt: checkedAt,
      issues: issues,
      auditEntries: audit.count,
      auditChainOk: audit.ok,
      auditHeadHash: audit.headHash,
      auditTailHash: audit.tailHash,
    );
  }

  Future<IntegrityCheckResult> _runIntegrityCheckCore() async {
    final checkedAt = DateTime.now();
    final issues = <IntegrityIssue>[];

    final walletIds = <int>{};
    for (final w in _wallets) {
      if (!walletIds.add(w.id)) {
        issues.add(
          _issue('wallet_duplicate_id', 'Wallet id duplicated: ${w.id}'),
        );
      }
    }

    final txnIds = <int>{};
    for (final t in _txns) {
      if (!txnIds.add(t.id)) {
        issues.add(_issue('txn_duplicate_id', 'Txn id duplicated: ${t.id}'));
      }
      if (t.walletFromId != null && !walletIds.contains(t.walletFromId)) {
        issues.add(
          _issue(
            'txn_wallet_from_missing',
            'Txn #${t.id} references missing walletFromId=${t.walletFromId}',
          ),
        );
      }
      if (t.walletToId != null && !walletIds.contains(t.walletToId)) {
        issues.add(
          _issue(
            'txn_wallet_to_missing',
            'Txn #${t.id} references missing walletToId=${t.walletToId}',
          ),
        );
      }
    }

    final claimIds = <int>{};
    for (final c in _claims) {
      if (!claimIds.add(c.id)) {
        issues.add(
          _issue('claim_duplicate_id', 'Claim id duplicated: ${c.id}'),
        );
      }
      if (c.settledTxnId != null && !txnIds.contains(c.settledTxnId)) {
        issues.add(
          _issue(
            'claim_settled_txn_missing',
            'Claim #${c.id} settledTxnId=${c.settledTxnId} is missing',
          ),
        );
      }
      if (c.sourceTxnId != null && !txnIds.contains(c.sourceTxnId)) {
        issues.add(
          _issue(
            'claim_source_txn_missing',
            'Claim #${c.id} sourceTxnId=${c.sourceTxnId} is missing',
          ),
        );
      }
    }

    final closeKeys = <String>{};
    for (final c in _dailyCloses) {
      if (!closeKeys.add(c.dateKey)) {
        issues.add(
          _issue(
            'daily_close_duplicate_date',
            'Duplicate daily close date: ${c.dateKey}',
          ),
        );
      }
    }

    for (final w in _wallets) {
      final postedQ = _state.getWalletQirsh(w.id.toString());
      if (postedQ < 0) {
        issues.add(
          _issue(
            'wallet_negative_posted',
            'Wallet #${w.id} posted balance is negative: ${Money.toEgpDouble(postedQ)}',
          ),
        );
      }
    }

    final projected = _projectedBalances();
    for (final w in _wallets) {
      final projectedQ = projected.walletsQirsh[w.id.toString()] ?? 0;
      if (projectedQ < 0) {
        issues.add(
          _issue(
            'wallet_negative_available',
            'Wallet #${w.id} available balance is negative: ${Money.toEgpDouble(projectedQ)}',
          ),
        );
      }
    }

    if (_nextWalletId <= _maxId(_wallets, (w) => w.id)) {
      issues.add(
        _issue(
          'next_wallet_id_invalid',
          'nextWalletId is not above current max wallet id',
        ),
      );
    }
    if (_nextTxnId <= _maxId(_txns, (t) => t.id)) {
      issues.add(
        _issue(
          'next_txn_id_invalid',
          'nextTxnId is not above current max txn id',
        ),
      );
    }
    if (_nextClaimId <= _maxId(_claims, (c) => c.id)) {
      issues.add(
        _issue(
          'next_claim_id_invalid',
          'nextClaimId is not above current max claim id',
        ),
      );
    }
    if (_nextCloseId <= _maxId(_dailyCloses, (c) => c.id)) {
      issues.add(
        _issue(
          'next_close_id_invalid',
          'nextCloseId is not above current max daily-close id',
        ),
      );
    }

    final audit = await verifyAuditChain();
    if (!audit.ok) {
      issues.add(
        _issue(
          audit.error ?? 'audit_chain_invalid',
          'Audit chain broken at index ${audit.brokenIndex ?? -1}',
        ),
      );
    }

    return _integrityFromCore(
      checkedAt: checkedAt,
      issues: issues,
      audit: audit,
    );
  }

  bool _sameWallet(Wallet a, Wallet b) {
    return a.name == b.name &&
        a.allowNegative == b.allowNegative &&
        a.phone == b.phone &&
        a.dailyLimit == b.dailyLimit &&
        a.monthlyLimit == b.monthlyLimit &&
        a.lowBalanceThreshold == b.lowBalanceThreshold;
  }

  bool _sameTxn(Txn a, Txn b) {
    return a.kind == b.kind &&
        a.status == b.status &&
        a.entryDate == b.entryDate &&
        a.walletFromId == b.walletFromId &&
        a.walletToId == b.walletToId &&
        a.amount == b.amount &&
        a.clientFee == b.clientFee &&
        a.networkFee == b.networkFee &&
        a.mode == b.mode &&
        a.note == b.note &&
        a.serviceName == b.serviceName &&
        a.reference == b.reference &&
        a.party == b.party &&
        a.createdBy == b.createdBy &&
        a.createdRole == b.createdRole &&
        a.createdAt == b.createdAt;
  }

  bool _sameClaim(Claim a, Claim b) {
    return a.type == b.type &&
        a.party == b.party &&
        a.amount == b.amount &&
        a.note == b.note &&
        a.entryDate == b.entryDate &&
        a.status == b.status &&
        a.settledTxnId == b.settledTxnId &&
        a.settledDate == b.settledDate &&
        a.sourceTxnId == b.sourceTxnId;
  }

  bool _walletDuplicateGroupIsIdentical(List<Wallet> group) {
    final first = group.first;
    return group.skip(1).every((w) => _sameWallet(first, w));
  }

  bool _txnDuplicateGroupIsIdentical(List<Txn> group) {
    final first = group.first;
    return group.skip(1).every((t) => _sameTxn(first, t));
  }

  bool _claimDuplicateGroupIsIdentical(List<Claim> group) {
    final first = group.first;
    return group.skip(1).every((c) => _sameClaim(first, c));
  }

  bool _walletIdHasOperationalReferences(int walletId) {
    if (_lowBalanceAlertDate.containsKey(walletId)) return true;
    if (_dailyUsageResetAt.containsKey(walletId)) return true;
    if (_monthlyUsageResetAt.containsKey(walletId)) return true;
    return _txns.any(
      (t) => t.walletFromId == walletId || t.walletToId == walletId,
    );
  }

  bool _txnIdHasOperationalReferences(int txnId) {
    final claimRefs = _claims.any(
      (c) => c.sourceTxnId == txnId || c.settledTxnId == txnId,
    );
    if (claimRefs) return true;
    return _txns.any((t) => _extractPendingSettlementRef(t.note) == txnId);
  }

  bool _claimIdHasOperationalReferences(int claimId) {
    return _txns.any((t) => _extractClaimIdFromNote(t.note) == claimId);
  }

  void _ensureAutoRepairSafety() {
    for (final group in _duplicateGroupsById(_wallets, (w) => w.id)) {
      final duplicatedId = group.first.id;
      if (_walletDuplicateGroupIsIdentical(group)) continue;
      if (_walletIdHasOperationalReferences(duplicatedId)) {
        throw Exception(
          'Auto-repair blocked for wallet id=$duplicatedId because the duplicate records are different and already referenced by transactions or wallet state.',
        );
      }
    }

    for (final group in _duplicateGroupsById(_txns, (t) => t.id)) {
      final duplicatedId = group.first.id;
      if (_txnDuplicateGroupIsIdentical(group)) continue;
      if (_txnIdHasOperationalReferences(duplicatedId)) {
        throw Exception(
          'Auto-repair blocked for txn id=$duplicatedId because the duplicate records are different and already referenced by claims or pending settlements.',
        );
      }
    }

    for (final group in _duplicateGroupsById(_claims, (c) => c.id)) {
      final duplicatedId = group.first.id;
      if (_claimDuplicateGroupIsIdentical(group)) continue;
      if (_claimIdHasOperationalReferences(duplicatedId)) {
        throw Exception(
          'Auto-repair blocked for claim id=$duplicatedId because the duplicate records are different and already referenced by settlement transactions.',
        );
      }
    }
  }

  DailyClose _dailyCloseWithId(DailyClose c, int id) {
    return DailyClose(
      id: id,
      dateKey: c.dateKey,
      closedAt: c.closedAt,
      drawerBalance: c.drawerBalance,
      walletsTotal: c.walletsTotal,
      treasuryTotal: c.treasuryTotal,
      profitTotal: c.profitTotal,
      profitTransfer: c.profitTransfer,
      profitReceive: c.profitReceive,
      profitFawry: c.profitFawry,
      inflow: c.inflow,
      outflow: c.outflow,
      net: c.net,
      transferCount: c.transferCount,
      receiveCount: c.receiveCount,
      fawryCashCount: c.fawryCashCount,
      fawryCreditCount: c.fawryCreditCount,
      expenseCount: c.expenseCount,
      claimCollectCount: c.claimCollectCount,
      claimPayCount: c.claimPayCount,
      pendingCount: c.pendingCount,
    );
  }

  int _fixWalletDuplicates() {
    final byId = <int, Wallet>{};
    final fixed = <Wallet>[];
    var fixedCount = 0;

    for (final w in _wallets) {
      final existing = byId[w.id];
      if (existing == null) {
        byId[w.id] = w;
        fixed.add(w);
        continue;
      }

      if (_sameWallet(existing, w)) {
        fixedCount++;
        continue;
      }

      var newId = _nextWalletId;
      while (byId.containsKey(newId)) {
        newId++;
      }
      _nextWalletId = newId + 1;
      final moved = w.copyWith(id: newId);
      byId[newId] = moved;
      fixed.add(moved);
      fixedCount++;
    }

    _wallets
      ..clear()
      ..addAll(fixed);
    return fixedCount;
  }

  int _fixTxnDuplicates() {
    final byId = <int, Txn>{};
    final fixed = <Txn>[];
    var fixedCount = 0;

    for (final t in _txns) {
      final existing = byId[t.id];
      if (existing == null) {
        byId[t.id] = t;
        fixed.add(t);
        continue;
      }

      if (_sameTxn(existing, t)) {
        fixedCount++;
        continue;
      }

      var newId = _nextTxnId;
      while (byId.containsKey(newId)) {
        newId++;
      }
      _nextTxnId = newId + 1;
      final moved = t.copyWith(id: newId);
      byId[newId] = moved;
      fixed.add(moved);
      fixedCount++;
    }

    _txns
      ..clear()
      ..addAll(fixed);
    return fixedCount;
  }

  int _fixClaimDuplicates() {
    final byId = <int, Claim>{};
    final fixed = <Claim>[];
    var fixedCount = 0;

    for (final c in _claims) {
      final existing = byId[c.id];
      if (existing == null) {
        byId[c.id] = c;
        fixed.add(c);
        continue;
      }

      if (_sameClaim(existing, c)) {
        fixedCount++;
        continue;
      }

      var newId = _nextClaimId;
      while (byId.containsKey(newId)) {
        newId++;
      }
      _nextClaimId = newId + 1;
      final moved = c.copyWith(id: newId);
      byId[newId] = moved;
      fixed.add(moved);
      fixedCount++;
    }

    _claims
      ..clear()
      ..addAll(fixed);
    return fixedCount;
  }

  int _fixDailyCloseDuplicates() {
    var fixedCount = 0;

    // Keep one close per dateKey (latest by closedAt).
    final byDate = <String, DailyClose>{};
    for (final c in _dailyCloses) {
      final existing = byDate[c.dateKey];
      if (existing == null) {
        byDate[c.dateKey] = c;
        continue;
      }
      fixedCount++;
      if (c.closedAt.isAfter(existing.closedAt)) {
        byDate[c.dateKey] = c;
      }
    }

    final usedIds = <int>{};
    final fixed = <DailyClose>[];
    final ordered = byDate.values.toList()
      ..sort((a, b) => a.closedAt.compareTo(b.closedAt));
    for (final c in ordered) {
      if (usedIds.add(c.id)) {
        fixed.add(c);
        continue;
      }
      var newId = _nextCloseId;
      while (usedIds.contains(newId)) {
        newId++;
      }
      _nextCloseId = newId + 1;
      usedIds.add(newId);
      fixed.add(_dailyCloseWithId(c, newId));
      fixedCount++;
    }

    _dailyCloses
      ..clear()
      ..addAll(fixed);
    return fixedCount;
  }

  void _normalizeNextIdsAndMaps() {
    _nextWalletId = _maxId(_wallets, (w) => w.id) + 1;
    _nextTxnId = _maxId(_txns, (t) => t.id) + 1;
    _nextClaimId = _maxId(_claims, (c) => c.id) + 1;
    _nextCloseId = _maxId(_dailyCloses, (c) => c.id) + 1;
    _nextAttachmentId = _maxId(_customerAttachments, (a) => a.id) + 1;

    final validWalletIds = _wallets.map((w) => w.id).toSet();
    _lowBalanceAlertDate.removeWhere((id, _) => !validWalletIds.contains(id));
    _dailyUsageResetAt.removeWhere((id, _) => !validWalletIds.contains(id));
    _monthlyUsageResetAt.removeWhere((id, _) => !validWalletIds.contains(id));
  }

  Future<IntegrityRepairResult> repairDuplicateIntegrityIssues({
    bool createJsonBackup = true,
  }) async {
    await _ensureLoaded();
    if (!AppSession.isAdmin) {
      throw Exception('Admin only');
    }
    await ensureAuditChainInitialized();

    final before = await _runIntegrityCheckCore();
    if (before.ok) {
      await _writeHealthResult(before);
      return IntegrityRepairResult(
        changed: false,
        backupPath: null,
        walletsFixed: 0,
        txnsFixed: 0,
        claimsFixed: 0,
        dailyClosesFixed: 0,
        before: before,
        after: before,
      );
    }

    final unsupported = before.issues
        .where((i) => !_autoRepairSupportedCodes.contains(i.code))
        .toList();
    if (unsupported.isNotEmpty) {
      throw Exception(
        'Auto-repair supports duplicate/id-counter issues only. Unsupported issue: '
        '${unsupported.first.code} (${unsupported.first.message})',
      );
    }

    _ensureAutoRepairSafety();

    String? backupPath;
    if (createJsonBackup) {
      final dir = await getApplicationSupportDirectory();
      backupPath = await exportJsonBackupToPath(dir.path);
    }

    try {
      final walletsFixed = _fixWalletDuplicates();
      final txnsFixed = _fixTxnDuplicates();
      final claimsFixed = _fixClaimDuplicates();
      final dailyClosesFixed = _fixDailyCloseDuplicates();
      _normalizeNextIdsAndMaps();

      _rebuildEngineFromTxns();
      await _save();
      await appendAudit(
        type: 'integrity_repair',
        note: 'auto_duplicate_repair',
      );

      final after = await _runIntegrityCheckCore();
      if (!after.ok) {
        throw Exception(
          'Auto-repair did not resolve all integrity issues safely.',
        );
      }
      await _writeHealthResult(after);
      return IntegrityRepairResult(
        changed:
            walletsFixed > 0 ||
            txnsFixed > 0 ||
            claimsFixed > 0 ||
            dailyClosesFixed > 0,
        backupPath: backupPath,
        walletsFixed: walletsFixed,
        txnsFixed: txnsFixed,
        claimsFixed: claimsFixed,
        dailyClosesFixed: dailyClosesFixed,
        before: before,
        after: after,
      );
    } catch (e) {
      if (backupPath != null) {
        try {
          await restoreJsonBackupFromPath(backupPath);
        } catch (_) {}
      }
      rethrow;
    }
  }

  Future<void> _runDailyIntegrityCheckIfNeeded() async {
    final m = await _readSettingsMap();
    final health = _readHealthMap(m);
    final lastDateKey = (health['lastRunDateKey'] ?? '').toString();
    final today = _todayBusinessKey();
    if (lastDateKey == today) return;

    await ensureAuditChainInitialized();
    final result = await _runIntegrityCheckCore();
    await _writeHealthResult(result);
  }

  Future<IntegrityCheckResult> runIntegrityCheck({bool force = false}) async {
    await _ensureLoaded();
    final m = await _readSettingsMap();
    final health = _readHealthMap(m);
    final today = _todayBusinessKey();
    final lastDateKey = (health['lastRunDateKey'] ?? '').toString();
    if (!force && lastDateKey == today) {
      final cachedAt = _parseIsoOrNull(health['lastRunAt']) ?? DateTime.now();
      final cachedError = (health['error'] ?? '').toString().trim();
      final cachedIssueCount =
          int.tryParse((health['issuesCount'] ?? '0').toString()) ?? 0;
      final issues = <IntegrityIssue>[];
      if (cachedIssueCount > 0 && cachedError.isNotEmpty) {
        issues.add(_issue('cached', cachedError));
      }
      return IntegrityCheckResult(
        ok: (health['ok'] ?? false) == true,
        checkedAt: cachedAt,
        issues: issues,
        auditEntries:
            int.tryParse((health['auditEntries'] ?? '0').toString()) ?? 0,
        auditChainOk: (health['auditChainOk'] ?? false) == true,
        auditHeadHash: (health['auditHeadHash'] ?? '').toString().trim().isEmpty
            ? null
            : (health['auditHeadHash'] ?? '').toString(),
        auditTailHash: (health['auditTailHash'] ?? '').toString().trim().isEmpty
            ? null
            : (health['auditTailHash'] ?? '').toString(),
      );
    }

    await ensureAuditChainInitialized();
    final result = await _runIntegrityCheckCore();
    await _writeHealthResult(result);
    return result;
  }

  Future<SystemHealthSummary> getSystemHealthSummary() async {
    await _ensureLoaded();
    final m = await _readSettingsMap();
    final health = _readHealthMap(m);
    final backup = (m['backupMeta'] is Map)
        ? Map<String, dynamic>.from(
            (m['backupMeta'] as Map).map((k, v) => MapEntry(k.toString(), v)),
          )
        : <String, dynamic>{};

    final file = await _sqliteFile();
    final size = await file.exists() ? await file.length() : 0;
    final pending = _txns.where((t) => t.status == 'pending').length;

    return SystemHealthSummary(
      lastBackupAt: _parseIsoOrNull(backup['lastAt']),
      lastBackupType: (backup['type'] ?? '').toString().trim().isEmpty
          ? null
          : (backup['type'] ?? '').toString(),
      databaseSizeBytes: size,
      pendingCount: pending,
      lastIntegrityAt: _parseIsoOrNull(health['lastRunAt']),
      lastIntegrityOk: health.containsKey('ok')
          ? ((health['ok'] ?? false) == true)
          : null,
      lastIntegrityIssues:
          int.tryParse((health['issuesCount'] ?? '0').toString()) ?? 0,
      lastIntegrityError: (health['error'] ?? '').toString().trim().isEmpty
          ? null
          : (health['error'] ?? '').toString(),
      auditTailHash: (health['auditTailHash'] ?? '').toString().trim().isEmpty
          ? null
          : (health['auditTailHash'] ?? '').toString(),
    );
  }
}
