// Dashboard: KPIs + navigation (admin-aware)
import 'package:flutter/material.dart';
import '../config/app_env.dart';
import '../data/app_db.dart';
import '../data/app_session.dart';
import '../data/reporting.dart';
import '../models/app_settings.dart';
import '../models/claim.dart';
import '../models/license_info.dart';
import '../models/quick_action_item.dart';
import '../models/transaction.dart';

import 'package:flutter/services.dart';
import '../ai_sms/sms_inbox_screen.dart';
import '../ai_sms/models/parsed_transaction_draft.dart';
import '../ai_sms/sms_review_screen.dart';
import '../ai_sms/customer_matching_service.dart';
import '../services/sms_parser.dart';
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
import 'monther_chat_screen.dart';

bool shouldShowSmsImportAction() => enableSms;

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => DashboardScreenState();
}

class DashboardScreenState extends State<DashboardScreen> with WidgetsBindingObserver {
  String? _lastProcessedClipboard;
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
  double _pendingOpenReceivable = 0;
  double _pendingOpenPayable = 0;
  double _expensesTotalAll = 0;
  double _expensesTotalToday = 0;
  double _expensesTotalMonth = 0;
  int _pendingDueTodayCount = 0;
  int _pendingOverdueCount = 0;

  String _formatLastUpdated(DateTime dt) {
    final hour12 = dt.hour == 0 ? 12 : (dt.hour > 12 ? dt.hour - 12 : dt.hour);
    final minute = dt.minute.toString().padLeft(2, '0');
    final period = dt.hour >= 12 ? 'م' : 'ص';
    return '${hour12.toString().padLeft(2, '0')}:$minute $period';
  }

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

  int? _extractPendingSettlementRef(String? note) {
    if (note == null || note.trim().isEmpty) return null;
    final m = RegExp(r'pending_txn:(\d+)').firstMatch(note);
    if (m == null) return null;
    return int.tryParse(m.group(1) ?? '');
  }

  Map<int, double> _pendingSettledByTxn(List<Txn> txns) {
    final settled = <int, double>{};
    for (final t in txns) {
      if (t.status != 'posted') continue;
      if (t.kind != 'claim_collect' && t.kind != 'claim_pay') continue;
      final pendingTxnId = _extractPendingSettlementRef(t.note);
      if (pendingTxnId == null) continue;
      settled[pendingTxnId] = (settled[pendingTxnId] ?? 0) + t.amount;
    }
    return settled;
  }

  ({double receivable, double payable}) _pendingOpenTotals({
    required List<Txn> txns,
    required Map<int, double> settledByPending,
  }) {
    double receivable = 0;
    double payable = 0;

    for (final t in txns) {
      if (t.status != 'pending') continue;
      if (t.kind == 'transfer') {
        final due = (_pendingTransferDue(t) - (settledByPending[t.id] ?? 0))
            .clamp(0, 1e18)
            .toDouble();
        if (due > 0) receivable += due;
      } else if (t.kind == 'receive') {
        final due = (_pendingReceiveDue(t) - (settledByPending[t.id] ?? 0))
            .clamp(0, 1e18)
            .toDouble();
        if (due > 0) payable += due;
      } else if (t.kind == 'fawry_credit') {
        final due = (t.amount + t.clientFee - (settledByPending[t.id] ?? 0))
            .clamp(0, 1e18)
            .toDouble();
        if (due > 0) receivable += due;
      }
    }

    return (receivable: receivable, payable: payable);
  }

  ({double receivable, double payable}) _customerTotals({
    required List<Txn> txns,
    required List<Claim> claims,
    required Map<int, double> settledByPending,
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
        final due = (_pendingTransferDue(t) - (settledByPending[t.id] ?? 0))
            .clamp(0, 1e18)
            .toDouble();
        if (due > 0) receivable += due;
      } else if (t.kind == 'receive') {
        final due = (_pendingReceiveDue(t) - (settledByPending[t.id] ?? 0))
            .clamp(0, 1e18)
            .toDouble();
        if (due > 0) payable += due;
      } else if (t.kind == 'fawry_credit') {
        final due = (t.amount + t.clientFee - (settledByPending[t.id] ?? 0))
            .clamp(0, 1e18)
            .toDouble();
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
      final settledByPending = _pendingSettledByTxn(txns);
      final customerTotals = _customerTotals(
        txns: txns,
        claims: claims,
        settledByPending: settledByPending,
      );
      final pendingOpenTotals = _pendingOpenTotals(
        txns: txns,
        settledByPending: settledByPending,
      );
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
        _pendingOpenReceivable = pendingOpenTotals.receivable;
        _pendingOpenPayable = pendingOpenTotals.payable;
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
    WidgetsBinding.instance.addObserver(this);
    _load();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkClipboardForSms();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkClipboardForSms();
    }
  }

  @visibleForTesting
  Future<void> handleSmsDraftReview(ParsedTransactionDraft initialDraft) =>
      _handleSmsDraftReview(initialDraft);

  Future<void> _handleSmsDraftReview(ParsedTransactionDraft initialDraft) async {
    try {
      // 1. Auto-Match Customer: Look up customer in AppDb by phone number
      final draftWithMatchedCustomer = await SmsParser.autoMatchCustomer(initialDraft);
      final phone = SmsParser.extractPhone(
        '${draftWithMatchedCustomer.customerName ?? ''} ${draftWithMatchedCustomer.note ?? ''} ${draftWithMatchedCustomer.rawMessage}',
      );
      final customerFound = phone != null &&
          await SmsParser.lookupCustomerByPhone(phone) != null;

      // Load wallet options
      final wallets = await AppDb.instance.listWallets();
      final walletOptions = wallets
          .map(
            (w) => SmsReviewWalletOption(
              id: w.id,
              name: w.name,
              phone: w.phone,
            ),
          )
          .toList(growable: false);

      final candidates = await AppDb.instance.listCustomerCandidates();
      final customerMatchSuggestion = const CustomerMatchingService().suggest(
        draft: draftWithMatchedCustomer,
        existingCustomers: candidates,
      );

      if (!mounted) return;
      final reviewedDraft = await Navigator.of(context).push<ParsedTransactionDraft>(
        MaterialPageRoute(
          builder: (_) => SmsReviewScreen(
            draft: draftWithMatchedCustomer,
            walletOptions: walletOptions,
            customerMatchSuggestion: customerMatchSuggestion,
          ),
        ),
      );

      if (!mounted || reviewedDraft == null) return;

      // Execute transaction into AppDb
      final walletId = reviewedDraft.walletId ?? (walletOptions.isNotEmpty ? walletOptions.first.id : null);
      final draftAmount = reviewedDraft.amount;
      if (walletId != null && draftAmount != null && draftAmount > 0) {
        final isPending = reviewedDraft.transactionMode == TransactionMode.deferred;
        if (reviewedDraft.operationType == ParsedOperationType.transfer) {
          await AppDb.instance.addTransfer(
            walletId: walletId,
            amount: draftAmount,
            clientFee: 0,
            networkFee: 0,
            transferType: 'type1',
            isPending: isPending,
            party: reviewedDraft.customerName,
            note: reviewedDraft.note,
          );
        } else if (reviewedDraft.operationType == ParsedOperationType.receive) {
          await AppDb.instance.addReceive(
            walletId: walletId,
            amount: draftAmount,
            commission: 0,
            receiveType: 'cash',
            isPending: isPending,
            party: reviewedDraft.customerName,
            note: reviewedDraft.note,
          );
        }
      }

      await _load();
      if (!mounted) return;

      // If customer was not found in AppDb and we have a phone number, offer one-tap save
      if (!customerFound && phone != null && phone.isNotEmpty) {
        _showSaveCustomerDialog(phone, reviewedDraft.customerName);
      }

      // 2. WhatsApp Receipt Button: On transaction confirmation from SMS, provide direct option to launch WhatsApp
      final opName = reviewedDraft.operationType == ParsedOperationType.receive ? 'الاستلام' : 'التحويل';
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 10),
          backgroundColor: const Color(0xFF0F172A),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          content: Row(
            children: [
              const Icon(Icons.check_circle, color: Color(0xFF10B981), size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'تم تسجيل $opName (${reviewedDraft.amount} ج)',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.white),
                ),
              ),
            ],
          ),
          action: SnackBarAction(
            label: 'إيصال واتساب 💬',
            textColor: const Color(0xFF38BDF8),
            onPressed: () {
              SmsParser.launchWhatsAppReceipt(reviewedDraft);
            },
          ),
        ),
      );
    } catch (e, st) {
      debugPrint('ERROR in _handleSmsDraftReview: $e\n$st');
    }
  }

  void _showSaveCustomerDialog(String phone, String? currentName) {
    final nameCtrl = TextEditingController(
      text: (currentName != null && currentName != phone) ? currentName : '',
    );
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.person_add, color: Color(0xFF0284C7)),
            SizedBox(width: 8),
            Text('حفظ العميل في الحسابات', style: TextStyle(fontSize: 16)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('الرقم: $phone', style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            TextField(
              controller: nameCtrl,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'اسم العميل',
                hintText: 'أدخل اسم العميل',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('تخطي'),
          ),
          ElevatedButton.icon(
            onPressed: () async {
              final name = nameCtrl.text.trim();
              if (name.isNotEmpty) {
                await SmsParser.saveCustomer(phone: phone, name: name);
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('تم حفظ العميل $name بنجاح')),
                  );
                }
              }
              if (ctx.mounted) Navigator.of(ctx).pop();
            },
            icon: const Icon(Icons.save),
            label: const Text('حفظ بنقرة واحدة'),
          ),
        ],
      ),
    );
  }

  Future<void> _checkClipboardForSms() async {
    try {
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      final text = data?.text?.trim();
      if (text == null || text.isEmpty || text == _lastProcessedClipboard) {
        return;
      }
      if (text.length < 15 || text.length > 500) return;

      final parsed = SmsParser.parseText(text, sender: 'Clipboard');
      if (parsed.draft.amount != null && parsed.draft.operationType != ParsedOperationType.unknown) {
        _lastProcessedClipboard = text;
        if (!mounted) return;
        
        final opName = parsed.draft.operationType == ParsedOperationType.receive ? 'استلام' : 'تحويل';
        final providerName = parsed.draft.provider ?? 'محفظة';
        final amount = parsed.draft.amount!;

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            duration: const Duration(seconds: 8),
            backgroundColor: const Color(0xFF0F172A),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            content: Row(
              children: [
                const Icon(Icons.auto_awesome, color: Color(0xFF38BDF8), size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'رسالة $providerName: $opName $amount ج',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.white),
                  ),
                ),
              ],
            ),
            action: SnackBarAction(
              label: 'تسجيل القيد ⚡',
              textColor: const Color(0xFF38BDF8),
              onPressed: () {
                ScaffoldMessenger.of(context).hideCurrentSnackBar();
                _handleSmsDraftReview(parsed.draft);
              },
            ),
          ),
        );
      }
    } catch (_) {}
  }

  Future<void> _pasteAndReviewSms() async {
    try {
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      final text = data?.text?.trim();
      if (text != null && text.isNotEmpty) {
        final parsed = SmsParser.parseText(text, sender: 'Clipboard');
        if (parsed.draft.amount != null) {
          if (!mounted) return;
          await _handleSmsDraftReview(parsed.draft);
          return;
        }
      }
    } catch (_) {}

    // If clipboard is empty or unparsed, show paste dialog
    if (!mounted) return;
    final ctrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.auto_awesome, color: Color(0xFF0284C7)),
            SizedBox(width: 8),
            Text('تحليل رسالة محفظة ذكياً'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('الصق نص رسالة التحويل أو الاستلام هنا:', style: TextStyle(fontSize: 13)),
            const SizedBox(height: 10),
            TextField(
              controller: ctrl,
              maxLines: 4,
              decoration: const InputDecoration(
                hintText: 'مثال: تم تحويل 500 جنيه لرقم 010... رقم العملية: 123456',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('إلغاء'),
          ),
          ElevatedButton.icon(
            onPressed: () {
              final raw = ctrl.text.trim();
              if (raw.isEmpty) return;
              Navigator.of(ctx).pop();
              final parsed = SmsParser.parseText(raw, sender: 'Manual');
              _handleSmsDraftReview(parsed.draft);
            },
            icon: const Icon(Icons.bolt),
            label: const Text('تحليل القيد فوراً'),
          ),
        ],
      ),
    );
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
    final pendingOpenTotal = _pendingOpenReceivable + _pendingOpenPayable;
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
            Text('إجمالي القيمة: ${pendingOpenTotal.toStringAsFixed(2)}'),
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
    final pendingIn = _pendingOpenPayable;
    final pendingOut = _pendingOpenReceivable;
    final pendingTotal = pendingIn + pendingOut;
    final pendingDiff = pendingOut - pendingIn;
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
                        builder: (_) => const MontherChatScreen(),
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
                ? 'إجمالي المتبقي المفتوح في الآجل'
                : 'إجمالي السيولة المتاحة الآن',
            style: const TextStyle(color: Colors.white70, fontSize: 14),
          ),
          const SizedBox(height: 6),
          Text(
            focusPending
                ? pendingTotal.toStringAsFixed(2)
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
              const SizedBox(height: 6),
              _darkRow('رأس المال الحقيقي (معتمد)', realCapitalApproved),
            ],
          ] else ...[
            _darkRow('داخل الآجل', pendingIn),
            _darkRow('خارج الآجل', pendingOut),
            const SizedBox(height: 6),
            _darkRow('الفرق ($pendingDiffLabel)', pendingDiffAbs),
            const SizedBox(height: 6),
            const Text(
              'المعروض هنا هو المتبقي المفتوح بعد أي تحصيل أو سداد جزئي.',
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
        int cross = 3;
        if (width >= 900) {
          cross = 6;
        } else if (width >= 600) {
          cross = 4;
        } else {
          cross = 3;
        }

        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: cross,
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
            childAspectRatio: 1.1,
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
          IconButton(
            tooltip: 'لصق وتحليل رسالة محفظة ⚡',
            icon: const Icon(Icons.content_paste_go, color: Color(0xFF38BDF8)),
            onPressed: _pasteAndReviewSms,
          ),
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
                    'آخر تحديث: ${_formatLastUpdated(_lastUpdated!.toLocal())}',
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
      if (shouldShowSmsImportAction())
        QuickActionItem(
          id: 'sms_import',
          title: 'استيراد من الرسائل',
          icon: Icons.sms_outlined,
          color: const Color(0xFF7C3AED),
          onTap: () async {
            final changed = await Navigator.of(context).push<bool>(
              MaterialPageRoute(builder: (_) => SmsInboxScreen.withDefaults()),
            );
            if (changed == true) {
              _load();
            }
          },
        ),
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
        color: const Color(0xFFEA580C),
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
        color: const Color(0xFF16A34A),
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
    final isTransfer = item.id == 'transfer';
    final isReceive = item.id == 'receive';
    final isProminent = isTransfer || isReceive;

    final LinearGradient cardGradient;
    final LinearGradient? badgeGradient;
    final Color badgeBg;
    final Color iconColor;
    final double borderWidth;
    final Color borderColor;
    final List<BoxShadow> shadows;

    if (isTransfer) {
      cardGradient = LinearGradient(
        colors: [
          const Color(0xFFEA580C).withValues(alpha: 0.15),
          const Color(0xFFDC2626).withValues(alpha: 0.04),
        ],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      );
      badgeGradient = const LinearGradient(
        colors: [Color(0xFFEA580C), Color(0xFFDC2626)],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      );
      badgeBg = const Color(0xFFEA580C);
      iconColor = Colors.white;
      borderWidth = 1.5;
      borderColor = const Color(0xFFEA580C).withValues(alpha: 0.40);
      shadows = [
        BoxShadow(
          color: const Color(0xFFEA580C).withValues(alpha: 0.15),
          blurRadius: 10,
          offset: const Offset(0, 3),
        ),
      ];
    } else if (isReceive) {
      cardGradient = LinearGradient(
        colors: [
          const Color(0xFF16A34A).withValues(alpha: 0.15),
          const Color(0xFF059669).withValues(alpha: 0.04),
        ],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      );
      badgeGradient = const LinearGradient(
        colors: [Color(0xFF16A34A), Color(0xFF059669)],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      );
      badgeBg = const Color(0xFF16A34A);
      iconColor = Colors.white;
      borderWidth = 1.5;
      borderColor = const Color(0xFF16A34A).withValues(alpha: 0.40);
      shadows = [
        BoxShadow(
          color: const Color(0xFF16A34A).withValues(alpha: 0.15),
          blurRadius: 10,
          offset: const Offset(0, 3),
        ),
      ];
    } else {
      cardGradient = LinearGradient(
        colors: [
          item.color.withValues(alpha: 0.10),
          item.color.withValues(alpha: 0.02),
        ],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      );
      badgeGradient = null;
      badgeBg = item.color.withValues(alpha: 0.12);
      iconColor = item.color;
      borderWidth = 1.0;
      borderColor = item.color.withValues(alpha: 0.18);
      shadows = [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.03),
          blurRadius: 8,
          offset: const Offset(0, 2),
        ),
      ];
    }

    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: item.onTap,
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          gradient: cardGradient,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: borderColor, width: borderWidth),
          boxShadow: shadows,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: badgeGradient == null ? badgeBg : null,
                gradient: badgeGradient,
                borderRadius: BorderRadius.circular(10),
                border: badgeGradient == null
                    ? Border.all(
                        color: item.color.withValues(alpha: 0.20),
                        width: 1,
                      )
                    : null,
                boxShadow: isProminent
                    ? [
                        BoxShadow(
                          color: (isTransfer
                                  ? const Color(0xFFEA580C)
                                  : const Color(0xFF16A34A))
                              .withValues(alpha: 0.35),
                          blurRadius: 6,
                          offset: const Offset(0, 2),
                        ),
                      ]
                    : null,
              ),
              child: Icon(item.icon, color: iconColor, size: 18),
            ),
            const SizedBox(height: 8),
            Text(
              item.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                fontWeight: isProminent ? FontWeight.w800 : FontWeight.w700,
                color: isProminent
                    ? (isTransfer
                        ? const Color(0xFFC2410C)
                        : const Color(0xFF15803D))
                    : null,
              ),
            ),
            if (item.valueText != null) ...[
              const SizedBox(height: 2),
              Text(
                item.valueText!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w800),
              ),
            ],
            if (item.metaText != null) ...[
              const SizedBox(height: 1),
              Text(
                item.metaText!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
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