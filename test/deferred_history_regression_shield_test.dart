import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:king_wallet_accounting/data/app_db.dart';
import 'package:king_wallet_accounting/data/app_session.dart';
import 'package:king_wallet_accounting/screens/claims_screen.dart';
import 'package:king_wallet_accounting/screens/customer_report_screen.dart';
import 'package:king_wallet_accounting/screens/customers_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const pathProviderChannel = MethodChannel('plugins.flutter.io/path_provider');
  final supportDir = Directory.systemTemp.createTempSync(
    'kw_deferred_history_shield_',
  );

  const customerName = 'Deferred History Shield Customer';
  const customerPhone = '01055554444';

  Future<void> resetAndActivate() async {
    AppSession.enterAdmin();
    final db = AppDb.instance;
    final info = await db.getLicenseInfo();
    final code = db.generateActivationCodeForDeviceCode(info.deviceCode);
    await db.activateWithCode(code);
    await db.resetEncryptedRestoreGuard();
    await db.resetDatabaseEmpty();
  }

  Future<({int pendingTxnId, DateTime originalDate})> seedScenario() async {
    final db = AppDb.instance;
    final walletId = await db.addWallet(
      name: 'Deferred History Wallet',
      phone: '01010000777',
      openingBalance: 2000,
    );
    final pendingTxnId = await db.addTransfer(
      walletId: walletId,
      amount: 900,
      clientFee: 5,
      networkFee: 0,
      transferType: 'type1',
      isPending: true,
      party: customerName,
      note: customerPhone,
    );

    final originalTxn = (await db.listTxns()).firstWhere(
      (t) => t.id == pendingTxnId,
    );
    await db.addPendingSettlementForTxn(pendingTxnId: pendingTxnId, amount: 500);
    await db.confirmPending(pendingTxnId);
    return (pendingTxnId: pendingTxnId, originalDate: originalTxn.entryDate);
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

  List<double> yPositionsFor(Finder finder, WidgetTester tester) {
    final positions = <double>[];
    for (final element in finder.evaluate()) {
      positions.add(
        tester
            .getTopLeft(find.byElementPredicate((candidate) => candidate == element))
            .dy,
      );
    }
    positions.sort();
    return positions;
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

  test(
    'deferred history shield keeps cash stable and prevents duplicate cash effect',
    () async {
      final seeded = await seedScenario();
      final db = AppDb.instance;

      final snap = await db.getTreasurySnapshot();
      final claims = await db.listClaims();
      final openClaim = claims.singleWhere((c) => c.sourceTxnId == seeded.pendingTxnId);

      expect(snap.drawerActualBalance, closeTo(500, 0.0001));
      expect(snap.walletsActualTotal, closeTo(1100, 0.0001));
      expect(snap.availableLiquidityNow, closeTo(1600, 0.0001));
      expect(snap.pendingReceivableOpen, closeTo(0, 0.0001));
      expect(snap.claimsReceivableOpen, closeTo(405, 0.0001));
      expect(
        snap.realCapitalApproved,
        closeTo(
          snap.actualTreasuryApproved +
              snap.claimsReceivableOpen +
              snap.pendingReceivableOpen -
              snap.claimsPayableOpen -
              snap.pendingPayableOpen,
          0.0001,
        ),
      );
      expect(openClaim.status, equals('open'));
      expect(openClaim.amount, closeTo(405, 0.0001));
    },
  );

  testWidgets(
    'deferred history shield keeps customer ledger history consistent',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1080, 2200));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final seeded = (await tester.runAsync(seedScenario))!;
      final expectedDate =
          '${seeded.originalDate.year}-${seeded.originalDate.month.toString().padLeft(2, '0')}-${seeded.originalDate.day.toString().padLeft(2, '0')}';

      await tester.pumpWidget(const MaterialApp(home: CustomersScreen()));
      await pumpUntilFound(tester, find.text(customerName));

      expect(
        customerSummaryTextContaining('عليه: 405.00 | له: 0.00'),
        findsOneWidget,
      );

      await tester.tap(find.text(customerName).first);
      await pumpFrames(tester);
      await pumpUntilFound(tester, find.byType(BottomSheet));

      expect(sheetScope(find.text('+905.00')), findsOneWidget);
      expect(sheetScope(find.textContaining('500.00')), findsWidgets);

      await tester.tap(sheetScope(find.text('+905.00')).first, warnIfMissed: false);
      await pumpFrames(tester, count: 8);
      expect(find.textContaining('التاريخ: $expectedDate'), findsOneWidget);
    },
  );

  testWidgets(
    'deferred history shield keeps customer report consistent with ledger history',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1080, 2200));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.runAsync(seedScenario);

      await tester.pumpWidget(
        const MaterialApp(
          home: CustomerReportScreen(
            customerName: customerName,
            customerPhone: customerPhone,
          ),
        ),
      );
      await pumpUntilFound(tester, find.byType(ChoiceChip));
      await pumpFrames(tester, count: 10);

      expect(find.textContaining('لنا: 405.00'), findsOneWidget);
      expect(find.text('+905.00'), findsOneWidget);
      expect(find.text('-500.00'), findsOneWidget);
      expect(find.text('+405.00'), findsOneWidget);
    },
  );

  testWidgets(
    'deferred history shield keeps claims chronology ordered as original then settlement then open claim',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1080, 2200));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.runAsync(seedScenario);

      await tester.pumpWidget(const MaterialApp(home: ClaimsScreen()));
      await pumpUntilFound(tester, find.textContaining('405.00'));
      await pumpFrames(tester, count: 10);

      final originalFinder = find.textContaining('905.00');
      final settlementFinder = find.textContaining('500.00');
      final remainingFinder = find.textContaining('405.00');

      expect(originalFinder, findsWidgets);
      expect(settlementFinder, findsWidgets);
      expect(remainingFinder, findsWidgets);

      final originalYs = yPositionsFor(originalFinder, tester);
      final settlementYs = yPositionsFor(settlementFinder, tester);
      final remainingYs = yPositionsFor(remainingFinder, tester);
      final settlementY = settlementYs.first;

      expect(originalYs.any((y) => y < settlementY), isTrue);
      expect(remainingYs.any((y) => y > settlementY), isTrue);
    },
  );
}
