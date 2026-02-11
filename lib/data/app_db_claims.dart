part of 'app_db.dart';

extension AppDbClaims on AppDb {
  // ==========================
  // Claims (Receivables/Payables)
  // ==========================
  Claim _buildClaimFromFawry(Txn txn, DateTime entryDate) {
    final party = (txn.party ?? '').trim();
    if (party.isEmpty) {
      throw Exception('اسم العميل مطلوب للمستحقات');
    }

    final parts = <String>[];
    if (txn.serviceName != null && txn.serviceName!.trim().isNotEmpty) {
      parts.add('خدمة: ${txn.serviceName}');
    }
    if (txn.reference != null && txn.reference!.trim().isNotEmpty) {
      parts.add('رقم: ${txn.reference}');
    }
    if (txn.note != null && txn.note!.trim().isNotEmpty) {
      parts.add(txn.note!.trim());
    }

    final note = parts.isEmpty ? null : parts.join(' - ');

    return Claim(
      id: _nextClaimId++,
      type: 'receivable',
      party: party,
      amount: txn.amount + txn.clientFee,
      note: note,
      entryDate: entryDate,
      status: 'open',
      sourceTxnId: txn.id,
    );
  }

  Future<int> addClaim({
    required String type, // receivable | payable
    required String party,
    required double amount,
    String? note,
    DateTime? entryDate,
    int? sourceTxnId,
  }) async {
    await _ensureLoaded();
    await _ensureOperationAllowed();
    if (!AppSession.isAdmin) {
      throw Exception('هذا الإجراء متاح للأدمن فقط');
    }
    final t = type.trim();
    if (t != 'receivable' && t != 'payable') {
      throw Exception('نوع المستحق غير صحيح');
    }
    final p = party.trim();
    if (p.isEmpty) throw Exception('اسم الطرف مطلوب');
    if (amount <= 0) throw Exception('المبلغ يجب أن يكون أكبر من صفر');

    final claim = Claim(
      id: _nextClaimId++,
      type: t,
      party: p,
      amount: amount,
      note: note,
      entryDate: entryDate ?? DateTime.now(),
      status: 'open',
      sourceTxnId: sourceTxnId,
    );

    _claims.add(claim);
    await _save();
    await enqueueOutbox(
      entity: 'claim',
      entityId: claim.id.toString(),
      action: 'create',
      payload: claim.toJson(),
    );
    await appendAudit(
      type: 'claim_add',
      claimId: claim.id,
      amount: amount,
      note: '${claim.type}:${claim.party}',
    );
    await _incrementOperationUsed();
    return claim.id;
  }

  Future<List<Claim>> listClaims({String? type, String? status}) async {
    await _ensureLoaded();
    return _claims.where((c) {
      if (type != null && c.type != type) return false;
      if (status != null && c.status != status) return false;
      return true;
    }).toList()
      ..sort((a, b) => b.entryDate.compareTo(a.entryDate));
  }

  Future<int> settleClaim({required int claimId}) async {
    await _ensureLoaded();
    await _ensureOperationAllowed();
    if (!AppSession.isAdmin) {
      throw Exception('هذا الإجراء متاح للأدمن فقط');
    }
    final idx = _claims.indexWhere((c) => c.id == claimId);
    if (idx < 0) throw Exception('المستحق غير موجود');

    final claim = _claims[idx];
    if (claim.status != 'open') throw Exception('المستحق مغلق بالفعل');

    final isReceivable = claim.type == 'receivable';
    final now = DateTime.now();
    final entryDate = _nextOpenDate(now);

    final base = isReceivable
        ? 'تحصيل مستحقات من ${claim.party}'
        : 'سداد مستحقات إلى ${claim.party}';
    final noteParts = <String>[base];
    if (claim.note != null && claim.note!.trim().isNotEmpty) {
      noteParts.add(claim.note!.trim());
    }

    final txn = Txn(
      id: _nextTxnId++,
      kind: isReceivable ? 'claim_collect' : 'claim_pay',
      status: 'posted',
      entryDate: entryDate,
      amount: claim.amount,
      clientFee: 0,
      networkFee: 0,
      mode: claim.type,
      note: noteParts.join(' - '),
      createdBy: _actorName(),
      createdRole: _actorRole(),
      createdAt: now,
    );

    final spec = _specFromTxn(txn);
    final txId = _txId(txn.id);
    _engine.createPending(txId: txId, spec: spec, payload: txn.toJson());
    _engine.approve(txId: txId, spec: spec);

    _txns.add(txn);
    _claims[idx] = claim.copyWith(
      status: 'closed',
      settledTxnId: txn.id,
      settledDate: now,
    );

    await _save();
    await enqueueOutbox(
      entity: 'claim',
      entityId: claim.id.toString(),
      action: 'update',
      payload: _claims[idx].toJson(),
    );
    await enqueueOutbox(
      entity: 'txn',
      entityId: txn.id.toString(),
      action: 'create',
      payload: txn.toJson(),
    );
    await appendAudit(
      type: 'claim_settle',
      txnId: txn.id,
      claimId: claim.id,
      amount: claim.amount,
      note: '${claim.type}:${claim.party}',
    );
    await _incrementOperationUsed();
    return txn.id;
  }
}
