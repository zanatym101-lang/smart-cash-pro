part of 'app_db.dart';

extension _AppDbInternal on AppDb {
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
    _nextWalletId = (j['nextWalletId'] ?? 1) as int;
    _nextTxnId = (j['nextTxnId'] ?? 1) as int;
    _nextClaimId = (j['nextClaimId'] ?? 1) as int;
    _nextCloseId = (j['nextCloseId'] ?? 1) as int;

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

    _lastPendingAlertDate = (j['lastPendingAlertDate'] as String?)?.trim();
    final lowMap = (j['lowBalanceAlertDate'] as Map<String, dynamic>?) ?? {};
    _lowBalanceAlertDate
      ..clear()
      ..addAll(
        lowMap.map(
          (k, v) => MapEntry(int.tryParse(k) ?? 0, (v ?? '').toString()),
        ),
      );
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
  }

  Future<void> _ensureLoaded() async {
    if (_loaded) return;
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

    _rebuildEngineFromTxns();
    _loaded = true;
  }

  Future<void> _seed() async {
    _wallets.clear();
    _txns.clear();
    _claims.clear();
    _dailyCloses.clear();
    _recentNumbers.clear();
    _nextWalletId = 1;
    _nextTxnId = 1;
    _nextClaimId = 1;
    _nextCloseId = 1;
    _lastPendingAlertDate = null;
    _lowBalanceAlertDate.clear();

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
    _nextWalletId = 1;
    _nextTxnId = 1;
    _nextClaimId = 1;
    _nextCloseId = 1;
    _lastPendingAlertDate = null;
    _lowBalanceAlertDate.clear();
    await _save();
  }

  Future<void> _resetEmpty() async {
    await _closeSqlite();
    final file = await _sqliteFile();
    if (await file.exists()) await file.delete();
    final legacy = await _dataFile();
    if (await legacy.exists()) await legacy.delete();
    await _reopenSqlite();
    _loaded = false;
    await _seedEmpty();
    _rebuildEngineFromTxns();
    _loaded = true;
  }

  Future<void> _save() async {
    final meta = <String, String>{
      'nextWalletId': _nextWalletId.toString(),
      'nextTxnId': _nextTxnId.toString(),
      'nextClaimId': _nextClaimId.toString(),
      'nextCloseId': _nextCloseId.toString(),
      'lastPendingAlertDate': _lastPendingAlertDate ?? '',
      'lowBalanceAlertDate': jsonEncode(
        _lowBalanceAlertDate.map((k, v) => MapEntry(k.toString(), v)),
      ),
    };
    await _sqlite.saveSnapshot(
      walletItems: _wallets,
      txnItems: _txns,
      claimItems: _claims,
      dailyCloseItems: _dailyCloses,
      recentNumberItems: _recentNumbers,
      metaItems: meta,
    );
  }

  /// Rebuild AccountingState from _txns list.
  /// This makes JSON schema stable and avoids drift between old/new.
  void _rebuildEngineFromTxns() {
    _state.walletBalancesQirsh.clear();
    _state.drawerBalanceQirsh = 0;
    _state.ledger.clear();
    _state.transactions.clear();

    // Apply txns in chronological order
    final sorted = [..._txns]
      ..sort((a, b) => a.entryDate.compareTo(b.entryDate));

    for (final t in sorted) {
      final txId = _txId(t.id);
      final spec = _specFromTxn(t);

      if (t.status == 'pending') {
        _engine.createPending(txId: txId, spec: spec, payload: t.toJson());
        continue;
      }

      if (t.status == 'posted') {
        // Use engine path to ensure validation is respected.
        _engine.createPending(txId: txId, spec: spec, payload: t.toJson());
        _engine.approve(txId: txId, spec: spec);
        continue;
      }

      // canceled/rejected -> ignore for balances
    }
  }

  String _txId(int txnId) => 'txn:$txnId';

  ({int drawerQirsh, Map<String, int> walletsQirsh}) _projectedBalances({
    Txn? includeTxn,
    int? excludeTxnId,
  }) {
    final wallets = <String, int>{};
    for (final w in _wallets) {
      wallets[w.id.toString()] = _state.getWalletQirsh(w.id.toString());
    }
    var drawer = _state.drawerBalanceQirsh;

    void applyTxn(Txn txn) {
      final spec = _specFromTxn(txn);
      final entries = spec.buildEntries(_txId(txn.id));
      for (final e in entries) {
        if (e.accountKey == 'drawer') {
          drawer += e.deltaQirsh;
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
                  t.status == 'pending' &&
                  (excludeTxnId == null || t.id != excludeTxnId),
            )
            .toList()
          ..sort((a, b) => a.entryDate.compareTo(b.entryDate));
    for (final t in pendingSorted) {
      applyTxn(t);
    }
    if (includeTxn != null && includeTxn.status == 'pending') {
      applyTxn(includeTxn);
    }
    return (drawerQirsh: drawer, walletsQirsh: wallets);
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

      // In v47 we store wallet movement as amount = (transferAmount + networkFee)
      // So transferAmount = storedAmount - networkFee
      final spendQ = Money.fromEgpDouble(t.amount);
      final nfQ = Money.fromEgpDouble(t.networkFee);
      final cfQ = Money.fromEgpDouble(t.clientFee);
      final transferAmountQ = spendQ - nfQ;

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
      final label = (t.note ?? 'تحصيل مستحقات').toString();
      return DrawerFundingTxSpec(amountQirsh: amtQ, note: label);
    }

    if (kind == 'claim_pay') {
      final amtQ = Money.fromEgpDouble(t.amount);
      final label = (t.note ?? 'سداد مستحقات').toString();
      return DrawerFundingTxSpec(amountQirsh: -amtQ, note: label);
    }

    if (kind == 'fawry_cash') {
      final feeQ = Money.fromEgpDouble(t.clientFee);
      final label = (t.note ?? 'فوري نقدي').toString();
      return DrawerFundingTxSpec(amountQirsh: feeQ, note: label);
    }

    if (kind == 'fawry_credit') {
      final amtQ = Money.fromEgpDouble(t.amount);
      final label = (t.note ?? 'فوري آجل').toString();
      return DrawerFundingTxSpec(amountQirsh: -amtQ, note: label);
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
