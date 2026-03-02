part of 'app_db.dart';

extension _AppDbInternal on AppDb {
  bool _hasStatus(Txn t, String status) =>
      t.status.trim().toLowerCase() == status;

  String _txnKind(Txn t) => t.kind.trim().toLowerCase();

  bool _walletPendingAffectsBalance(Txn t) {
    final kind = _txnKind(t);
    return kind == 'transfer' || kind == 'receive';
  }

  Future<void> _closeSqlite() async {
    try {
      await _sqlite.close();
    } catch (_) {}
  }

  Future<void> _reopenSqlite() async {
    await _closeSqlite();
    _sqlite = AppDatabase();
  }

  Future<File> _dataFile() async {
    final dir = await getApplicationSupportDirectory();
    return File('${dir.path}/king_wallet_data.json');
  }

  Future<File> _settingsFile() async {
    final dir = await getApplicationSupportDirectory();
    return File('${dir.path}/king_wallet_settings.json');
  }

  Future<File> _sqliteFile() async {
    final dir = await getApplicationSupportDirectory();
    return File('${dir.path}/king_wallet.db');
  }

  Future<void> _deleteSqliteArtifacts() async {
    final dbFile = await _sqliteFile();
    final parent = dbFile.parent;
    if (!await parent.exists()) {
      await parent.create(recursive: true);
    }
    for (final suffix in ['', '-wal', '-shm']) {
      final target = File('${dbFile.path}$suffix');
      try {
        if (await target.exists()) {
          await target.delete();
        }
      } catch (_) {}
    }
  }

  void _setDayStartHourCache(int hour) {
    _cachedDayStartHour = hour.clamp(0, 23);
  }

  int _dayStartHour() => _cachedDayStartHour ?? 0;

  DateTime _businessShift(DateTime dt) {
    final h = _dayStartHour();
    if (h <= 0) return dt;
    return dt.subtract(Duration(hours: h));
  }

  String _formatDateKey(DateTime d) {
    final y = d.year.toString().padLeft(4, '0');
    final m = d.month.toString().padLeft(2, '0');
    final day = d.day.toString().padLeft(2, '0');
    return '$y-$m-$day';
  }

  String _businessDateKeyFromDateTime(DateTime dt) {
    final shifted = _businessShift(dt);
    return _formatDateKey(shifted);
  }

  Future<void> _ensureDayStartHourLoaded() async {
    if (_cachedDayStartHour != null) return;
    var hour = 0;
    try {
      final settings = await _settingsFile();
      if (await settings.exists()) {
        final raw = await settings.readAsString();
        if (raw.trim().isNotEmpty) {
          final j = jsonDecode(raw);
          if (j is Map<String, dynamic>) {
            hour = int.tryParse((j['dayStartHour'] ?? '0').toString()) ?? 0;
          }
        }
      }
    } catch (_) {}
    _setDayStartHourCache(hour);
  }

  void _applyJson(Map<String, dynamic> j) {
    int readCounter(dynamic raw, int fallback) {
      if (raw is int) return raw;
      return int.tryParse((raw ?? '').toString()) ?? fallback;
    }

    _nextWalletId = readCounter(j['nextWalletId'], 1);
    _nextTxnId = readCounter(j['nextTxnId'], 1);
    _nextClaimId = readCounter(j['nextClaimId'], 1);
    _nextCloseId = readCounter(j['nextCloseId'], 1);
    _nextAttachmentId = readCounter(j['nextAttachmentId'], 1);

    final walletsJson = (j['wallets'] ?? []) as List<dynamic>;
    _wallets
      ..clear()
      ..addAll(
        walletsJson.map((e) => Wallet.fromJson(e as Map<String, dynamic>)),
      );

    final txnsJson = (j['txns'] ?? []) as List<dynamic>;
    _txns
      ..clear()
      ..addAll(txnsJson.map((e) => Txn.fromJson(e as Map<String, dynamic>)));

    final claimsJson = (j['claims'] ?? []) as List<dynamic>;
    _claims
      ..clear()
      ..addAll(
        claimsJson.map((e) => Claim.fromJson(e as Map<String, dynamic>)),
      );

    final closesJson = (j['dailyCloses'] ?? []) as List<dynamic>;
    _dailyCloses
      ..clear()
      ..addAll(
        closesJson.map((e) => DailyClose.fromJson(e as Map<String, dynamic>)),
      );

    final recentJson = (j['recentNumbers'] ?? []) as List<dynamic>;
    _recentNumbers
      ..clear()
      ..addAll(
        recentJson.map((e) => RecentNumber.fromJson(e as Map<String, dynamic>)),
      );

    final attachmentsJson = (j['customerAttachments'] ?? []) as List<dynamic>;
    _customerAttachments
      ..clear()
      ..addAll(
        attachmentsJson.map(
          (e) => CustomerAttachment.fromJson(e as Map<String, dynamic>),
        ),
      );

    _lastPendingAlertDate = (j['lastPendingAlertDate'] as String?)?.trim();
    final lowMap = (j['lowBalanceAlertDate'] as Map<String, dynamic>?) ?? {};
    _lowBalanceAlertDate
      ..clear()
      ..addAll(
        lowMap.map(
          (k, v) => MapEntry(int.tryParse(k) ?? 0, (v ?? '').toString()),
        ),
      );

    DateTime? parseIso(dynamic raw) {
      final s = (raw ?? '').toString().trim();
      if (s.isEmpty) return null;
      return DateTime.tryParse(s);
    }

    final dailyResetMap =
        (j['dailyUsageResetAt'] as Map<String, dynamic>?) ?? {};
    _dailyUsageResetAt
      ..clear()
      ..addAll({
        for (final e in dailyResetMap.entries)
          if (parseIso(e.value) != null)
            (int.tryParse(e.key) ?? 0): parseIso(e.value)!,
      });

    final monthlyResetMap =
        (j['monthlyUsageResetAt'] as Map<String, dynamic>?) ?? {};
    _monthlyUsageResetAt
      ..clear()
      ..addAll({
        for (final e in monthlyResetMap.entries)
          if (parseIso(e.value) != null)
            (int.tryParse(e.key) ?? 0): parseIso(e.value)!,
      });

    int maxWalletId = 0;
    for (final w in _wallets) {
      if (w.id > maxWalletId) maxWalletId = w.id;
    }
    int maxTxnId = 0;
    for (final t in _txns) {
      if (t.id > maxTxnId) maxTxnId = t.id;
    }
    int maxClaimId = 0;
    for (final c in _claims) {
      if (c.id > maxClaimId) maxClaimId = c.id;
    }
    int maxCloseId = 0;
    for (final c in _dailyCloses) {
      if (c.id > maxCloseId) maxCloseId = c.id;
    }
    int maxAttachmentId = 0;
    for (final a in _customerAttachments) {
      if (a.id > maxAttachmentId) maxAttachmentId = a.id;
    }
    _nextWalletId = max(_nextWalletId, maxWalletId + 1);
    _nextTxnId = max(_nextTxnId, maxTxnId + 1);
    _nextClaimId = max(_nextClaimId, maxClaimId + 1);
    _nextCloseId = max(_nextCloseId, maxCloseId + 1);
    _nextAttachmentId = max(_nextAttachmentId, maxAttachmentId + 1);
  }

  Future<void> _loadFromSqlite() async {
    _wallets
      ..clear()
      ..addAll(await _sqlite.loadWallets());
    _txns
      ..clear()
      ..addAll(await _sqlite.loadTxns());
    _claims
      ..clear()
      ..addAll(await _sqlite.loadClaims());
    _dailyCloses
      ..clear()
      ..addAll(await _sqlite.loadDailyCloses());
    _recentNumbers
      ..clear()
      ..addAll(await _sqlite.loadRecentNumbers());

    final meta = await _sqlite.loadMeta();
    _nextWalletId = int.tryParse(meta['nextWalletId'] ?? '') ?? 1;
    _nextTxnId = int.tryParse(meta['nextTxnId'] ?? '') ?? 1;
    _nextClaimId = int.tryParse(meta['nextClaimId'] ?? '') ?? 1;
    _nextCloseId = int.tryParse(meta['nextCloseId'] ?? '') ?? 1;
    _nextAttachmentId = int.tryParse(meta['nextAttachmentId'] ?? '') ?? 1;

    final attachmentsRaw = (meta['customerAttachments'] ?? '').trim();
    _customerAttachments.clear();
    if (attachmentsRaw.isNotEmpty) {
      try {
        final list = jsonDecode(attachmentsRaw) as List<dynamic>;
        _customerAttachments.addAll(
          list.map(
            (e) => CustomerAttachment.fromJson(e as Map<String, dynamic>),
          ),
        );
      } catch (_) {}
    }
    int maxWalletId = 0;
    for (final w in _wallets) {
      if (w.id > maxWalletId) maxWalletId = w.id;
    }
    int maxTxnId = 0;
    for (final t in _txns) {
      if (t.id > maxTxnId) maxTxnId = t.id;
    }
    int maxClaimId = 0;
    for (final c in _claims) {
      if (c.id > maxClaimId) maxClaimId = c.id;
    }
    int maxCloseId = 0;
    for (final c in _dailyCloses) {
      if (c.id > maxCloseId) maxCloseId = c.id;
    }
    int maxAttachmentId = 0;
    for (final a in _customerAttachments) {
      if (a.id > maxAttachmentId) maxAttachmentId = a.id;
    }
    // Safety: if meta was missing/corrupted, never reuse existing ids.
    _nextWalletId = max(_nextWalletId, maxWalletId + 1);
    _nextTxnId = max(_nextTxnId, maxTxnId + 1);
    _nextClaimId = max(_nextClaimId, maxClaimId + 1);
    _nextCloseId = max(_nextCloseId, maxCloseId + 1);
    _nextAttachmentId = max(_nextAttachmentId, maxAttachmentId + 1);

    final lastPending = (meta['lastPendingAlertDate'] ?? '').trim();
    _lastPendingAlertDate = lastPending.isEmpty ? null : lastPending;

    final lowRaw = (meta['lowBalanceAlertDate'] ?? '').trim();
    _lowBalanceAlertDate.clear();
    if (lowRaw.isNotEmpty) {
      try {
        final lowMap = jsonDecode(lowRaw) as Map<String, dynamic>;
        _lowBalanceAlertDate.addAll(
          lowMap.map(
            (k, v) => MapEntry(int.tryParse(k) ?? 0, (v ?? '').toString()),
          ),
        );
      } catch (_) {}
    }

    final dailyResetRaw = (meta['dailyUsageResetAt'] ?? '').trim();
    _dailyUsageResetAt.clear();
    if (dailyResetRaw.isNotEmpty) {
      try {
        final m = jsonDecode(dailyResetRaw) as Map<String, dynamic>;
        for (final e in m.entries) {
          final id = int.tryParse(e.key);
          final dt = DateTime.tryParse((e.value ?? '').toString());
          if (id != null && dt != null) {
            _dailyUsageResetAt[id] = dt;
          }
        }
      } catch (_) {}
    }

    final monthlyResetRaw = (meta['monthlyUsageResetAt'] ?? '').trim();
    _monthlyUsageResetAt.clear();
    if (monthlyResetRaw.isNotEmpty) {
      try {
        final m = jsonDecode(monthlyResetRaw) as Map<String, dynamic>;
        for (final e in m.entries) {
          final id = int.tryParse(e.key);
          final dt = DateTime.tryParse((e.value ?? '').toString());
          if (id != null && dt != null) {
            _monthlyUsageResetAt[id] = dt;
          }
        }
      } catch (_) {}
    }
  }

  Future<void> _ensureLoaded() async {
    if (_loaded) return;
    if (_loadingFuture != null) {
      await _loadingFuture;
      return;
    }

    final completer = Completer<void>();
    _loadingFuture = completer.future;
    try {
      await _ensureDayStartHourLoaded();

      final hasSqlite = await _sqlite.hasAnyData();
      if (hasSqlite) {
        await _loadFromSqlite();
      } else {
        final file = await _dataFile();
        if (await file.exists()) {
          final raw = await file.readAsString();
          if (raw.trim().isNotEmpty) {
            final j = jsonDecode(raw) as Map<String, dynamic>;
            _applyJson(j);
            await _save();
          } else {
            await _seed();
          }
        } else {
          await _seed();
        }
      }

      final repaired = _autoRepairInMemoryDuplicatesAndCounters();
      if (repaired) {
        await _save();
      }

      _rebuildEngineFromTxns();
      _loaded = true;
      await _runDailyIntegrityCheckIfNeeded();
      completer.complete();
    } catch (e, st) {
      completer.completeError(e, st);
      rethrow;
    } finally {
      _loadingFuture = null;
    }
  }

  Future<void> _seed() async {
    _wallets.clear();
    _txns.clear();
    _claims.clear();
    _dailyCloses.clear();
    _recentNumbers.clear();
    _customerAttachments.clear();
    _nextWalletId = 1;
    _nextTxnId = 1;
    _nextClaimId = 1;
    _nextCloseId = 1;
    _nextAttachmentId = 1;
    _lastPendingAlertDate = null;
    _lowBalanceAlertDate.clear();
    _dailyUsageResetAt.clear();
    _monthlyUsageResetAt.clear();

    // Example wallets (edit as needed)
    _wallets.addAll([
      Wallet(id: _nextWalletId++, name: 'Vodafone Cash'),
      Wallet(id: _nextWalletId++, name: 'Etisalat Cash'),
    ]);

    // Example: initial drawer funding
    _txns.add(
      Txn(
        id: _nextTxnId++,
        kind: 'drawer_deposit',
        status: 'posted',
        entryDate: DateTime.now(),
        amount: 500.0,
        clientFee: 0,
        networkFee: 0,
        mode: 'drawer',
        note: 'Seed drawer',
        createdBy: 'system',
        createdRole: 'system',
        createdAt: DateTime.now(),
      ),
    );

    await _save();
  }

  Future<void> _seedEmpty() async {
    _wallets.clear();
    _txns.clear();
    _claims.clear();
    _dailyCloses.clear();
    _recentNumbers.clear();
    _customerAttachments.clear();
    _nextWalletId = 1;
    _nextTxnId = 1;
    _nextClaimId = 1;
    _nextCloseId = 1;
    _nextAttachmentId = 1;
    _lastPendingAlertDate = null;
    _lowBalanceAlertDate.clear();
    _dailyUsageResetAt.clear();
    _monthlyUsageResetAt.clear();
    await _save();
  }

  Future<void> _resetEmpty() async {
    await _closeSqlite();
    await _deleteSqliteArtifacts();
    final legacy = await _dataFile();
    if (await legacy.exists()) await legacy.delete();
    await _reopenSqlite();
    await _clearSqliteAllData();
    _loaded = false;
    await _seedEmpty();
    _rebuildEngineFromTxns();
    _loaded = true;
  }

  Future<void> _clearSqliteAllData() async {
    try {
      await _sqlite.clearAll();
    } catch (e) {
      if (!_isReadonlyDatabaseError(e)) rethrow;
      await _recoverWritableDatabaseFile();
      await _sqlite.clearAll();
    }
  }

  bool _isReadonlyDatabaseError(Object e) {
    final m = e.toString().toLowerCase();
    return m.contains('readonly database') ||
        m.contains('attempt to write a readonly database') ||
        m.contains('code 1032');
  }

  Future<void> _recoverWritableDatabaseFile() async {
    await _closeSqlite();
    final file = await _sqliteFile();
    final parent = file.parent;
    if (!await parent.exists()) {
      await parent.create(recursive: true);
    }
    for (final suffix in ['', '-wal', '-shm']) {
      final target = File('${file.path}$suffix');
      try {
        if (await target.exists()) {
          await target.delete();
        }
      } catch (_) {}
    }
    try {
      if (!await file.exists()) {
        await file.create(recursive: true);
      }
    } catch (_) {}
    await _reopenSqlite();
  }

  Future<void> _save() async {
    final meta = <String, String>{
      'nextWalletId': _nextWalletId.toString(),
      'nextTxnId': _nextTxnId.toString(),
      'nextClaimId': _nextClaimId.toString(),
      'nextCloseId': _nextCloseId.toString(),
      'nextAttachmentId': _nextAttachmentId.toString(),
      'lastPendingAlertDate': _lastPendingAlertDate ?? '',
      'lowBalanceAlertDate': jsonEncode(
        _lowBalanceAlertDate.map((k, v) => MapEntry(k.toString(), v)),
      ),
      'dailyUsageResetAt': jsonEncode(
        _dailyUsageResetAt.map(
          (k, v) => MapEntry(k.toString(), v.toIso8601String()),
        ),
      ),
      'monthlyUsageResetAt': jsonEncode(
        _monthlyUsageResetAt.map(
          (k, v) => MapEntry(k.toString(), v.toIso8601String()),
        ),
      ),
      'customerAttachments': jsonEncode(
        _customerAttachments.map((a) => a.toJson()).toList(),
      ),
    };
    try {
      await _sqlite.saveSnapshot(
        walletItems: _wallets,
        txnItems: _txns,
        claimItems: _claims,
        dailyCloseItems: _dailyCloses,
        recentNumberItems: _recentNumbers,
        metaItems: meta,
      );
    } catch (e) {
      if (!_isReadonlyDatabaseError(e)) rethrow;
      await _recoverWritableDatabaseFile();
      await _sqlite.saveSnapshot(
        walletItems: _wallets,
        txnItems: _txns,
        claimItems: _claims,
        dailyCloseItems: _dailyCloses,
        recentNumberItems: _recentNumbers,
        metaItems: meta,
      );
    }
  }

  bool _hasDuplicateIds<T>(Iterable<T> items, int Function(T item) idOf) {
    final seen = <int>{};
    for (final item in items) {
      if (!seen.add(idOf(item))) return true;
    }
    return false;
  }

  bool _hasDuplicateDateKeys(Iterable<DailyClose> items) {
    final seen = <String>{};
    for (final item in items) {
      if (!seen.add(item.dateKey)) return true;
    }
    return false;
  }

  bool _autoRepairInMemoryDuplicatesAndCounters() {
    bool changed = false;

    final hasWalletDup = _hasDuplicateIds(_wallets, (w) => w.id);
    final hasTxnDup = _hasDuplicateIds(_txns, (t) => t.id);
    final hasClaimDup = _hasDuplicateIds(_claims, (c) => c.id);
    final hasCloseDupDate = _hasDuplicateDateKeys(_dailyCloses);
    final hasCloseDupId = _hasDuplicateIds(_dailyCloses, (c) => c.id);

    if (hasWalletDup) {
      final fixed = _fixWalletDuplicates();
      changed = changed || fixed > 0;
    }
    if (hasTxnDup) {
      final fixed = _fixTxnDuplicates();
      changed = changed || fixed > 0;
    }
    if (hasClaimDup) {
      final fixed = _fixClaimDuplicates();
      changed = changed || fixed > 0;
    }
    if (hasCloseDupDate || hasCloseDupId) {
      final fixed = _fixDailyCloseDuplicates();
      changed = changed || fixed > 0;
    }

    final maxWalletId = _maxId(_wallets, (w) => w.id);
    final maxTxnId = _maxId(_txns, (t) => t.id);
    final maxClaimId = _maxId(_claims, (c) => c.id);
    final maxCloseId = _maxId(_dailyCloses, (c) => c.id);
    final invalidCounters =
        _nextWalletId <= maxWalletId ||
        _nextTxnId <= maxTxnId ||
        _nextClaimId <= maxClaimId ||
        _nextCloseId <= maxCloseId;

    if (invalidCounters || changed) {
      _normalizeNextIdsAndMaps();
      changed = true;
    }

    return changed;
  }

  /// Rebuild AccountingState from _txns list.
  /// This makes JSON schema stable and avoids drift between old/new.
  void _rebuildEngineFromTxns() {
    _state.walletBalancesQirsh.clear();
    _state.drawerBalanceQirsh = 0;
    _state.fawryBalanceQirsh = 0;
    _state.ledger.clear();
    _state.transactions.clear();

    // Apply txns in chronological order
    final sorted = [..._txns]
      ..sort((a, b) => a.entryDate.compareTo(b.entryDate));

    for (final t in sorted) {
      final txId = _txId(t.id);
      final spec = _specFromTxn(t);

      if (_hasStatus(t, 'pending')) {
        _engine.createPending(txId: txId, spec: spec, payload: t.toJson());
        continue;
      }

      if (_hasStatus(t, 'posted')) {
        // Use engine path to ensure validation is respected.
        _engine.createPending(txId: txId, spec: spec, payload: t.toJson());
        _engine.approve(txId: txId, spec: spec);
        continue;
      }

      // canceled/rejected -> ignore for balances
    }
  }

  String _txId(int txnId) => 'txn:$txnId';

  ({int drawerQirsh, int fawryQirsh, Map<String, int> walletsQirsh})
  _projectedBalances({Txn? includeTxn, int? excludeTxnId}) {
    final wallets = <String, int>{};
    for (final w in _wallets) {
      wallets[w.id.toString()] = _state.getWalletQirsh(w.id.toString());
    }
    var drawer = _state.drawerBalanceQirsh;
    var fawry = _state.fawryBalanceQirsh;

    void applyTxn(Txn txn, {required bool walletOnly}) {
      final spec = _specFromTxn(txn);
      final entries = spec.buildEntries(_txId(txn.id));
      for (final e in entries) {
        if (e.accountKey == 'drawer') {
          if (walletOnly) continue;
          drawer += e.deltaQirsh;
        } else if (e.accountKey == 'fawry') {
          if (walletOnly) continue;
          fawry += e.deltaQirsh;
        } else if (e.accountKey.startsWith('wallet:')) {
          final wid = e.accountKey.split(':')[1];
          wallets[wid] = (wallets[wid] ?? 0) + e.deltaQirsh;
        }
      }
    }

    final pendingSorted =
        _txns
            .where(
              (t) =>
                  _hasStatus(t, 'pending') &&
                  (excludeTxnId == null || t.id != excludeTxnId),
            )
            .toList()
          ..sort((a, b) => a.entryDate.compareTo(b.entryDate));
    for (final t in pendingSorted) {
      final walletOnly = _walletPendingAffectsBalance(t);
      // Pending projection policy:
      // - transfer/receive impact wallets only
      // - other pending kinds have no projected balance impact
      if (!walletOnly) continue;
      applyTxn(t, walletOnly: true);
    }
    if (includeTxn != null && _hasStatus(includeTxn, 'pending')) {
      final walletOnly = _walletPendingAffectsBalance(includeTxn);
      if (walletOnly) {
        applyTxn(includeTxn, walletOnly: true);
      }
    }
    return (drawerQirsh: drawer, fawryQirsh: fawry, walletsQirsh: wallets);
  }

  void _validateProjectedWalletsNonNegative(Txn candidate) {
    final simulated = candidate.status == 'pending'
        ? candidate
        : candidate.copyWith(status: 'pending');
    final projected = _projectedBalances(includeTxn: simulated);
    for (final w in _wallets) {
      final q = projected.walletsQirsh[w.id.toString()] ?? 0;
      if (q < 0) {
        throw Exception(
          'لا يمكن تنفيذ العملية: رصيد المحفظة ${w.name} سيصبح سالبًا',
        );
      }
    }
  }

  TxSpec _specFromTxn(Txn t) {
    final kind = t.kind;

    if (kind == 'external_funding') {
      final wid = (t.walletToId ?? 0).toString();
      return WalletFundingTxSpec(
        walletId: wid,
        amountQirsh: Money.fromEgpDouble(t.amount),
        note: t.note,
      );
    }

    if (kind == 'drawer_deposit') {
      return DrawerFundingTxSpec(
        amountQirsh: Money.fromEgpDouble(t.amount),
        note: t.note,
      );
    }

    if (kind == 'transfer') {
      final fromId = (t.walletFromId ?? 0).toString();

      // Stored transfer amount is wallet spend.
      // Actual transferred amount to receiver = spend - networkFee.
      final spendQ = Money.fromEgpDouble(t.amount);
      final nfQ = Money.fromEgpDouble(t.networkFee);
      final cfQ = Money.fromEgpDouble(t.clientFee);
      final transferAmountQ = spendQ - nfQ;

      // Keep old type2 records stable, use new logic only for type2_v2.
      if (t.mode == 'type2') {
        return TransferLegacyType2TxSpec(
          fromWalletId: fromId,
          spendQirsh: spendQ,
          nfQirsh: nfQ,
          cfQirsh: cfQ,
        );
      }

      final mode = (t.mode == 'type1')
          ? CommissionMode.cash
          : CommissionMode.deductFromAmount;

      return TransferTxSpec(
        fromWalletId: fromId,
        amountQirsh: transferAmountQ,
        nfQirsh: nfQ,
        cfQirsh: cfQ,
        mode: mode,
      );
    }

    if (kind == 'receive') {
      final wid = (t.walletToId ?? 0).toString();
      final amtQ = Money.fromEgpDouble(t.amount);
      final cfQ = Money.fromEgpDouble(t.clientFee);

      final m = t.mode;
      final rm = (m == 'cash')
          ? ReceiveMode.cashCommission
          : (m == 'deduct')
          ? ReceiveMode.deductFromAmount
          : ReceiveMode.electronic;

      return ReceiveTxSpec(
        walletId: wid,
        amountQirsh: amtQ,
        cfQirsh: cfQ,
        mode: rm,
      );
    }
    if (kind == 'claim_collect') {
      final amtQ = Money.fromEgpDouble(t.amount);
      final label = (t.note ?? 'طھط­طµ طھط­ظ‚طھ').toString();
      return DrawerFundingTxSpec(amountQirsh: amtQ, note: label);
    }

    if (kind == 'claim_pay') {
      final amtQ = Money.fromEgpDouble(t.amount);
      final label = (t.note ?? 'ط¯ط¯ طھط­ظ‚طھ').toString();
      return DrawerFundingTxSpec(amountQirsh: -amtQ, note: label);
    }

    if (kind == 'claim_open_receivable') {
      final amtQ = Money.fromEgpDouble(t.amount);
      final label = (t.note ?? 'ظپطھط­ طھط­ظ‚ ').toString();
      return DrawerFundingTxSpec(amountQirsh: -amtQ, note: label);
    }

    if (kind == 'claim_open_payable') {
      final amtQ = Money.fromEgpDouble(t.amount);
      final label = (t.note ?? 'ظپطھط­ طھط­ظ‚ ').toString();
      return DrawerFundingTxSpec(amountQirsh: amtQ, note: label);
    }

    if (kind == 'pending_settlement_adjust') {
      final amtQ = Money.fromEgpDouble(t.amount);
      final label = (t.note ?? 'تسوية تحصيل معلّق').toString();
      return DrawerFundingTxSpec(amountQirsh: amtQ, note: label);
    }

    if (kind == 'fawry_cash') {
      final amountQ = Money.fromEgpDouble(t.amount);
      final feeQ = Money.fromEgpDouble(t.clientFee);
      final label = (t.note ?? 'Fawry cash').toString();
      return FawryCashTxSpec(amountQirsh: amountQ, feeQirsh: feeQ, note: label);
    }

    if (kind == 'fawry_credit') {
      final amtQ = Money.fromEgpDouble(t.amount);
      final label = (t.note ?? 'Fawry credit').toString();
      return FawryCreditTxSpec(amountQirsh: amtQ, note: label);
    }

    if (kind == 'fawry_fund_drawer') {
      final amtQ = Money.fromEgpDouble(t.amount);
      final label = (t.note ?? 'Fawry drawer top-up').toString();
      return FawryDrawerTopupTxSpec(amountQirsh: amtQ, note: label);
    }
    if (kind == 'expense') {
      // Expense subtracts from drawer only.
      // Reuse DrawerFundingTxSpec with NEGATIVE amountQirsh.
      final amtQ = Money.fromEgpDouble(t.amount);
      final cat = t.mode;
      final label =
          'مصروف: $cat${t.note != null && t.note!.trim().isNotEmpty ? ' - ${t.note}' : ''}';
      return DrawerFundingTxSpec(amountQirsh: -amtQ, note: label);
    }
    // Fallback (should not happen)
    throw Exception('Unknown txn kind: $kind');
  }
}
