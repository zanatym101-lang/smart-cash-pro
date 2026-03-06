import 'package:flutter/material.dart';

import '../data/app_db.dart';
import '../data/report_exporter.dart';
import '../data/reporting.dart';
import '../models/claim.dart';
import '../models/license_info.dart';
import '../models/transaction.dart';
import '../widgets/app_title.dart';

class CustomerReportScreen extends StatefulWidget {
  final String customerName;
  final String? customerPhone;

  const CustomerReportScreen({
    super.key,
    required this.customerName,
    this.customerPhone,
  });

  @override
  State<CustomerReportScreen> createState() => _CustomerReportScreenState();
}

class _CustomerReportScreenState extends State<CustomerReportScreen> {
  bool _loading = true;
  String? _error;
  String _period = 'today'; // today | month | custom
  DateRange? _customRange;
  int _dayStartHour = 0;
  LicenseInfo? _license;

  List<Txn> _allTxns = [];
  List<Claim> _allClaims = [];
  _CustomerStats? _stats;

  String _normalizeDigit(String ch) {
    switch (ch) {
      case '٠':
        return '0';
      case '١':
        return '1';
      case '٢':
        return '2';
      case '٣':
        return '3';
      case '٤':
        return '4';
      case '٥':
        return '5';
      case '٦':
        return '6';
      case '٧':
        return '7';
      case '٨':
        return '8';
      case '٩':
        return '9';
      default:
        return ch;
    }
  }

  String _normalizePhone(String input) {
    final buf = StringBuffer();
    for (final r in input.runes) {
      final raw = String.fromCharCode(r);
      final ch = _normalizeDigit(raw);
      final code = ch.codeUnitAt(0);
      if (code >= 48 && code <= 57) {
        buf.write(ch);
      }
    }
    return buf.toString();
  }

  String? _extractPhone(String? text) {
    if (text == null || text.trim().isEmpty) return null;
    final normalized = _normalizePhone(text);
    final m = RegExp(r'\d{10,15}').firstMatch(normalized);
    return m?.group(0);
  }

  int? _extractClaimIdFromNote(String? note) {
    if (note == null || note.trim().isEmpty) return null;
    final m = RegExp(r'claim_id:(\d+)').firstMatch(note);
    if (m == null) return null;
    return int.tryParse(m.group(1) ?? '');
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

  DateRange _activeRange() {
    if (_period == 'month') return _monthRange();
    if (_period == 'custom' && _customRange != null) return _customRange!;
    return _todayRange();
  }

  String _fmtDate(DateTime d) {
    final y = d.year.toString().padLeft(4, '0');
    final m = d.month.toString().padLeft(2, '0');
    final day = d.day.toString().padLeft(2, '0');
    return '$y-$m-$day';
  }

  bool _matchesName(String value) {
    return value.trim().toLowerCase() ==
        widget.customerName.trim().toLowerCase();
  }

  bool _matchesPhone(String? candidate) {
    final target = _normalizePhone(widget.customerPhone ?? '');
    if (target.isEmpty) return false;
    final current = _normalizePhone(candidate ?? '');
    return current.isNotEmpty && current == target;
  }

  bool _matchesTxn(Txn t) {
    final party = (t.party ?? '').trim();
    if (party.isNotEmpty && _matchesName(party)) return true;
    if (_matchesPhone(_extractPhone(party))) return true;
    if (_matchesPhone(_extractPhone(t.note))) return true;
    if (_matchesPhone(_extractPhone(t.reference))) return true;
    return false;
  }

  bool _matchesClaim(Claim c) {
    if (_matchesName(c.party)) return true;
    if (_matchesPhone(_extractPhone(c.party))) return true;
    if (_matchesPhone(_extractPhone(c.note))) return true;
    return false;
  }

  double _transferDue(Txn t) {
    if (t.mode == 'type2_v2') return t.amount + t.clientFee;
    return t.amount - t.networkFee;
  }

  double _receiveDue(Txn t) {
    if (t.mode == 'cash') return t.amount;
    if (t.mode == 'deduct') return (t.amount - t.clientFee).clamp(0, 1e18);
    return 0;
  }

  double _txnVolume(Txn t) {
    switch (t.kind) {
      case 'transfer':
        return _transferDue(t);
      case 'fawry_cash':
      case 'fawry_credit':
        return t.amount + t.clientFee;
      default:
        return t.amount;
    }
  }

  String _kindLabel(Txn t) {
    switch (t.kind) {
      case 'transfer':
        return 'تحويل';
      case 'receive':
        return 'استلام';
      case 'fawry_cash':
        return 'فوري نقدي';
      case 'fawry_credit':
        return 'فوري آجل';
      case 'claim_collect':
        return 'تحصيل مستحق';
      case 'claim_pay':
        return 'سداد مستحق';
      default:
        return t.kind;
    }
  }

  String _statusLabel(String status) {
    switch (status) {
      case 'posted':
        return 'منفذ';
      case 'pending':
        return 'معلق';
      case 'rolled_back':
        return 'ملغي';
      default:
        return status;
    }
  }

  String _claimOpenLabel(String type) {
    if (type == 'receivable') return 'فتح مستحق (لنا)';
    return 'فتح مستحق (علينا)';
  }

  String _statementLabelForTxn(Txn t) {
    if (t.kind == 'transfer' && t.status == 'pending') return 'تحويل معلق';
    if (t.kind == 'receive' && t.status == 'pending') return 'استلام معلق';
    if (t.kind == 'fawry_credit' && t.status == 'pending') {
      return 'فوري آجل معلق';
    }
    if (t.kind == 'claim_collect') return 'تحصيل مستحق';
    if (t.kind == 'claim_pay') return 'سداد مستحق';
    return _kindLabel(t);
  }

  String _statementDetailsForTxn(Txn t) {
    final parts = <String>[];
    final service = (t.serviceName ?? '').trim();
    if (service.isNotEmpty) {
      parts.add('الخدمة: $service');
    }
    final note = (t.note ?? '').trim();
    if (note.isNotEmpty) {
      parts.add(note);
    }
    parts.add('Txn#${t.id}');
    return parts.join(' | ');
  }

  int? _extractClaimIdFromRef(String? ref) {
    if (ref == null || ref.trim().isEmpty) return null;
    final m = RegExp(r'claim#?(\d+)', caseSensitive: false).firstMatch(ref);
    if (m == null) return null;
    return int.tryParse(m.group(1) ?? '');
  }

  String _claimStatusLabel(String status) {
    switch (status) {
      case 'open':
        return 'مفتوح';
      case 'closed':
        return 'مغلق';
      default:
        return status;
    }
  }

  String _statementDetailsForClaim(Claim c) {
    final parts = <String>[];
    final note = (c.note ?? '').trim();
    if (note.isNotEmpty) parts.add(note);
    parts.add('Claim#${c.id}');
    return parts.join(' | ');
  }

  bool _isReceivableByText(String? text) {
    final s = (text ?? '').toLowerCase();
    if (s.contains('receivable') || s.contains('لنا')) return true;
    if (s.contains('payable') || s.contains('علينا')) return false;
    return true;
  }

  _StatementEvent? _statementEventFromTxn(Txn t, Map<int, Claim> claimsById) {
    double delta = 0;
    String title = _statementLabelForTxn(t);

    final claimId =
        _extractClaimIdFromNote(t.note) ??
        _extractClaimIdFromNote(t.reference) ??
        _extractClaimIdFromRef(t.reference) ??
        _extractClaimIdFromRef(t.note);
    final linkedClaim = claimId == null ? null : claimsById[claimId];

    if (t.kind == 'claim_collect' || t.kind == 'claim_pay') {
      final bool isReceivable = linkedClaim != null
          ? linkedClaim.type == 'receivable'
          : _isReceivableByText(t.note);
      title = isReceivable ? 'تحصيل مستحق' : 'سداد مستحق';
      delta = isReceivable ? -t.amount.abs() : t.amount.abs();
    } else if (t.kind == 'transfer' && t.status == 'pending') {
      delta = _transferDue(t).abs();
      title = 'تحويل معلق';
    } else if (t.kind == 'receive' && t.status == 'pending') {
      delta = -_receiveDue(t).abs();
      title = 'استلام معلق';
    } else if (t.kind == 'fawry_credit' && t.status == 'pending') {
      if (linkedClaim != null) return null;
      delta = (t.amount + t.clientFee).abs();
      title = 'فوري آجل معلق';
    } else if (t.kind.startsWith('claim_open_')) {
      if (linkedClaim != null) return null;
      final isReceivable = _isReceivableByText(t.kind);
      title = isReceivable ? 'مستحق مفتوح (لنا)' : 'مستحق مفتوح (علينا)';
      delta = isReceivable ? t.amount.abs() : -t.amount.abs();
    }

    if (delta == 0) return null;
    return _StatementEvent(
      date: t.entryDate,
      sourceOrder: t.id,
      title: title,
      details: _statementDetailsForTxn(t),
      statusLabel: _statusLabel(t.status),
      amountSigned: delta,
    );
  }

  Future<void> _pickCustomRange() async {
    final now = DateTime.now();
    final res = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 5),
      lastDate: DateTime(now.year + 1),
      initialDateRange: _customRange == null
          ? DateTimeRange(start: now, end: now)
          : DateTimeRange(start: _customRange!.start, end: _customRange!.end),
    );
    if (res == null) return;
    final start = DateTime(res.start.year, res.start.month, res.start.day);
    final end = DateTime(
      res.end.year,
      res.end.month,
      res.end.day,
      23,
      59,
      59,
      999,
    );
    setState(() => _customRange = DateRange(start: start, end: end));
    await _load();
  }

  _CustomerStats _buildStats() {
    final range = _activeRange();
    final customerTxns = _allTxns.where(_matchesTxn).toList()
      ..sort((a, b) => a.entryDate.compareTo(b.entryDate));
    final txnsInRange =
        customerTxns.where((t) => range.contains(t.entryDate)).toList()
          ..sort((a, b) => b.entryDate.compareTo(a.entryDate));
    final customerClaims = _allClaims.where(_matchesClaim).toList();
    final claimsById = {for (final c in customerClaims) c.id: c};
    final openClaims = customerClaims.where((c) => c.status == 'open').toList();

    int postedCount = 0;
    int pendingCount = 0;
    double postedVolume = 0;
    double pendingVolume = 0;
    double postedProfit = 0;
    int transferCount = 0;
    int receiveCount = 0;
    int fawryCount = 0;

    double pendingReceivable = 0;
    double pendingPayable = 0;

    for (final t in txnsInRange) {
      if (t.kind == 'transfer') transferCount++;
      if (t.kind == 'receive') receiveCount++;
      if (t.kind == 'fawry_cash' || t.kind == 'fawry_credit') fawryCount++;

      final volume = _txnVolume(t);
      if (t.status == 'posted') {
        postedCount++;
        postedVolume += volume;
        if (t.clientFee > 0) postedProfit += t.clientFee;
      } else if (t.status == 'pending') {
        pendingCount++;
        pendingVolume += volume;

        if (t.kind == 'transfer') {
          final due = _transferDue(t);
          if (due > 0) pendingReceivable += due;
        } else if (t.kind == 'receive') {
          final due = _receiveDue(t);
          if (due > 0) pendingPayable += due;
        } else if (t.kind == 'fawry_credit') {
          final due = t.amount + t.clientFee;
          if (due > 0) pendingReceivable += due;
        }
      }
    }

    final statementEvents = <_StatementEvent>[
      ...customerClaims.map(
        (c) => _StatementEvent(
          date: c.entryDate,
          sourceOrder: c.id,
          title: _claimOpenLabel(c.type),
          details: _statementDetailsForClaim(c),
          statusLabel: _claimStatusLabel(c.status),
          amountSigned: c.type == 'receivable'
              ? c.amount.abs()
              : -c.amount.abs(),
        ),
      ),
    ];
    for (final t in customerTxns) {
      final event = _statementEventFromTxn(t, claimsById);
      if (event != null) statementEvents.add(event);
    }
    statementEvents.sort((a, b) {
      final byDate = a.date.compareTo(b.date);
      if (byDate != 0) return byDate;
      return a.sourceOrder.compareTo(b.sourceOrder);
    });

    double running = 0;
    double openingNet = 0;
    final statementAsc = <_CustomerStatementRow>[];
    for (final e in statementEvents) {
      if (e.date.isAfter(range.end)) break;
      running += e.amountSigned;
      if (e.date.isBefore(range.start)) {
        openingNet = running;
        continue;
      }
      statementAsc.add(
        _CustomerStatementRow(
          date: e.date,
          title: e.title,
          details: e.details,
          statusLabel: e.statusLabel,
          amountSigned: e.amountSigned,
          runningNet: running,
        ),
      );
    }
    final closingNet = running;
    final statementRows = statementAsc.reversed.toList(growable: false);

    final openReceivable = openClaims
        .where((c) => c.type == 'receivable')
        .fold<double>(0, (s, c) => s + c.amount);
    final openPayable = openClaims
        .where((c) => c.type == 'payable')
        .fold<double>(0, (s, c) => s + c.amount);

    return _CustomerStats(
      range: range,
      openReceivable: openReceivable,
      openPayable: openPayable,
      pendingReceivable: pendingReceivable,
      pendingPayable: pendingPayable,
      postedCount: postedCount,
      pendingCount: pendingCount,
      postedVolume: postedVolume,
      pendingVolume: pendingVolume,
      postedProfit: postedProfit,
      transferCount: transferCount,
      receiveCount: receiveCount,
      fawryCount: fawryCount,
      latestTxns: txnsInRange.take(25).toList(),
      openingNet: openingNet,
      closingNet: closingNet,
      statementRows: statementRows,
    );
  }

  CustomerReportExportData _toExportData(_CustomerStats stats) {
    return CustomerReportExportData(
      customerName: widget.customerName,
      customerPhone: widget.customerPhone ?? '',
      range: stats.range,
      receivable: stats.currentReceivable,
      payable: stats.currentPayable,
      net: stats.netCurrent,
      postedCount: stats.postedCount,
      pendingCount: stats.pendingCount,
      postedVolume: stats.postedVolume,
      pendingVolume: stats.pendingVolume,
      postedProfit: stats.postedProfit,
      transferCount: stats.transferCount,
      receiveCount: stats.receiveCount,
      fawryCount: stats.fawryCount,
      openingNet: stats.openingNet,
      closingNet: stats.closingNet,
      latestTxns: stats.latestTxns
          .map(
            (t) => CustomerTxnExportRow(
              date: t.entryDate,
              kind: _kindLabel(t),
              status: _statusLabel(t.status),
              amount: _txnVolume(t),
            ),
          )
          .toList(),
      statementRows: stats.statementRows
          .map(
            (r) => CustomerStatementExportRow(
              date: r.date,
              title: r.title,
              details: r.details,
              status: r.statusLabel,
              amountSigned: r.amountSigned,
              runningNet: r.runningNet,
              runningSideLabel: r.runningNet >= 0 ? 'لنا' : 'علينا',
            ),
          )
          .toList(),
    );
  }

  bool get _exportAllowed => (_license?.isActivated ?? true);

  Future<void> _exportPdf() async {
    if (!_exportAllowed) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('التصدير متاح بعد تفعيل النسخة')),
      );
      return;
    }
    final stats = _stats;
    if (stats == null) return;
    try {
      final path = await ReportExporter.exportCustomerPdf(
        data: _toExportData(stats),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('تم تصدير PDF: $path')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('فشل التصدير: $e')));
    }
  }

  Future<void> _exportExcel() async {
    if (!_exportAllowed) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('التصدير متاح بعد تفعيل النسخة')),
      );
      return;
    }
    final stats = _stats;
    if (stats == null) return;
    try {
      final path = await ReportExporter.exportCustomerExcel(
        data: _toExportData(stats),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('تم تصدير Excel: $path')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('فشل التصدير: $e')));
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final settings = await AppDb.instance.getAppSettings();
      _license = await AppDb.instance.getLicenseInfo();
      _dayStartHour = settings.dayStartHour;
      _allTxns = await AppDb.instance.listTxns();
      _allClaims = await AppDb.instance.listClaims();
      _stats = _buildStats();
    } catch (e) {
      _error = e.toString();
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final stats = _stats;
    final range = stats?.range ?? _activeRange();

    return Scaffold(
      appBar: AppBar(
        title: const AppTitle(subtitle: 'تقرير عميل'),
        actions: [
          IconButton(
            tooltip: 'تحديث',
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
          PopupMenuButton<String>(
            onSelected: (v) {
              if (v == 'pdf') {
                _exportPdf();
              } else if (v == 'excel') {
                _exportExcel();
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'pdf', child: Text('تصدير PDF')),
              PopupMenuItem(value: 'excel', child: Text('تصدير Excel')),
            ],
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(child: Text('خطأ: $_error'))
          : stats == null
          ? const SizedBox.shrink()
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              children: [
                _headerCard(stats, range),
                const SizedBox(height: 12),
                _kpiCard(
                  title: 'الموقف الحالي',
                  lines: [
                    'لنا: ${(stats.currentReceivable).toStringAsFixed(2)}',
                    'علينا: ${(stats.currentPayable).toStringAsFixed(2)}',
                    'الصافي: ${stats.netCurrent.abs().toStringAsFixed(2)} ${stats.netCurrent >= 0 ? '(لنا)' : '(علينا)'}',
                    'رصيد افتتاحي: ${stats.openingNet.abs().toStringAsFixed(2)} ${stats.openingNet >= 0 ? '(لنا)' : '(علينا)'}',
                    'رصيد ختامي: ${stats.closingNet.abs().toStringAsFixed(2)} ${stats.closingNet >= 0 ? '(لنا)' : '(علينا)'}',
                  ],
                ),
                _kpiCard(
                  title: 'حركة الفترة',
                  lines: [
                    'منفذ: ${stats.postedCount} • حجم ${stats.postedVolume.toStringAsFixed(2)}',
                    'معلق: ${stats.pendingCount} • حجم ${stats.pendingVolume.toStringAsFixed(2)}',
                    'ربح منفذ من العميل: ${stats.postedProfit.toStringAsFixed(2)}',
                  ],
                ),
                _kpiCard(
                  title: 'تفصيل العمليات',
                  lines: [
                    'تحويل: ${stats.transferCount}',
                    'استلام: ${stats.receiveCount}',
                    'فوري: ${stats.fawryCount}',
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  'كشف حساب الفترة',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                if (stats.statementRows.isEmpty)
                  const Card(
                    child: ListTile(
                      title: Text(
                        'لا توجد حركات تؤثر على الرصيد في الفترة المختارة',
                      ),
                    ),
                  )
                else
                  ...stats.statementRows.map(_statementCard),
              ],
            ),
    );
  }

  Widget _statementCard(_CustomerStatementRow row) {
    final d = row.date;
    final date =
        '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
    final signed = row.amountSigned;
    final amountText =
        '${signed >= 0 ? '+' : '-'}${signed.abs().toStringAsFixed(2)}';
    final amountColor = signed >= 0 ? Colors.teal : Colors.redAccent;
    final running = row.runningNet;
    final side = running >= 0 ? 'لنا' : 'علينا';

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    row.title,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: amountColor.withAlpha(30),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    amountText,
                    style: TextStyle(
                      color: amountColor,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(date, style: Theme.of(context).textTheme.bodySmall),
            if (row.details?.trim().isNotEmpty == true) ...[
              const SizedBox(height: 4),
              Text(row.details!),
            ],
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                Chip(label: Text(row.statusLabel)),
                Chip(
                  label: Text(
                    'المتبقي: ${running.abs().toStringAsFixed(2)} ($side)',
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _headerCard(_CustomerStats stats, DateRange range) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF0F172A), Color(0xFF1E293B)],
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
        ),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.customerName,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'الهاتف: ${widget.customerPhone?.trim().isNotEmpty == true ? widget.customerPhone : 'غير مسجل'}',
            style: const TextStyle(color: Colors.white70),
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
                  setState(() => _period = 'today');
                  await _load();
                },
              ),
              ChoiceChip(
                label: const Text('الشهر'),
                selected: _period == 'month',
                onSelected: (_) async {
                  setState(() => _period = 'month');
                  await _load();
                },
              ),
              ChoiceChip(
                label: const Text('مخصص'),
                selected: _period == 'custom',
                onSelected: (_) async {
                  setState(() => _period = 'custom');
                  await _pickCustomRange();
                },
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'الفترة: من ${_fmtDate(range.start)} إلى ${_fmtDate(range.end)}',
            style: const TextStyle(color: Colors.white70),
          ),
        ],
      ),
    );
  }

  Widget _kpiCard({required String title, required List<String> lines}) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            ...lines.map(
              (l) => Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(l),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CustomerStats {
  final DateRange range;
  final double openReceivable;
  final double openPayable;
  final double pendingReceivable;
  final double pendingPayable;
  final int postedCount;
  final int pendingCount;
  final double postedVolume;
  final double pendingVolume;
  final double postedProfit;
  final int transferCount;
  final int receiveCount;
  final int fawryCount;
  final List<Txn> latestTxns;
  final double openingNet;
  final double closingNet;
  final List<_CustomerStatementRow> statementRows;

  const _CustomerStats({
    required this.range,
    required this.openReceivable,
    required this.openPayable,
    required this.pendingReceivable,
    required this.pendingPayable,
    required this.postedCount,
    required this.pendingCount,
    required this.postedVolume,
    required this.pendingVolume,
    required this.postedProfit,
    required this.transferCount,
    required this.receiveCount,
    required this.fawryCount,
    required this.latestTxns,
    required this.openingNet,
    required this.closingNet,
    required this.statementRows,
  });

  double get currentReceivable => openReceivable + pendingReceivable;
  double get currentPayable => openPayable + pendingPayable;
  double get netCurrent => currentReceivable - currentPayable;
}

class _StatementEvent {
  final DateTime date;
  final int sourceOrder;
  final String title;
  final String? details;
  final String statusLabel;
  final double amountSigned;

  const _StatementEvent({
    required this.date,
    required this.sourceOrder,
    required this.title,
    this.details,
    required this.statusLabel,
    required this.amountSigned,
  });
}

class _CustomerStatementRow {
  final DateTime date;
  final String title;
  final String? details;
  final String statusLabel;
  final double amountSigned;
  final double runningNet;

  const _CustomerStatementRow({
    required this.date,
    required this.title,
    this.details,
    required this.statusLabel,
    required this.amountSigned,
    required this.runningNet,
  });
}
