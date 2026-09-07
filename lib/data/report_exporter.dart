import 'dart:io';

import 'package:excel/excel.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/widgets.dart' as pw;

import 'app_db.dart';
import 'reporting.dart';
import '../models/daily_close.dart';
import '../domain/models/wallet_ledger.dart';
import '../domain/models/treasury_ledger.dart';
import '../screens/customer_account/customer_account_models.dart';

class CustomerTxnExportRow {
  final DateTime date;
  final String kind;
  final String status;
  final double amount;

  const CustomerTxnExportRow({
    required this.date,
    required this.kind,
    required this.status,
    required this.amount,
  });
}

class CustomerStatementExportRow {
  final DateTime date;
  final String title;
  final String? details;
  final String status;
  final double amountSigned;
  final double runningNet;
  final String runningSideLabel;

  const CustomerStatementExportRow({
    required this.date,
    required this.title,
    this.details,
    required this.status,
    required this.amountSigned,
    required this.runningNet,
    required this.runningSideLabel,
  });
}

class CustomerReportExportData {
  final String customerName;
  final String customerPhone;
  final DateRange range;
  final double receivable;
  final double payable;
  final double net;
  final int postedCount;
  final int pendingCount;
  final double postedVolume;
  final double pendingVolume;
  final double postedProfit;
  final int transferCount;
  final int receiveCount;
  final int fawryCount;
  final List<CustomerTxnExportRow> latestTxns;
  final double openingNet;
  final double closingNet;
  final List<CustomerStatementExportRow> statementRows;

  const CustomerReportExportData({
    required this.customerName,
    required this.customerPhone,
    required this.range,
    required this.receivable,
    required this.payable,
    required this.net,
    required this.postedCount,
    required this.pendingCount,
    required this.postedVolume,
    required this.pendingVolume,
    required this.postedProfit,
    required this.transferCount,
    required this.receiveCount,
    required this.fawryCount,
    this.latestTxns = const [],
    this.openingNet = 0,
    this.closingNet = 0,
    this.statementRows = const [],
  });
}

class WalletReportExportData {
  final String walletName;
  final String walletNumber;
  final DateRange range;
  final double currentBalance;
  final double totalReceived;
  final double totalTransferred;
  final double totalFees;
  final double netMovement;
  final List<WalletLedgerRow> rows;

  const WalletReportExportData({
    required this.walletName,
    required this.walletNumber,
    required this.range,
    required this.currentBalance,
    required this.totalReceived,
    required this.totalTransferred,
    required this.totalFees,
    required this.netMovement,
    this.rows = const [],
  });
}

class TreasuryReportExportData {
  final DateRange range;
  final double openingBalance;
  final double totalIn;
  final double totalOut;
  final double expenses;
  final double adjustments;
  final double closingBalance;
  final List<TreasuryLedgerRow> rows;

  const TreasuryReportExportData({
    required this.range,
    required this.openingBalance,
    required this.totalIn,
    required this.totalOut,
    required this.expenses,
    required this.adjustments,
    required this.closingBalance,
    this.rows = const [],
  });
}

class ReportExporter {
  static pw.Font? _pdfBaseFont;
  static pw.Font? _pdfBoldFont;
  static Future<void>? _fontLoadFuture;
  static Future<pw.Document> Function()? _pdfDocumentFactoryOverride;
  static Future<Directory> Function()? _exportDirOverride;
  static DateTime Function()? _nowProviderOverride;
  static List<int>? Function(Excel excel)? _excelEncodeOverride;

  @visibleForTesting
  static void setTestOverrides({
    Future<pw.Document> Function()? pdfDocumentFactory,
    Future<Directory> Function()? exportDirResolver,
    DateTime Function()? nowProvider,
    List<int>? Function(Excel excel)? excelEncode,
  }) {
    _pdfDocumentFactoryOverride = pdfDocumentFactory;
    _exportDirOverride = exportDirResolver;
    _nowProviderOverride = nowProvider;
    _excelEncodeOverride = excelEncode;
  }

  @visibleForTesting
  static void resetTestOverrides() {
    _pdfDocumentFactoryOverride = null;
    _exportDirOverride = null;
    _nowProviderOverride = null;
    _excelEncodeOverride = null;
  }

  static DateTime _now() => _nowProviderOverride?.call() ?? DateTime.now();

  static Future<void> _ensurePdfFonts() {
    if (_pdfBaseFont != null && _pdfBoldFont != null) {
      return Future.value();
    }
    _fontLoadFuture ??= () async {
      _pdfBaseFont = pw.Font.ttf(
        await rootBundle.load('assets/fonts/Amiri-Regular.ttf'),
      );
      _pdfBoldFont = pw.Font.ttf(
        await rootBundle.load('assets/fonts/Amiri-Bold.ttf'),
      );
    }();
    return _fontLoadFuture!;
  }

  static Future<pw.Document> _newPdfDocument() async {
    final overrideFactory = _pdfDocumentFactoryOverride;
    if (overrideFactory != null) {
      return overrideFactory();
    }
    await _ensurePdfFonts();
    return pw.Document(
      theme: pw.ThemeData.withFont(base: _pdfBaseFont!, bold: _pdfBoldFont!),
    );
  }

  static pw.Widget _rtlBlock(List<pw.Widget> children) {
    return pw.Directionality(
      textDirection: pw.TextDirection.rtl,
      child: pw.DefaultTextStyle(
        style: pw.TextStyle(font: _pdfBaseFont, fontSize: 11),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: children,
        ),
      ),
    );
  }

  static String _fmtDate(DateTime d) {
    final y = d.year.toString().padLeft(4, '0');
    final m = d.month.toString().padLeft(2, '0');
    final day = d.day.toString().padLeft(2, '0');
    return '$y-$m-$day';
  }

  static String _fmtDateTime(DateTime d) {
    final date = _fmtDate(d);
    final hh = d.hour.toString().padLeft(2, '0');
    final mm = d.minute.toString().padLeft(2, '0');
    return '$date $hh:$mm';
  }

    static Future<Directory> _exportDir() async {
    final resolver = _exportDirOverride;
    if (resolver != null) {
      return resolver();
    }
    return getTemporaryDirectory();
  }

  static Future<Directory> exportDirectory() async {
    final dir = await _exportDir();
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  static String _fileName(String prefix, DateRange range, String ext) {
    final start = _fmtDate(range.start);
    final end = _fmtDate(range.end);
    return '${prefix}_${start}_$end.$ext';
  }

  static Future<String> exportPdf({
    required ReportData data,
    required TreasurySnapshot treasury,
    required DateRange range,
  }) async {
    final doc = await _newPdfDocument();
    final period =
        '\u0645\u0646 ${_fmtDate(range.start)} \u0625\u0644\u0649 ${_fmtDate(range.end)}';

    doc.addPage(
      pw.Page(
        build: (_) => _rtlBlock([
          pw.Text(
            '\u062a\u0642\u0631\u064a\u0631 \u0627\u0644\u0623\u0631\u0628\u0627\u062d',
            style: pw.TextStyle(font: _pdfBoldFont, fontSize: 18),
          ),
          pw.Text('\u0627\u0644\u0641\u062a\u0631\u0629: $period'),
          pw.SizedBox(height: 12),
          pw.Text('\u0627\u0644\u0623\u0631\u0628\u0627\u062d'),
          pw.Text(
            '\u062a\u062d\u0648\u064a\u0644: ${data.profit.transfer.toStringAsFixed(2)}',
          ),
          pw.Text(
            '\u0627\u0633\u062a\u0644\u0627\u0645: ${data.profit.receive.toStringAsFixed(2)}',
          ),
          pw.Text(
            '\u0641\u0648\u0631\u064a: ${data.profit.fawry.toStringAsFixed(2)}',
          ),
          pw.Text(
            '\u0627\u0644\u0625\u062c\u0645\u0627\u0644\u064a: ${data.profit.total.toStringAsFixed(2)}',
          ),
          pw.SizedBox(height: 12),
          pw.Text('\u062d\u0631\u0643\u0629 \u0627\u0644\u062f\u0631\u062c'),
          pw.Text(
            '\u062f\u0627\u062e\u0644: ${data.cashflow.inflow.toStringAsFixed(2)}',
          ),
          pw.Text(
            '\u062e\u0627\u0631\u062c: ${data.cashflow.outflow.toStringAsFixed(2)}',
          ),
          pw.Text(
            '\u0635\u0627\u0641\u064a: ${data.cashflow.net.toStringAsFixed(2)}',
          ),
          pw.SizedBox(height: 12),
          pw.Text(
            '\u0645\u0644\u062e\u0635 \u0627\u0644\u0639\u0645\u0644\u064a\u0627\u062a',
          ),
          pw.Text(
            '\u0639\u062f\u062f \u0627\u0644\u062a\u062d\u0648\u064a\u0644\u0627\u062a: ${data.ops.transferCount}',
          ),
          pw.Text(
            '\u0639\u062f\u062f \u0627\u0644\u0627\u0633\u062a\u0644\u0627\u0645\u0627\u062a: ${data.ops.receiveCount}',
          ),
          pw.Text(
            '\u0639\u062f\u062f \u0641\u0648\u0631\u064a \u0646\u0642\u062f\u064a: ${data.ops.fawryCashCount}',
          ),
          pw.Text(
            '\u0639\u062f\u062f \u0641\u0648\u0631\u064a \u0622\u062c\u0644: ${data.ops.fawryCreditCount}',
          ),
          pw.Text(
            '\u0639\u062f\u062f \u0627\u0644\u0645\u0635\u0631\u0648\u0641\u0627\u062a: ${data.ops.expenseCount}',
          ),
          pw.Text(
            '\u0639\u062f\u062f \u062a\u062d\u0635\u064a\u0644 \u0627\u0644\u0645\u0633\u062a\u062d\u0642\u0627\u062a: ${data.ops.claimCollectCount}',
          ),
          pw.Text(
            '\u0639\u062f\u062f \u0633\u062f\u0627\u062f \u0627\u0644\u0645\u0633\u062a\u062d\u0642\u0627\u062a: ${data.ops.claimPayCount}',
          ),
          pw.Text(
            '\u0639\u062f\u062f \u0627\u0644\u0645\u0639\u0644\u0642: ${data.ops.pendingCount}',
          ),
          pw.SizedBox(height: 12),
          pw.Text(
            '\u0627\u0644\u0645\u0633\u062a\u062d\u0642\u0627\u062a (\u0627\u0644\u0645\u0641\u062a\u0648\u062d\u0629)',
          ),
          pw.Text(
            '\u0644\u0646\u0627: ${data.claims.receivableOpen.toStringAsFixed(2)}',
          ),
          pw.Text(
            '\u0639\u0644\u064a\u0646\u0627: ${data.claims.payableOpen.toStringAsFixed(2)}',
          ),
          pw.Text(
            '\u0627\u0644\u0635\u0627\u0641\u064a: ${data.claims.net.toStringAsFixed(2)}',
          ),
          pw.SizedBox(height: 12),
          pw.Text(
            '\u0627\u0644\u062e\u0632\u0646\u0629 \u0627\u0644\u0625\u062c\u0645\u0627\u0644\u064a\u0629',
          ),
          pw.Text(
            '\u0627\u0644\u062f\u0631\u062c: ${treasury.drawerBalance.toStringAsFixed(2)}',
          ),
          pw.Text(
            '\u0627\u0644\u0645\u062d\u0627\u0641\u0638: ${treasury.walletsTotal.toStringAsFixed(2)}',
          ),
          pw.Text(
            '\u0627\u0644\u0625\u062c\u0645\u0627\u0644\u064a: ${(treasury.drawerBalance + treasury.walletsTotal).toStringAsFixed(2)}',
          ),
        ]),
      ),
    );

    final dir = await _exportDir();
    final name = _fileName('report', range, 'pdf');
    final file = File('${dir.path}/$name');
    await file.writeAsBytes(await doc.save());
    return file.path;
  }

  static Future<String> exportExcel({
    required ReportData data,
    required TreasurySnapshot treasury,
    required DateRange range,
  }) async {
    final excel = Excel.createExcel();

    CellValue t(String v) => TextCellValue(v);
    CellValue n(num v) =>
        v is int ? IntCellValue(v) : DoubleCellValue(v.toDouble());

    final period =
        '\u0645\u0646 ${_fmtDate(range.start)} \u0625\u0644\u0649 ${_fmtDate(range.end)}';

    final profitSheet = excel['\u0627\u0644\u0623\u0631\u0628\u0627\u062d'];
    profitSheet.appendRow([
      t('\u0627\u0644\u0641\u062a\u0631\u0629'),
      t(period),
    ]);
    profitSheet.appendRow([
      t('\u0631\u0628\u062d \u0627\u0644\u062a\u062d\u0648\u064a\u0644'),
      n(data.profit.transfer),
    ]);
    profitSheet.appendRow([
      t('\u0631\u0628\u062d \u0627\u0644\u0627\u0633\u062a\u0644\u0627\u0645'),
      n(data.profit.receive),
    ]);
    profitSheet.appendRow([
      t('\u0631\u0628\u062d \u0641\u0648\u0631\u064a'),
      n(data.profit.fawry),
    ]);
    profitSheet.appendRow([
      t('\u0625\u062c\u0645\u0627\u0644\u064a \u0627\u0644\u0631\u0628\u062d'),
      n(data.profit.total),
    ]);

    final cashSheet =
        excel['\u062d\u0631\u0643\u0629 \u0627\u0644\u062f\u0631\u062c'];
    cashSheet.appendRow([
      t('\u062f\u0627\u062e\u0644'),
      n(data.cashflow.inflow),
    ]);
    cashSheet.appendRow([
      t('\u062e\u0627\u0631\u062c'),
      n(data.cashflow.outflow),
    ]);
    cashSheet.appendRow([t('\u0635\u0627\u0641\u064a'), n(data.cashflow.net)]);
    cashSheet.appendRow([]);
    cashSheet.appendRow([
      t('\u062a\u0641\u0635\u064a\u0644 \u0627\u0644\u062f\u0627\u062e\u0644'),
    ]);
    for (final e in data.cashflow.inflowByType.entries) {
      cashSheet.appendRow([t(e.key), n(e.value)]);
    }
    cashSheet.appendRow([]);
    cashSheet.appendRow([
      t('\u062a\u0641\u0635\u064a\u0644 \u0627\u0644\u062e\u0627\u0631\u062c'),
    ]);
    for (final e in data.cashflow.outflowByType.entries) {
      cashSheet.appendRow([t(e.key), n(e.value)]);
    }

    final opsSheet =
        excel['\u0645\u0644\u062e\u0635 \u0627\u0644\u0639\u0645\u0644\u064a\u0627\u062a'];
    opsSheet.appendRow([
      t(
        '\u0639\u062f\u062f \u0627\u0644\u062a\u062d\u0648\u064a\u0644\u0627\u062a',
      ),
      n(data.ops.transferCount),
    ]);
    opsSheet.appendRow([
      t(
        '\u0639\u062f\u062f \u0627\u0644\u0627\u0633\u062a\u0644\u0627\u0645\u0627\u062a',
      ),
      n(data.ops.receiveCount),
    ]);
    opsSheet.appendRow([
      t('\u0639\u062f\u062f \u0641\u0648\u0631\u064a \u0646\u0642\u062f\u064a'),
      n(data.ops.fawryCashCount),
    ]);
    opsSheet.appendRow([
      t('\u0639\u062f\u062f \u0641\u0648\u0631\u064a \u0622\u062c\u0644'),
      n(data.ops.fawryCreditCount),
    ]);
    opsSheet.appendRow([
      t(
        '\u0639\u062f\u062f \u0627\u0644\u0645\u0635\u0631\u0648\u0641\u0627\u062a',
      ),
      n(data.ops.expenseCount),
    ]);
    opsSheet.appendRow([
      t(
        '\u0639\u062f\u062f \u062a\u062d\u0635\u064a\u0644 \u0627\u0644\u0645\u0633\u062a\u062d\u0642\u0627\u062a',
      ),
      n(data.ops.claimCollectCount),
    ]);
    opsSheet.appendRow([
      t(
        '\u0639\u062f\u062f \u0633\u062f\u0627\u062f \u0627\u0644\u0645\u0633\u062a\u062d\u0642\u0627\u062a',
      ),
      n(data.ops.claimPayCount),
    ]);
    opsSheet.appendRow([
      t('\u0639\u062f\u062f \u0627\u0644\u0645\u0639\u0644\u0642'),
      n(data.ops.pendingCount),
    ]);

    final claimsSheet =
        excel['\u0627\u0644\u0645\u0633\u062a\u062d\u0642\u0627\u062a'];
    claimsSheet.appendRow([
      t(
        '\u0625\u062c\u0645\u0627\u0644\u064a \u0644\u0646\u0627 (\u0645\u0641\u062a\u0648\u062d\u0629)',
      ),
      n(data.claims.receivableOpen),
    ]);
    claimsSheet.appendRow([
      t(
        '\u0625\u062c\u0645\u0627\u0644\u064a \u0639\u0644\u064a\u0646\u0627 (\u0645\u0641\u062a\u0648\u062d\u0629)',
      ),
      n(data.claims.payableOpen),
    ]);
    claimsSheet.appendRow([
      t('\u0627\u0644\u0635\u0627\u0641\u064a'),
      n(data.claims.net),
    ]);

    final treasurySheet = excel['\u0627\u0644\u062e\u0632\u0646\u0629'];
    treasurySheet.appendRow([
      t('\u0631\u0635\u064a\u062f \u0627\u0644\u062f\u0631\u062c'),
      n(treasury.drawerBalance),
    ]);
    treasurySheet.appendRow([
      t(
        '\u0625\u062c\u0645\u0627\u0644\u064a \u0627\u0644\u0645\u062d\u0627\u0641\u0638',
      ),
      n(treasury.walletsTotal),
    ]);
    treasurySheet.appendRow([
      t(
        '\u0625\u062c\u0645\u0627\u0644\u064a \u0627\u0644\u062e\u0632\u0646\u0629',
      ),
      n(treasury.drawerBalance + treasury.walletsTotal),
    ]);

    final dir = await _exportDir();
    final name = _fileName('report', range, 'xlsx');
    final file = File('${dir.path}/$name');
    final encodeOverride = _excelEncodeOverride;
    final bytes = encodeOverride != null
        ? encodeOverride(excel)
        : excel.encode();
    if (bytes == null) {
      throw Exception(
        '\u0641\u0634\u0644 \u062a\u0635\u062f\u064a\u0631 Excel',
      );
    }
    await file.writeAsBytes(bytes, flush: true);
    return file.path;
  }

  static Future<String> exportDailyClosePdf({required DailyClose close}) async {
    final doc = await _newPdfDocument();
    doc.addPage(
      pw.Page(
        build: (_) => _rtlBlock([
          pw.Text(
            '\u0645\u062d\u0636\u0631 \u0625\u063a\u0644\u0627\u0642 \u0627\u0644\u064a\u0648\u0645',
            style: pw.TextStyle(font: _pdfBoldFont, fontSize: 18),
          ),
          pw.SizedBox(height: 8),
          pw.Text(
            '\u062a\u0627\u0631\u064a\u062e \u0627\u0644\u064a\u0648\u0645: ${close.dateKey}',
          ),
          pw.Text(
            '\u0648\u0642\u062a \u0627\u0644\u0625\u063a\u0644\u0627\u0642: ${close.closedAt}',
          ),
          pw.SizedBox(height: 12),
          pw.Text('\u0627\u0644\u062e\u0632\u0646\u0629'),
          pw.Text(
            '\u0631\u0635\u064a\u062f \u0627\u0644\u062f\u0631\u062c: ${close.drawerBalance.toStringAsFixed(2)}',
          ),
          pw.Text(
            '\u0625\u062c\u0645\u0627\u0644\u064a \u0627\u0644\u0645\u062d\u0627\u0641\u0638: ${close.walletsTotal.toStringAsFixed(2)}',
          ),
          pw.Text(
            '\u0625\u062c\u0645\u0627\u0644\u064a \u0627\u0644\u062e\u0632\u0646\u0629: ${close.treasuryTotal.toStringAsFixed(2)}',
          ),
          pw.SizedBox(height: 12),
          pw.Text('\u0627\u0644\u0623\u0631\u0628\u0627\u062d'),
          pw.Text(
            '\u0625\u062c\u0645\u0627\u0644\u064a \u0627\u0644\u0631\u0628\u062d: ${close.profitTotal.toStringAsFixed(2)}',
          ),
          pw.Text(
            '\u0631\u0628\u062d \u0627\u0644\u062a\u062d\u0648\u064a\u0644: ${close.profitTransfer.toStringAsFixed(2)}',
          ),
          pw.Text(
            '\u0631\u0628\u062d \u0627\u0644\u0627\u0633\u062a\u0644\u0627\u0645: ${close.profitReceive.toStringAsFixed(2)}',
          ),
          pw.Text(
            '\u0631\u0628\u062d \u0641\u0648\u0631\u064a: ${close.profitFawry.toStringAsFixed(2)}',
          ),
          pw.SizedBox(height: 12),
          pw.Text('\u062d\u0631\u0643\u0629 \u0627\u0644\u062f\u0631\u062c'),
          pw.Text(
            '\u062f\u0627\u062e\u0644: ${close.inflow.toStringAsFixed(2)}',
          ),
          pw.Text(
            '\u062e\u0627\u0631\u062c: ${close.outflow.toStringAsFixed(2)}',
          ),
          pw.Text('\u0635\u0627\u0641\u064a: ${close.net.toStringAsFixed(2)}'),
          pw.SizedBox(height: 12),
          pw.Text(
            '\u0639\u062f\u062f \u0627\u0644\u0639\u0645\u0644\u064a\u0627\u062a',
          ),
          pw.Text('\u062a\u062d\u0648\u064a\u0644: ${close.transferCount}'),
          pw.Text(
            '\u0627\u0633\u062a\u0644\u0627\u0645: ${close.receiveCount}',
          ),
          pw.Text(
            '\u0641\u0648\u0631\u064a \u0646\u0642\u062f\u064a: ${close.fawryCashCount}',
          ),
          pw.Text(
            '\u0641\u0648\u0631\u064a \u0622\u062c\u0644: ${close.fawryCreditCount}',
          ),
          pw.Text(
            '\u0645\u0635\u0631\u0648\u0641\u0627\u062a: ${close.expenseCount}',
          ),
          pw.Text(
            '\u062a\u062d\u0635\u064a\u0644 \u0645\u0633\u062a\u062d\u0642\u0627\u062a: ${close.claimCollectCount}',
          ),
          pw.Text(
            '\u0633\u062f\u0627\u062f \u0645\u0633\u062a\u062d\u0642\u0627\u062a: ${close.claimPayCount}',
          ),
          pw.Text('\u0645\u0639\u0644\u0642: ${close.pendingCount}'),
        ]),
      ),
    );

    final dir = await _exportDir();
    final file = File('${dir.path}/daily_close_${close.dateKey}.pdf');
    await file.writeAsBytes(await doc.save(), flush: true);
    return file.path;
  }

  static Future<String> exportCustomerPdf({
    required CustomerAccount account,
    required DateRange range,
  }) async {
    final doc = await _newPdfDocument();
    final period = 'من ${_fmtDate(range.start)} إلى ${_fmtDate(range.end)}';
    final netLabel = account.summary.netBalance >= 0 ? 'صافي لنا' : 'صافي علينا';

    final rowsInRange = account.rows.where((r) => !r.date.isBefore(range.start) && !r.date.isAfter(range.end)).toList();

    doc.addPage(
      pw.MultiPage(
        build: (_) => [
          _rtlBlock([
            pw.Text(
              'كشف حساب عميل',
              style: pw.TextStyle(font: _pdfBoldFont, fontSize: 18),
            ),
            pw.SizedBox(height: 8),
            pw.Text('العميل: ${account.summary.customerName}'),
            pw.Text(
              'الهاتف: ${(account.summary.phone ?? '').trim().isEmpty ? '-' : account.summary.phone}',
            ),
            pw.Text('الفترة: $period'),
            pw.SizedBox(height: 12),
            pw.Text(
              'الموقف الحالي',
              style: pw.TextStyle(font: _pdfBoldFont, fontSize: 14),
            ),
            pw.Text('لنا: ${account.summary.totalForUs.toStringAsFixed(2)}'),
            pw.Text('علينا: ${account.summary.totalAgainstUs.toStringAsFixed(2)}'),
            pw.Text('$netLabel: ${account.summary.netBalance.abs().toStringAsFixed(2)}'),
            pw.SizedBox(height: 12),
            pw.Text(
              'كشف الحركات (الرصيد بعد كل حركة)',
              style: pw.TextStyle(font: _pdfBoldFont, fontSize: 14),
            ),
            if (rowsInRange.isEmpty)
              pw.Text('لا توجد حركات في الفترة المختارة'),
            if (rowsInRange.isNotEmpty)
              pw.TableHelper.fromTextArray(
                headerStyle: pw.TextStyle(font: _pdfBoldFont, fontSize: 10),
                cellStyle: pw.TextStyle(font: _pdfBaseFont, fontSize: 9),
                cellAlignment: pw.Alignment.centerRight,
                headers: const [
                  'التاريخ',
                  'الحركة',
                  'المبلغ',
                  'الرصيد بعد الحركة',
                  'الحالة',
                ],
                data: rowsInRange
                    .map(
                      (r) => [
                        _fmtDateTime(r.date),
                        r.description,
                        r.amount.abs().toStringAsFixed(2),
                        r.remainingBalanceAfterRow.abs().toStringAsFixed(2),
                        r.status.name,
                      ],
                    )
                    .toList(),
              ),
          ]),
        ],
      ),
    );

    final dir = await _exportDir();
    final stamp = _now().millisecondsSinceEpoch;
    final file = File('${dir.path}/customer_report_$stamp.pdf');
    await file.writeAsBytes(await doc.save(), flush: true);
    return file.path;
  }

  static Future<String> exportCustomerExcel({
    required CustomerAccount account,
    required DateRange range,
  }) async {
    final excel = Excel.createExcel();

    CellValue t(String v) => TextCellValue(v);
    CellValue n(num v) =>
        v is int ? IntCellValue(v) : DoubleCellValue(v.toDouble());

    final period = 'من ${_fmtDate(range.start)} إلى ${_fmtDate(range.end)}';
    final netLabel = account.summary.netBalance >= 0 ? 'لنا' : 'علينا';
    
    final rowsInRange = account.rows.where((r) => !r.date.isBefore(range.start) && !r.date.isAfter(range.end)).toList();

    final summary = excel['الملخص'];
    summary.appendRow([t('اسم العميل'), t(account.summary.customerName)]);
    summary.appendRow([
      t('الهاتف'),
      t((account.summary.phone ?? '').trim().isEmpty ? '-' : account.summary.phone!),
    ]);
    summary.appendRow([t('الفترة'), t(period)]);
    summary.appendRow([]);
    summary.appendRow([t('لنا'), n(account.summary.totalForUs)]);
    summary.appendRow([t('علينا'), n(account.summary.totalAgainstUs)]);
    summary.appendRow([t('الصافي ($netLabel)'), n(account.summary.netBalance.abs())]);

    final statement = excel['كشف_الحساب'];
    statement.appendRow([
      t('التاريخ'),
      t('الحركة'),
      t('المبلغ'),
      t('الرصيد بعد الحركة'),
      t('الحالة'),
    ]);
    for (final row in rowsInRange) {
      statement.appendRow([
        t(_fmtDateTime(row.date)),
        t(row.description.trim().isEmpty ? '-' : row.description.trim()),
        t('${row.amount.abs().toStringAsFixed(2)} ${row.direction == CustomerLedgerDirection.forUs ? '(لنا)' : row.direction == CustomerLedgerDirection.againstUs ? '(علينا)' : ''}'),
        t('${row.remainingBalanceAfterRow.abs().toStringAsFixed(2)} ${row.remainingBalanceAfterRow >= 0 ? 'لنا' : 'علينا'}'),
        t(row.status.name),
      ]);
    }

    final dir = await _exportDir();
    final stamp = _now().millisecondsSinceEpoch;
    final file = File('${dir.path}/customer_report_$stamp.xlsx');
    final encodeOverride = _excelEncodeOverride;
    final bytes = encodeOverride != null ? encodeOverride(excel) : excel.encode();
    if (bytes == null) throw Exception('Failed to export Excel');
    await file.writeAsBytes(bytes, flush: true);
    return file.path;
  }

  static String _formatWalletTxnType(dynamic type) {
    final str = type.toString();
    if (str.contains('transferOut')) return 'تحويل صادر';
    if (str.contains('receiveIn')) return 'استلام/إيداع';
    if (str.contains('feeDeduction')) return 'خصم عمولة';
    if (str.contains('adjustment')) return 'تسوية';
    return str;
  }

  static Future<String> exportWalletPdf({
    required WalletReportExportData data,
  }) async {
    final doc = await _newPdfDocument();
    final period = 'من ${_fmtDate(data.range.start)} إلى ${_fmtDate(data.range.end)}';

    doc.addPage(
      pw.MultiPage(
        build: (_) => [
          _rtlBlock([
            pw.Text(
              'كشف حساب محفظة',
              style: pw.TextStyle(font: _pdfBoldFont, fontSize: 18),
            ),
            pw.SizedBox(height: 8),
            pw.Text('اسم المحفظة: ${data.walletName}'),
            pw.Text('الرقم: ${data.walletNumber}'),
            pw.Text('الفترة: $period'),
            pw.SizedBox(height: 12),
            pw.Text(
              'ملخص الحركة',
              style: pw.TextStyle(font: _pdfBoldFont, fontSize: 14),
            ),
            pw.Text('الرصيد الحالي: ${data.currentBalance.toStringAsFixed(2)}'),
            pw.Text('إجمالي المستلم: ${data.totalReceived.toStringAsFixed(2)}'),
            pw.Text('إجمالي المحول: ${data.totalTransferred.toStringAsFixed(2)}'),
            pw.Text('إجمالي العمولات: ${data.totalFees.toStringAsFixed(2)}'),
            pw.Text('صافي الحركة: ${data.netMovement.toStringAsFixed(2)}'),
            pw.SizedBox(height: 12),
            pw.Text(
              'العمليات',
              style: pw.TextStyle(font: _pdfBoldFont, fontSize: 14),
            ),
            if (data.rows.isEmpty)
              pw.Text('لا توجد حركات في الفترة المختارة'),
            if (data.rows.isNotEmpty)
              pw.TableHelper.fromTextArray(
                headerStyle: pw.TextStyle(font: _pdfBoldFont, fontSize: 10),
                cellStyle: pw.TextStyle(font: _pdfBaseFont, fontSize: 9),
                cellAlignment: pw.Alignment.centerRight,
                headers: const [
                  'التاريخ',
                  'النوع',
                  'المرجع',
                  'المبلغ',
                  'الرصيد بعد الحركة',
                  'ملاحظات',
                ],
                data: data.rows
                    .map(
                      (r) => [
                        _fmtDateTime(r.date),
                        _formatWalletTxnType(r.transactionType),
                        r.reference ?? '',
                        (r.amount.inSmallestUnit / 100).toStringAsFixed(2),
                        (r.balanceAfter.inSmallestUnit / 100).toStringAsFixed(2),
                        r.reference ?? '',
                      ],
                    )
                    .toList(),
              ),
          ]),
        ],
      ),
    );

    final dir = await _exportDir();
    final stamp = _now().millisecondsSinceEpoch;
    final file = File('${dir.path}/wallet_report_$stamp.pdf');
    await file.writeAsBytes(await doc.save(), flush: true);
    return file.path;
  }

  static Future<String> exportTreasuryPdf({
    required TreasuryReportExportData data,
  }) async {
    final doc = await _newPdfDocument();
    final period = 'من ${_fmtDate(data.range.start)} إلى ${_fmtDate(data.range.end)}';

    doc.addPage(
      pw.MultiPage(
        build: (_) => [
          _rtlBlock([
            pw.Text(
              'كشف حساب الخزينة',
              style: pw.TextStyle(font: _pdfBoldFont, fontSize: 18),
            ),
            pw.SizedBox(height: 8),
            pw.Text('الفترة: $period'),
            pw.SizedBox(height: 12),
            pw.Text(
              'ملخص الحركة',
              style: pw.TextStyle(font: _pdfBoldFont, fontSize: 14),
            ),
            pw.Text('الرصيد الافتتاحي: ${data.openingBalance.toStringAsFixed(2)}'),
            pw.Text('إجمالي الداخل: ${data.totalIn.toStringAsFixed(2)}'),
            pw.Text('إجمالي الخارج: ${data.totalOut.toStringAsFixed(2)}'),
            pw.Text('إجمالي المصروفات: ${data.expenses.toStringAsFixed(2)}'),
            pw.Text('إجمالي التسويات: ${data.adjustments.toStringAsFixed(2)}'),
            pw.Text('الرصيد الختامي: ${data.closingBalance.toStringAsFixed(2)}'),
            pw.SizedBox(height: 12),
            pw.Text(
              'العمليات',
              style: pw.TextStyle(font: _pdfBoldFont, fontSize: 14),
            ),
            if (data.rows.isEmpty)
              pw.Text('لا توجد حركات في الفترة المختارة'),
            if (data.rows.isNotEmpty)
              pw.TableHelper.fromTextArray(
                headerStyle: pw.TextStyle(font: _pdfBoldFont, fontSize: 10),
                cellStyle: pw.TextStyle(font: _pdfBaseFont, fontSize: 9),
                cellAlignment: pw.Alignment.centerRight,
                headers: const [
                  'التاريخ',
                  'البيان',
                  'المبلغ',
                  'الرصيد بعد الحركة',
                  'ملاحظات',
                ],
                data: data.rows
                    .map(
                      (r) => [
                        _fmtDateTime(r.date),
                        r.description,
                        (r.amount.inSmallestUnit / 100).toStringAsFixed(2),
                        (r.balanceAfter.inSmallestUnit / 100).toStringAsFixed(2),
                        r.reference ?? '',
                      ],
                    )
                    .toList(),
              ),
          ]),
        ],
      ),
    );

    final dir = await _exportDir();
    final stamp = _now().millisecondsSinceEpoch;
    final file = File('${dir.path}/treasury_report_$stamp.pdf');
    await file.writeAsBytes(await doc.save(), flush: true);
    return file.path;
  }

  static Future<String> exportWalletExcel({
    required WalletReportExportData data,
  }) async {
    final excel = Excel.createExcel();

    CellValue t(String v) => TextCellValue(v);
    CellValue n(num v) =>
        v is int ? IntCellValue(v) : DoubleCellValue(v.toDouble());

    final period = 'من ${_fmtDate(data.range.start)} إلى ${_fmtDate(data.range.end)}';

    final summary = excel['الملخص'];
    summary.appendRow([t('اسم المحفظة'), t(data.walletName)]);
    summary.appendRow([t('الرقم'), t(data.walletNumber)]);
    summary.appendRow([t('الفترة'), t(period)]);
    summary.appendRow([]);
    summary.appendRow([t('الرصيد الحالي'), n(data.currentBalance)]);
    summary.appendRow([t('إجمالي المستلم'), n(data.totalReceived)]);
    summary.appendRow([t('إجمالي المحول'), n(data.totalTransferred)]);
    summary.appendRow([t('إجمالي العمولات'), n(data.totalFees)]);
    summary.appendRow([t('صافي الحركة'), n(data.netMovement)]);

    final statement = excel['كشف_الحساب'];
    statement.appendRow([
      t('التاريخ'),
      t('النوع'),
      t('المرجع'),
      t('المبلغ'),
      t('الرصيد بعد الحركة'),
      t('ملاحظات'),
    ]);
    for (final row in data.rows) {
      statement.appendRow([
        t(_fmtDateTime(row.date)),
        t(_formatWalletTxnType(row.transactionType)),
        t(row.reference ?? ''),
        n(row.amount.inSmallestUnit / 100),
        n(row.balanceAfter.inSmallestUnit / 100),
        t(row.reference ?? ''),
      ]);
    }

    final dir = await _exportDir();
    final stamp = _now().millisecondsSinceEpoch;
    final file = File('${dir.path}/wallet_report_$stamp.xlsx');
    final encodeOverride = _excelEncodeOverride;
    final bytes = encodeOverride != null ? encodeOverride(excel) : excel.encode();
    if (bytes == null) throw Exception('Failed to export wallet Excel');
    await file.writeAsBytes(bytes, flush: true);
    return file.path;
  }

  static Future<String> exportTreasuryExcel({
    required TreasuryReportExportData data,
  }) async {
    final excel = Excel.createExcel();

    CellValue t(String v) => TextCellValue(v);
    CellValue n(num v) =>
        v is int ? IntCellValue(v) : DoubleCellValue(v.toDouble());

    final period = 'من ${_fmtDate(data.range.start)} إلى ${_fmtDate(data.range.end)}';

    final summary = excel['الملخص'];
    summary.appendRow([t('كشف حساب الخزينة')]);
    summary.appendRow([t('الفترة'), t(period)]);
    summary.appendRow([]);
    summary.appendRow([t('الرصيد الافتتاحي'), n(data.openingBalance)]);
    summary.appendRow([t('إجمالي الداخل'), n(data.totalIn)]);
    summary.appendRow([t('إجمالي الخارج'), n(data.totalOut)]);
    summary.appendRow([t('إجمالي المصروفات'), n(data.expenses)]);
    summary.appendRow([t('إجمالي التسويات'), n(data.adjustments)]);
    summary.appendRow([t('الرصيد الختامي'), n(data.closingBalance)]);

    final statement = excel['كشف_الحساب'];
    statement.appendRow([
      t('التاريخ'),
      t('البيان'),
      t('المبلغ'),
      t('الرصيد بعد الحركة'),
      t('ملاحظات'),
    ]);
    for (final row in data.rows) {
      statement.appendRow([
        t(_fmtDateTime(row.date)),
        t(row.description),
        n(row.amount.inSmallestUnit / 100),
        n(row.balanceAfter.inSmallestUnit / 100),
        t(row.reference ?? ''),
      ]);
    }

    final dir = await _exportDir();
    final stamp = _now().millisecondsSinceEpoch;
    final file = File('${dir.path}/treasury_report_$stamp.xlsx');
    final encodeOverride = _excelEncodeOverride;
    final bytes = encodeOverride != null ? encodeOverride(excel) : excel.encode();
    if (bytes == null) throw Exception('Failed to export treasury Excel');
    await file.writeAsBytes(bytes, flush: true);
    return file.path;
  }

}
