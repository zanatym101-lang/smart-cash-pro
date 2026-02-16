import 'dart:io';

import 'package:excel/excel.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/widgets.dart' as pw;

import 'app_db.dart';
import 'reporting.dart';
import '../models/daily_close.dart';

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
    required this.latestTxns,
  });
}

class ReportExporter {
  static pw.Font? _pdfBaseFont;
  static pw.Font? _pdfBoldFont;
  static Future<void>? _fontLoadFuture;

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
    final downloads = await getDownloadsDirectory();
    if (downloads != null) return downloads;
    return getApplicationSupportDirectory();
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
    final bytes = excel.encode();
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
    required CustomerReportExportData data,
  }) async {
    final doc = await _newPdfDocument();
    final period =
        'From ${_fmtDate(data.range.start)} to ${_fmtDate(data.range.end)}';

    doc.addPage(
      pw.MultiPage(
        build: (_) => [
          pw.Text('Customer Report', style: pw.TextStyle(fontSize: 18)),
          pw.SizedBox(height: 8),
          pw.Text('Name: ${data.customerName}'),
          pw.Text(
            'Phone: ${data.customerPhone.trim().isEmpty ? '-' : data.customerPhone}',
          ),
          pw.Text('Period: $period'),
          pw.SizedBox(height: 12),
          pw.Text('Current Position'),
          pw.Text('Receivable: ${data.receivable.toStringAsFixed(2)}'),
          pw.Text('Payable: ${data.payable.toStringAsFixed(2)}'),
          pw.Text('Net: ${data.net.toStringAsFixed(2)}'),
          pw.SizedBox(height: 12),
          pw.Text('Period Movement'),
          pw.Text('Posted count: ${data.postedCount}'),
          pw.Text('Pending count: ${data.pendingCount}'),
          pw.Text('Posted volume: ${data.postedVolume.toStringAsFixed(2)}'),
          pw.Text('Pending volume: ${data.pendingVolume.toStringAsFixed(2)}'),
          pw.Text('Posted profit: ${data.postedProfit.toStringAsFixed(2)}'),
          pw.SizedBox(height: 12),
          pw.Text('Operation Types'),
          pw.Text('Transfer: ${data.transferCount}'),
          pw.Text('Receive: ${data.receiveCount}'),
          pw.Text('Fawry: ${data.fawryCount}'),
          pw.SizedBox(height: 12),
          pw.Text('Latest Operations'),
          if (data.latestTxns.isEmpty)
            pw.Text('No operations in selected period'),
          ...data.latestTxns.map(
            (t) => pw.Text(
              '${_fmtDateTime(t.date)} | ${t.kind} | ${t.status} | ${t.amount.toStringAsFixed(2)}',
            ),
          ),
        ],
      ),
    );

    final dir = await _exportDir();
    final stamp = DateTime.now().millisecondsSinceEpoch;
    final file = File('${dir.path}/customer_report_$stamp.pdf');
    await file.writeAsBytes(await doc.save(), flush: true);
    return file.path;
  }

  static Future<String> exportCustomerExcel({
    required CustomerReportExportData data,
  }) async {
    final excel = Excel.createExcel();

    CellValue t(String v) => TextCellValue(v);
    CellValue n(num v) =>
        v is int ? IntCellValue(v) : DoubleCellValue(v.toDouble());

    final period =
        'From ${_fmtDate(data.range.start)} to ${_fmtDate(data.range.end)}';

    final summary = excel['Summary'];
    summary.appendRow([t('Customer Name'), t(data.customerName)]);
    summary.appendRow([
      t('Phone'),
      t(data.customerPhone.trim().isEmpty ? '-' : data.customerPhone),
    ]);
    summary.appendRow([t('Period'), t(period)]);
    summary.appendRow([]);
    summary.appendRow([t('Receivable'), n(data.receivable)]);
    summary.appendRow([t('Payable'), n(data.payable)]);
    summary.appendRow([t('Net'), n(data.net)]);
    summary.appendRow([]);
    summary.appendRow([t('Posted Count'), n(data.postedCount)]);
    summary.appendRow([t('Pending Count'), n(data.pendingCount)]);
    summary.appendRow([t('Posted Volume'), n(data.postedVolume)]);
    summary.appendRow([t('Pending Volume'), n(data.pendingVolume)]);
    summary.appendRow([t('Posted Profit'), n(data.postedProfit)]);
    summary.appendRow([]);
    summary.appendRow([t('Transfer Count'), n(data.transferCount)]);
    summary.appendRow([t('Receive Count'), n(data.receiveCount)]);
    summary.appendRow([t('Fawry Count'), n(data.fawryCount)]);

    final operations = excel['Operations'];
    operations.appendRow([t('Date'), t('Kind'), t('Status'), t('Amount')]);
    for (final row in data.latestTxns) {
      operations.appendRow([
        t(_fmtDateTime(row.date)),
        t(row.kind),
        t(row.status),
        n(row.amount),
      ]);
    }

    final dir = await _exportDir();
    final stamp = DateTime.now().millisecondsSinceEpoch;
    final file = File('${dir.path}/customer_report_$stamp.xlsx');
    final bytes = excel.encode();
    if (bytes == null) throw Exception('Failed to export customer Excel');
    await file.writeAsBytes(bytes, flush: true);
    return file.path;
  }
}
