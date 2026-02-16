part of 'app_db.dart';

extension AppDbReports on AppDb {
  String _calendarDateKey(DateTime d) => _formatDateKey(d);

  DateRange _dayRange(DateTime d) {
    final start = DateTime(d.year, d.month, d.day, _dayStartHour());
    final end = start
        .add(const Duration(days: 1))
        .subtract(const Duration(milliseconds: 1));
    return DateRange(start: start, end: end);
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
    final key = _calendarDateKey(date);
    final existing = _dailyCloses.where((c) => c.dateKey == key).toList();
    if (existing.isNotEmpty) {
      throw Exception(
        'تم إغلاق اليوم بالفعل بتاريخ/وقت ${existing.first.closedAt}',
      );
    }

    final range = _dayRange(date);
    final report = ReportCalculator.build(
      txns: _txns,
      claims: _claims,
      range: range,
    );
    final snap = await getTreasurySnapshot();

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
    await appendAudit(type: 'daily_close', dateKey: key);
    await _save();
    await enqueueOutbox(
      entity: 'daily_close',
      entityId: close.id.toString(),
      action: 'create',
      payload: close.toJson(),
    );
    return close;
  }

  Future<void> reopenDaily(DateTime date) async {
    await _ensureLoaded();
    if (!AppSession.isAdmin) {
      throw Exception('هذا الإجراء متاح للأدمن فقط');
    }
    final key = _calendarDateKey(date);
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
    await appendAudit(type: 'daily_close_reopen', dateKey: key);
    await _save();
    await enqueueOutbox(
      entity: 'daily_close',
      entityId: close.id.toString(),
      action: 'delete',
      payload: close.toJson(),
    );
  }
}
