part of 'app_db.dart';

extension AppDbTransactionsApprove on AppDb {
  Future<void> confirmPending(int txnId) async {
    await _ensureLoaded();
    _requireTxnAdmin();

    if (_confirmingPendingTxnIds.contains(txnId)) {
      throw Exception('هذه العملية قيد الاعتماد بالفعل.');
    }
    _confirmingPendingTxnIds.add(txnId);

    try {
      final outboxItems = <PendingOutboxInsert>[];
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
      final appliedOnCreate = _walletPendingAffectsBalance(t);
      final pendingTxn = (appliedOnCreate || effectiveDate == t.entryDate)
          ? t
          : t.copyWith(entryDate: effectiveDate);

      if (!appliedOnCreate &&
          pendingTxn.kind == 'transfer' &&
          pendingTxn.walletFromId != null) {
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

      if (!appliedOnCreate) {
        final spec = _specFromTxn(pendingTxn);
        _engine.approve(txId: _txId(pendingTxn.id), spec: spec);
      }

      final settled = _pendingSettledAmount(pendingTxn.id);
      if (!appliedOnCreate &&
          settled > 0 &&
          (pendingTxn.kind == 'transfer' || pendingTxn.kind == 'receive')) {
        final adjustAmount = pendingTxn.kind == 'receive' ? settled : -settled;
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
        _engine.createPending(
          txId: adjId,
          spec: adjSpec,
          payload: adjustTxn.toJson(),
        );
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

      if (pendingTxn.kind == 'transfer' || pendingTxn.kind == 'receive') {
        final due = pendingTxn.kind == 'transfer'
            ? _pendingTransferDueForTxn(pendingTxn)
            : _pendingReceiveDueForTxn(pendingTxn);
        final remaining = (due - settled).clamp(0, 1e18).toDouble();
        final existing = _claims.indexWhere(
          (c) => c.sourceTxnId == pendingTxn.id,
        );
        if (remaining > 0) {
          final party = (pendingTxn.party ?? '').trim().isNotEmpty
              ? pendingTxn.party!.trim()
              : 'آجل ${pendingTxn.kind == 'transfer' ? 'تحويل' : 'استلام'} #${pendingTxn.id}';
          if (existing == -1) {
            final claim = Claim(
              id: _nextClaimId++,
              type: pendingTxn.kind == 'transfer' ? 'receivable' : 'payable',
              party: party,
              amount: remaining,
              note: pendingTxn.note,
              entryDate: pendingTxn.entryDate,
              status: 'open',
              sourceTxnId: pendingTxn.id,
            );
            _claims.add(claim);
            outboxItems.add(
              _outboxInsert(
                entity: 'claim',
                entityId: claim.id.toString(),
                action: 'create',
                payload: claim.toJson(),
              ),
            );
          } else if (_claims[existing].status == 'open') {
            _claims[existing] = _claims[existing].copyWith(
              amount: remaining,
              entryDate: pendingTxn.entryDate,
            );
            outboxItems.add(
              _outboxInsert(
                entity: 'claim',
                entityId: _claims[existing].id.toString(),
                action: 'update',
                payload: _claims[existing].toJson(),
              ),
            );
          }
        } else if (existing != -1 && _claims[existing].status == 'open') {
          _claims[existing] = _claims[existing].copyWith(
            status: 'closed',
            settledDate: now,
          );
          outboxItems.add(
            _outboxInsert(
              entity: 'claim',
              entityId: _claims[existing].id.toString(),
              action: 'update',
              payload: _claims[existing].toJson(),
            ),
          );
        }
      }

      final posted = pendingTxn.copyWith(status: 'posted');
      _txns[idx] = posted;
      outboxItems.add(
        _outboxInsert(
          entity: 'txn',
          entityId: posted.id.toString(),
          action: 'update',
          payload: posted.toJson(),
        ),
      );
      await _save(outboxItems: outboxItems);
      await appendAudit(
        type: 'pending_confirm',
        txnId: posted.id,
        amount: posted.amount,
        dateKey: _dayKey(posted.entryDate),
        note: '${posted.kind}|created_at:${posted.createdAt.toIso8601String()}',
      );
    } finally {
      _confirmingPendingTxnIds.remove(txnId);
    }
  }

  Future<String?> getTxnApprovedBy(int txnId) async {
    await _ensureLoaded();
    final audit = await listAudit(limit: 1000);
    for (final entry in audit) {
      if ((entry['type'] ?? '').toString() != 'pending_confirm') continue;
      final entryTxnId = (entry['txnId'] as num?)?.toInt();
      if (entryTxnId != txnId) continue;
      final by = entry['by']?.toString().trim();
      if (by != null && by.isNotEmpty) return by;
      final actor = entry['actor']?.toString().trim();
      if (actor != null && actor.isNotEmpty) return actor;
    }
    return null;
  }

  Future<DateTime?> getTxnApprovedAt(int txnId) async {
    await _ensureLoaded();
    final audit = await listAudit(limit: 1000);
    for (final entry in audit) {
      if ((entry['type'] ?? '').toString() != 'pending_confirm') continue;
      final entryTxnId = (entry['txnId'] as num?)?.toInt();
      if (entryTxnId != txnId) continue;

      final rawAt = entry['at']?.toString();
      if (rawAt != null && rawAt.trim().isNotEmpty) {
        final parsed = DateTime.tryParse(rawAt);
        if (parsed != null) return parsed;
      }

      final note = entry['note']?.toString() ?? '';
      final marker = 'created_at:';
      final idx = note.indexOf(marker);
      if (idx >= 0) {
        final rawCreated = note.substring(idx + marker.length).trim();
        final parsedCreated = DateTime.tryParse(rawCreated);
        if (parsedCreated != null) return parsedCreated;
      }
    }
    return null;
  }
}
