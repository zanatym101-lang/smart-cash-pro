import 'dart:io';

import 'package:excel/excel.dart';
import 'package:flutter/foundation.dart';
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
    required CustomerReportExportData data,
  }) async {
    final doc = await _newPdfDocument();
    final period =
        'من ${_fmtDate(data.range.start)} إلى ${_fmtDate(data.range.end)}';
    final netLabel = data.net >= 0 ? 'صافي لنا' : 'صافي علينا';

    doc.addPage(
      pw.MultiPage(
        build: (_) => [
          _rtlBlock([
            pw.Text(
              'كشف حساب عميل',
              style: pw.TextStyle(font: _pdfBoldFont, fontSize: 18),
            ),
            pw.SizedBox(height: 8),
            pw.Text('العميل: ${data.customerName}'),
            pw.Text(
              'الهاتف: ${data.customerPhone.trim().isEmpty ? '-' : data.customerPhone}',
            ),
            pw.Text('الفترة: $period'),
            pw.SizedBox(height: 12),
            pw.Text(
              'الموقف الحالي',
              style: pw.TextStyle(font: _pdfBoldFont, fontSize: 14),
            ),
            pw.Text('لنا: ${data.receivable.toStringAsFixed(2)}'),
            pw.Text('علينا: ${data.payable.toStringAsFixed(2)}'),
            pw.Text('$netLabel: ${data.net.abs().toStringAsFixed(2)}'),
            pw.SizedBox(height: 12),
            pw.Text(
              'ملخص الفترة',
              style: pw.TextStyle(font: _pdfBoldFont, fontSize: 14),
            ),
            pw.Text(
              'الرصيد الافتتاحي: ${data.openingNet.abs().toStringAsFixed(2)} ${data.openingNet >= 0 ? '(لنا)' : '(علينا)'}',
            ),
            pw.Text(
              'الرصيد الختامي: ${data.closingNet.abs().toStringAsFixed(2)} ${data.closingNet >= 0 ? '(لنا)' : '(علينا)'}',
            ),
            pw.Text(
              'منفذ: ${data.postedCount} • حجم ${data.postedVolume.toStringAsFixed(2)}',
            ),
            pw.Text(
              'معلق: ${data.pendingCount} • حجم ${data.pendingVolume.toStringAsFixed(2)}',
            ),
            pw.Text('ربح منفذ: ${data.postedProfit.toStringAsFixed(2)}'),
            pw.SizedBox(height: 12),
            pw.Text(
              'أنواع العمليات',
              style: pw.TextStyle(font: _pdfBoldFont, fontSize: 14),
            ),
            pw.Text('تحويل: ${data.transferCount}'),
            pw.Text('استلام: ${data.receiveCount}'),
            pw.Text('فوري: ${data.fawryCount}'),
            pw.SizedBox(height: 12),
            pw.Text(
              'كشف الحركات (الرصيد بعد كل حركة)',
              style: pw.TextStyle(font: _pdfBoldFont, fontSize: 14),
            ),
            if (data.statementRows.isEmpty)
              pw.Text('لا توجد حركات في الفترة المختارة'),
            if (data.statementRows.isNotEmpty)
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
                data: data.statementRows
                    .map(
                      (r) => [
                        _fmtDateTime(r.date),
                        r.title,
                        r.amountSigned.toStringAsFixed(2),
                        '${r.runningNet.abs().toStringAsFixed(2)} ${r.runningSideLabel}',
                        r.status,
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
    required CustomerReportExportData data,
  }) async {
    final excel = Excel.createExcel();

    CellValue t(String v) => TextCellValue(v);
    CellValue n(num v) =>
        v is int ? IntCellValue(v) : DoubleCellValue(v.toDouble());

    final period =
        'من ${_fmtDate(data.range.start)} إلى ${_fmtDate(data.range.end)}';
    final openingLabel = data.openingNet >= 0 ? 'لنا' : 'علينا';
    final closingLabel = data.closingNet >= 0 ? 'لنا' : 'علينا';
    final netLabel = data.net >= 0 ? 'لنا' : 'علينا';

    final summary = excel['الملخص'];
    summary.appendRow([t('اسم العميل'), t(data.customerName)]);
    summary.appendRow([
      t('الهاتف'),
      t(data.customerPhone.trim().isEmpty ? '-' : data.customerPhone),
    ]);
    summary.appendRow([t('الفترة'), t(period)]);
    summary.appendRow([]);
    summary.appendRow([t('لنا'), n(data.receivable)]);
    summary.appendRow([t('علينا'), n(data.payable)]);
    summary.appendRow([t('الصافي ($netLabel)'), n(data.net.abs())]);
    summary.appendRow([]);
    summary.appendRow([
      t('الرصيد الافتتاحي ($openingLabel)'),
      n(data.openingNet.abs()),
    ]);
    summary.appendRow([
      t('الرصيد الختامي ($closingLabel)'),
      n(data.closingNet.abs()),
    ]);
    summary.appendRow([]);
    summary.appendRow([t('عدد المنفذ'), n(data.postedCount)]);
    summary.appendRow([t('عدد المعلق'), n(data.pendingCount)]);
    summary.appendRow([t('حجم المنفذ'), n(data.postedVolume)]);
    summary.appendRow([t('حجم المعلق'), n(data.pendingVolume)]);
    summary.appendRow([t('ربح منفذ'), n(data.postedProfit)]);
    summary.appendRow([]);
    summary.appendRow([t('عدد التحويل'), n(data.transferCount)]);
    summary.appendRow([t('عدد الاستلام'), n(data.receiveCount)]);
    summary.appendRow([t('عدد فوري'), n(data.fawryCount)]);

    final operations = excel['العمليات'];
    operations.appendRow([t('التاريخ'), t('النوع'), t('الحالة'), t('المبلغ')]);
    for (final row in data.latestTxns) {
      operations.appendRow([
        t(_fmtDateTime(row.date)),
        t(row.kind),
        t(row.status),
        n(row.amount),
      ]);
    }

    final statement = excel['كشف_الحساب'];
    statement.appendRow([
      t('التاريخ'),
      t('الحركة'),
      t('التفاصيل'),
      t('الحالة'),
      t('المبلغ'),
      t('الرصيد بعد الحركة'),
    ]);
    for (final row in data.statementRows) {
      statement.appendRow([
        t(_fmtDateTime(row.date)),
        t(row.title),
        t((row.details ?? '').trim().isEmpty ? '-' : row.details!.trim()),
        t(row.status),
        n(row.amountSigned),
        t('${row.runningNet.abs().toStringAsFixed(2)} ${row.runningSideLabel}'),
      ]);
    }

    final dir = await _exportDir();
    final stamp = _now().millisecondsSinceEpoch;
    final file = File('${dir.path}/customer_report_$stamp.xlsx');
    final encodeOverride = _excelEncodeOverride;
    final bytes = encodeOverride != null
        ? encodeOverride(excel)
        : excel.encode();
    if (bytes == null) throw Exception('Failed to export customer Excel');
    await file.writeAsBytes(bytes, flush: true);
    return file.path;
  }
}
