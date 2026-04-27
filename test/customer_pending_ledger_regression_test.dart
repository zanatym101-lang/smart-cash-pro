import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:king_wallet_accounting/data/app_db.dart';
import 'package:king_wallet_accounting/data/app_session.dart';
import 'package:king_wallet_accounting/models/transaction.dart';
import 'package:king_wallet_accounting/screens/customers_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const pathProviderChannel = MethodChannel('plugins.flutter.io/path_provider');
  final supportDir = Directory.systemTemp.createTempSync(
    'kw_customer_pending_ledger_regression_',
  );

  const transferCustomer = 'Pending Transfer Ledger Customer';
  const receiveCustomer = 'Pending Receive Ledger Customer';
  const customerPhone = '01055556666';

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

  Finder sheetScope(Finder child) {
    return find.descendant(of: find.byType(BottomSheet), matching: child);
  }

  Finder customerSummaryTextContaining(String text) {
    return find.byWidgetPredicate(
      (w) => w is Text && (w.data?.contains(text) ?? false),
    );
  }

  Future<Txn> seedPendingTransferWithPartialSettlement() async {
    final db = AppDb.instance;
    final walletId = await db.addWallet(
      name: 'Transfer Ledger Wallet',
      phone: '01010000021',
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
    return (await db.listTxns()).firstWhere((t) => t.id == txnId);
  }

  Future<Txn> seedPendingReceiveWithPartialSettlement() async {
    final db = AppDb.instance;
    final walletId = await db.addWallet(
      name: 'Receive Ledger Wallet',
      phone: '01010000022',
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
    return (await db.listTxns()).firstWhere((t) => t.id == txnId);
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
    'pending transfer ledger should keep original amount while summary shows remaining open',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1080, 2200));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final originalTxn =
          (await tester.runAsync(seedPendingTransferWithPartialSettlement))!;
      final expectedDate =
          '${originalTxn.entryDate.year}-${originalTxn.entryDate.month.toString().padLeft(2, '0')}-${originalTxn.entryDate.day.toString().padLeft(2, '0')}';

      await tester.pumpWidget(const MaterialApp(home: CustomersScreen()));
      await pumpUntilFound(tester, find.text(transferCustomer));

      expect(
        customerSummaryTextContaining('عليه: 500.00 | له: 0.00'),
        findsOneWidget,
      );

      await tester.tap(find.text(transferCustomer).first);
      await pumpFrames(tester);
      await pumpUntilFound(tester, find.byType(BottomSheet));

      final originalDetails = sheetScope(
        find.textContaining('المطلوب من العميل: 1000.00'),
      );
      expect(originalDetails, findsOneWidget);

      final originalRow = find.ancestor(
        of: originalDetails,
        matching: find.byType(InkWell),
      );
      expect(
        find.descendant(of: originalRow.first, matching: find.text('+1000.00')),
        findsOneWidget,
      );

      expect(sheetScope(find.textContaining('المبلغ: 500.00')), findsOneWidget);

      await tester.tap(originalRow.first, warnIfMissed: false);
      await pumpFrames(tester, count: 8);

      expect(find.textContaining('التاريخ: $expectedDate'), findsOneWidget);
    },
  );

  testWidgets(
    'pending receive ledger should keep original amount while summary shows remaining open',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1080, 2200));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final originalTxn =
          (await tester.runAsync(seedPendingReceiveWithPartialSettlement))!;
      final expectedDate =
          '${originalTxn.entryDate.year}-${originalTxn.entryDate.month.toString().padLeft(2, '0')}-${originalTxn.entryDate.day.toString().padLeft(2, '0')}';

      await tester.pumpWidget(const MaterialApp(home: CustomersScreen()));
      await pumpUntilFound(tester, find.text(receiveCustomer));

      expect(
        customerSummaryTextContaining('عليه: 0.00 | له: 500.00'),
        findsOneWidget,
      );

      await tester.tap(find.text(receiveCustomer).first);
      await pumpFrames(tester);
      await pumpUntilFound(tester, find.byType(BottomSheet));

      final originalDetails = sheetScope(
        find.textContaining('المبلغ المستلم: 1000.00'),
      );
      expect(originalDetails, findsOneWidget);

      final originalRow = find.ancestor(
        of: originalDetails,
        matching: find.byType(InkWell),
      );
      expect(
        find.descendant(of: originalRow.first, matching: find.text('-1000.00')),
        findsOneWidget,
      );

      expect(sheetScope(find.textContaining('المبلغ: 500.00')), findsOneWidget);

      await tester.tap(originalRow.first, warnIfMissed: false);
      await pumpFrames(tester, count: 8);

      expect(find.textContaining('التاريخ: $expectedDate'), findsOneWidget);
    },
  );
}
