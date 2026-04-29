import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:king_wallet_accounting/data/app_db.dart';
import 'package:king_wallet_accounting/data/app_session.dart';
import 'package:king_wallet_accounting/screens/claims_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const pathProviderChannel = MethodChannel('plugins.flutter.io/path_provider');
  final supportDir = Directory.systemTemp.createTempSync(
    'kw_claims_chronology_regression_',
  );

  const customerName = 'Claims Chronology Customer';
  const customerPhone = '01012344321';

  Future<void> resetAndActivate() async {
    AppSession.enterAdmin();
    final db = AppDb.instance;
    final info = await db.getLicenseInfo();
    final code = db.generateActivationCodeForDeviceCode(info.deviceCode);
    await db.activateWithCode(code);
    await db.resetEncryptedRestoreGuard();
    await db.resetDatabaseEmpty();
  }

  Future<void> seedDeferredClaimTimeline() async {
    final db = AppDb.instance;
    final walletId = await db.addWallet(
      name: 'Claims Timeline Wallet',
      phone: '01010000444',
      openingBalance: 3000,
    );
    final txnId = await db.addTransfer(
      walletId: walletId,
      amount: 900,
      clientFee: 5,
      networkFee: 0,
      transferType: 'type1',
      isPending: true,
      party: customerName,
      note: customerPhone,
    );
    await db.addPendingSettlementForTxn(pendingTxnId: txnId, amount: 500);
    await db.confirmPending(txnId);
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
    'claims screen shows deferred source, settlement, then remaining claim in chronological order',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1080, 2200));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.runAsync(seedDeferredClaimTimeline);

      await tester.pumpWidget(const MaterialApp(home: ClaimsScreen()));
      await pumpUntilFound(tester, find.text('مبالغ لنا'));
      await pumpFrames(tester, count: 10);

      final originalFinder = find.text('تحويل آجل • 905.00');
      final settlementFinder = find.text('تحصيل مستحق • 500.00');
      final remainingFinder = find.text('مستحق مفتوح • 405.00');

      expect(originalFinder, findsOneWidget);
      expect(settlementFinder, findsOneWidget);
      expect(remainingFinder, findsOneWidget);

      final originalY = tester.getTopLeft(originalFinder).dy;
      final settlementY = tester.getTopLeft(settlementFinder).dy;
      final remainingY = tester.getTopLeft(remainingFinder).dy;

      expect(originalY, lessThan(settlementY));
      expect(settlementY, lessThan(remainingY));
    },
  );
}
