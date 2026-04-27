import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:king_wallet_accounting/data/app_db.dart';
import 'package:king_wallet_accounting/data/app_session.dart';
import 'package:king_wallet_accounting/screens/dashboard_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const pathProviderChannel = MethodChannel('plugins.flutter.io/path_provider');
  final supportDir = Directory.systemTemp.createTempSync(
    'kw_dashboard_pending_open_regression_',
  );

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

  Future<void> seedPendingTransferWithPartialCollection() async {
    final db = AppDb.instance;
    final walletId = await db.addWallet(
      name: 'Dashboard Pending Wallet',
      phone: '01010000041',
      openingBalance: 3000,
    );
    final txnId = await db.addTransfer(
      walletId: walletId,
      amount: 500,
      clientFee: 5,
      networkFee: 0,
      transferType: 'type1',
      isPending: true,
      party: 'Dashboard Pending Customer',
      note: '01044445555',
    );
    await db.addPendingSettlementForTxn(pendingTxnId: txnId, amount: 400);
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
    'dashboard pending card uses remaining open amount after partial collection',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1080, 2200));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.runAsync(seedPendingTransferWithPartialCollection);

      await tester.pumpWidget(const MaterialApp(home: DashboardScreen()));
      await pumpUntilFound(tester, find.text('العمليات الآجلة المفتوحة'));
      await pumpFrames(tester, count: 10);

      expect(find.textContaining('إجمالي القيمة: 105.00'), findsOneWidget);

      await tester.tap(find.textContaining('عرض التفاصيل').first);
      await pumpFrames(tester, count: 8);
      expect(find.text('فوري (فعلي)'), findsNothing);

      await tester.tap(find.text('الآجل').first, warnIfMissed: false);
      await pumpFrames(tester, count: 10);

      expect(find.text('105.00'), findsWidgets);
      expect(find.text('إجمالي المتبقي المفتوح في الآجل'), findsOneWidget);
      expect(find.text('خارج الآجل'), findsOneWidget);
      expect(find.text('داخل الآجل'), findsOneWidget);
    },
  );
}
