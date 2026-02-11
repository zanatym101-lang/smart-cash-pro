import 'dart:io';

import 'package:excel/excel.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/widgets.dart' as pw;

import '../data/reporting.dart';
import 'app_db.dart';

class ReportExporter {
  static String _fmtDate(DateTime d) {
    final y = d.year.toString().padLeft(4, '0');
    final m = d.month.toString().padLeft(2, '0');
    final day = d.day.toString().padLeft(2, '0');
    return '$y-$m-$day';
  }

  static Future<Directory> _exportDir() async {
    final downloads = await getDownloadsDirectory();
    if (downloads != null) return downloads;
    return getApplicationSupportDirectory();
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
    final doc = pw.Document();
    final period = 'من ${_fmtDate(range.start)} إلى ${_fmtDate(range.end)}';

    doc.addPage(
      pw.Page(
        build: (_) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text('تقرير الأرباح', style: pw.TextStyle(fontSize: 18)),
            pw.Text('الفترة: $period'),
            pw.SizedBox(height: 12),
            pw.Text('الأرباح'),
            pw.Text('تحويل: ${data.profit.transfer.toStringAsFixed(2)}'),
            pw.Text('استلام: ${data.profit.receive.toStringAsFixed(2)}'),
            pw.Text('فوري: ${data.profit.fawry.toStringAsFixed(2)}'),
            pw.Text('الإجمالي: ${data.profit.total.toStringAsFixed(2)}'),
            pw.SizedBox(height: 12),
            pw.Text('حركة الدرج'),
            pw.Text('داخل: ${data.cashflow.inflow.toStringAsFixed(2)}'),
            pw.Text('خارج: ${data.cashflow.outflow.toStringAsFixed(2)}'),
            pw.Text('صافي: ${data.cashflow.net.toStringAsFixed(2)}'),
            pw.SizedBox(height: 12),
            pw.Text('ملخص العمليات'),
            pw.Text('عدد التحويلات: ${data.ops.transferCount}'),
            pw.Text('عدد الاستلامات: ${data.ops.receiveCount}'),
            pw.Text('عدد فوري نقدي: ${data.ops.fawryCashCount}'),
            pw.Text('عدد فوري آجل: ${data.ops.fawryCreditCount}'),
            pw.Text('عدد المصروفات: ${data.ops.expenseCount}'),
            pw.Text('عدد تحصيل المستحقات: ${data.ops.claimCollectCount}'),
            pw.Text('عدد سداد المستحقات: ${data.ops.claimPayCount}'),
            pw.Text('عدد المعلّق: ${data.ops.pendingCount}'),
            pw.SizedBox(height: 12),
            pw.Text('المستحقات (المفتوحة)'),
            pw.Text('لنا: ${data.claims.receivableOpen.toStringAsFixed(2)}'),
            pw.Text('علينا: ${data.claims.payableOpen.toStringAsFixed(2)}'),
            pw.Text('الصافي: ${data.claims.net.toStringAsFixed(2)}'),
            pw.SizedBox(height: 12),
            pw.Text('الخزنة الإجمالية'),
            pw.Text('الدرج: ${treasury.drawerBalance.toStringAsFixed(2)}'),
            pw.Text('المحافظ: ${treasury.walletsTotal.toStringAsFixed(2)}'),
            pw.Text('الإجمالي: ${(treasury.drawerBalance + treasury.walletsTotal).toStringAsFixed(2)}'),
          ],
        ),
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
    CellValue n(num v) => v is int ? IntCellValue(v) : DoubleCellValue(v.toDouble());

    final period = 'من ${_fmtDate(range.start)} إلى ${_fmtDate(range.end)}';

    final profitSheet = excel['الأرباح'];
    profitSheet.appendRow([t('الفترة'), t(period)]);
    profitSheet.appendRow([t('ربح التحويل'), n(data.profit.transfer)]);
    profitSheet.appendRow([t('ربح الاستلام'), n(data.profit.receive)]);
    profitSheet.appendRow([t('ربح فوري'), n(data.profit.fawry)]);
    profitSheet.appendRow([t('إجمالي الربح'), n(data.profit.total)]);

    final cashSheet = excel['حركة الدرج'];
    cashSheet.appendRow([t('داخل'), n(data.cashflow.inflow)]);
    cashSheet.appendRow([t('خارج'), n(data.cashflow.outflow)]);
    cashSheet.appendRow([t('صافي'), n(data.cashflow.net)]);
    cashSheet.appendRow([]);
    cashSheet.appendRow([t('تفصيل الداخل')]);
    for (final e in data.cashflow.inflowByType.entries) {
      cashSheet.appendRow([t(e.key), n(e.value)]);
    }
    cashSheet.appendRow([]);
    cashSheet.appendRow([t('تفصيل الخارج')]);
    for (final e in data.cashflow.outflowByType.entries) {
      cashSheet.appendRow([t(e.key), n(e.value)]);
    }

    final opsSheet = excel['ملخص العمليات'];
    opsSheet.appendRow([t('عدد التحويلات'), n(data.ops.transferCount)]);
    opsSheet.appendRow([t('عدد الاستلامات'), n(data.ops.receiveCount)]);
    opsSheet.appendRow([t('عدد فوري نقدي'), n(data.ops.fawryCashCount)]);
    opsSheet.appendRow([t('عدد فوري آجل'), n(data.ops.fawryCreditCount)]);
    opsSheet.appendRow([t('عدد المصروفات'), n(data.ops.expenseCount)]);
    opsSheet.appendRow([t('عدد تحصيل المستحقات'), n(data.ops.claimCollectCount)]);
    opsSheet.appendRow([t('عدد سداد المستحقات'), n(data.ops.claimPayCount)]);
    opsSheet.appendRow([t('عدد المعلّق'), n(data.ops.pendingCount)]);

    final claimsSheet = excel['المستحقات'];
    claimsSheet.appendRow([t('إجمالي لنا (مفتوحة)'), n(data.claims.receivableOpen)]);
    claimsSheet.appendRow([t('إجمالي علينا (مفتوحة)'), n(data.claims.payableOpen)]);
    claimsSheet.appendRow([t('الصافي'), n(data.claims.net)]);

    final treasurySheet = excel['الخزنة'];
    treasurySheet.appendRow([t('رصيد الدرج'), n(treasury.drawerBalance)]);
    treasurySheet.appendRow([t('إجمالي المحافظ'), n(treasury.walletsTotal)]);
    treasurySheet.appendRow([t('إجمالي الخزنة'), n(treasury.drawerBalance + treasury.walletsTotal)]);

    final dir = await _exportDir();
    final name = _fileName('report', range, 'xlsx');
    final file = File('${dir.path}/$name');
    final bytes = excel.encode();
    if (bytes == null) throw Exception('فشل تصدير Excel');
    await file.writeAsBytes(bytes, flush: true);
    return file.path;
  }
}
