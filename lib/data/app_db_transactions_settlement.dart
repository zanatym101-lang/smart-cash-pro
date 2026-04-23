part of 'app_db.dart';

extension AppDbTransactionsSettlement on AppDb {
  Future<int> addPendingSettlementForTxn({
    required int pendingTxnId,
    required double amount,
    String? note,
  }) async {
    await _ensureLoaded();
    await _ensureOperationAllowed();
    _requireTxnAdmin();

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

    final isReceivable = src.kind == 'transfer' || src.kind == 'fawry_credit';
    final kind = isReceivable ? 'claim_collect' : 'claim_pay';
    final actionLabel = isReceivable
        ? 'تحصيل مستحق (معلّق)'
        : 'سداد مستحق (معلّق)';
    final typeLabel = src.kind == 'transfer'
        ? 'تحويل معلّق'
        : src.kind == 'receive'
        ? 'استلام معلّق'
        : 'فوري آجل معلّق';

    final settlementNote = note?.trim();
    final noteText =
        '$actionLabel - نوع العملية: $typeLabel - المتبقي بعد التحصيل: ${remainingAfter.toStringAsFixed(2)}'
        '${settlementNote == null || settlementNote.isEmpty ? '' : ' - settlement_note:$settlementNote'}'
        ' - ${_pendingSettlementTag(pendingTxnId)}';

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
      note: noteText,
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

  Future<void> rollbackPendingSettlement(int txnId) async {
    await _ensureLoaded();
    _requireTxnAdmin();

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

    final settlements =
        _txns
            .where(
              (s) =>
                  s.status == 'posted' &&
                  (s.kind == 'claim_collect' || s.kind == 'claim_pay') &&
                  _extractPendingSettlementRef(s.note) == pendingId,
            )
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
}
