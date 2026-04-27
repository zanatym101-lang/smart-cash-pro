import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:king_wallet_accounting/data/app_db.dart';
import 'package:king_wallet_accounting/data/app_session.dart';
import 'package:king_wallet_accounting/screens/customer_report_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const pathProviderChannel = MethodChannel('plugins.flutter.io/path_provider');
  final supportDir = Directory.systemTemp.createTempSync(
    'kw_customer_report_pending_regression_',
  );

  const transferCustomer = 'Customer Report Pending Transfer';
  const receiveCustomer = 'Customer Report Pending Receive';
  const customerPhone = '01077778888';

  Future<void> resetAndActivate() async {
    AppSession.enterAdmin();
    final db = AppDb.instance;
    final info = await db.getLicenseInfo();
    final code = db.generateActivationCodeForDeviceCode(info.deviceCode);
    await db.activateWithCode(code);
    await db.resetEncryptedRestoreGuard();
    await db.resetDatabaseEmpty();
  }

  Future<void> pumpUntilFound(
    WidgetTester tester,
    Finder finder, {
    int maxPumps = 120,
  }) async {
    for (var i = 0; i < maxPumps; i++) {
      await tester.runAsync(
        () async => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump(const Duration(milliseconds: 80));
      if (finder.evaluate().isNotEmpty) return;
    }
    fail('Widget not found in time: $finder');
  }

  Future<void> pumpFrames(WidgetTester tester, {int count = 12}) async {
    for (var i = 0; i < count; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  Future<void> seedPendingTransferWithPartialSettlement() async {
    final db = AppDb.instance;
    final walletId = await db.addWallet(
      name: 'Report Pending Transfer Wallet',
      phone: '01010000031',
      openingBalance: 5000,
    );
    final txnId = await db.addTransfer(
      walletId: walletId,
      amount: 1000,
      clientFee: 0,
      networkFee: 0,
      transferType: 'type2',
      isPending: true,
      party: transferCustomer,
      note: customerPhone,
    );
    await db.addPendingSettlementForTxn(pendingTxnId: txnId, amount: 500);
  }

  Future<void> seedPendingReceiveWithPartialSettlement() async {
    final db = AppDb.instance;
    final walletId = await db.addWallet(
      name: 'Report Pending Receive Wallet',
      phone: '01010000032',
      openingBalance: 5000,
    );
    final txnId = await db.addReceive(
      walletId: walletId,
      amount: 1000,
      commission: 0,
      receiveType: 'cash',
      isPending: true,
      party: receiveCustomer,
      note: customerPhone,
    );
    await db.addPendingSettlementForTxn(pendingTxnId: txnId, amount: 500);
  }

  setUpAll(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProviderChannel, (call) async {
          if (call.method.endsWith('Paths')) {
            return <String>[supportDir.path];
          }
          return supportDir.path;
        });
  });

  setUp(() async {
    await resetAndActivate();
  });

  tearDownAll(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProviderChannel, null);
    try {
      if (supportDir.existsSync()) {
        supportDir.deleteSync(recursive: true);
      }
    } catch (_) {}
  });

  testWidgets(
    'customer report pending transfer partial settlement shows remaining total and original statement row',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1080, 2200));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.runAsync(seedPendingTransferWithPartialSettlement);

      await tester.pumpWidget(
        const MaterialApp(
          home: CustomerReportScreen(
            customerName: transferCustomer,
            customerPhone: customerPhone,
          ),
        ),
      );
      await pumpUntilFound(tester, find.byType(ChoiceChip));
      await pumpFrames(tester, count: 10);

      expect(find.textContaining('لنا: 500.00'), findsOneWidget);
      expect(find.textContaining('علينا: 0.00'), findsOneWidget);

      expect(find.text('تحويل آجل'), findsOneWidget);
      expect(find.text('+1000.00'), findsOneWidget);

      expect(find.text('تحصيل مستحق'), findsOneWidget);
      expect(find.text('-500.00'), findsOneWidget);
    },
  );

  testWidgets(
    'customer report pending receive partial settlement shows remaining total and original statement row',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1080, 2200));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.runAsync(seedPendingReceiveWithPartialSettlement);

      await tester.pumpWidget(
        const MaterialApp(
          home: CustomerReportScreen(
            customerName: receiveCustomer,
            customerPhone: customerPhone,
          ),
        ),
      );
      await pumpUntilFound(tester, find.byType(ChoiceChip));
      await pumpFrames(tester, count: 10);

      expect(find.textContaining('لنا: 0.00'), findsOneWidget);
      expect(find.textContaining('علينا: 500.00'), findsOneWidget);

      expect(find.text('استلام آجل'), findsOneWidget);
      expect(find.text('-1000.00'), findsOneWidget);

      expect(find.text('سداد مستحق'), findsOneWidget);
      expect(find.text('+500.00'), findsOneWidget);
    },
  );
}
