part of 'app_db.dart';

extension AppDbTransactions on AppDb {
  Wallet _requireWallet(int walletId) {
    final idx = _wallets.indexWhere((w) => w.id == walletId);
    if (idx == -1) throw Exception('المحفظة غير موجودة');
    return _wallets[idx];
  }

  double _transferBaseAmount(Txn t) => t.amount - t.networkFee;

  bool _sameDay(DateTime a, DateTime b) => _dayKey(a) == _dayKey(b);

  bool _sameMonth(DateTime a, DateTime b) {
    final sa = _businessShift(a);
    final sb = _businessShift(b);
    return sa.year == sb.year && sa.month == sb.month;
  }

  String _dayKey(DateTime d) => _businessDateKeyFromDateTime(d);

  void _requireAdmin() {
    if (!AppSession.isAdmin) {
      throw Exception('هذا الإجراء متاح للأدمن فقط');
    }
  }

  bool _isDayClosed(DateTime d) {
    final key = _dayKey(d);
    return _dailyCloses.any((c) => c.dateKey == key);
  }

  DateTime _nextOpenDate(DateTime now) {
    if (!_isDayClosed(now)) {
      return now;
    }
    var shifted = _businessShift(now);
    var businessDate = DateTime(
      shifted.year,
      shifted.month,
      shifted.day,
    ).add(const Duration(days: 1));
    while (_dailyCloses.any((c) => c.dateKey == _formatDateKey(businessDate))) {
      businessDate = businessDate.add(const Duration(days: 1));
    }
    return DateTime(
      businessDate.year,
      businessDate.month,
      businessDate.day,
      _dayStartHour(),
    );
  }

  void _ensureNotClosed(DateTime d) {
    if (_isDayClosed(d)) {
      throw Exception('تم إغلاق هذا اليوم، لا يمكن تعديل العمليات المرتبطة به');
    }
  }

  ({double daily, double monthly}) _transferUsage({
    required int walletId,
    required DateTime entryDate,
    int? excludeTxnId,
  }) {
    double dailySum = 0;
    double monthlySum = 0;

    for (final t in _txns) {
      if (t.kind != 'transfer') continue;
      if (t.walletFromId != walletId) continue;
      if (excludeTxnId != null && t.id == excludeTxnId) continue;
      if (t.status != 'posted' && t.status != 'pending') continue;

      final base = _transferBaseAmount(t);
      if (_sameDay(t.entryDate, entryDate)) dailySum += base;
      if (_sameMonth(t.entryDate, entryDate)) monthlySum += base;
    }

    return (daily: dailySum, monthly: monthlySum);
  }

  Future<void> _notifyLimitCross({
    required Wallet wallet,
    required double beforeDaily,
    required double afterDaily,
    required double beforeMonthly,
    required double afterMonthly,
  }) async {
    Future<void> check(
      double before,
      double after,
      double limit,
      double threshold,
      String label,
    ) async {
      if (limit <= 0) return;
      final beforePct = before / limit;
      final afterPct = after / limit;
      if (beforePct < threshold && afterPct >= threshold) {
        await NotificationService.show(
          title: 'تنبيه حدود المحفظة',
          body:
              '${wallet.name}: اقتربت من الحد $label (${(threshold * 100).toInt()}%).',
        );
      }
    }

    await check(beforeDaily, afterDaily, wallet.dailyLimit, 0.8, 'اليومي');
    await check(beforeDaily, afterDaily, wallet.dailyLimit, 0.9, 'اليومي');
    await check(
      beforeMonthly,
      afterMonthly,
      wallet.monthlyLimit,
      0.8,
      'الشهري',
    );
    await check(
      beforeMonthly,
      afterMonthly,
      wallet.monthlyLimit,
      0.9,
      'الشهري',
    );
  }

  Future<void> _notifyLowBalanceIfNeeded(Wallet wallet) async {
    final threshold = wallet.lowBalanceThreshold;
    if (threshold <= 0) return;
    final balQ = _state.getWalletQirsh(wallet.id.toString());
    final balance = Money.toEgpDouble(balQ);
    if (balance > threshold) return;

    final todayKey = _dayKey(DateTime.now());
    if (_lowBalanceAlertDate[wallet.id] == todayKey) return;

    await NotificationService.show(
      title: 'تنبيه رصيد منخفض',
      body:
          '${wallet.name}: الرصيد الحالي ${balance.toStringAsFixed(2)} أقل من الحد ${threshold.toStringAsFixed(2)}.',
    );
    _lowBalanceAlertDate[wallet.id] = todayKey;
    await _save();
  }

  void _checkTransferLimits({
    required int walletId,
    required double amount,
    required DateTime entryDate,
    int? excludeTxnId,
  }) {
    final w = _requireWallet(walletId);
    final dailyLimit = w.dailyLimit;
    final monthlyLimit = w.monthlyLimit;

    final usage = _transferUsage(
      walletId: walletId,
      entryDate: entryDate,
      excludeTxnId: excludeTxnId,
    );
    final dailySum = usage.daily;
    final monthlySum = usage.monthly;

    if (dailyLimit > 0 && (dailySum + amount) > dailyLimit) {
      NotificationService.show(
        title: 'تجاوز الحد اليومي',
        body:
            '${w.name}: محاولة تجاوز الحد اليومي (${dailyLimit.toStringAsFixed(2)}).',
      );
      throw Exception(
        'تجاوز الحد اليومي للمحفظة (${dailyLimit.toStringAsFixed(2)})',
      );
    }
    if (monthlyLimit > 0 && (monthlySum + amount) > monthlyLimit) {
      NotificationService.show(
        title: 'تجاوز الحد الشهري',
        body:
            '${w.name}: محاولة تجاوز الحد الشهري (${monthlyLimit.toStringAsFixed(2)}).',
      );
      throw Exception(
        'تجاوز الحد الشهري للمحفظة (${monthlyLimit.toStringAsFixed(2)})',
      );
    }
  }

  Future<int> addExternalFunding({
    required int walletId,
    required double amount,
    String? note,
  }) async {
    await _ensureLoaded();
    await _ensureOperationAllowed();
    _requireAdmin();
    if (amount <= 0) throw Exception('المبلغ يجب أن يكون أكبر من صفر');
    final now = DateTime.now();
    final entryDate = _nextOpenDate(now);
    final txn = Txn(
      id: _nextTxnId++,
      kind: 'external_funding',
      status: 'posted',
      entryDate: entryDate,
      walletToId: walletId,
      amount: amount,
      clientFee: 0,
      networkFee: 0,
      mode: 'fund',
      note: note,
      createdBy: _actorName(),
      createdRole: _actorRole(),
      createdAt: now,
    );

    // Apply through engine (always safe; wallet funding can't make negative)
    final spec = _specFromTxn(txn);
    _engine.createPending(
      txId: _txId(txn.id),
      spec: spec,
      payload: txn.toJson(),
    );
    _engine.approve(txId: _txId(txn.id), spec: spec);

    _txns.add(txn);
    await _save();
    await enqueueOutbox(
      entity: 'txn',
      entityId: txn.id.toString(),
      action: 'create',
      payload: txn.toJson(),
    );
    await appendAudit(
      type: 'external_funding',
      txnId: txn.id,
      walletId: walletId,
      amount: amount,
      note: note,
    );
    await _incrementOperationUsed();
    return txn.id;
  }

  // Drawer deposit: external cash to drawer. Drawer can go negative overall, but delta must not be zero.
  Future<int> drawerDeposit({required double amount, String? note}) async {
    await _ensureLoaded();
    await _ensureOperationAllowed();
    _requireAdmin();
    if (amount == 0) throw Exception('المبلغ لا يمكن أن يساوي صفر');
    final now = DateTime.now();
    final entryDate = _nextOpenDate(now);
    final txn = Txn(
      id: _nextTxnId++,
      kind: 'drawer_deposit',
      status: 'posted',
      entryDate: entryDate,
      amount: amount,
      clientFee: 0,
      networkFee: 0,
      mode: 'drawer',
      note: note,
      createdBy: _actorName(),
      createdRole: _actorRole(),
      createdAt: now,
    );

    final spec = _specFromTxn(txn);
    _engine.createPending(
      txId: _txId(txn.id),
      spec: spec,
      payload: txn.toJson(),
    );
    _engine.approve(txId: _txId(txn.id), spec: spec);

    _txns.add(txn);
    await _save();
    await enqueueOutbox(
      entity: 'txn',
      entityId: txn.id.toString(),
      action: 'create',
      payload: txn.toJson(),
    );
    await appendAudit(
      type: 'drawer_deposit',
      txnId: txn.id,
      amount: amount,
      note: note,
    );
    await _incrementOperationUsed();
    return txn.id;
  }

  Future<int> addTransfer({
    required int walletId,
    required double amount,
    required double clientFee,
    required double networkFee,
    required String transferType, // 'type1' or 'type2'
    bool isPending = false,
    String? note,
    String? party,
  }) async {
    await _ensureLoaded();
    await _ensureOperationAllowed();
    if (amount <= 0) throw Exception('المبلغ يجب أن يكون أكبر من صفر');
    final now = DateTime.now();
    final entryDate = _nextOpenDate(now);
    final beforeUsage = _transferUsage(
      walletId: walletId,
      entryDate: entryDate,
    );
    _checkTransferLimits(
      walletId: walletId,
      amount: amount,
      entryDate: entryDate,
    );

    final effectivePending = AppSession.isAdmin ? isPending : true;
    final status = effectivePending ? 'pending' : 'posted';

    // Keep the same stored meaning as v47:
    // amount field = wallet spend = amount + networkFee
    final walletSpend = amount + networkFee;

    final txn = Txn(
      id: _nextTxnId++,
      kind: 'transfer',
      status: status,
      entryDate: entryDate,
      walletFromId: walletId,
      amount: walletSpend,
      clientFee: clientFee,
      networkFee: networkFee,
      mode: transferType,
      note: note,
      party: party?.trim().isEmpty ?? true ? null : party?.trim(),
      createdBy: _actorName(),
      createdRole: _actorRole(),
      createdAt: now,
    );

    final spec = _specFromTxn(txn);
    final txId = _txId(txn.id);
    _validateProjectedWalletsNonNegative(txn);

    if (status == 'pending') {
      _engine.createPending(txId: txId, spec: spec, payload: txn.toJson());
    } else {
      // Validate + apply now (wallet cannot go negative)
      _engine.createPending(txId: txId, spec: spec, payload: txn.toJson());
      _engine.approve(txId: txId, spec: spec);
    }

    _txns.add(txn);
    final afterDaily = beforeUsage.daily + amount;
    final afterMonthly = beforeUsage.monthly + amount;
    final w = _requireWallet(walletId);
    await _notifyLimitCross(
      wallet: w,
      beforeDaily: beforeUsage.daily,
      afterDaily: afterDaily,
      beforeMonthly: beforeUsage.monthly,
      afterMonthly: afterMonthly,
    );
    if (status == 'posted') {
      await _notifyLowBalanceIfNeeded(w);
    }
    await _save();
    await enqueueOutbox(
      entity: 'txn',
      entityId: txn.id.toString(),
      action: 'create',
      payload: txn.toJson(),
    );
    await appendAudit(
      type: 'transfer_add',
      txnId: txn.id,
      walletId: walletId,
      amount: amount,
      note: note,
    );
    await _incrementOperationUsed();
    return txn.id;
  }

  Future<int> addReceive({
    required int walletId,
    required double amount,
    required double commission,
    required String receiveType, // 'cash' | 'deduct' | 'electronic'
    bool isPending = true,
    String? note,
    String? party,
  }) async {
    await _ensureLoaded();
    await _ensureOperationAllowed();
    if (amount <= 0) throw Exception('المبلغ يجب أن يكون أكبر من صفر');
    if (commission < 0) throw Exception('العمولة لا يمكن أن تكون سالبة');

    final effectivePending = AppSession.isAdmin ? isPending : true;
    final status = effectivePending ? 'pending' : 'posted';

    final now = DateTime.now();
    final entryDate = _nextOpenDate(now);
    final txn = Txn(
      id: _nextTxnId++,
      kind: 'receive',
      status: status,
      entryDate: entryDate,
      walletToId: walletId,
      amount:
          amount, // base amount (EGP). Engine handles mode-specific wallet delta.
      clientFee: commission,
      networkFee: 0,
      mode: receiveType,
      note: note,
      party: party?.trim().isEmpty ?? true ? null : party?.trim(),
      createdBy: _actorName(),
      createdRole: _actorRole(),
      createdAt: now,
    );

    final spec = _specFromTxn(txn);
    final txId = _txId(txn.id);
    _validateProjectedWalletsNonNegative(txn);

    if (status == 'pending') {
      _engine.createPending(txId: txId, spec: spec, payload: txn.toJson());
    } else {
      _engine.createPending(txId: txId, spec: spec, payload: txn.toJson());
      _engine.approve(txId: txId, spec: spec);
    }

    _txns.add(txn);
    await _save();
    await enqueueOutbox(
      entity: 'txn',
      entityId: txn.id.toString(),
      action: 'create',
      payload: txn.toJson(),
    );
    await appendAudit(
      type: 'receive_add',
      txnId: txn.id,
      walletId: walletId,
      amount: amount,
      note: note,
    );
    await _incrementOperationUsed();
    return txn.id;
  }

  // =====================
  // Expenses (Drawer only)
  // =====================
  Future<int> addExpense({
    required double amount,
    required String category,
    String? note,
    bool isPending = false,
    String? party,
  }) async {
    await _ensureLoaded();
    await _ensureOperationAllowed();
    _requireAdmin();
    if (amount <= 0) throw Exception('المبلغ يجب أن يكون أكبر من صفر');

    final status = isPending ? 'pending' : 'posted';

    final now = DateTime.now();
    final entryDate = _nextOpenDate(now);
    final txn = Txn(
      id: _nextTxnId++,
      kind: 'expense',
      status: status,
      entryDate: entryDate,
      amount: amount, // positive EGP
      clientFee: 0,
      networkFee: 0,
      mode: category, // category
      note: note,
      party: party?.trim().isEmpty ?? true ? null : party?.trim(),
      createdBy: _actorName(),
      createdRole: _actorRole(),
      createdAt: now,
    );

    final spec = _specFromTxn(txn);
    final txId = _txId(txn.id);

    _engine.createPending(txId: txId, spec: spec, payload: txn.toJson());
    if (status == 'posted') {
      // Drawer can go negative; approval should always pass.
      _engine.approve(txId: txId, spec: spec);
    }

    _txns.add(txn);
    await _save();
    await enqueueOutbox(
      entity: 'txn',
      entityId: txn.id.toString(),
      action: 'create',
      payload: txn.toJson(),
    );
    await appendAudit(
      type: 'expense_add',
      txnId: txn.id,
      amount: amount,
      note: note ?? category,
    );
    await _incrementOperationUsed();
    return txn.id;
  }

  // =====================
  // Fawry Services
  // =====================
  Future<int> addFawry({
    required String serviceName,
    String? reference,
    required double amount,
    required double fee,
    required String collectionMethod, // cash | credit
    String? party,
    String? note,
    bool isPending = false,
  }) async {
    await _ensureLoaded();
    await _ensureOperationAllowed();
    final svc = serviceName.trim();
    if (svc.isEmpty) throw Exception('اسم الخدمة مطلوب');
    if (amount <= 0) throw Exception('قيمة الخدمة يجب أن تكون أكبر من صفر');
    if (fee < 0) throw Exception('الربح/العمولة لا يمكن أن تكون سالبة');

    final method = collectionMethod.trim();
    if (method != 'cash' && method != 'credit') {
      throw Exception('طريقة التحصيل غير صحيحة');
    }

    final partyName = party?.trim();
    if (method == 'credit' && (partyName == null || partyName.isEmpty)) {
      throw Exception('اسم العميل مطلوب في الآجل');
    }

    final effectivePending = AppSession.isAdmin ? isPending : true;
    final status = effectivePending ? 'pending' : 'posted';
    final kind = method == 'cash' ? 'fawry_cash' : 'fawry_credit';

    final now = DateTime.now();
    final entryDate = _nextOpenDate(now);
    final txn = Txn(
      id: _nextTxnId++,
      kind: kind,
      status: status,
      entryDate: entryDate,
      amount: amount,
      clientFee: fee,
      networkFee: 0,
      mode: 'fawry',
      note: note?.trim().isEmpty ?? true ? null : note!.trim(),
      serviceName: svc,
      reference: reference?.trim().isEmpty ?? true ? null : reference!.trim(),
      party: partyName?.isEmpty ?? true ? null : partyName,
      createdBy: _actorName(),
      createdRole: _actorRole(),
      createdAt: now,
    );

    final spec = _specFromTxn(txn);
    final txId = _txId(txn.id);

    if (status == 'pending') {
      _engine.createPending(txId: txId, spec: spec, payload: txn.toJson());
    } else {
      _engine.createPending(txId: txId, spec: spec, payload: txn.toJson());
      _engine.approve(txId: txId, spec: spec);
    }

    _txns.add(txn);

    if (status == 'posted' && kind == 'fawry_credit') {
      final claim = _buildClaimFromFawry(txn, entryDate);
      _claims.add(claim);
    }

    await _save();
    await enqueueOutbox(
      entity: 'txn',
      entityId: txn.id.toString(),
      action: 'create',
      payload: txn.toJson(),
    );
    await appendAudit(
      type: 'fawry_add',
      txnId: txn.id,
      amount: amount,
      note: serviceName,
    );
    await _incrementOperationUsed();
    return txn.id;
  }

  Future<List<Txn>> listTxns({String? kind, String? status}) async {
    await _ensureLoaded();
    return _txns.where((t) {
      if (kind != null && t.kind != kind) return false;
      if (status != null && t.status != status) return false;
      return true;
    }).toList()..sort((a, b) => b.entryDate.compareTo(a.entryDate));
  }

  Future<void> confirmPending(int txnId) async {
    await _ensureLoaded();
    _requireAdmin();

    final idx = _txns.indexWhere((t) => t.id == txnId);
    if (idx < 0) throw Exception('العملية غير موجودة');
    final t = _txns[idx];
    if (t.status != 'pending') throw Exception('العملية ليست معلّقة');
    final now = DateTime.now();
    final effectiveDate = (_isDayClosed(now) || _isDayClosed(t.entryDate))
        ? _nextOpenDate(now)
        : t.entryDate;
    final pendingTxn = (effectiveDate == t.entryDate)
        ? t
        : t.copyWith(entryDate: effectiveDate);

    if (pendingTxn.kind == 'transfer' && pendingTxn.walletFromId != null) {
      final beforeUsage = _transferUsage(
        walletId: pendingTxn.walletFromId!,
        entryDate: pendingTxn.entryDate,
        excludeTxnId: pendingTxn.id,
      );
      _checkTransferLimits(
        walletId: pendingTxn.walletFromId!,
        amount: _transferBaseAmount(pendingTxn),
        entryDate: pendingTxn.entryDate,
        excludeTxnId: pendingTxn.id,
      );

      final w = _requireWallet(pendingTxn.walletFromId!);
      await _notifyLimitCross(
        wallet: w,
        beforeDaily: beforeUsage.daily,
        afterDaily: beforeUsage.daily + _transferBaseAmount(pendingTxn),
        beforeMonthly: beforeUsage.monthly,
        afterMonthly: beforeUsage.monthly + _transferBaseAmount(pendingTxn),
      );
      await _notifyLowBalanceIfNeeded(w);
    }

    final spec = _specFromTxn(pendingTxn);
    _engine.approve(txId: _txId(pendingTxn.id), spec: spec);

    if (pendingTxn.kind == 'fawry_credit') {
      final existing = _claims.indexWhere(
        (c) => c.sourceTxnId == pendingTxn.id,
      );
      if (existing == -1) {
        final claim = _buildClaimFromFawry(pendingTxn, pendingTxn.entryDate);
        _claims.add(claim);
      }
    }

    final posted = pendingTxn.copyWith(status: 'posted');
    _txns[idx] = posted;
    await _save();
    await enqueueOutbox(
      entity: 'txn',
      entityId: posted.id.toString(),
      action: 'update',
      payload: posted.toJson(),
    );
    await appendAudit(
      type: 'pending_confirm',
      txnId: posted.id,
      note: posted.kind,
    );
  }

  Future<void> cancelPending(int txnId) async {
    await _ensureLoaded();
    _requireAdmin();

    final idx = _txns.indexWhere((t) => t.id == txnId);
    if (idx < 0) throw Exception('العملية غير موجودة');
    final t = _txns[idx];
    if (t.status != 'pending') throw Exception('العملية ليست معلّقة');
    _ensureNotClosed(t.entryDate);

    _engine.reject(_txId(t.id));

    _txns[idx] = t.copyWith(status: 'canceled');
    await _save();
    await enqueueOutbox(
      entity: 'txn',
      entityId: t.id.toString(),
      action: 'update',
      payload: _txns[idx].toJson(),
    );
    await appendAudit(type: 'pending_cancel', txnId: t.id, note: t.kind);
  }

  Future<void> rollbackPosted(int txnId) async {
    await _ensureLoaded();
    _requireAdmin();

    final idx = _txns.indexWhere((t) => t.id == txnId);
    if (idx < 0) throw Exception('العملية غير موجودة');
    final t = _txns[idx];
    if (t.status != 'posted') {
      throw Exception('Rollback مسموح فقط للعمليات المعتمدة');
    }
    _ensureNotClosed(t.entryDate);

    if (t.kind != 'fawry_cash' && t.kind != 'fawry_credit') {
      throw Exception('Rollback متاح فقط لفوري');
    }

    if (t.kind == 'fawry_credit') {
      final cIdx = _claims.indexWhere((c) => c.sourceTxnId == t.id);
      if (cIdx < 0) {
        throw Exception('لم يتم العثور على مستحق لهذه العملية');
      }
      final claim = _claims[cIdx];
      if (claim.status == 'closed' && claim.settledTxnId != null) {
        throw Exception('لا يمكن Rollback بعد تحصيل المستحق');
      }
      if (claim.status == 'open') {
        _claims[cIdx] = claim.copyWith(
          status: 'closed',
          settledDate: DateTime.now(),
          settledTxnId: null,
        );
      }
    }

    _txns[idx] = t.copyWith(status: 'rolled_back');
    _rebuildEngineFromTxns();
    await _save();
    await enqueueOutbox(
      entity: 'txn',
      entityId: t.id.toString(),
      action: 'update',
      payload: _txns[idx].toJson(),
    );
    await appendAudit(type: 'txn_rollback', txnId: t.id, note: t.kind);
  }
}
