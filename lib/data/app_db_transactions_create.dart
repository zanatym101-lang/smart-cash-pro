part of 'app_db.dart';

extension AppDbTransactionsCreate on AppDb {
  Future<int> addExternalFunding({
    required int walletId,
    required double amount,
    String? note,
  }) async {
    await _ensureLoaded();
    await _ensureOperationAllowed();
    _requireTxnAdmin();
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
    _requireTxnAdmin();
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

    _engine.createPending(txId: txId, spec: spec, payload: txn.toJson());
    try {
      _engine.approve(txId: txId, spec: spec);
    } catch (e) {
      if (_isWalletNegativeException(e)) {
        throw Exception(
          '\u0644\u0627 \u064a\u0645\u0643\u0646 \u062a\u0646\u0641\u064a\u0630 \u0627\u0644\u062a\u062d\u0648\u064a\u0644: \u0627\u0644\u0631\u0635\u064a\u062f \u0627\u0644\u062d\u0627\u0644\u064a \u0644\u0644\u0645\u062d\u0641\u0638\u0629 \u0644\u0627 \u064a\u0643\u0641\u064a.',
        );
      }
      rethrow;
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
    _requireTxnAdmin();
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
    _requireTxnAdmin();
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

  Future<void> updateExpense({
    required int txnId,
    required double amount,
    required String category,
    String? note,
    String? party,
  }) async {
    await _ensureLoaded();
    await _ensureOperationAllowed();
    _requireTxnAdmin();
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
    _requireTxnAdmin();
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
}
