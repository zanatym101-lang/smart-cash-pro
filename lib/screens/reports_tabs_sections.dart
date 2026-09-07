part of 'reports_screen.dart';

extension _ReportsTabsSections on _ReportsScreenState {
  Widget _periodHero(DateRange range, LicenseInfo? license) {
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
          Text(
            _formatPeriodSubtitle(range),
            style: const TextStyle(color: Colors.white70),
          ),
          if (license != null && !license.isActivated) ...[
            const SizedBox(height: 6),
            Text(
              'تجريبي • متبقي ${license.daysLeft} أيام',
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
        _kpiCard(
          'إجمالي الربح',
          report.profit.total,
          icon: Icons.trending_up,
          color: kReportEmeraldGreen,
        ),
        _kpiCard(
          'صافي الربح بعد المصروفات',
          netProfit,
          icon: Icons.savings,
          color: netProfit >= 0 ? kReportEmeraldGreen : kReportOutflowRed,
        ),
        _kpiCard(
          'إجمالي المصروفات',
          expenses,
          icon: Icons.payments_outlined,
          color: kReportExpenseOrange,
        ),
        _kpiCard(
          'ربح التحويل',
          report.profit.transfer,
          icon: Icons.compare_arrows,
          color: kReportEmeraldGreen,
        ),
        _kpiCard(
          'ربح الاستلام',
          report.profit.receive,
          icon: Icons.call_received,
          color: kReportEmeraldGreen,
        ),
        _kpiCard(
          'ربح فوري',
          report.profit.fawry,
          icon: Icons.bolt,
          color: kReportEmeraldGreen,
        ),
      ],
    );
  }

  Widget _smartTab(SmartInsights? smart, TreasurySnapshot? treasury) {
    final range = _activeRange();
    final topWallet = _computeTopActiveWallet(range);
    final avgTicket = _computeAvgTicketSize(range);

    final drawer = treasury?.drawerBalance ?? 0;
    final wallets = treasury?.walletsTotal ?? 0;
    final totalTreasury = drawer + wallets;
    String liquidityRatioStr = 'كاش: 0% • محافظ: 0%';
    String? liquiditySubtitle;
    if (totalTreasury > 0) {
      final drawerPct = ((drawer / totalTreasury) * 100).clamp(0, 100);
      final walletsPct = ((wallets / totalTreasury) * 100).clamp(0, 100);
      liquidityRatioStr =
          'كاش ${drawerPct.toStringAsFixed(0)}% • محافظ ${walletsPct.toStringAsFixed(0)}%';
      liquiditySubtitle =
          'درج: ${drawer.toStringAsFixed(2)} | محافظ: ${wallets.toStringAsFixed(2)}';
    }

    final hasDetailedInsights = smart != null &&
        (smart.bestProfitDays.isNotEmpty ||
            smart.mostActiveDays.isNotEmpty ||
            smart.topCustomersByProfit.isNotEmpty ||
            smart.topCustomersByVolume.isNotEmpty);

    final bestProfit = (smart != null && smart.bestProfitDays.isNotEmpty)
        ? smart.bestProfitDays.first
        : null;
    final mostActive = (smart != null && smart.mostActiveDays.isNotEmpty)
        ? smart.mostActiveDays.first
        : null;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        _sectionTitle('مؤشرات الأداء الذكية'),
        _smartKpi(
          'المحفظة الأكثر نشاطاً',
          topWallet != null
              ? '${topWallet.name} (${topWallet.count} عملية)'
              : 'لا توجد حركات محافظ',
          Icons.account_balance_wallet,
          color: const Color(0xFF3B82F6),
        ),
        _smartKpi(
          'نسبة السيولة (كاش / محافظ)',
          liquidityRatioStr,
          Icons.pie_chart_outline,
          color: kReportEmeraldGreen,
          subtitle: liquiditySubtitle,
        ),
        _smartKpi(
          'متوسط حجم العملية',
          avgTicket > 0 ? '${avgTicket.toStringAsFixed(2)} ج.م' : '0.00 ج.م',
          Icons.analytics_outlined,
          color: const Color(0xFF8B5CF6),
        ),
        if (bestProfit != null)
          _smartKpi(
            'أفضل يوم ربحًا',
            '${bestProfit.dateKey} • ${bestProfit.profit.toStringAsFixed(2)}',
            Icons.emoji_events,
            color: kReportEmeraldGreen,
          ),
        if (mostActive != null)
          _smartKpi(
            'أكثر يوم نشاطًا',
            '${mostActive.dateKey} • ${mostActive.count} عملية',
            Icons.local_fire_department,
            color: kReportExpenseOrange,
          ),
        const SizedBox(height: 12),
        if (hasDetailedInsights) ...[
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
        ] else ...[
          const Card(
            child: ListTile(
              leading: Icon(Icons.info_outline, color: Colors.blueGrey),
              title: Text('تحليل إضافي'),
              subtitle: Text(
                'سيتم إدراج أفضل الأيام والعملاء تلقائياً عند تسجيل عمليات خلال هذه الفترة.',
              ),
            ),
          ),
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
          color: kReportEmeraldGreen,
        ),
        _kpiCard(
          'إجمالي الخارج',
          report.cashflow.outflow,
          icon: Icons.north_east,
          color: kReportOutflowRed,
        ),
        _kpiCard(
          'صافي الحركة',
          report.cashflow.net,
          icon: Icons.swap_vert,
          color: report.cashflow.net >= 0
              ? kReportEmeraldGreen
              : kReportOutflowRed,
        ),
        const SizedBox(height: 12),
        _sectionTitle('تفصيل الداخل'),
        ...inflow.map(
          (e) => _lineRow(
            e.key,
            e.value,
            color: kReportEmeraldGreen,
            icon: Icons.south_west,
          ),
        ),
        const SizedBox(height: 12),
        _sectionTitle('تفصيل الخارج'),
        ...outflow.map(
          (e) => _lineRow(
            e.key,
            e.value,
            color: kReportOutflowRed,
            icon: Icons.north_east,
          ),
        ),
      ],
    );
  }

  Widget _opsTab(ReportData? report) {
    if (report == null) return const SizedBox.shrink();
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        _countTile(
          'عدد التحويلات',
          report.ops.transferCount,
          Icons.compare_arrows,
          color: const Color(0xFF3B82F6),
        ),
        _countTile(
          'عدد الاستلامات',
          report.ops.receiveCount,
          Icons.call_received,
          color: kReportEmeraldGreen,
        ),
        _countTile(
          'عدد فوري نقدي',
          report.ops.fawryCashCount,
          Icons.bolt,
          color: Colors.amber.shade700,
        ),
        _countTile(
          'عدد فوري آجل',
          report.ops.fawryCreditCount,
          Icons.hourglass_bottom,
          color: kReportExpenseOrange,
        ),
        _countTile(
          'عدد المصروفات',
          report.ops.expenseCount,
          Icons.payments,
          color: kReportOutflowRed,
        ),
        _countTile(
          'عدد تحصيل المستحقات',
          report.ops.claimCollectCount,
          Icons.request_quote,
          color: kReportEmeraldGreen,
        ),
        _countTile(
          'عدد سداد المستحقات',
          report.ops.claimPayCount,
          Icons.assignment_return,
          color: kReportOutflowRed,
        ),
        const Divider(),
        _countTile(
          'عدد الآجل',
          report.ops.pendingCount,
          Icons.pending_actions,
          color: Colors.indigo,
        ),
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
          color: kReportEmeraldGreen,
        ),
        _kpiCard(
          'إجمالي مستحقات علينا (مفتوحة)',
          report.claims.payableOpen,
          icon: Icons.trending_down,
          color: kReportOutflowRed,
        ),
        _kpiCard(
          netLabel,
          net.abs(),
          icon: Icons.balance,
          color: net >= 0 ? kReportEmeraldGreen : kReportOutflowRed,
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
              color: r.ok ? kReportEmeraldGreen : kReportOutflowRed,
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
        ? kReportEmeraldGreen
        : (diff > 0 ? const Color(0xFF3B82F6) : kReportOutflowRed);

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
          color: treasury.availableLiquidityNow >= 0
              ? kReportEmeraldGreen
              : kReportOutflowRed,
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
          color: netProfitAfterExpenses >= 0
              ? kReportEmeraldGreen
              : kReportOutflowRed,
        ),
        const SizedBox(height: 10),
        _sectionTitle('أرصدة الخزنة والدرج'),
        _kpiCard(
          'رصيد الدرج الحالي',
          treasury.drawerBalance,
          icon: Icons.account_balance,
          color: kReportEmeraldGreen,
        ),
        _kpiCard(
          'إجمالي المحافظ الحالي',
          treasury.walletsTotal,
          icon: Icons.account_balance_wallet,
          color: kReportEmeraldGreen,
        ),
        _kpiCard(
          'إجمالي الخزنة (درج + محافظ)',
          treasury.drawerBalance + treasury.walletsTotal,
          icon: Icons.savings,
          color: kReportEmeraldGreen,
        ),
        const SizedBox(height: 10),
        _sectionTitle('ملخص سريع'),
        _lineRow('إجمالي الربح', report.profit.total, color: kReportEmeraldGreen),
        _lineRow('إجمالي المصروفات', expenses, color: kReportExpenseOrange),
        _lineRow(
          'صافي حركة الدرج',
          report.cashflow.net,
          color: report.cashflow.net >= 0
              ? kReportEmeraldGreen
              : kReportOutflowRed,
        ),
        _lineRow(
          'مستحقات لنا (مفتوح)',
          report.claims.receivableOpen,
          color: kReportEmeraldGreen,
        ),
        _lineRow(
          'مستحقات علينا (مفتوح)',
          report.claims.payableOpen,
          color: kReportOutflowRed,
        ),
        _lineRow(
          'صافي المستحقات',
          report.claims.net,
          color: report.claims.net >= 0
              ? kReportEmeraldGreen
              : kReportOutflowRed,
        ),
        _lineRow('رصيد الآجل (صافي)', treasury.pendingNet),
        const SizedBox(height: 10),
        _sectionTitle('تنبيهات سريعة'),
        if (alerts.isEmpty)
          const Card(
            child: ListTile(
              leading: Icon(Icons.verified, color: kReportEmeraldGreen),
              title: Text('وضع سليم'),
              subtitle: Text('لا توجد مؤشرات خطر حالياً.'),
            ),
          )
        else
          ...alerts.map(
            (msg) => Card(
              child: ListTile(
                leading: const Icon(
                  Icons.warning_amber_rounded,
                  color: kReportOutflowRed,
                ),
                title: Text(msg),
              ),
            ),
          ),
      ],
    );
  }

  ({String name, int count})? _computeTopActiveWallet(DateRange range) {
    final walletOps = <int, int>{};
    for (final t in _txns) {
      if (t.status != 'posted' || !range.contains(t.entryDate)) continue;
      if (t.walletFromId != null) {
        walletOps[t.walletFromId!] = (walletOps[t.walletFromId!] ?? 0) + 1;
      }
      if (t.walletToId != null) {
        walletOps[t.walletToId!] = (walletOps[t.walletToId!] ?? 0) + 1;
      }
    }
    if (walletOps.isEmpty) return null;
    var bestId = walletOps.keys.first;
    var bestCount = walletOps[bestId]!;
    for (final entry in walletOps.entries) {
      if (entry.value > bestCount) {
        bestId = entry.key;
        bestCount = entry.value;
      }
    }
    final wallet = _wallets.firstWhere(
      (w) => w.id == bestId,
      orElse: () => Wallet(id: bestId, name: 'محفظة #$bestId'),
    );
    return (name: wallet.name, count: bestCount);
  }

  double _computeAvgTicketSize(DateRange range) {
    double totalVol = 0;
    int count = 0;
    for (final t in _txns) {
      if (t.status != 'posted' || !range.contains(t.entryDate)) continue;
      if (t.kind == 'drawer_deposit' ||
          t.kind == 'external_funding' ||
          t.kind == 'rollback') {
        continue;
      }
      count++;
      switch (t.kind) {
        case 'transfer':
          totalVol += (t.mode == 'type2_v2'
              ? t.amount + t.clientFee
              : t.amount - t.networkFee);
          break;
        case 'fawry_cash':
        case 'fawry_credit':
          totalVol += (t.amount + t.clientFee);
          break;
        default:
          totalVol += t.amount;
          break;
      }
    }
    return count > 0 ? (totalVol / count) : 0.0;
  }
}

