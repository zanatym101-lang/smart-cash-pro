import 'package:flutter/material.dart';
import '../../data/app_db.dart';
import '../../domain/models/treasury_ledger.dart';
import '../../models/transaction.dart';
import 'treasury_ledger_builder.dart';
import '../../widgets/app_title.dart';
import 'package:intl/intl.dart';

import 'package:share_plus/share_plus.dart';
import '../../data/reporting.dart';
import '../../data/report_exporter.dart';

class TreasuryLedgerScreen extends StatefulWidget {
  const TreasuryLedgerScreen({super.key});

  @override
  State<TreasuryLedgerScreen> createState() => _TreasuryLedgerScreenState();
}

class _TreasuryLedgerScreenState extends State<TreasuryLedgerScreen> {
  DateTime? _startDate;
  DateTime? _endDate;
  bool _loading = true;
  String? _error;
  TreasuryAccount? _account;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final db = AppDb.instance;
      final drawerEntries = db.ledgerEntries.where((e) => e.accountKey == 'drawer').toList();
      
      final txnsList = await db.listTxns();
      final Map<String, Txn> txnsMap = {
        for (var t in txnsList) t.id.toString(): t
      };

      final account = TreasuryLedgerBuilder.build(
        drawerEntries: drawerEntries,
        txnsMap: txnsMap,
        startDate: _startDate,
        endDate: _endDate,
      );

      if (!mounted) return;
      setState(() => _account = account);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _export(bool pdf) async {
    if (_account == null) return;
    try {
      final exportData = TreasuryReportExportData(
        range: DateRange(
          start: _startDate ?? DateTime(2000), 
          end: _endDate ?? DateTime.now(),
        ),
        openingBalance: _account!.openingBalance.toDouble(),
        totalIn: _account!.totalIn.toDouble(),
        totalOut: _account!.totalOut.toDouble(),
        expenses: _account!.expenses.toDouble(),
        adjustments: _account!.adjustments.toDouble(),
        closingBalance: _account!.closingBalance.toDouble(),
        rows: _account!.rows,
      );

      final path = pdf
          ? await ReportExporter.exportTreasuryPdf(data: exportData)
          : await ReportExporter.exportTreasuryExcel(data: exportData);
      
      // ignore: deprecated_member_use
                        await Share.shareXFiles([XFile(path)], text: 'كشف حساب الخزينة');
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('خطأ التصدير: $e')));
    }
  }

  Future<void> _pickDateRange() async {
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2023),
      lastDate: DateTime(2050),
      initialDateRange: _startDate != null && _endDate != null
          ? DateTimeRange(start: _startDate!, end: _endDate!)
          : null,
    );
    if (range != null) {
      setState(() {
        _startDate = range.start;
        _endDate = DateTime(
          range.end.year,
          range.end.month,
          range.end.day,
          23,
          59,
          59,
        );
      });
      _load();
    }
  }

  void _clearDates() {
    setState(() {
      _startDate = null;
      _endDate = null;
    });
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const AppTitle(subtitle: 'سجل الخزينة'),
        actions: [
          if (_account != null)
            PopupMenuButton<String>(
              onSelected: (v) {
                if (v == 'pdf') _export(true);
                if (v == 'excel') _export(false);
              },
              itemBuilder: (context) => [
                const PopupMenuItem(value: 'pdf', child: Text('تصدير PDF')),
                const PopupMenuItem(value: 'excel', child: Text('تصدير Excel')),
              ],
            ),
          IconButton(
            icon: const Icon(Icons.date_range),
            onPressed: _pickDateRange,
            tooltip: 'تحديد فترة',
          ),
          if (_startDate != null)
            IconButton(
              icon: const Icon(Icons.clear),
              onPressed: _clearDates,
              tooltip: 'إلغاء التصفية',
            ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _load,
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) return Center(child: Text('خطأ: $_error'));
    if (_account == null) return const Center(child: Text('لا توجد بيانات'));

    return Column(
      children: [
        _buildDateFilterHeader(),
        _buildSummaryCards(),
        const Divider(),
        Expanded(
          child: _account!.rows.isEmpty
              ? const Center(child: Text('لا توجد حركات في هذه الفترة'))
              : ListView.builder(
                  itemCount: _account!.rows.length,
                  itemBuilder: (ctx, idx) => _buildRow(_account!.rows[idx]),
                ),
        ),
      ],
    );
  }

  Widget _buildDateFilterHeader() {
    if (_startDate == null || _endDate == null) return const SizedBox.shrink();
    final fmt = DateFormat('yyyy/MM/dd');
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: Colors.blue.withValues(alpha: 0.1),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.filter_alt, size: 16, color: Colors.blue),
          const SizedBox(width: 8),
          Text(
            'من ${fmt.format(_startDate!)} إلى ${fmt.format(_endDate!)}',
            style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.blue),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryCards() {
    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        alignment: WrapAlignment.center,
        children: [
          _StatCard('رصيد افتتاحي', _account!.openingBalance.formatted, Colors.blueGrey),
          _StatCard('إجمالي الداخل', _account!.totalIn.formatted, Colors.green),
          _StatCard('إجمالي الخارج', _account!.totalOut.formatted, Colors.orange),
          _StatCard('المصروفات', _account!.expenses.formatted, Colors.red),
          _StatCard('التسويات', _account!.adjustments.formatted, Colors.purple),
          _StatCard('رصيد ختامي', _account!.closingBalance.formatted, Colors.blue),
        ],
      ),
    );
  }

  Widget _buildRow(TreasuryLedgerRow row) {
    final df = DateFormat('yyyy/MM/dd hh:mm a');
    final isPos = row.amount.qirsh > 0;
    
    IconData icon;
    Color color;
    switch (row.eventType) {
      case TreasuryEventType.cashReceived:
        icon = Icons.arrow_downward;
        color = Colors.green;
        break;
      case TreasuryEventType.cashTransferred:
        icon = Icons.arrow_upward;
        color = Colors.orange;
        break;
      case TreasuryEventType.expense:
        icon = Icons.money_off;
        color = Colors.red;
        break;
      case TreasuryEventType.funding:
        icon = Icons.account_balance_wallet;
        color = Colors.blue;
        break;
      case TreasuryEventType.withdrawal:
        icon = Icons.atm;
        color = Colors.deepOrange;
        break;
      case TreasuryEventType.settlement:
        icon = Icons.handshake;
        color = Colors.teal;
        break;
      case TreasuryEventType.adjustment:
        icon = Icons.edit;
        color = Colors.purple;
        break;
    }

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: color.withValues(alpha: 0.1),
          child: Icon(icon, color: color),
        ),
        title: Text(row.description),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (row.reference != null && row.reference!.isNotEmpty)
              Text('المرجع: ${row.reference}'),
            Text(df.format(row.date)),
          ],
        ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              (isPos ? '+' : '') + row.amount.formatted,
              style: TextStyle(
                color: isPos ? Colors.green : Colors.red,
                fontWeight: FontWeight.bold,
              ),
            ),
            Text(
              'الرصيد: ${row.balanceAfter.formatted}',
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final String title;
  final String value;
  final Color color;
  const _StatCard(this.title, this.value, this.color);

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 110,
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        border: Border.all(color: color.withValues(alpha: 0.5)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          Text(title, style: TextStyle(fontSize: 12, color: color)),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(fontWeight: FontWeight.bold, color: color),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}
