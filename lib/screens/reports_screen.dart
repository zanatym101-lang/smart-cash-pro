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

part 'reports_date_range_helpers.dart';
part 'reports_export_section.dart';
part 'reports_daily_close_section.dart';
part 'reports_summary_cards.dart';
part 'reports_tabs_sections.dart';

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

  void _setMountedState(VoidCallback fn) {
    if (mounted) setState(fn);
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
  void initState() {
    super.initState();
    _init();
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
}
