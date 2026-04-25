// Dashboard: KPIs + navigation (admin-aware)
import 'package:flutter/material.dart';
import '../data/app_db.dart';
import '../data/app_session.dart';
import '../data/reporting.dart';
import '../models/app_settings.dart';
import '../models/claim.dart';
import '../models/license_info.dart';
import '../models/quick_action_item.dart';
import '../models/transaction.dart';

import '../widgets/app_title.dart';
import 'wallets_screen.dart';
import 'treasury_screen.dart';
import 'transfer_screen.dart';
import 'receive_screen.dart';
import 'pending_screen.dart';
import 'wallet_funding_screen.dart';
import 'ledger_screen.dart';
import 'expenses_screen.dart';
import 'admin_settings_screen.dart';
import 'claims_screen.dart';
import 'reports_screen.dart';
import 'help_screen.dart';
import 'quick_actions_order_screen.dart';
import 'customers_screen.dart';
import 'assistant_screen.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  TreasurySnapshot? _snap;
  LicenseInfo? _license;
  ReportData? _todayReport;
  bool _loading = true;
  String? _error;
  DateTime? _lastUpdated;
  _DashboardFocus _focus = _DashboardFocus.treasury;
  bool _showHeroDetails = false;
  List<String> _actionOrder = [];
  Map<int, WalletLimitUsage> _walletUsage = {};
  int _dayStartHour = 0;
  double _customersReceivable = 0;
  double _customersPayable = 0;
  double _expensesTotalAll = 0;
  double _expensesTotalToday = 0;
  double _expensesTotalMonth = 0;
  int _pendingDueTodayCount = 0;
  int _pendingOverdueCount = 0;

  DateTime _businessShift(DateTime d) {
    if (_dayStartHour <= 0) return d;
    return d.subtract(Duration(hours: _dayStartHour));
  }

  DateRange _todayRange() {
    final now = DateTime.now();
    final shifted = _businessShift(now);
    final start = DateTime(
      shifted.year,
      shifted.month,
      shifted.day,
      _dayStartHour,
    );
    final end = start
        .add(const Duration(days: 1))
        .subtract(const Duration(milliseconds: 1));
    return DateRange(start: start, end: end);
  }

  DateRange _monthRange() {
    final now = DateTime.now();
    final shifted = _businessShift(now);
    final start = DateTime(shifted.year, shifted.month, 1, _dayStartHour);
    final end = DateTime(
      shifted.year,
      shifted.month + 1,
      1,
      _dayStartHour,
    ).subtract(const Duration(milliseconds: 1));
    return DateRange(start: start, end: end);
  }

  int _opsCount(OperationalSummary ops) {
    return ops.transferCount +
        ops.receiveCount +
        ops.fawryCashCount +
        ops.fawryCreditCount +
        ops.expenseCount +
        ops.claimCollectCount +
        ops.claimPayCount;
  }

  double _pendingTransferDue(Txn t) {
    if (t.mode == 'type2_v2') return t.amount + t.clientFee;
    final base = t.amount - t.networkFee;
    if (t.mode == 'type1') return base + t.clientFee;
    return base;
  }

  double _pendingReceiveDue(Txn t) {
    if (t.mode == 'cash') return t.amount;
    if (t.mode == 'deduct') {
      return (t.amount - t.clientFee).clamp(0, 1e18).toDouble();
    }
    return 0;
  }

  ({double receivable, double payable}) _customerTotals({
    required List<Txn> txns,
    required List<Claim> claims,
  }) {
    double receivable = 0;
    double payable = 0;

    for (final c in claims) {
      if (c.status != 'open') continue;
      if (c.party.trim().isEmpty) continue;
      if (c.type == 'receivable') {
        receivable += c.amount;
      } else if (c.type == 'payable') {
        payable += c.amount;
      }
    }

    for (final t in txns) {
      if (t.status != 'pending') continue;
      if ((t.party ?? '').trim().isEmpty) continue;
      if (t.kind == 'transfer') {
        final due = _pendingTransferDue(t);
        if (due > 0) receivable += due;
      } else if (t.kind == 'receive') {
        final due = _pendingReceiveDue(t);
        if (due > 0) payable += due;
      } else if (t.kind == 'fawry_credit') {
        final due = t.amount + t.clientFee;
        if (due > 0) receivable += due;
      }
    }

    return (receivable: receivable, payable: payable);
  }

  ({int dueToday, int overdue}) _pendingDateCounts({
    required List<Txn> txns,
    required DateRange todayRange,
  }) {
    var dueToday = 0;
    var overdue = 0;

    for (final t in txns) {
      if (t.status != 'pending') continue;
      if (todayRange.contains(t.entryDate)) {
        dueToday++;
      } else if (t.entryDate.isBefore(todayRange.start)) {
        overdue++;
      }
    }

    return (dueToday: dueToday, overdue: overdue);
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final results = await Future.wait([
        AppDb.instance.getTreasurySnapshot(),
        AppDb.instance.getLicenseInfo(),
        AppDb.instance.getQuickActionsOrder(),
        AppDb.instance.getWalletLimitUsage(),
        AppDb.instance.getAppSettings(),
        AppDb.instance.listTxns(),
        AppDb.instance.listClaims(),
      ]);
      final s = results[0] as TreasurySnapshot;
      final license = results[1] as LicenseInfo;
      final order = (results[2] as List).map((e) => e.toString()).toList();
      final usage = results[3] as Map<int, WalletLimitUsage>;
      final settings = results[4] as AppSettings;
      final txns = results[5] as List<Txn>;
      final claims = results[6] as List<Claim>;
      final customerTotals = _customerTotals(txns: txns, claims: claims);
      _dayStartHour = settings.dayStartHour;
      final todayRange = _todayRange();
      final monthRange = _monthRange();
      final pendingDateCounts = _pendingDateCounts(
        txns: txns,
        todayRange: todayRange,
      );
      final todayReport = ReportCalculator.build(
        txns: txns,
        claims: claims,
        range: todayRange,
      );
      double expensesAll = 0;
      double expensesToday = 0;
      double expensesMonth = 0;
      for (final t in txns) {
        if (t.kind != 'expense' || t.status != 'posted') continue;
        expensesAll += t.amount;
        if (todayRange.contains(t.entryDate)) {
          expensesToday += t.amount;
        }
        if (monthRange.contains(t.entryDate)) {
          expensesMonth += t.amount;
        }
      }
      if (!mounted) return;
      setState(() {
        _snap = s;
        _license = license;
        _actionOrder = order;
        _walletUsage = usage;
        _todayReport = todayReport;
        _customersReceivable = customerTotals.receivable;
        _customersPayable = customerTotals.payable;
        _expensesTotalAll = expensesAll;
        _expensesTotalToday = expensesToday;
        _expensesTotalMonth = expensesMonth;
        _pendingDueTodayCount = pendingDateCounts.dueToday;
        _pendingOverdueCount = pendingDateCounts.overdue;
        _lastUpdated = DateTime.now();
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Widget _kpiCard({
    required String title,
    required String value,
    required IconData icon,
    String? hint,
  }) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(icon, size: 28),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 4),
                  Text(value, style: Theme.of(context).textTheme.headlineSmall),
                  if (hint != null) ...[
                    const SizedBox(height: 6),
                    Text(hint, style: Theme.of(context).textTheme.bodySmall),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _pendingSummaryTile(TreasurySnapshot snap) {
    final hasOverdue = _pendingOverdueCount > 0;
    return Card(
      child: ListTile(
        leading: Icon(
          hasOverdue ? Icons.warning_amber_rounded : Icons.pending_actions,
          color: hasOverdue ? Colors.red.shade700 : null,
        ),
        title: const Text('العمليات الآجلة المفتوحة'),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('إجمالي القيمة: ${snap.pendingTotal.toStringAsFixed(2)}'),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                _pendingBadge(
                  label: 'مستحق اليوم',
                  count: _pendingDueTodayCount,
                  color: Colors.blue.shade700,
                ),
                if (hasOverdue)
                  _pendingBadge(
                    label: 'متأخر',
                    count: _pendingOverdueCount,
                    color: Colors.red.shade700,
                  ),
              ],
            ),
          ],
        ),
        trailing: Text(
          snap.pendingCount.toString(),
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        onTap: () async {
          await Navigator.of(
            context,
          ).push(MaterialPageRoute(builder: (_) => const PendingScreen()));
          await _load();
        },
      ),
    );
  }

  Widget _pendingBadge({
    required String label,
    required int count,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Text(
        '$label: $count',
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _heroCard({
    required TreasurySnapshot snap,
    required bool isAdmin,
    LicenseInfo? license,
  }) {
    final availableNow = snap.availableLiquidityNow;
    final actualTreasuryApproved = snap.actualTreasuryApproved;
    final realCapitalApproved = snap.realCapitalApproved;
    final pendingDiff = snap.pendingNet;
    final pendingDiffAbs = pendingDiff.abs();
    final pendingDiffLabel = pendingDiff >= 0 ? 'لنا' : 'علينا';
    final isTrial = license != null && !license.isActivated;
    final trialDaysLeft = license?.daysLeft ?? 0;
    final focusPending = _focus == _DashboardFocus.pending;

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        gradient: const LinearGradient(
          colors: [Color(0xFF0F172A), Color(0xFF111827)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.15),
            blurRadius: 24,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Tooltip(
                message: 'المساعد الذكي',
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () async {
                    await Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const AssistantScreen(),
                      ),
                    );
                    _load();
                  },
                  child: _miniIcon(Icons.smart_toy_outlined, active: false),
                ),
              ),
              const Spacer(),
              SegmentedButton<_DashboardFocus>(
                showSelectedIcon: false,
                style: ButtonStyle(
                  visualDensity: VisualDensity.compact,
                  backgroundColor: WidgetStateProperty.resolveWith((states) {
                    if (states.contains(WidgetState.selected)) {
                      return Colors.white;
                    }
                    return Colors.white.withValues(alpha: 0.12);
                  }),
                  foregroundColor: WidgetStateProperty.resolveWith((states) {
                    if (states.contains(WidgetState.selected)) {
                      return const Color(0xFF0F172A);
                    }
                    return Colors.white70;
                  }),
                  shape: WidgetStateProperty.all(
                    RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18),
                    ),
                  ),
                ),
                segments: const [
                  ButtonSegment(
                    value: _DashboardFocus.treasury,
                    label: Text('الخزنة'),
                  ),
                  ButtonSegment(
                    value: _DashboardFocus.pending,
                    label: Text('الآجل'),
                  ),
                ],
                selected: {_focus},
                onSelectionChanged: (v) {
                  setState(() => _focus = v.first);
                },
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            focusPending
                ? 'إجمالي المبالغ الآجلة'
                : 'إجمالي السيولة المتاحة الآن',
            style: const TextStyle(color: Colors.white70, fontSize: 14),
          ),
          const SizedBox(height: 6),
          Text(
            focusPending
                ? snap.pendingTotal.toStringAsFixed(2)
                : availableNow.toStringAsFixed(2),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 28,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 16),
          if (!focusPending) ...[
            _darkRow('الخزنة الفعلية', actualTreasuryApproved),
            const SizedBox(height: 6),
            _darkRow('السيولة المتاحة', availableNow),
            const SizedBox(height: 6),
            _darkRow('ربح اليوم', snap.dailyProfit),
            const SizedBox(height: 4),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                style: TextButton.styleFrom(foregroundColor: Colors.white70),
                onPressed: () {
                  setState(() => _showHeroDetails = !_showHeroDetails);
                },
                icon: Icon(
                  _showHeroDetails
                      ? Icons.expand_less_rounded
                      : Icons.expand_more_rounded,
                ),
                label: Text(
                  _showHeroDetails ? 'إخفاء التفاصيل' : 'عرض التفاصيل',
                ),
              ),
            ),
            if (_showHeroDetails) ...[
              const Divider(color: Colors.white24, height: 8),
              _darkRow('الدرج (فعلي)', snap.drawerActualBalance),
              _darkRow('المحافظ (فعلي)', snap.walletsActualTotal),
              _darkRow('فوري (فعلي)', snap.fawryActualBalance),
              const SizedBox(height: 6),
              _darkRow('رأس المال الحقيقي (معتمد)', realCapitalApproved),
            ],
          ] else ...[
            _darkRow('داخل الآجل', snap.pendingInflow),
            _darkRow('خارج الآجل', snap.pendingOutflow),
            const SizedBox(height: 6),
            _darkRow('الفرق ($pendingDiffLabel)', pendingDiffAbs),
            const SizedBox(height: 6),
            const Text(
              '\u0627\u0644\u0633\u064a\u0648\u0644\u0629 \u0627\u0644\u0645\u062a\u0627\u062d\u0629 = \u0627\u0644\u062e\u0632\u0646\u0629 \u0627\u0644\u0641\u0639\u0644\u064a\u0629 + \u0627\u0633\u062a\u0644\u0627\u0645 \u0645\u0639\u0644\u0642 - \u062a\u062d\u0648\u064a\u0644 \u0645\u0639\u0644\u0642',
              style: TextStyle(color: Colors.white70),
            ),
          ],
          const SizedBox(height: 16),
          Row(
            children: [
              if (isAdmin)
                Expanded(
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: const BorderSide(color: Colors.white24),
                    ),
                    onPressed: () async {
                      await Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const ReportsScreen(),
                        ),
                      );
                      _load();
                    },
                    child: const Text('عرض التقارير'),
                  ),
                ),
              if (isAdmin) const SizedBox(width: 10),
              Expanded(
                child: ElevatedButton(
                  onPressed: () async {
                    await Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const LedgerScreen()),
                    );
                    _load();
                  },
                  child: const Text('سجل العمليات'),
                ),
              ),
            ],
          ),
          if (isTrial) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                const Icon(
                  Icons.timer_outlined,
                  color: Colors.white70,
                  size: 18,
                ),
                const SizedBox(width: 6),
                Text(
                  'تجريبي • متبقي $trialDaysLeft يوم',
                  style: const TextStyle(color: Colors.white70),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _miniIcon(IconData icon, {bool active = false}) {
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: active ? Colors.white : Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Icon(
        icon,
        color: active ? const Color(0xFF0F172A) : Colors.white70,
        size: 18,
      ),
    );
  }

  Widget _darkRow(String label, double value) {
    return Row(
      children: [
        Expanded(
          child: Text(label, style: const TextStyle(color: Colors.white70)),
        ),
        Text(
          value.toStringAsFixed(2),
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  Widget _sectionTitle(String title, {String? hint, Widget? action}) {
    final trailing =
        action ??
        (hint == null
            ? null
            : Text(hint, style: Theme.of(context).textTheme.bodySmall));
    return Padding(
      padding: const EdgeInsets.only(top: 18, bottom: 10),
      child: Row(
        children: [
          Expanded(
            child: Text(title, style: Theme.of(context).textTheme.titleMedium),
          ),
          ...?(trailing == null ? null : [trailing]),
        ],
      ),
    );
  }

  List<QuickActionItem> _applyOrder(
    List<QuickActionItem> items,
    List<String> order,
  ) {
    if (order.isEmpty) return items;
    final byId = {for (final i in items) i.id: i};
    final sorted = <QuickActionItem>[];
    for (final id in order) {
      final item = byId.remove(id);
      if (item != null) sorted.add(item);
    }
    sorted.addAll(byId.values);
    return sorted;
  }

  Future<void> _openReorder(bool isAdmin) async {
    final visible = _actions(isAdmin);
    final order = await Navigator.of(context).push<List<String>>(
      MaterialPageRoute(
        builder: (_) =>
            QuickActionsOrderScreen(items: List<QuickActionItem>.from(visible)),
      ),
    );
    if (order == null) return;
    await AppDb.instance.setQuickActionsOrder(order);
    await _load();
  }

  Widget _actionGrid(List<QuickActionItem> items) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        int cross = 2;
        if (width >= 900) {
          cross = 4;
        } else if (width >= 600) {
          cross = 3;
        } else if (width >= 360) {
          cross = 3;
        }

        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: cross,
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
            childAspectRatio: width < 360 ? 1.2 : 1.05,
          ),
          itemCount: items.length,
          itemBuilder: (_, i) => _ActionTile(item: items[i]),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = _snap;
    final isAdmin = AppSession.isAdmin;
    final license = _license;
    final today = _todayReport;
    final dailyLimitUsed = _walletUsage.values.fold<double>(
      0,
      (sum, v) => sum + v.dailyUsed,
    );
    final dailyLimitTotal = _walletUsage.values.fold<double>(
      0,
      (sum, v) => sum + v.dailyLimit,
    );
    final monthlyRemaining = _walletUsage.values.fold<double>(
      0,
      (sum, v) => sum + v.monthlyRemaining,
    );
    final dailyPct = dailyLimitTotal <= 0
        ? 0.0
        : (dailyLimitUsed / dailyLimitTotal) * 100;

    return Scaffold(
      appBar: AppBar(
        title: AppTitle(
          subtitle: isAdmin ? 'لوحة التحكم (أدمن)' : 'لوحة التحكم',
        ),
        actions: [
          if (isAdmin)
            IconButton(
              tooltip: 'إعدادات الأدمن',
              icon: const Icon(Icons.settings),
              onPressed: () async {
                await Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const AdminSettingsScreen(),
                  ),
                );
              },
            ),
          IconButton(
            tooltip: 'تحديث',
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (_loading)
              const Center(
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: CircularProgressIndicator(),
                ),
              )
            else if (_error != null)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('حدث خطأ أثناء التحميل'),
                      const SizedBox(height: 8),
                      Text(_error!),
                      const SizedBox(height: 12),
                      ElevatedButton.icon(
                        onPressed: _load,
                        icon: const Icon(Icons.refresh),
                        label: const Text('إعادة المحاولة'),
                      ),
                    ],
                  ),
                ),
              )
            else if (s != null) ...[
              _heroCard(snap: s, isAdmin: isAdmin, license: license),
              const SizedBox(height: 10),
              _pendingSummaryTile(s),
              if (_lastUpdated != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    'آخر تحديث: ${_lastUpdated!.toLocal()}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),

              _sectionTitle(
                'الإجراءات السريعة',
                action: TextButton.icon(
                  onPressed: () => _openReorder(isAdmin),
                  icon: const Icon(Icons.tune),
                  label: const Text('ترتيب'),
                ),
              ),
              _actionGrid(_applyOrder(_actions(isAdmin), _actionOrder)),

              _sectionTitle('ملخصات سريعة'),
              _kpiCard(
                title: 'إجمالي السيولة المتاحة الآن',
                value: s.availableLiquidityNow.toStringAsFixed(2),
                icon: Icons.summarize,
                hint:
                    '\u0627\u0644\u062e\u0632\u0646\u0629 \u0627\u0644\u0641\u0639\u0644\u064a\u0629: ${s.actualTreasuryApproved.toStringAsFixed(2)}',
              ),
              if (today != null)
                _kpiCard(
                  title: 'مؤشرات اليوم',
                  value:
                      'ربح: ${s.dailyProfit.toStringAsFixed(2)} • عمليات: ${_opsCount(today.ops)}',
                  icon: Icons.insights,
                  hint:
                      'آجل اليوم: ${today.ops.pendingCount}\n'
                      'استهلاك الحد اليومي: ${dailyLimitUsed.toStringAsFixed(0)} / ${dailyLimitTotal.toStringAsFixed(0)} (${dailyPct.toStringAsFixed(0)}%)\n'
                      'متبقي الحدود الشهرية: ${monthlyRemaining.toStringAsFixed(0)}',
                ),
              _kpiCard(
                title: 'ربح الشهر',
                value: s.monthlyProfit.toStringAsFixed(2),
                icon: Icons.calendar_month,
                hint:
                    'صافي الربح بعد المصروفات: ${(s.monthlyProfit - _expensesTotalMonth).toStringAsFixed(2)}',
              ),
            ],
          ],
        ),
      ),
    );
  }

  List<QuickActionItem> _actions(bool isAdmin) {
    final snap = _snap;
    double? treasuryAvailable;
    double? claimsNet;
    if (snap != null) {
      treasuryAvailable =
          snap.drawerBalance + snap.walletsTotal + snap.fawryBalance;
      claimsNet = snap.claimsReceivableOpen - snap.claimsPayableOpen;
    }
    final customersNet = _customersReceivable - _customersPayable;

    String? netValue(double? value) => value?.abs().toStringAsFixed(2);
    String? netLabel(double? value) => value?.isNegative == true
        ? '\u0639\u0644\u064a\u0646\u0627'
        : (value?.isNegative == false ? '\u0644\u0646\u0627' : null);

    final items = <QuickActionItem>[
      QuickActionItem(
        id: 'help',
        title: 'شرح البرنامج',
        icon: Icons.help_outline,
        color: const Color(0xFF06B6D4),
        onTap: () {
          Navigator.of(
            context,
          ).push(MaterialPageRoute(builder: (_) => const HelpScreen()));
        },
      ),
      QuickActionItem(
        id: 'transfer',
        title: isAdmin ? 'تحويل' : 'تحويل (آجل)',
        icon: Icons.swap_horiz,
        color: const Color(0xFF14B8A6),
        onTap: () async {
          await Navigator.of(
            context,
          ).push(MaterialPageRoute(builder: (_) => const TransferScreen()));
          _load();
        },
      ),
      QuickActionItem(
        id: 'receive',
        title: isAdmin ? 'استلام' : 'استلام (آجل)',
        icon: Icons.call_received,
        color: const Color(0xFF1D4ED8),
        onTap: () async {
          await Navigator.of(
            context,
          ).push(MaterialPageRoute(builder: (_) => const ReceiveScreen()));
          _load();
        },
      ),
      /* QuickActionItem(
        id: 'fawry',
        title: 'خدمات فوري',
        icon: Icons.flash_on,
        color: const Color(0xFFF97316),
        onTap: () async {
          await Navigator.of(
            context,
          ).push(MaterialPageRoute(builder: (_) => const FawryScreen()));
          _load();
        },
      ),
      ), */
      QuickActionItem(
        id: 'wallets',
        title: 'المحافظ',
        icon: Icons.account_balance_wallet,
        color: const Color(0xFF64748B),
        valueText: snap?.walletsTotal.toStringAsFixed(2),
        metaText: snap == null
            ? null
            : '\u0625\u062c\u0645\u0627\u0644\u064a \u0627\u0644\u0645\u062d\u0627\u0641\u0638',
        onTap: () async {
          await Navigator.of(
            context,
          ).push(MaterialPageRoute(builder: (_) => const WalletsScreen()));
          _load();
        },
      ),
      QuickActionItem(
        id: 'customers',
        title: 'العملاء',
        icon: Icons.people_alt_outlined,
        color: const Color(0xFF0891B2),
        valueText: netValue(customersNet),
        metaText: netLabel(customersNet),
        onTap: () async {
          await Navigator.of(
            context,
          ).push(MaterialPageRoute(builder: (_) => const CustomersScreen()));
          _load();
        },
      ),
      QuickActionItem(
        id: 'treasury',
        title: 'الخزنة',
        icon: Icons.account_balance,
        color: const Color(0xFF0F172A),
        valueText: treasuryAvailable?.toStringAsFixed(2),
        metaText: snap == null
            ? null
            : '\u0627\u0644\u0645\u0648\u062c\u0648\u062f \u0627\u0644\u0622\u0646',
        onTap: () async {
          await Navigator.of(
            context,
          ).push(MaterialPageRoute(builder: (_) => const TreasuryScreen()));
          _load();
        },
      ),
      QuickActionItem(
        id: 'pending',
        title: 'الآجل',
        icon: Icons.pending_actions,
        color: const Color(0xFF0EA5E9),
        onTap: () async {
          await Navigator.of(
            context,
          ).push(MaterialPageRoute(builder: (_) => const PendingScreen()));
          _load();
        },
      ),
    ];

    if (isAdmin) {
      items.addAll([
        QuickActionItem(
          id: 'reports',
          title: 'التقارير',
          icon: Icons.analytics,
          color: const Color(0xFF10B981),
          onTap: () async {
            await Navigator.of(
              context,
            ).push(MaterialPageRoute(builder: (_) => const ReportsScreen()));
            _load();
          },
        ),
        QuickActionItem(
          id: 'expenses',
          title: 'المصروفات',
          icon: Icons.money_off_csred,
          color: const Color(0xFFEF4444),
          valueText: _expensesTotalAll.toStringAsFixed(2),
          metaText:
              '\u0627\u0644\u064a\u0648\u0645: ${_expensesTotalToday.toStringAsFixed(2)}',
          onTap: () async {
            final changed = await Navigator.of(context).push<bool>(
              MaterialPageRoute(builder: (_) => const ExpensesScreen()),
            );
            if (changed == true) _load();
          },
        ),
        QuickActionItem(
          id: 'claims',
          title: 'مستحقات',
          icon: Icons.request_quote,
          color: const Color(0xFF8B5CF6),
          valueText: netValue(claimsNet),
          metaText: netLabel(claimsNet),
          onTap: () async {
            await Navigator.of(
              context,
            ).push(MaterialPageRoute(builder: (_) => const ClaimsScreen()));
            _load();
          },
        ),
        QuickActionItem(
          id: 'wallet_funding',
          title: 'تمويل محفظة',
          icon: Icons.add_card,
          color: const Color(0xFF0F766E),
          onTap: () async {
            final changed = await Navigator.of(context).push<bool>(
              MaterialPageRoute(builder: (_) => const WalletFundingScreen()),
            );
            if (changed == true) _load();
          },
        ),
      ]);
    }

    return items;
  }
}

enum _DashboardFocus { treasury, pending }

class _ActionTile extends StatelessWidget {
  final QuickActionItem item;

  const _ActionTile({required this.item});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: item.onTap,
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              item.color.withValues(alpha: 0.18),
              item.color.withValues(alpha: 0.06),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: item.color.withValues(alpha: 0.2)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.03),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.8),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(item.icon, color: item.color, size: 18),
            ),
            const Spacer(),
            Text(
              item.title,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w700),
            ),
            if (item.valueText != null) ...[
              const SizedBox(height: 2),
              Text(
                item.valueText!,
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w800),
              ),
            ],
            if (item.metaText != null) ...[
              const SizedBox(height: 1),
              Text(
                item.metaText!,
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: Colors.black54),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
