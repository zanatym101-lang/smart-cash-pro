part of 'app_db.dart';

extension AppDbTransactionsCancel on AppDb {
  Future<void> cancelPending(int txnId) async {
    await _ensureLoaded();
    _requireTxnAdmin();

    final idx = _txns.indexWhere((t) => t.id == txnId);
    if (idx < 0) {
      throw Exception('المعاملة غير موجودة.');
    }
    final t = _txns[idx];
    if (t.status != 'pending') {
      throw Exception('لا يمكن إلغاء هذه العملية لأنها ليست معلقة.');
    }
    _ensureNotClosed(t.entryDate);

    if (_walletPendingAffectsBalance(t)) {
      _txns[idx] = t.copyWith(status: 'canceled');
      _rebuildEngineFromTxns();
    } else {
      _engine.reject(_txId(t.id));
      _txns[idx] = t.copyWith(status: 'canceled');
    }
    await _save();
    await enqueueOutbox(
      entity: 'txn',
      entityId: t.id.toString(),
      action: 'update',
      payload: _txns[idx].toJson(),
    );
    await appendAudit(type: 'pending_cancel', txnId: t.id, note: t.kind);
  }
}
