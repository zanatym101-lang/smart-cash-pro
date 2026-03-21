part of 'app_db.dart';

extension AppDbTransactions on AppDb {
  Wallet _requireWallet(int walletId) {
    final idx = _wallets.indexWhere((w) => w.id == walletId);
    if (idx == -1) {
      throw Exception('المحفظة غير موجودة.');
    }
    return _wallets[idx];
  }

  double _transferBaseAmount(Txn t) {
    if (t.mode == 'type2_v2') return t.amount + t.clientFee;
    return t.amount - t.networkFee;
  }

  bool _sameDay(DateTime a, DateTime b) => _dayKey(a) == _dayKey(b);

  bool _sameMonth(DateTime a, DateTime b) {
    final sa = _businessShift(a);
    final sb = _businessShift(b);
    return sa.year == sb.year && sa.month == sb.month;
  }

  String _dayKey(DateTime d) => _businessDateKeyFromDateTime(d);

  bool _isWalletNegativeException(Object e) {
    final m = e.toString().toLowerCase();
    return m.contains('would go negative') ||
        m.contains('will go negative') ||
        m.contains('negative wallet');
  }

  String _pendingSettlementTag(int txnId) => 'pending_txn:$txnId';

  int? _extractPendingSettlementRef(String? note) {
    if (note == null || note.trim().isEmpty) return null;
    final m = RegExp(r'pending_txn:(\d+)').firstMatch(note);
    if (m == null) return null;
    return int.tryParse(m.group(1) ?? '');
  }

  double _pendingSettledAmount(int txnId) {
    double sum = 0;
    for (final t in _txns) {
      if (t.status != 'posted') continue;
      if (t.kind != 'claim_collect' && t.kind != 'claim_pay') continue;
      final ref = _extractPendingSettlementRef(t.note);
      if (ref == null || ref != txnId) continue;
      sum += t.amount;
    }
    return sum;
  }

  double _pendingTransferDueForTxn(Txn t) {
    if (t.mode == 'type2_v2') return t.amount + t.clientFee;
    final base = t.amount - t.networkFee;
    if (t.mode == 'type1') return base + t.clientFee;
    return base;
  }

  double _pendingReceiveDueForTxn(Txn t) {
    if (t.mode == 'cash') return t.amount;
    if (t.mode == 'deduct') {
      return (t.amount - t.clientFee).clamp(0, 1e18).toDouble();
    }
    return 0;
  }

  void _requireAdmin() {
    if (!AppSession.isAdmin) {
      throw Exception('هذه العملية متاحة للأدمن فقط.');
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
      throw Exception(
        'لا يمكن تعديل عملية في يوم مغلق. ألغِ إغلاق اليوم أولًا إذا لزم.',
      );
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
      if (_txnKind(t) != 'transfer') continue;
      if (t.walletFromId != walletId) continue;
      if (excludeTxnId != null && t.id == excludeTxnId) continue;
      if (!_hasStatus(t, 'posted') && !_hasStatus(t, 'pending')) continue;

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
          title: 'تنبيه حدود التحويل',
          body:
              '${wallet.name}: تم الوصول إلى $label بنسبة ${(threshold * 100).toInt()}% من الحد المسموح.',
        );
      }
    }

    await check(beforeDaily, afterDaily, wallet.dailyLimit, 0.8, 'الحد اليومي');
    await check(beforeDaily, afterDaily, wallet.dailyLimit, 0.9, 'الحد اليومي');
    await check(
      beforeMonthly,
      afterMonthly,
      wallet.monthlyLimit,
      0.8,
      'الحد الشهري',
    );
    await check(
      beforeMonthly,
      afterMonthly,
      wallet.monthlyLimit,
      0.9,
      'الحد الشهري',
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
          '${wallet.name}: الرصيد الحالي ${balance.toStringAsFixed(2)} أقل من حد التنبيه ${threshold.toStringAsFixed(2)}.',
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
        title: 'تجاوز الحد اليومي للتحويل',
        body:
            '${w.name}: العملية تتجاوز الحد اليومي (${dailyLimit.toStringAsFixed(2)}).',
      );
      throw Exception(
        'لا يمكن تنفيذ العملية: سيتجاوز إجمالي التحويل الحد اليومي (${dailyLimit.toStringAsFixed(2)}).',
      );
    }

    if (monthlyLimit > 0 && (monthlySum + amount) > monthlyLimit) {
      NotificationService.show(
        title: 'تجاوز الحد الشهري للتحويل',
        body:
            '${w.name}: العملية تتجاوز الحد الشهري (${monthlyLimit.toStringAsFixed(2)}).',
      );
      throw Exception(
        'لا يمكن تنفيذ العملية: سيتجاوز إجمالي التحويل الحد الشهري (${monthlyLimit.toStringAsFixed(2)}).',
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
    _requireWallet(walletId);
    if (amount <= 0) {
      throw Exception('Amount must be greater than zero.');
    }
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
    if (amount == 0) {
      throw Exception('Drawer amount cannot be zero.');
    }
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
    if (clientFee < 0 || networkFee < 0) {
      throw Exception('Fees cannot be negative');
    }
    if (transferType == 'type2' && amount <= (clientFee + networkFee)) {
      throw Exception('For type2: amount must be greater than CF + NF');
    }
    _requireWallet(walletId);
    if (amount <= 0) {
      throw Exception('Amount must be greater than zero.');
    }
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
    final storedMode = transferType == 'type2' ? 'type2_v2' : transferType;

    // Stored amount = wallet spend.
    final walletSpend = transferType == 'type2'
        ? (amount - clientFee)
        : (amount + networkFee);

    final txn = Txn(
      id: _nextTxnId++,
      kind: 'transfer',
      status: status,
      entryDate: entryDate,
      walletFromId: walletId,
      amount: walletSpend,
      clientFee: clientFee,
      networkFee: networkFee,
      mode: storedMode,
      note: note,
      party: party?.trim().isEmpty ?? true ? null : party?.trim(),
      createdBy: _actorName(),
      createdRole: _actorRole(),
      createdAt: now,
    );

    final spec = _specFromTxn(txn);
    final txId = _txId(txn.id);
    _validateProjectedWalletsNonNegative(txn);

    var savedTxn = txn;

    if (status == 'pending') {
      _engine.createPending(txId: txId, spec: spec, payload: txn.toJson());
    } else {
      // Validate + apply now (wallet cannot go negative)
      _engine.createPending(txId: txId, spec: spec, payload: txn.toJson());
      try {
        _engine.approve(txId: txId, spec: spec);
      } catch (e) {
        if (_isWalletNegativeException(e)) {
          final approvedQ = _state.getWalletQirsh(walletId.toString());
          final projected = _projectedBalances();
          final availableQ = projected.walletsQirsh[walletId.toString()] ?? 0;
          final neededQ = Money.fromEgpDouble(walletSpend);
          if (availableQ >= neededQ && approvedQ < neededQ) {
            // Keep it pending when approved balance is not enough,
            // while preserving available-balance usability.
            savedTxn = txn.copyWith(status: 'pending');
          } else {
            throw Exception(
              '\u0644\u0627 \u064a\u0645\u0643\u0646 \u062a\u0646\u0641\u064a\u0630 \u0627\u0644\u062a\u062d\u0648\u064a\u0644: \u0627\u0644\u0631\u0635\u064a\u062f \u0627\u0644\u062d\u0627\u0644\u064a \u0644\u0644\u0645\u062d\u0641\u0638\u0629 \u0644\u0627 \u064a\u0643\u0641\u064a.',
            );
          }
        } else {
          rethrow;
        }
      }
    }

    _txns.add(savedTxn);
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
    if (savedTxn.status == 'posted') {
      await _notifyLowBalanceIfNeeded(w);
    }
    await _save();
    await enqueueOutbox(
      entity: 'txn',
      entityId: savedTxn.id.toString(),
      action: 'create',
      payload: savedTxn.toJson(),
    );
    await appendAudit(
      type: 'transfer_add',
      txnId: savedTxn.id,
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
    _requireWallet(walletId);
    if (amount <= 0) {
      throw Exception('Amount must be greater than zero.');
    }
    if (commission < 0) {
      throw Exception('Commission cannot be negative.');
    }

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
    if (amount <= 0) {
      throw Exception('Amount must be greater than zero.');
    }

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
    if (svc.isEmpty) {
      throw Exception('اسم خدمة فوري مطلوب.');
    }
    if (amount <= 0) {
      throw Exception('المبلغ يجب أن يكون أكبر من صفر.');
    }
    if (fee < 0) {
      throw Exception('الربح/العمولة لا يمكن أن يكون سالبًا.');
    }

    final method = collectionMethod.trim();
    if (method != 'cash' && method != 'credit') {
      throw Exception('طريقة التحصيل غير صالحة (cash أو credit).');
    }

    final partyName = party?.trim();
    if (method == 'credit' && (partyName == null || partyName.isEmpty)) {
      throw Exception('اسم العميل مطلوب في فوري الآجل.');
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

  Future<int> addFawryFundingFromDrawer({
    required double amount,
    String? note,
  }) async {
    await _ensureLoaded();
    await _ensureOperationAllowed();
    _requireAdmin();
    if (amount <= 0) {
      throw Exception('Amount must be greater than zero.');
    }

    final now = DateTime.now();
    final entryDate = _nextOpenDate(now);
    final txn = Txn(
      id: _nextTxnId++,
      kind: 'fawry_fund_drawer',
      status: 'posted',
      entryDate: entryDate,
      amount: amount,
      clientFee: 0,
      networkFee: 0,
      mode: 'fawry_fund_drawer',
      note: note?.trim().isEmpty ?? true ? null : note!.trim(),
      createdBy: _actorName(),
      createdRole: _actorRole(),
      createdAt: now,
    );

    final spec = _specFromTxn(txn);
    final txId = _txId(txn.id);
    _engine.createPending(txId: txId, spec: spec, payload: txn.toJson());
    _engine.approve(txId: txId, spec: spec);

    _txns.add(txn);
    await _save();
    await enqueueOutbox(
      entity: 'txn',
      entityId: txn.id.toString(),
      action: 'create',
      payload: txn.toJson(),
    );
    await appendAudit(
      type: 'fawry_fund_drawer',
      txnId: txn.id,
      amount: amount,
      note: note,
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

  Future<int> addPendingSettlementForTxn({
    required int pendingTxnId,
    required double amount,
  }) async {
    await _ensureLoaded();
    await _ensureOperationAllowed();
    _requireAdmin();

    final idx = _txns.indexWhere((t) => t.id == pendingTxnId);
    if (idx < 0) throw Exception('المعاملة غير موجودة.');
    final src = _txns[idx];
    if (src.status != 'pending') {
      throw Exception('لا يمكن التحصيل من عملية غير معلّقة.');
    }

    if (amount <= 0) {
      throw Exception('المبلغ يجب أن يكون أكبر من صفر.');
    }

    final due = src.kind == 'transfer'
        ? _pendingTransferDueForTxn(src)
        : src.kind == 'receive'
            ? _pendingReceiveDueForTxn(src)
            : src.kind == 'fawry_credit'
                ? (src.amount + src.clientFee)
                : 0;
    if (due <= 0) {
      throw Exception('لا يوجد مبلغ مستحق لهذه العملية.');
    }

    final settledBefore = _pendingSettledAmount(pendingTxnId);
    final remainingBefore = (due - settledBefore).clamp(0, 1e18).toDouble();
    if (amount > remainingBefore) {
      throw Exception('المبلغ أكبر من المتبقي.');
    }
    final remainingAfter = (remainingBefore - amount).clamp(0, 1e18).toDouble();

    final isReceivable =
        src.kind == 'transfer' || src.kind == 'fawry_credit';
    final kind = isReceivable ? 'claim_collect' : 'claim_pay';
    final actionLabel = isReceivable ? 'تحصيل مستحق (معلّق)' : 'سداد مستحق (معلّق)';
    final typeLabel = src.kind == 'transfer'
        ? 'تحويل معلّق'
        : src.kind == 'receive'
            ? 'استلام معلّق'
            : 'فوري آجل معلّق';

    final note =
        '$actionLabel - نوع العملية: $typeLabel - المتبقي بعد التحصيل: ${remainingAfter.toStringAsFixed(2)} - ${_pendingSettlementTag(pendingTxnId)}';

    final now = DateTime.now();
    final entryDate = _nextOpenDate(now);
    final txn = Txn(
      id: _nextTxnId++,
      kind: kind,
      status: 'posted',
      entryDate: entryDate,
      amount: amount,
      clientFee: 0,
      networkFee: 0,
      mode: 'pending_settlement',
      note: note,
      createdBy: _actorName(),
      createdRole: _actorRole(),
      createdAt: now,
    );

    final spec = _specFromTxn(txn);
    final txId = _txId(txn.id);
    _engine.createPending(txId: txId, spec: spec, payload: txn.toJson());
    _engine.approve(txId: txId, spec: spec);

    _txns.add(txn);
    await _save();
    await enqueueOutbox(
      entity: 'txn',
      entityId: txn.id.toString(),
      action: 'create',
      payload: txn.toJson(),
    );
    await appendAudit(
      type: 'pending_settlement',
      txnId: txn.id,
      amount: amount,
      note: 'pending:$pendingTxnId',
    );
    await _incrementOperationUsed();
    return txn.id;
  }

  Future<void> updateExpense({
    required int txnId,
    required double amount,
    required String category,
    String? note,
    String? party,
  }) async {
    await _ensureLoaded();
    await _ensureOperationAllowed();
    _requireAdmin();
    if (amount <= 0) {
      throw Exception('Amount must be greater than zero.');
    }
    final idx = _txns.indexWhere((t) => t.id == txnId);
    if (idx < 0) {
      throw Exception('Expense not found.');
    }
    final existing = _txns[idx];
    if (existing.kind != 'expense') {
      throw Exception('Only expense transactions can be edited.');
    }

    final updated = existing.copyWith(
      amount: amount,
      mode: category,
      note: note?.trim().isEmpty ?? true ? null : note!.trim(),
      party: party?.trim().isEmpty ?? true ? null : party!.trim(),
    );

    _txns[idx] = updated;
    _rebuildEngineFromTxns();
    await _save();
    await enqueueOutbox(
      entity: 'txn',
      entityId: updated.id.toString(),
      action: 'update',
      payload: updated.toJson(),
    );
    await appendAudit(
      type: 'expense_update',
      txnId: updated.id,
      amount: amount,
      note: note ?? category,
    );
  }

  Future<void> deleteExpense(int txnId) async {
    await _ensureLoaded();
    await _ensureOperationAllowed();
    _requireAdmin();
    final idx = _txns.indexWhere((t) => t.id == txnId);
    if (idx < 0) {
      throw Exception('Expense not found.');
    }
    final existing = _txns[idx];
    if (existing.kind != 'expense') {
      throw Exception('Only expense transactions can be deleted.');
    }
    _txns.removeAt(idx);
    _rebuildEngineFromTxns();
    await _save();
    await enqueueOutbox(
      entity: 'txn',
      entityId: existing.id.toString(),
      action: 'delete',
      payload: existing.toJson(),
    );
    await appendAudit(
      type: 'expense_delete',
      txnId: existing.id,
      amount: existing.amount,
      note: existing.note ?? existing.mode,
    );
  }

  Future<void> confirmPending(int txnId) async {
    await _ensureLoaded();
    _requireAdmin();

    final idx = _txns.indexWhere((t) => t.id == txnId);
    if (idx < 0) {
      throw Exception('المعاملة غير موجودة.');
    }
    final t = _txns[idx];
    if (t.status != 'pending') {
      throw Exception('لا يمكن تنفيذ هذه العملية لأنها ليست معلقة.');
    }
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

    final settled = _pendingSettledAmount(pendingTxn.id);
    if (settled > 0 &&
        (pendingTxn.kind == 'transfer' || pendingTxn.kind == 'receive')) {
      final adjustAmount =
          pendingTxn.kind == 'receive' ? settled : -settled;
      final nowAdjust = DateTime.now();
      final adjustTxn = Txn(
        id: _nextTxnId++,
        kind: 'pending_settlement_adjust',
        status: 'posted',
        entryDate: pendingTxn.entryDate,
        amount: adjustAmount,
        clientFee: 0,
        networkFee: 0,
        mode: 'pending_settlement_adjust',
        note: 'تسوية تحصيل معلّق: Txn#${pendingTxn.id}',
        createdBy: _actorName(),
        createdRole: 'system',
        createdAt: nowAdjust,
      );
      final adjSpec = _specFromTxn(adjustTxn);
      final adjId = _txId(adjustTxn.id);
      _engine.createPending(txId: adjId, spec: adjSpec, payload: adjustTxn.toJson());
      _engine.approve(txId: adjId, spec: adjSpec);
      _txns.add(adjustTxn);
      await enqueueOutbox(
        entity: 'txn',
        entityId: adjustTxn.id.toString(),
        action: 'create',
        payload: adjustTxn.toJson(),
      );
      await appendAudit(
        type: 'pending_settlement_adjust',
        txnId: adjustTxn.id,
        amount: adjustAmount,
        note: 'pending:${pendingTxn.id}',
      );
    }

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
    if (idx < 0) {
      throw Exception('المعاملة غير موجودة.');
    }
    final t = _txns[idx];
    if (t.status != 'pending') {
      throw Exception('لا يمكن إلغاء هذه العملية لأنها ليست معلقة.');
    }
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

  Future<void> rollbackPendingSettlement(int txnId) async {
    await _ensureLoaded();
    _requireAdmin();

    final idx = _txns.indexWhere((t) => t.id == txnId);
    if (idx < 0) {
      throw Exception('المعاملة غير موجودة.');
    }
    final t = _txns[idx];
    if (t.status != 'posted') {
      throw Exception('لا يمكن حذف/تعديل هذه العملية لأنها ليست منفذة.');
    }
    if (t.kind != 'claim_collect' && t.kind != 'claim_pay') {
      throw Exception('العملية ليست تحصيل/سداد.');
    }
    final pendingId = _extractPendingSettlementRef(t.note);
    if (pendingId == null) {
      throw Exception('هذه العملية ليست تسوية لمعاملة معلّقة.');
    }
    _ensureNotClosed(t.entryDate);

    final pendingIdx = _txns.indexWhere((x) => x.id == pendingId);
    if (pendingIdx < 0) {
      throw Exception('المعاملة المعلّقة المرتبطة غير موجودة.');
    }
    final pendingTxn = _txns[pendingIdx];
    if (pendingTxn.status != 'pending') {
      throw Exception('لا يمكن تعديل تسوية لمعاملة تم اعتمادها/إلغاؤها.');
    }

    final settlements = _txns
        .where((s) =>
            s.status == 'posted' &&
            (s.kind == 'claim_collect' || s.kind == 'claim_pay') &&
            _extractPendingSettlementRef(s.note) == pendingId)
        .toList()
      ..sort((a, b) {
        final c = a.entryDate.compareTo(b.entryDate);
        if (c != 0) return c;
        return a.id.compareTo(b.id);
      });
    if (settlements.isNotEmpty && settlements.last.id != t.id) {
      throw Exception('لا يمكن تعديل تسوية ليست الأحدث للمعلّق.');
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
    await appendAudit(
      type: 'pending_settlement_rollback',
      txnId: t.id,
      note: 'pending:$pendingId',
    );
  }

  Future<void> rollbackPosted(int txnId) async {
    await _ensureLoaded();
    _requireAdmin();

    final idx = _txns.indexWhere((t) => t.id == txnId);
    if (idx < 0) {
      throw Exception('المعاملة غير موجودة.');
    }
    final t = _txns[idx];
    if (t.status != 'posted') {
      throw Exception('Rollback متاح للعمليات المنفذة فقط.');
    }
    _ensureNotClosed(t.entryDate);

    if (t.kind != 'fawry_cash' &&
        t.kind != 'fawry_credit' &&
        t.kind != 'transfer' &&
        t.kind != 'receive') {
      throw Exception('Rollback مدعوم فقط لخدمات فوري.');
    }

    if (t.kind == 'transfer' || t.kind == 'receive') {
      final linkedClaims = _claims.where((c) => c.sourceTxnId == t.id).toList();
      if (linkedClaims.isNotEmpty) {
        throw Exception(
          'لا يمكن عمل Rollback لعملية مرتبطة بمطالبات. قم بإغلاق/تسوية المطالبة أولًا.',
        );
      }
    }

    if (t.kind == 'fawry_credit') {
      final cIdx = _claims.indexWhere((c) => c.sourceTxnId == t.id);
      if (cIdx < 0) {
        throw Exception('تعذر إيجاد مطالبة فوري الآجل المرتبطة بالمعاملة.');
      }
      final claim = _claims[cIdx];
      final totalDueQ = Money.fromEgpDouble(t.amount + t.clientFee);
      final remainingQ = Money.fromEgpDouble(claim.amount);
      final collectedAny = remainingQ < totalDueQ;
      if (collectedAny ||
          (claim.status == 'closed' && claim.settledTxnId != null)) {
        throw Exception(
          'لا يمكن عمل Rollback لأن مطالبة فوري الآجل تم تحصيلها كليًا أو جزئيًا.',
        );
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
