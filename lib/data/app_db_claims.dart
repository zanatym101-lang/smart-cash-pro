part of 'app_db.dart';

extension AppDbClaims on AppDb {
  String _normalizePhoneClaim(String input) {
    final buf = StringBuffer();
    for (final r in input.runes) {
      final ch = String.fromCharCode(r);
      final code = ch.codeUnitAt(0);
      if (code >= 48 && code <= 57) {
        buf.write(ch);
      }
    }
    return buf.toString();
  }

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
    String? phone,
    DateTime? entryDate,
    int? sourceTxnId,
    bool applyDrawerEffect = true,
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

    final now = DateTime.now();
    final effectiveDate = entryDate ?? _nextOpenDate(now);
    final normalizedPhone = _normalizePhoneClaim(phone ?? '');
    final noteParts = <String>[];
    final n = note?.trim() ?? '';
    if (n.isNotEmpty) {
      noteParts.add(n);
    }
    if (normalizedPhone.isNotEmpty) {
      noteParts.add('رقم الطرف: $normalizedPhone');
    }
    final finalNote = noteParts.isEmpty ? null : noteParts.join(' - ');

    final claim = Claim(
      id: _nextClaimId++,
      type: t,
      party: p,
      amount: amount,
      note: finalNote,
      entryDate: effectiveDate,
      status: 'open',
      sourceTxnId: sourceTxnId,
    );

    _claims.add(claim);

    Txn? openTxn;
    if (applyDrawerEffect) {
      openTxn = Txn(
        id: _nextTxnId++,
        kind: t == 'receivable'
            ? 'claim_open_receivable'
            : 'claim_open_payable',
        status: 'posted',
        entryDate: effectiveDate,
        amount: amount,
        clientFee: 0,
        networkFee: 0,
        mode: t,
        note:
            'فتح مستحق ${t == 'receivable' ? 'لنا' : 'علينا'} - $p${finalNote == null ? '' : ' - $finalNote'}',
        createdBy: _actorName(),
        createdRole: _actorRole(),
        createdAt: now,
      );
      final spec = _specFromTxn(openTxn);
      final txId = _txId(openTxn.id);
      _engine.createPending(txId: txId, spec: spec, payload: openTxn.toJson());
      _engine.approve(txId: txId, spec: spec);
      _txns.add(openTxn);
    }

    await _save();
    await enqueueOutbox(
      entity: 'claim',
      entityId: claim.id.toString(),
      action: 'create',
      payload: claim.toJson(),
    );
    if (openTxn != null) {
      await enqueueOutbox(
        entity: 'txn',
        entityId: openTxn.id.toString(),
        action: 'create',
        payload: openTxn.toJson(),
      );
      await appendAudit(
        type: 'claim_open_post',
        txnId: openTxn.id,
        claimId: claim.id,
        amount: amount,
        note: '${claim.type}:${claim.party}',
      );
    }
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
    }).toList()..sort((a, b) => b.entryDate.compareTo(a.entryDate));
  }

  Future<int> settleClaim({
    required int claimId,
    required double amount,
  }) async {
    await _ensureLoaded();
    await _ensureOperationAllowed();
    if (!AppSession.isAdmin) {
      throw Exception('هذا الإجراء متاح للأدمن فقط');
    }
    final idx = _claims.indexWhere((c) => c.id == claimId);
    if (idx < 0) throw Exception('المستحق غير موجود');

    final claim = _claims[idx];
    if (claim.status != 'open') throw Exception('المستحق مغلق بالفعل');

    final claimAmountQ = Money.fromEgpDouble(claim.amount);
    final settleAmountQ = Money.fromEgpDouble(amount);
    if (settleAmountQ <= 0) {
      throw Exception('مبلغ التحصيل/السداد يجب أن يكون أكبر من صفر');
    }
    if (settleAmountQ > claimAmountQ) {
      throw Exception('المبلغ أكبر من المتبقي في المستحق');
    }
    final remainingQ = claimAmountQ - settleAmountQ;
    final settleAmount = Money.toEgpDouble(settleAmountQ);
    final remainingAmount = Money.toEgpDouble(remainingQ);

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
      amount: settleAmount,
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
    if (remainingQ == 0) {
      _claims[idx] = claim.copyWith(
        status: 'closed',
        settledTxnId: txn.id,
        settledDate: now,
      );
    } else {
      _claims[idx] = claim.copyWith(amount: remainingAmount);
    }

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
      type: remainingQ == 0 ? 'claim_settle' : 'claim_settle_partial',
      txnId: txn.id,
      claimId: claim.id,
      amount: settleAmount,
      note: '${claim.type}:${claim.party}',
    );
    await _incrementOperationUsed();
    return txn.id;
  }
}
