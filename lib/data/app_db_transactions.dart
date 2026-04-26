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

  bool _hasDeferredSettlementLink(int txnId) {
    for (final t in _txns) {
      if (t.kind != 'claim_collect' && t.kind != 'claim_pay') continue;
      if (t.status != 'posted' && t.status != 'rolled_back') continue;
      if (_extractPendingSettlementRef(t.note) == txnId) {
        return true;
      }
    }
    return false;
  }

  bool _hasDeferredOpenClaim(int txnId) {
    for (final c in _claims) {
      if (c.sourceTxnId == txnId) return true;
    }
    return false;
  }

  bool _shouldAffectDrawerForTxn(Txn t) {
    if (_txnKind(t) != 'transfer' && _txnKind(t) != 'receive') return true;
    if (_hasStatus(t, 'pending')) return false;
    if (_hasDeferredOpenClaim(t.id)) return false;
    if (_hasDeferredSettlementLink(t.id)) return false;
    return true;
  }

  void _requireTxnAdmin() {
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

  Future<void> rollbackPosted(int txnId) async {
    await _ensureLoaded();
    _requireTxnAdmin();

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
