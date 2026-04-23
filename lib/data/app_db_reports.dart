part of 'app_db.dart';

extension AppDbReports on AppDb {
  String _businessCloseDateKey(DateTime d) => _businessDateKeyFromDateTime(d);

  DateRange _businessDayRange(DateTime d) {
    final shifted = _businessShift(d);
    final businessDate = DateTime(shifted.year, shifted.month, shifted.day);
    final start = businessDate.add(Duration(hours: _dayStartHour()));
    final end = start
        .add(const Duration(days: 1))
        .subtract(const Duration(milliseconds: 1));
    return DateRange(start: start, end: end);
  }

  TreasurySnapshot _historicalTreasurySnapshotAt(DateTime cutoff) {
    final state = AccountingState(
      walletBalancesQirsh: <String, int>{},
      drawerBalanceQirsh: 0,
      fawryBalanceQirsh: 0,
      ledger: <LedgerEntry>[],
      transactions: <String, TransactionRecord>{},
    );
    final engine = AccountingEngine(state);

    final posted =
        _txns
            .where(
              (t) =>
                  (_hasStatus(t, 'posted') ||
                      _pendingAppliesToActualBalance(t)) &&
                  !t.entryDate.isAfter(cutoff),
            )
            .toList()
          ..sort((a, b) {
            final c = a.entryDate.compareTo(b.entryDate);
            if (c != 0) return c;
            return a.id.compareTo(b.id);
          });

    for (final t in posted) {
      final txId = _txId(t.id);
      final spec = _specFromTxn(t);
      engine.createPending(txId: txId, spec: spec, payload: t.toJson());
      engine.approve(txId: txId, spec: spec);
    }

    int walletsActualQ = 0;
    for (final w in _wallets) {
      walletsActualQ += state.getWalletQirsh(w.id.toString());
    }

    return TreasurySnapshot(
      drawerBalance: Money.toEgpDouble(state.drawerBalanceQirsh),
      walletsTotal: Money.toEgpDouble(walletsActualQ),
      fawryBalance: Money.toEgpDouble(state.fawryBalanceQirsh),
      drawerActualBalance: Money.toEgpDouble(state.drawerBalanceQirsh),
      walletsActualTotal: Money.toEgpDouble(walletsActualQ),
      fawryActualBalance: Money.toEgpDouble(state.fawryBalanceQirsh),
      pendingCount: 0,
      pendingInflow: 0,
      pendingOutflow: 0,
      claimsReceivableOpen: 0,
      claimsPayableOpen: 0,
      profitApprovedTotal: 0,
      dailyProfit: 0,
      monthlyProfit: 0,
    );
  }

  Future<List<DailyClose>> listDailyCloses() async {
    await _ensureLoaded();
    final items = _dailyCloses.toList()
      ..sort((a, b) => b.closedAt.compareTo(a.closedAt));
    return items;
  }

  Future<DailyClose> closeDaily(DateTime date) async {
    await _ensureLoaded();
    if (!AppSession.isAdmin) {
      throw Exception('هذا الإجراء متاح للأدمن فقط');
    }
    final key = _businessCloseDateKey(date);
    final existing = _dailyCloses.where((c) => c.dateKey == key).toList();
    if (existing.isNotEmpty) {
      throw Exception(
        'تم إغلاق اليوم بالفعل بتاريخ/وقت ${existing.first.closedAt}',
      );
    }

    final range = _businessDayRange(date);
    final report = ReportCalculator.build(
      txns: _txns,
      claims: _claims,
      range: range,
    );
    final snap = _historicalTreasurySnapshotAt(range.end);

    final close = DailyClose(
      id: _nextCloseId++,
      dateKey: key,
      closedAt: DateTime.now(),
      drawerBalance: snap.drawerActualBalance,
      walletsTotal: snap.walletsActualTotal,
      treasuryTotal: snap.actualTreasuryApproved,
      profitTotal: report.profit.total,
      profitTransfer: report.profit.transfer,
      profitReceive: report.profit.receive,
      profitFawry: report.profit.fawry,
      inflow: report.cashflow.inflow,
      outflow: report.cashflow.outflow,
      net: report.cashflow.net,
      transferCount: report.ops.transferCount,
      receiveCount: report.ops.receiveCount,
      fawryCashCount: report.ops.fawryCashCount,
      fawryCreditCount: report.ops.fawryCreditCount,
      expenseCount: report.ops.expenseCount,
      claimCollectCount: report.ops.claimCollectCount,
      claimPayCount: report.ops.claimPayCount,
      pendingCount: report.ops.pendingCount,
    );

    _dailyCloses.add(close);
    await _save(
      outboxItems: [
        _outboxInsert(
          entity: 'daily_close',
          entityId: close.id.toString(),
          action: 'create',
          payload: close.toJson(),
        ),
      ],
    );
    await appendAudit(type: 'daily_close', dateKey: key);
    return close;
  }

  Future<void> reopenDaily(DateTime date) async {
    await _ensureLoaded();
    if (!AppSession.isAdmin) {
      throw Exception('هذا الإجراء متاح للأدمن فقط');
    }
    final key = _businessCloseDateKey(date);
    final idx = _dailyCloses.indexWhere((c) => c.dateKey == key);
    if (idx < 0) {
      throw Exception('لم يتم إغلاق هذا اليوم');
    }
    final close = _dailyCloses[idx];
    final hasAfter = _txns.any(
      (t) =>
          t.createdAt.isAfter(close.closedAt) &&
          _businessDateKeyFromDateTime(t.entryDate) == key,
    );
    if (hasAfter) {
      throw Exception(
        'لا يمكن إلغاء الإغلاق: توجد عمليات بعد الإغلاق لهذا اليوم',
      );
    }
    _dailyCloses.removeAt(idx);
    await _save(
      outboxItems: [
        _outboxInsert(
          entity: 'daily_close',
          entityId: close.id.toString(),
          action: 'delete',
          payload: close.toJson(),
        ),
      ],
    );
    await appendAudit(type: 'daily_close_reopen', dateKey: key);
  }
}
