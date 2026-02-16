part of 'app_db.dart';

extension AppDbWallets on AppDb {
  String _normalizeDigit(String ch) {
    switch (ch) {
      case '٠':
      case '۰':
        return '0';
      case '١':
      case '۱':
        return '1';
      case '٢':
      case '۲':
        return '2';
      case '٣':
      case '۳':
        return '3';
      case '٤':
      case '۴':
        return '4';
      case '٥':
      case '۵':
        return '5';
      case '٦':
      case '۶':
        return '6';
      case '٧':
      case '۷':
        return '7';
      case '٨':
      case '۸':
        return '8';
      case '٩':
      case '۹':
        return '9';
      default:
        return ch;
    }
  }

  String _normalizePhone(String input) {
    final buf = StringBuffer();
    for (final r in input.runes) {
      final raw = String.fromCharCode(r);
      final ch = _normalizeDigit(raw);
      final code = ch.codeUnitAt(0);
      if (code >= 48 && code <= 57) {
        buf.write(ch);
      }
    }
    return buf.toString();
  }

  bool _walletPhoneExists(String normalizedPhone, {int? exceptWalletId}) {
    for (final w in _wallets) {
      if (exceptWalletId != null && w.id == exceptWalletId) continue;
      if (_normalizePhone(w.phone) == normalizedPhone) {
        return true;
      }
    }
    return false;
  }

  Future<void> resetDatabase() async {
    if (!AppSession.isAdmin) {
      throw Exception('هذا الإجراء متاح للأدمن فقط');
    }
    await _closeSqlite();
    await _deleteSqliteArtifacts();
    final legacy = await _dataFile();
    if (await legacy.exists()) await legacy.delete();
    await _reopenSqlite();
    await _clearSqliteAllData();
    _loaded = false;
    await _seed();
    _rebuildEngineFromTxns();
    _loaded = true;
  }

  Future<void> resetDatabaseEmpty() async {
    if (!AppSession.isAdmin) {
      throw Exception('هذا الإجراء متاح للأدمن فقط');
    }
    await _resetEmpty();
  }

  Future<List<Wallet>> listWallets() async {
    await _ensureLoaded();
    return List.unmodifiable(_wallets);
  }

  Future<int> addWallet({
    required String name,
    required String phone,
    double openingBalance = 0,
    double dailyLimit = 60000,
    double monthlyLimit = 200000,
    double lowBalanceThreshold = 0,
    bool allowNegative = false,
  }) async {
    await _ensureLoaded();
    await _ensureWalletAllowed();
    final n = name.trim();
    if (n.isEmpty) {
      throw Exception('اسم المحفظة مطلوب');
    }
    final p = _normalizePhone(phone);
    if (p.isEmpty) {
      throw Exception('رقم هاتف المحفظة مطلوب');
    }
    if (_walletPhoneExists(p)) {
      throw Exception(
        '\u0631\u0642\u0645 \u0627\u0644\u0645\u062d\u0641\u0638\u0629 \u0645\u0633\u062c\u0644 \u0645\u0633\u0628\u0642\u064b\u0627',
      );
    }
    if (dailyLimit <= 0) {
      throw Exception('الحد اليومي يجب أن يكون أكبر من صفر');
    }
    if (monthlyLimit <= 0) {
      throw Exception('الحد الشهري يجب أن يكون أكبر من صفر');
    }
    if (monthlyLimit < dailyLimit) {
      throw Exception('الحد الشهري يجب أن يكون أكبر من أو يساوي الحد اليومي');
    }
    if (openingBalance < 0) {
      throw Exception('رصيد أول المدة لا يمكن أن يكون سالبًا');
    }
    if (lowBalanceThreshold < 0) {
      throw Exception('حد التنبيه المنخفض لا يمكن أن يكون سالبًا');
    }
    final w = Wallet(
      id: _nextWalletId++,
      name: n,
      allowNegative: allowNegative,
      phone: p,
      dailyLimit: dailyLimit,
      monthlyLimit: monthlyLimit,
      lowBalanceThreshold: lowBalanceThreshold,
    );
    _wallets.add(w);

    if (openingBalance > 0) {
      final now = DateTime.now();
      final entryDate = _nextOpenDate(now);
      final txn = Txn(
        id: _nextTxnId++,
        kind: 'external_funding',
        status: 'posted',
        entryDate: entryDate,
        walletToId: w.id,
        amount: openingBalance,
        clientFee: 0,
        networkFee: 0,
        mode: 'opening_balance',
        note: 'رصيد أول المدة',
        createdBy: _actorName(),
        createdRole: _actorRole(),
        createdAt: now,
      );
      final spec = WalletFundingTxSpec(
        walletId: w.id.toString(),
        amountQirsh: Money.fromEgpDouble(openingBalance),
        note: 'رصيد أول المدة',
      );
      _engine.createPending(
        txId: _txId(txn.id),
        spec: spec,
        payload: txn.toJson(),
      );
      _engine.approve(txId: _txId(txn.id), spec: spec);
      _txns.add(txn);
      await enqueueOutbox(
        entity: 'txn',
        entityId: txn.id.toString(),
        action: 'create',
        payload: txn.toJson(),
      );
      await appendAudit(
        type: 'wallet_opening_balance',
        txnId: txn.id,
        walletId: w.id,
        amount: openingBalance,
        note: 'رصيد أول المدة',
      );
    }

    await _save();
    await enqueueOutbox(
      entity: 'wallet',
      entityId: w.id.toString(),
      action: 'create',
      payload: w.toJson(),
    );
    await appendAudit(type: 'wallet_add', walletId: w.id, note: w.name);
    return w.id;
  }

  Future<void> updateWallet({
    required int walletId,
    required String name,
    required String phone,
    required double dailyLimit,
    required double monthlyLimit,
    required double lowBalanceThreshold,
  }) async {
    await _ensureLoaded();
    final n = name.trim();
    if (n.isEmpty) {
      throw Exception('اسم المحفظة مطلوب');
    }
    final p = _normalizePhone(phone);
    if (p.isEmpty) {
      throw Exception('رقم هاتف المحفظة مطلوب');
    }
    if (_walletPhoneExists(p, exceptWalletId: walletId)) {
      throw Exception(
        '\u0631\u0642\u0645 \u0627\u0644\u0645\u062d\u0641\u0638\u0629 \u0645\u0633\u062c\u0644 \u0645\u0633\u0628\u0642\u064b\u0627',
      );
    }
    if (dailyLimit <= 0) {
      throw Exception('الحد اليومي يجب أن يكون أكبر من صفر');
    }
    if (monthlyLimit <= 0) {
      throw Exception('الحد الشهري يجب أن يكون أكبر من صفر');
    }
    if (monthlyLimit < dailyLimit) {
      throw Exception('الحد الشهري يجب أن يكون أكبر من أو يساوي الحد اليومي');
    }
    if (lowBalanceThreshold < 0) {
      throw Exception('حد التنبيه المنخفض لا يمكن أن يكون سالبًا');
    }
    final idx = _wallets.indexWhere((w) => w.id == walletId);
    if (idx == -1) {
      throw Exception('المحفظة غير موجودة');
    }
    _wallets[idx] = _wallets[idx].copyWith(
      name: n,
      phone: p,
      dailyLimit: dailyLimit,
      monthlyLimit: monthlyLimit,
      lowBalanceThreshold: lowBalanceThreshold,
    );
    await _save();
    await enqueueOutbox(
      entity: 'wallet',
      entityId: walletId.toString(),
      action: 'update',
      payload: _wallets[idx].toJson(),
    );
    await appendAudit(type: 'wallet_update', walletId: walletId, note: n);
  }

  Future<double> getWalletBalance(int walletId) async {
    await _ensureLoaded();
    final q = _state.getWalletQirsh(walletId.toString());
    return Money.toEgpDouble(q);
  }

  Future<double> getWalletAvailableBalance(int walletId) async {
    await _ensureLoaded();
    final projected = _projectedBalances();
    final q = projected.walletsQirsh[walletId.toString()] ?? 0;
    return Money.toEgpDouble(q);
  }

  Future<double> getFawryBalance() async {
    await _ensureLoaded();
    return Money.toEgpDouble(_state.fawryBalanceQirsh);
  }

  String _businessMonthKeyFromDateTime(DateTime dt) {
    final shifted = _businessShift(dt);
    final y = shifted.year.toString().padLeft(4, '0');
    final m = shifted.month.toString().padLeft(2, '0');
    return '$y-$m';
  }

  Future<void> _cleanupUsageResetsIfNeeded() async {
    final now = DateTime.now();
    final todayKey = _businessDateKeyFromDateTime(now);
    final monthKey = _businessMonthKeyFromDateTime(now);
    var changed = false;
    final walletIds = _wallets.map((w) => w.id).toSet();

    _dailyUsageResetAt.removeWhere((walletId, _) {
      final keep = walletIds.contains(walletId);
      if (!keep) changed = true;
      return !keep;
    });
    _monthlyUsageResetAt.removeWhere((walletId, _) {
      final keep = walletIds.contains(walletId);
      if (!keep) changed = true;
      return !keep;
    });

    _dailyUsageResetAt.removeWhere((_, dt) {
      final keep = _businessDateKeyFromDateTime(dt) == todayKey;
      if (!keep) changed = true;
      return !keep;
    });

    _monthlyUsageResetAt.removeWhere((_, dt) {
      final keep = _businessMonthKeyFromDateTime(dt) == monthKey;
      if (!keep) changed = true;
      return !keep;
    });

    if (changed) {
      await _save();
    }
  }

  Future<void> resetWalletDailyUsage(int walletId) async {
    await _ensureLoaded();
    if (!AppSession.isAdmin) {
      throw Exception('هذا الإجراء متاح للأدمن فقط');
    }
    _requireWallet(walletId);
    _dailyUsageResetAt[walletId] = DateTime.now();
    await _save();
    await appendAudit(
      type: 'wallet_daily_limit_usage_reset',
      walletId: walletId,
    );
  }

  Future<void> resetWalletMonthlyUsage(int walletId) async {
    await _ensureLoaded();
    if (!AppSession.isAdmin) {
      throw Exception('هذا الإجراء متاح للأدمن فقط');
    }
    _requireWallet(walletId);
    _monthlyUsageResetAt[walletId] = DateTime.now();
    await _save();
    await appendAudit(
      type: 'wallet_monthly_limit_usage_reset',
      walletId: walletId,
    );
  }

  Future<void> resetAllWalletDailyUsage() async {
    await _ensureLoaded();
    if (!AppSession.isAdmin) {
      throw Exception('هذا الإجراء متاح للأدمن فقط');
    }
    final now = DateTime.now();
    for (final w in _wallets) {
      _dailyUsageResetAt[w.id] = now;
    }
    await _save();
    await appendAudit(type: 'wallet_daily_limit_usage_reset_all');
  }

  Future<void> resetAllWalletMonthlyUsage() async {
    await _ensureLoaded();
    if (!AppSession.isAdmin) {
      throw Exception('هذا الإجراء متاح للأدمن فقط');
    }
    final now = DateTime.now();
    for (final w in _wallets) {
      _monthlyUsageResetAt[w.id] = now;
    }
    await _save();
    await appendAudit(type: 'wallet_monthly_limit_usage_reset_all');
  }

  Future<Map<int, WalletLimitUsage>> getWalletLimitUsage() async {
    await _ensureLoaded();
    await _cleanupUsageResetsIfNeeded();

    final now = DateTime.now();
    final dayKey = _businessDateKeyFromDateTime(now);
    final monthKey = _businessMonthKeyFromDateTime(now);

    final dailyByWallet = <int, double>{};
    final monthlyByWallet = <int, double>{};

    for (final t in _txns) {
      if (t.kind != 'transfer') continue;
      if (t.status != 'posted' && t.status != 'pending') continue;
      final walletId = t.walletFromId;
      if (walletId == null) continue;

      final baseAmount = t.mode == 'type2_v2'
          ? (t.amount + t.clientFee)
          : (t.amount - t.networkFee);
      if (baseAmount <= 0) continue;

      final dailyResetAnchor = _dailyUsageResetAt[walletId];
      if (_businessDateKeyFromDateTime(t.entryDate) == dayKey &&
          (dailyResetAnchor == null ||
              !t.entryDate.isBefore(dailyResetAnchor))) {
        dailyByWallet[walletId] = (dailyByWallet[walletId] ?? 0) + baseAmount;
      }

      final monthlyResetAnchor = _monthlyUsageResetAt[walletId];
      if (_businessMonthKeyFromDateTime(t.entryDate) == monthKey &&
          (monthlyResetAnchor == null ||
              !t.entryDate.isBefore(monthlyResetAnchor))) {
        monthlyByWallet[walletId] =
            (monthlyByWallet[walletId] ?? 0) + baseAmount;
      }
    }

    final result = <int, WalletLimitUsage>{};
    for (final w in _wallets) {
      result[w.id] = WalletLimitUsage(
        walletId: w.id,
        dailyUsed: dailyByWallet[w.id] ?? 0,
        dailyLimit: w.dailyLimit,
        monthlyUsed: monthlyByWallet[w.id] ?? 0,
        monthlyLimit: w.monthlyLimit,
      );
    }
    return result;
  }

  Future<TreasurySnapshot> getTreasurySnapshot() async {
    await _ensureLoaded();

    // Posted/actual balances from engine state (qirsh -> EGP)
    final drawerActualBalance = Money.toEgpDouble(_state.drawerBalanceQirsh);
    final fawryActualBalance = Money.toEgpDouble(_state.fawryBalanceQirsh);
    int walletsActualQ = 0;
    for (final w in _wallets) {
      walletsActualQ += _state.getWalletQirsh(w.id.toString());
    }
    final walletsActualTotal = Money.toEgpDouble(walletsActualQ);

    // Available/projected balances (posted + pending)
    final projected = _projectedBalances();
    final drawerBalance = Money.toEgpDouble(projected.drawerQirsh);
    int walletsAvailableQ = 0;
    for (final w in _wallets) {
      walletsAvailableQ += projected.walletsQirsh[w.id.toString()] ?? 0;
    }
    final walletsTotal = Money.toEgpDouble(walletsAvailableQ);
    final fawryBalance = Money.toEgpDouble(projected.fawryQirsh);

    // Pending txns count
    final pendingCount = _txns.where((t) => t.status == 'pending').length;
    final pendingFlow = _pendingLiquidityFlowQirsh();
    final pendingInflow = Money.toEgpDouble(pendingFlow.inflowQirsh);
    final pendingOutflow = Money.toEgpDouble(pendingFlow.outflowQirsh);
    await _maybeNotifyPending();

    // Profits derived from posted txns (CF). Rolled-back originals are excluded by status.
    final now = DateTime.now();
    final nowDayKey = _businessDateKeyFromDateTime(now);
    final nowShifted = _businessShift(now);
    double dailyProfit = 0;
    double monthlyProfit = 0;
    double profitApprovedTotal = 0;

    for (final t in _txns) {
      if (t.status != 'posted') continue;
      if (t.kind == 'rollback') continue;

      final fee = t.clientFee;
      if (fee <= 0) continue;
      profitApprovedTotal += fee;

      if (_businessDateKeyFromDateTime(t.entryDate) == nowDayKey) {
        dailyProfit += fee;
      }
      final tShifted = _businessShift(t.entryDate);
      if (tShifted.year == nowShifted.year &&
          tShifted.month == nowShifted.month) {
        monthlyProfit += fee;
      }
    }

    double claimsReceivableOpen = 0;
    double claimsPayableOpen = 0;
    for (final c in _claims) {
      if (c.status != 'open') continue;
      if (c.type == 'receivable') {
        claimsReceivableOpen += c.amount;
      } else if (c.type == 'payable') {
        claimsPayableOpen += c.amount;
      }
    }

    return TreasurySnapshot(
      drawerBalance: drawerBalance,
      walletsTotal: walletsTotal,
      fawryBalance: fawryBalance,
      drawerActualBalance: drawerActualBalance,
      walletsActualTotal: walletsActualTotal,
      fawryActualBalance: fawryActualBalance,
      pendingCount: pendingCount,
      pendingInflow: pendingInflow,
      pendingOutflow: pendingOutflow,
      claimsReceivableOpen: claimsReceivableOpen,
      claimsPayableOpen: claimsPayableOpen,
      profitApprovedTotal: profitApprovedTotal,
      dailyProfit: dailyProfit,
      monthlyProfit: monthlyProfit,
    );
  }

  ({int inflowQirsh, int outflowQirsh}) _pendingLiquidityFlowQirsh() {
    int inflowQirsh = 0;
    int outflowQirsh = 0;
    final pendingSorted =
        _txns
            .where(
              (t) =>
                  t.status == 'pending' &&
                  (t.kind == 'receive' || t.kind == 'transfer'),
            )
            .toList()
          ..sort((a, b) => a.entryDate.compareTo(b.entryDate));

    for (final t in pendingSorted) {
      final spec = _specFromTxn(t);
      final entries = spec.buildEntries(_txId(t.id));
      for (final e in entries) {
        final k = e.accountKey;
        if (!k.startsWith('wallet:')) continue;
        if (e.deltaQirsh >= 0) {
          inflowQirsh += e.deltaQirsh;
        } else {
          outflowQirsh += -e.deltaQirsh;
        }
      }
    }

    return (inflowQirsh: inflowQirsh, outflowQirsh: outflowQirsh);
  }

  Future<void> _maybeNotifyPending() async {
    final now = DateTime.now();
    final todayKey = _businessDateKeyFromDateTime(now);
    if (_lastPendingAlertDate == todayKey) return;

    final cutoff = now.subtract(const Duration(days: 1));
    final oldPending = _txns
        .where((t) => t.status == 'pending' && t.entryDate.isBefore(cutoff))
        .length;
    if (oldPending <= 0) return;

    await NotificationService.show(
      title: 'تنبيه عمليات معلقة',
      body: 'يوجد لديك $oldPending عملية معلقة أقدم من يوم وتحتاج مراجعة.',
    );

    _lastPendingAlertDate = todayKey;
    await _save();
  }
}
