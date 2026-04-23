part of 'reports_screen.dart';

extension _ReportsTabsSections on _ReportsScreenState {
  Widget _periodHero(DateRange range, LicenseInfo? license) {
    final label = 'من ${_fmtDate(range.start)} إلى ${_fmtDate(range.end)}';
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF0F172A), Color(0xFF1E293B)],
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
        ),
        borderRadius: BorderRadius.circular(22),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'تقرير الفترة',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ChoiceChip(
                label: const Text('اليوم'),
                selected: _period == 'today',
                onSelected: (_) async {
                  _setMountedState(() => _period = 'today');
                  await _load();
                },
              ),
              ChoiceChip(
                label: const Text('هذا الشهر'),
                selected: _period == 'month',
                onSelected: (_) async {
                  _setMountedState(() => _period = 'month');
                  await _load();
                },
              ),
              ChoiceChip(
                label: const Text('مخصص'),
                selected: _period == 'custom',
                onSelected: (_) async {
                  _setMountedState(() => _period = 'custom');
                  await _pickCustomRange();
                },
              ),
              if (_period == 'custom')
                OutlinedButton.icon(
                  onPressed: _pickCustomRange,
                  icon: const Icon(Icons.date_range),
                  label: const Text('تغيير المدة'),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text('الفترة: $label', style: const TextStyle(color: Colors.white70)),
          if (license != null && !license.isActivated) ...[
            const SizedBox(height: 6),
            Text(
              'تجريبي • تقارير متبقية ${license.reportsLeft}',
              style: const TextStyle(color: Colors.white70),
            ),
          ],
        ],
      ),
    );
  }

  Widget _profitTab(ReportData? report) {
    if (report == null) return const SizedBox.shrink();
    final expenses = report.cashflow.outflowByType['مصروفات'] ?? 0;
    final netProfit = report.profit.total - expenses;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        _kpiCard('إجمالي الربح', report.profit.total, icon: Icons.trending_up),
        _kpiCard('صافي الربح بعد المصروفات', netProfit, icon: Icons.savings),
        _kpiCard('إجمالي المصروفات', expenses, icon: Icons.payments_outlined),
        _kpiCard(
          'ربح التحويل',
          report.profit.transfer,
          icon: Icons.compare_arrows,
        ),
        _kpiCard(
          'ربح الاستلام',
          report.profit.receive,
          icon: Icons.call_received,
        ),
        _kpiCard('ربح فوري', report.profit.fawry, icon: Icons.bolt),
      ],
    );
  }

  Widget _smartTab(SmartInsights? smart) {
    if (smart == null) return const SizedBox.shrink();
    final hasAny =
        smart.bestProfitDays.isNotEmpty ||
        smart.mostActiveDays.isNotEmpty ||
        smart.topCustomersByProfit.isNotEmpty ||
        smart.topCustomersByVolume.isNotEmpty;
    if (!hasAny) {
      return const Center(child: Text('لا توجد بيانات خلال الفترة المختارة'));
    }

    final bestProfit = smart.bestProfitDays.isNotEmpty
        ? smart.bestProfitDays.first
        : null;
    final mostActive = smart.mostActiveDays.isNotEmpty
        ? smart.mostActiveDays.first
        : null;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        if (bestProfit != null)
          _smartKpi(
            'أفضل يوم ربحًا',
            '${bestProfit.dateKey} • ${bestProfit.profit.toStringAsFixed(2)}',
            Icons.emoji_events,
          ),
        if (mostActive != null)
          _smartKpi(
            'أكثر يوم نشاطًا',
            '${mostActive.dateKey} • ${mostActive.count} عملية',
            Icons.local_fire_department,
          ),
        const SizedBox(height: 12),
        if (smart.bestProfitDays.isNotEmpty) ...[
          _sectionTitle('أفضل الأيام ربحًا'),
          ...smart.bestProfitDays.map(_dayRow),
          const SizedBox(height: 12),
        ],
        if (smart.mostActiveDays.isNotEmpty) ...[
          _sectionTitle('أكثر الأيام نشاطًا'),
          ...smart.mostActiveDays.map(_dayRow),
          const SizedBox(height: 12),
        ],
        if (smart.topCustomersByProfit.isNotEmpty) ...[
          _sectionTitle('أفضل العملاء (حسب الربح)'),
          ...smart.topCustomersByProfit.map(_customerRow),
          const SizedBox(height: 12),
        ],
        if (smart.topCustomersByVolume.isNotEmpty) ...[
          _sectionTitle('أعلى التعاملات (حسب المبلغ)'),
          ...smart.topCustomersByVolume.map(_customerRow),
        ],
      ],
    );
  }

  Widget _cashflowTab(ReportData? report) {
    if (report == null) return const SizedBox.shrink();
    final inflow = List<MapEntry<String, double>>.from(
      report.cashflow.inflowByType.entries,
    )..sort((a, b) => b.value.compareTo(a.value));
    final outflow = List<MapEntry<String, double>>.from(
      report.cashflow.outflowByType.entries,
    )..sort((a, b) => b.value.compareTo(a.value));

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        _kpiCard(
          'إجمالي الداخل',
          report.cashflow.inflow,
          icon: Icons.south_west,
        ),
        _kpiCard(
          'إجمالي الخارج',
          report.cashflow.outflow,
          icon: Icons.north_east,
        ),
        _kpiCard('صافي الحركة', report.cashflow.net, icon: Icons.swap_vert),
        const SizedBox(height: 12),
        _sectionTitle('تفصيل الداخل'),
        ...inflow.map((e) => _lineRow(e.key, e.value)),
        const SizedBox(height: 12),
        _sectionTitle('تفصيل الخارج'),
        ...outflow.map((e) => _lineRow(e.key, e.value)),
      ],
    );
  }

  Widget _opsTab(ReportData? report) {
    if (report == null) return const SizedBox.shrink();
    final range = _activeRange();
    final expenseTotal = _expenseTotalForRange(range);
    final expenseArchive = _expenseArchiveTotal(range);
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        _kpiCard(
          'إجمالي المصروفات (الفترة)',
          expenseTotal,
          icon: Icons.payments_outlined,
        ),
        _kpiCard(
          'أرشيف المصروفات (قبل الفترة)',
          expenseArchive,
          icon: Icons.archive_outlined,
        ),
        const Divider(),
        _countTile(
          'عدد التحويلات',
          report.ops.transferCount,
          Icons.compare_arrows,
        ),
        _countTile(
          'عدد الاستلامات',
          report.ops.receiveCount,
          Icons.call_received,
        ),
        _countTile('عدد فوري نقدي', report.ops.fawryCashCount, Icons.bolt),
        _countTile(
          'عدد فوري آجل',
          report.ops.fawryCreditCount,
          Icons.hourglass_bottom,
        ),
        _countTile('عدد المصروفات', report.ops.expenseCount, Icons.payments),
        _countTile(
          'عدد تحصيل المستحقات',
          report.ops.claimCollectCount,
          Icons.request_quote,
        ),
        _countTile(
          'عدد سداد المستحقات',
          report.ops.claimPayCount,
          Icons.assignment_return,
        ),
        const Divider(),
        _countTile('عدد الآجل', report.ops.pendingCount, Icons.pending_actions),
      ],
    );
  }

  Widget _claimsTab(ReportData? report) {
    if (report == null) return const SizedBox.shrink();
    final net = report.claims.net;
    final netLabel = net >= 0 ? 'صافي لنا' : 'صافي علينا';
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        _kpiCard(
          'إجمالي مستحقات لنا (مفتوحة)',
          report.claims.receivableOpen,
          icon: Icons.trending_up,
        ),
        _kpiCard(
          'إجمالي مستحقات علينا (مفتوحة)',
          report.claims.payableOpen,
          icon: Icons.trending_down,
        ),
        _kpiCard(netLabel, net.abs(), icon: Icons.balance),
      ],
    );
  }

  Widget _treasuryTab(TreasurySnapshot? treasury) {
    if (treasury == null) return const SizedBox.shrink();
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        _kpiCard(
          'رصيد الدرج الحالي',
          treasury.drawerBalance,
          icon: Icons.account_balance,
        ),
        _kpiCard(
          'إجمالي المحافظ الحالي',
          treasury.walletsTotal,
          icon: Icons.account_balance_wallet,
        ),
        _kpiCard(
          'إجمالي الخزنة',
          treasury.drawerBalance + treasury.walletsTotal,
          icon: Icons.savings,
        ),
      ],
    );
  }

  Widget _reconciliationTab(ReportData? report) {
    if (report == null) return const SizedBox.shrink();
    final r = report.reconciliation;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        Card(
          child: ListTile(
            leading: Icon(
              r.ok ? Icons.verified : Icons.warning_amber_rounded,
              color: r.ok ? Colors.green : Colors.red,
            ),
            title: const Text('حالة المطابقة'),
            subtitle: Text(
              r.ok
                  ? 'مطابقة سليمة: لا يوجد فرق'
                  : 'يوجد فرق بين المتوقع والفعلي',
            ),
          ),
        ),
        _reconLineCard(r.drawer),
        _reconLineCard(r.wallets),
        _reconLineCard(r.total),
      ],
    );
  }

  Widget _reconLineCard(ReconciliationLine line) {
    final diff = line.diff;
    final diffText = diff >= 0
        ? '+${diff.toStringAsFixed(2)}'
        : diff.toStringAsFixed(2);
    final diffColor = line.ok
        ? Colors.green
        : (diff > 0 ? Colors.blue : Colors.red);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              line.label,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Text('رصيد أول الفترة: ${line.opening.toStringAsFixed(2)}'),
            Text('إجمالي الداخل: ${line.inflow.toStringAsFixed(2)}'),
            Text('إجمالي الخارج: ${line.outflow.toStringAsFixed(2)}'),
            const Divider(),
            Text('الرصيد المتوقع: ${line.expectedClosing.toStringAsFixed(2)}'),
            Text('الرصيد الفعلي: ${line.actualClosing.toStringAsFixed(2)}'),
            const SizedBox(height: 6),
            Text(
              'الفرق: $diffText',
              style: TextStyle(color: diffColor, fontWeight: FontWeight.w700),
            ),
          ],
        ),
      ),
    );
  }

  Widget _executiveTab(ReportData? report, TreasurySnapshot? treasury) {
    if (report == null || treasury == null) return const SizedBox.shrink();
    final expenses = report.cashflow.outflowByType['مصروفات'] ?? 0;
    final netProfitAfterExpenses = report.profit.total - expenses;
    final alerts = <String>[
      if (!report.reconciliation.ok) 'تنبيه: يوجد فرق في مطابقة الأرصدة.',
      if (report.ops.pendingCount > 0)
        'تنبيه: يوجد ${report.ops.pendingCount} عملية آجلة.',
      if (treasury.availableLiquidityNow < 0) 'تنبيه: السيولة المتاحة سالبة.',
      if (netProfitAfterExpenses < 0) 'تنبيه: صافي الربح بعد المصروفات سالب.',
    ];

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        _kpiCard(
          'السيولة المتاحة',
          treasury.availableLiquidityNow,
          icon: Icons.account_balance_wallet_outlined,
        ),
        _kpiCard(
          'رأس المال الحقيقي (معتمد)',
          treasury.realCapitalApproved,
          icon: Icons.pie_chart_outline,
        ),
        _kpiCard(
          'الخزنة الفعلية (معتمد)',
          treasury.actualTreasuryApproved,
          icon: Icons.account_balance,
        ),
        _kpiCard(
          'صافي الربح بعد المصروفات',
          netProfitAfterExpenses,
          icon: Icons.trending_up,
        ),
        const SizedBox(height: 10),
        _sectionTitle('ملخص سريع'),
        _lineRow('إجمالي الربح', report.profit.total),
        _lineRow('إجمالي المصروفات', expenses),
        _lineRow('صافي حركة الدرج', report.cashflow.net),
        _lineRow('مستحقات لنا (مفتوح)', report.claims.receivableOpen),
        _lineRow('مستحقات علينا (مفتوح)', report.claims.payableOpen),
        _lineRow('صافي المستحقات', report.claims.net),
        _lineRow('رصيد الآجل (صافي)', treasury.pendingNet),
        const SizedBox(height: 10),
        _sectionTitle('تنبيهات سريعة'),
        if (alerts.isEmpty)
          const Card(
            child: ListTile(
              leading: Icon(Icons.verified, color: Colors.green),
              title: Text('وضع سليم'),
              subtitle: Text('لا توجد مؤشرات خطر حالياً.'),
            ),
          )
        else
          ...alerts.map(
            (msg) => Card(
              child: ListTile(
                leading: const Icon(Icons.warning_amber_rounded),
                title: Text(msg),
              ),
            ),
          ),
      ],
    );
  }

  double _expenseTotalForRange(DateRange range) {
    return _txns
        .where(
          (t) =>
              t.kind == 'expense' &&
              t.status == 'posted' &&
              range.contains(t.entryDate),
        )
        .fold<double>(0, (s, t) => s + t.amount);
  }

  double _expenseArchiveTotal(DateRange range) {
    return _txns
        .where(
          (t) =>
              t.kind == 'expense' &&
              t.status == 'posted' &&
              t.entryDate.isBefore(range.start),
        )
        .fold<double>(0, (s, t) => s + t.amount);
  }
}
