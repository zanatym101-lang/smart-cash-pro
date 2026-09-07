import 'package:flutter/material.dart';
import '../../domain/models/wallet_ledger.dart';
import '../../models/wallet.dart';
import '../../data/app_db.dart';
import 'wallet_ledger_builder.dart';
import '../../widgets/app_title.dart';

import 'package:share_plus/share_plus.dart';
import '../../data/reporting.dart';
import '../../data/report_exporter.dart';

class WalletLedgerScreen extends StatefulWidget {
  final Wallet wallet;
  const WalletLedgerScreen({super.key, required this.wallet});

  @override
  State<WalletLedgerScreen> createState() => _WalletLedgerScreenState();
}

class _WalletLedgerScreenState extends State<WalletLedgerScreen> {
  bool _loading = true;
  String? _error;
  WalletAccount? _account;

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
      final txns = await db.listTxns();
      final wallets = await db.listWallets();
      
      final accounts = WalletLedgerBuilder.build(
        txns: txns,
        wallets: wallets,
      );

      final wAccount = accounts.cast<WalletAccount?>().firstWhere(
        (a) => a?.walletId == widget.wallet.id.toString(),
        orElse: () => null,
      );

      if (mounted) {
        setState(() {
          _account = wAccount;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  Future<void> _export(bool pdf) async {
    if (_account == null) return;
    try {
      final exportData = WalletReportExportData(
        range: DateRange(start: DateTime(2000), end: DateTime.now()), // Assuming full range or filter can be added
        walletName: _account!.walletName,
        walletNumber: _account!.walletNumber,
        currentBalance: _account!.currentBalance.toDouble(),
        totalReceived: _account!.totalReceived.toDouble(),
        totalTransferred: _account!.totalTransferred.toDouble(),
        totalFees: _account!.totalFees.toDouble(),
        netMovement: _account!.netMovement.toDouble(),
        rows: _account!.rows,
      );

      final path = pdf
          ? await ReportExporter.exportWalletPdf(data: exportData)
          : await ReportExporter.exportWalletExcel(data: exportData);
      
      // ignore: deprecated_member_use
                        await Share.shareXFiles([XFile(path)], text: 'كشف حساب محفظة ${_account!.walletName}');
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('خطأ التصدير: $e')));
    }
  }

  String _formatType(WalletTransactionType type) {
    switch (type) {
      case WalletTransactionType.transferOut:
        return 'تحويل صادر';
      case WalletTransactionType.receiveIn:
        return 'إيداع/وارد';
      case WalletTransactionType.feeDeduction:
        return 'عمولة شبكة';
      case WalletTransactionType.adjustment:
        return 'تسوية';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: AppTitle(subtitle: 'كشف حساب: ${widget.wallet.name}'),
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
            icon: const Icon(Icons.refresh),
            onPressed: _loading ? null : _load,
          )
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text('خطأ: $_error'))
              : _account == null
                  ? const Center(child: Text('لم يتم العثور على حركات'))
                  : Column(
                      children: [
                        _buildSummaryHeader(_account!),
                        Expanded(
                          child: ListView.builder(
                            itemCount: _account!.rows.length,
                            itemBuilder: (context, index) {
                              final row = _account!.rows[index];
                              return _buildRowItem(row);
                            },
                          ),
                        ),
                      ],
                    ),
    );
  }

  Widget _buildSummaryHeader(WalletAccount account) {
    return Container(
      padding: const EdgeInsets.all(16),
      color: Colors.blueGrey.withValues(alpha: 0.1),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _summaryBox('رصيد حالي', account.currentBalance.toDouble()),
          _summaryBox('إجمالي وارد', account.totalReceived.toDouble()),
          _summaryBox('إجمالي صادر', account.totalTransferred.toDouble()),
        ],
      ),
    );
  }

  Widget _summaryBox(String title, double amount) {
    return Column(
      children: [
        Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
        const SizedBox(height: 4),
        Text(amount.toStringAsFixed(2), style: const TextStyle(color: Colors.blueGrey)),
      ],
    );
  }

  Widget _buildRowItem(WalletLedgerRow row) {
    final isOut = row.transactionType == WalletTransactionType.transferOut;
    final color = isOut ? Colors.red : Colors.green;
    final sign = isOut ? '-' : '+';
    
    final d = row.date;
    final dateStr = '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: ListTile(
        title: Text(_formatType(row.transactionType)),
        subtitle: Text('$dateStr\nالمرجع: ${row.reference ?? '-'}'),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              '$sign${row.amount.toDouble().abs().toStringAsFixed(2)}',
              style: TextStyle(color: color, fontWeight: FontWeight.bold),
            ),
            if (row.fee.toDouble() < 0)
              Text(
                'عمولة: ${row.fee.toDouble().abs().toStringAsFixed(2)}',
                style: const TextStyle(fontSize: 10, color: Colors.red),
              ),
            Text(
              'رصيد: ${row.balanceAfter.toDouble().toStringAsFixed(2)}',
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }
}
