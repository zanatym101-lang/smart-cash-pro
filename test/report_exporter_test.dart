import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:king_wallet_accounting/data/app_db.dart';
import 'package:king_wallet_accounting/data/report_exporter.dart';
import 'package:king_wallet_accounting/data/reporting.dart';
import 'package:king_wallet_accounting/models/daily_close.dart';
import 'package:pdf/widgets.dart' as pw;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late DateRange range;
  late ReportData reportData;
  late TreasurySnapshot treasury;
  late CustomerReportExportData customerData;
  late DailyClose dailyClose;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('kw_report_export_test_');

    range = DateRange(start: DateTime(2026, 2, 1), end: DateTime(2026, 2, 15));

    reportData = ReportData(
      profit: const ProfitReport(transfer: 10, receive: 20, fawry: 5),
      cashflow: const DrawerCashflow(
        inflow: 250,
        outflow: 120,
        inflowByType: {'تحويل': 100, 'استلام': 150},
        outflowByType: {'مصروف': 120},
      ),
      ops: const OperationalSummary(
        transferCount: 2,
        receiveCount: 3,
        fawryCashCount: 1,
        fawryCreditCount: 1,
        expenseCount: 1,
        claimCollectCount: 1,
        claimPayCount: 0,
        pendingCount: 2,
      ),
      claims: const ClaimsSnapshot(receivableOpen: 80, payableOpen: 30),
      reconciliation: const ReconciliationReport(
        drawer: ReconciliationLine(
          label: 'الدرج',
          opening: 100,
          inflow: 250,
          outflow: 120,
          expectedClosing: 230,
          actualClosing: 230,
        ),
        wallets: ReconciliationLine(
          label: 'المحافظ',
          opening: 500,
          inflow: 300,
          outflow: 80,
          expectedClosing: 720,
          actualClosing: 720,
        ),
        total: ReconciliationLine(
          label: 'الإجمالي',
          opening: 600,
          inflow: 550,
          outflow: 200,
          expectedClosing: 950,
          actualClosing: 950,
        ),
      ),
    );

    treasury = const TreasurySnapshot(
      drawerBalance: 230,
      walletsTotal: 720,
      fawryBalance: 0,
      drawerActualBalance: 230,
      walletsActualTotal: 720,
      fawryActualBalance: 0,
      pendingCount: 2,
      pendingInflow: 60,
      pendingOutflow: 40,
      claimsReceivableOpen: 80,
      claimsPayableOpen: 30,
      pendingReceivableOpen: 0,
      pendingPayableOpen: 0,
      profitApprovedTotal: 35,
      dailyProfit: 35,
      monthlyProfit: 140,
    );

    customerData = CustomerReportExportData(
      customerName: 'Customer A',
      customerPhone: '01012345678',
      range: range,
      receivable: 120,
      payable: 30,
      net: 90,
      postedCount: 4,
      pendingCount: 1,
      postedVolume: 1000,
      pendingVolume: 250,
      postedProfit: 45,
      transferCount: 2,
      receiveCount: 1,
      fawryCount: 1,
      latestTxns: [
        CustomerTxnExportRow(
          date: DateTime(2026, 2, 12, 11, 20),
          kind: 'transfer',
          status: 'posted',
          amount: 300,
        ),
      ],
    );

    dailyClose = DailyClose(
      id: 1,
      dateKey: '2026-02-15',
      closedAt: DateTime(2026, 2, 15, 23, 59),
      drawerBalance: 230,
      walletsTotal: 720,
      treasuryTotal: 950,
      profitTotal: 35,
      profitTransfer: 10,
      profitReceive: 20,
      profitFawry: 5,
      inflow: 250,
      outflow: 120,
      net: 130,
      transferCount: 2,
      receiveCount: 3,
      fawryCashCount: 1,
      fawryCreditCount: 1,
      expenseCount: 1,
      claimCollectCount: 1,
      claimPayCount: 0,
      pendingCount: 2,
    );

    ReportExporter.setTestOverrides(
      exportDirResolver: () async => tempDir,
      pdfDocumentFactory: _testPdfDocument,
      nowProvider: () => DateTime(2026, 2, 16, 12, 34, 56),
    );
  });

  tearDown(() async {
    ReportExporter.resetTestOverrides();
    if (tempDir.existsSync()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('exportDirectory creates target directory when missing', () async {
    final target = Directory('${tempDir.path}/exports');
    ReportExporter.setTestOverrides(
      exportDirResolver: () async => target,
      pdfDocumentFactory: _testPdfDocument,
      nowProvider: () => DateTime(2026, 2, 16, 12, 34, 56),
    );

    final dir = await ReportExporter.exportDirectory();
    expect(await dir.exists(), isTrue);
    expect(dir.path.replaceAll('\\', '/'), endsWith('/exports'));
  });

  test('exportPdf and exportExcel create files', () async {
    final pdfPath = await ReportExporter.exportPdf(
      data: reportData,
      treasury: treasury,
      range: range,
    );
    final excelPath = await ReportExporter.exportExcel(
      data: reportData,
      treasury: treasury,
      range: range,
    );

    expect(File(pdfPath).existsSync(), isTrue);
    expect(File(excelPath).existsSync(), isTrue);
    expect(pdfPath, endsWith('report_2026-02-01_2026-02-15.pdf'));
    expect(excelPath, endsWith('report_2026-02-01_2026-02-15.xlsx'));
  });

  test('exportDailyClosePdf uses date key in output name', () async {
    final path = await ReportExporter.exportDailyClosePdf(close: dailyClose);
    expect(File(path).existsSync(), isTrue);
    expect(path, endsWith('daily_close_2026-02-15.pdf'));
  });

  test(
    'customer exports generate deterministic names with test clock',
    () async {
      final expectedStamp = DateTime(
        2026,
        2,
        16,
        12,
        34,
        56,
      ).millisecondsSinceEpoch;

      final pdfPath = await ReportExporter.exportCustomerPdf(
        data: customerData,
      );
      final xlsxPath = await ReportExporter.exportCustomerExcel(
        data: customerData,
      );

      expect(File(pdfPath).existsSync(), isTrue);
      expect(File(xlsxPath).existsSync(), isTrue);
      expect(pdfPath, endsWith('customer_report_$expectedStamp.pdf'));
      expect(xlsxPath, endsWith('customer_report_$expectedStamp.xlsx'));
    },
  );

  test('excel exporters throw when encoder returns null bytes', () async {
    ReportExporter.setTestOverrides(
      exportDirResolver: () async => tempDir,
      pdfDocumentFactory: _testPdfDocument,
      nowProvider: () => DateTime(2026, 2, 16, 12, 34, 56),
      excelEncode: (_) => null,
    );

    await expectLater(
      ReportExporter.exportExcel(
        data: reportData,
        treasury: treasury,
        range: range,
      ),
      throwsA(isA<Exception>()),
    );
    await expectLater(
      ReportExporter.exportCustomerExcel(data: customerData),
      throwsA(isA<Exception>()),
    );
  });
}

Future<pw.Document> _testPdfDocument() async {
  final bytes = await File('assets/fonts/Amiri-Regular.ttf').readAsBytes();
  final font = pw.Font.ttf(ByteData.sublistView(Uint8List.fromList(bytes)));
  return pw.Document(
    theme: pw.ThemeData.withFont(base: font, bold: font),
  );
}
