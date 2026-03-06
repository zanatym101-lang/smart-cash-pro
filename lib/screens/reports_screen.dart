import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:open_filex/open_filex.dart';
import 'package:printing/printing.dart';
import 'package:url_launcher/url_launcher.dart';
import '../widgets/app_title.dart';
import '../data/app_db.dart';
import '../data/app_session.dart';
import '../data/report_exporter.dart';
import '../data/reporting.dart';
import '../models/claim.dart';
import '../models/daily_close.dart';
import '../models/transaction.dart';
import '../models/license_info.dart';

class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key});

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  bool _loading = true;
  String? _error;

  String _period = 'today'; // today | month | custom
  DateRange? _customRange;
  int _dayStartHour = 0;

  List<Txn> _txns = [];
  List<Claim> _claims = [];
  List<DailyClose> _closes = [];
  TreasurySnapshot? _treasury;
  ReportData? _report;
  SmartInsights? _smart;
  LicenseInfo? _license;

  DateTime _closeDate = DateTime.now();

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
    setState(() {
      _customRange = DateRange(start: start, end: end);
    });
    await _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final settings = await AppDb.instance.getAppSettings();
      _dayStartHour = settings.dayStartHour;
      _txns = await AppDb.instance.listTxns();
      _txns.sort((a, b) {
        final c = b.entryDate.compareTo(a.entryDate);
        if (c != 0) return c;
        return b.id.compareTo(a.id);
      });
      _claims = await AppDb.instance.listClaims();
      _closes = await AppDb.instance.listDailyCloses();
      _closes.sort((a, b) => b.dateKey.compareTo(a.dateKey));
      _treasury = await AppDb.instance.getTreasurySnapshot();
      _report = ReportCalculator.build(
        txns: _txns,
        claims: _claims,
        range: _activeRange(),
      );
      _smart = ReportCalculator.buildSmart(txns: _txns, range: _activeRange());
    } catch (e) {
      _error = e.toString();
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _exportPdf() async {
    final report = _report;
    final treasury = _treasury;
    if (report == null || treasury == null) return;
    try {
      final path = await ReportExporter.exportPdf(
        data: report,
        treasury: treasury,
        range: _activeRange(),
      );
      if (!mounted) return;
      await _openExportedFile(path: path, typeLabel: 'PDF');
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '\u0641\u0634\u0644 \u0627\u0644\u062a\u0635\u062f\u064a\u0631: $e',
          ),
        ),
      );
    }
  }

  Future<void> _exportExcel() async {
    final report = _report;
    final treasury = _treasury;
    if (report == null || treasury == null) return;
    try {
      final path = await ReportExporter.exportExcel(
        data: report,
        treasury: treasury,
        range: _activeRange(),
      );
      if (!mounted) return;
      await _openExportedFile(path: path, typeLabel: 'Excel');
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '\u0641\u0634\u0644 \u0627\u0644\u062a\u0635\u062f\u064a\u0631: $e',
          ),
        ),
      );
    }
  }

  Future<void> _openExportedFile({
    required String path,
    required String typeLabel,
  }) async {
    final ok = await _openFileViaSystem(path);
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    if (ok) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            '\u062a\u0645 \u062a\u0635\u062f\u064a\u0631 $typeLabel \u0648\u0641\u062a\u062d \u0627\u0644\u0645\u0644\u0641 \u0645\u0628\u0627\u0634\u0631\u0629',
          ),
        ),
      );
      return;
    }

    messenger.showSnackBar(
      SnackBar(
        content: Text(
          '\u062a\u0645 \u0627\u0644\u062a\u0635\u062f\u064a\u0631: $path',
        ),
      ),
    );
  }

  Future<bool> _openFileViaSystem(String path) async {
    final result = await OpenFilex.open(path);
    return result.type == ResultType.done;
  }

  Future<List<File>> _listExportedFiles() async {
    final dir = await ReportExporter.exportDirectory();
    final files = <File>[];
    await for (final entity in dir.list()) {
      if (entity is! File) continue;
      final path = entity.path.toLowerCase();
      if (path.endsWith('.pdf') ||
          path.endsWith('.xlsx') ||
          path.endsWith('.csv')) {
        files.add(entity);
      }
    }
    files.sort((a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()));
    return files;
  }

  Future<void> _showExportsSheet() async {
    final dir = await ReportExporter.exportDirectory();
    final files = await _listExportedFiles();
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'ملفات التقارير',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
              ),
              const SizedBox(height: 6),
              SelectableText(
                dir.path,
                style: const TextStyle(fontSize: 12, color: Colors.black54),
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: () async {
                    await Clipboard.setData(ClipboardData(text: dir.path));
                    if (!ctx.mounted) return;
                    ScaffoldMessenger.of(ctx).showSnackBar(
                      const SnackBar(content: Text('تم نسخ المسار')),
                    );
                  },
                  icon: const Icon(Icons.copy, size: 16),
                  label: const Text('نسخ المسار'),
                ),
              ),
              const Divider(),
              if (files.isEmpty)
                const Padding(
                  padding: EdgeInsets.only(bottom: 12),
                  child: Text('لا توجد ملفات تقارير بعد.'),
                )
              else
                Flexible(
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: files.length,
                    itemBuilder: (_, i) {
                      final f = files[i];
                      final name = f.uri.pathSegments.isNotEmpty
                          ? f.uri.pathSegments.last
                          : f.path;
                      return ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.insert_drive_file_outlined),
                        title: Text(
                          name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          f.lastModifiedSync().toString(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        onTap: () async {
                          final ok = await _openFileViaSystem(f.path);
                          if (!ok && ctx.mounted) {
                            ScaffoldMessenger.of(ctx).showSnackBar(
                              const SnackBar(
                                content: Text('تعذر فتح الملف من النظام'),
                              ),
                            );
                          }
                        },
                      );
                    },
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openExportsFolder() async {
    try {
      final dir = await ReportExporter.exportDirectory();
      final ok = await launchUrl(
        Uri.directory(dir.path),
        mode: LaunchMode.externalApplication,
      );
      if (!ok) {
        await _showExportsSheet();
      }
    } catch (_) {
      await _showExportsSheet();
    }
  }

  Future<void> _printLatestPdf() async {
    try {
      final files = await _listExportedFiles();
      final pdfs = files
          .where((f) => f.path.toLowerCase().endsWith('.pdf'))
          .toList();
      if (pdfs.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('لا يوجد PDF للطباعة بعد')),
        );
        return;
      }
      final latest = pdfs.first;
      final bytes = await latest.readAsBytes();
      await Printing.layoutPdf(
        name: latest.uri.pathSegments.isNotEmpty
            ? latest.uri.pathSegments.last
            : 'report.pdf',
        onLayout: (_) async => bytes,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('فشل الطباعة: $e')));
    }
  }

  Future<void> _closeDay() async {
    if (!AppSession.isAdmin) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('هذه الصفحة للأدمن فقط')));
      return;
    }
    try {
      await AppDb.instance.closeDaily(_closeDate);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('تم إغلاق اليوم ✅')));
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('خطأ: $e')));
    }
  }

  Future<void> _reopenDay() async {
    if (!AppSession.isAdmin) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('هذه الصفحة للأدمن فقط')));
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('إلغاء إغلاق اليوم'),
        content: const Text(
          'سيتم فتح اليوم مرة أخرى للسماح بإضافة أو تعديل العمليات.\n'
          'لن يُسمح بالإلغاء إذا كانت هناك عمليات بعد وقت الإغلاق.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('تأكيد الإلغاء'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    try {
      await AppDb.instance.reopenDaily(_closeDate);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('تم إلغاء إغلاق اليوم ✅')));
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('خطأ: $e')));
    }
  }

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final info = await AppDb.instance.getLicenseInfo();
      _license = info;
      if (!info.isActivated) {
        final ok = await AppDb.instance.consumeReportView();
        if (!ok) {
          setState(() {
            _loading = false;
            _error = 'نسخة تجريبية: تم استهلاك عدد التقارير المسموح (3)';
          });
          return;
        }
      }
    } catch (e) {
      setState(() {
        _loading = false;
        _error = 'خطأ في الترخيص: $e';
      });
      return;
    }

    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final report = _report;
    final treasury = _treasury;
    final range = _activeRange();
    final license = _license;

    return DefaultTabController(
      length: 9,
      child: Scaffold(
        appBar: AppBar(
          title: const AppTitle(subtitle: 'التقارير'),
          actions: [
            IconButton(
              tooltip: 'تحديث',
              onPressed: _loading ? null : _load,
              icon: const Icon(Icons.refresh),
            ),
            if ((license?.isActivated ?? true))
              IconButton(
                tooltip: 'فتح مجلد التقارير',
                onPressed: _openExportsFolder,
                icon: const Icon(Icons.folder_open),
              ),
            if ((license?.isActivated ?? true))
              IconButton(
                tooltip: 'طباعة آخر PDF',
                onPressed: _printLatestPdf,
                icon: const Icon(Icons.print_outlined),
              ),
            if ((license?.isActivated ?? true))
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
          bottom: const TabBar(
            isScrollable: true,
            tabs: [
              Tab(text: 'الأرباح'),
              Tab(text: 'تحليل ذكي'),
              Tab(text: 'حركة الدرج'),
              Tab(text: 'ملخص العمليات'),
              Tab(text: 'المستحقات'),
              Tab(text: 'الخزنة'),
              Tab(text: 'مطابقة الأرصدة'),
              Tab(text: 'إغلاق اليوم'),
              Tab(text: 'الملخص التنفيذي'),
            ],
          ),
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
            ? Center(child: Text('خطأ: $_error'))
            : Column(
                children: [
                  _periodHero(range, license),
                  Expanded(
                    child: TabBarView(
                      children: [
                        _profitTab(report),
                        _smartTab(_smart),
                        _cashflowTab(report),
                        _opsTab(report),
                        _claimsTab(report),
                        _treasuryTab(treasury),
                        _reconciliationTab(report),
                        _dailyCloseTab(),
                        _executiveTab(report, treasury),
                      ],
                    ),
                  ),
                ],
              ),
      ),
    );
  }

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
                  setState(() => _period = 'today');
                  await _load();
                },
              ),
              ChoiceChip(
                label: const Text('هذا الشهر'),
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
        _countTile(
          'عدد المعلّق',
          report.ops.pendingCount,
          Icons.pending_actions,
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

  Widget _dailyCloseTab() {
    final dateLabel = _fmtDate(_closeDate);
    final existing = _closes.where((c) => c.dateKey == dateLabel).toList();

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'إغلاق اليوم',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Text('التاريخ: $dateLabel'),
                    const SizedBox(width: 12),
                    TextButton.icon(
                      onPressed: () async {
                        final now = DateTime.now();
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: _closeDate,
                          firstDate: DateTime(now.year - 5),
                          lastDate: DateTime(now.year + 1),
                        );
                        if (picked == null) return;
                        setState(() => _closeDate = picked);
                      },
                      icon: const Icon(Icons.date_range),
                      label: const Text('تغيير'),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                if (existing.isNotEmpty) ...[
                  Text('تم الإغلاق بالفعل: ${existing.first.closedAt}'),
                  const SizedBox(height: 8),
                  if (AppSession.isAdmin)
                    OutlinedButton.icon(
                      onPressed: _reopenDay,
                      icon: const Icon(Icons.undo),
                      label: const Text('إلغاء الإغلاق'),
                    ),
                ] else
                  ElevatedButton.icon(
                    onPressed: _closeDay,
                    icon: const Icon(Icons.lock),
                    label: const Text('إغلاق اليوم'),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        const Text('سجل الإغلاقات'),
        const SizedBox(height: 8),
        ..._closes
            .take(10)
            .map(
              (c) => Card(
                child: ListTile(
                  title: Text('تاريخ: ${c.dateKey}'),
                  subtitle: Text('وقت الإغلاق: ${c.closedAt}'),
                  trailing: Text(c.profitTotal.toStringAsFixed(2)),
                ),
              ),
            ),
      ],
    );
  }

  Widget _executiveTab(ReportData? report, TreasurySnapshot? treasury) {
    if (report == null || treasury == null) return const SizedBox.shrink();
    final expenses = report.cashflow.outflowByType['مصروفات'] ?? 0;
    final netProfitAfterExpenses = report.profit.total - expenses;
    final alerts = <String>[
      if (!report.reconciliation.ok) 'تنبيه: يوجد فرق في مطابقة الأرصدة.',
      if (report.ops.pendingCount > 0)
        'تنبيه: يوجد ${report.ops.pendingCount} عملية معلقة.',
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
        _lineRow('أثر المعلق (صافي)', treasury.pendingNet),
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

  Widget _kpiCard(String title, double value, {IconData? icon}) {
    return Card(
      child: ListTile(
        leading: icon == null ? null : Icon(icon),
        title: Text(title),
        trailing: Text(value.toStringAsFixed(2)),
      ),
    );
  }

  Widget _countTile(String title, int value, IconData icon) {
    return Card(
      child: ListTile(
        leading: Icon(icon),
        title: Text(title),
        trailing: Text('$value'),
      ),
    );
  }

  Widget _sectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(title, style: Theme.of(context).textTheme.titleMedium),
    );
  }

  Widget _lineRow(String title, double value) {
    return Card(
      child: ListTile(
        title: Text(title),
        trailing: Text(value.toStringAsFixed(2)),
      ),
    );
  }

  Widget _smartKpi(String title, String value, IconData icon) {
    return Card(
      child: ListTile(
        leading: Icon(icon),
        title: Text(title),
        trailing: Text(value),
      ),
    );
  }

  Widget _dayRow(DayInsight d) {
    final parts = <String>[
      'الربح: ${d.profit.toStringAsFixed(2)}',
      'العدد: ${d.count}',
      'الحجم: ${d.volume.toStringAsFixed(2)}',
    ];
    return Card(
      child: ListTile(
        title: Text(d.dateKey),
        subtitle: Text(parts.join(' • ')),
      ),
    );
  }

  Widget _customerRow(CustomerInsight c) {
    final parts = <String>[
      'الربح: ${c.profit.toStringAsFixed(2)}',
      'العدد: ${c.count}',
      'الحجم: ${c.volume.toStringAsFixed(2)}',
    ];
    return Card(
      child: ListTile(title: Text(c.name), subtitle: Text(parts.join(' • '))),
    );
  }
}
