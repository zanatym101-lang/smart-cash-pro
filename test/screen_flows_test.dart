import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:king_wallet_accounting/data/app_db.dart';
import 'package:king_wallet_accounting/data/app_session.dart';
import 'package:king_wallet_accounting/models/transaction.dart';
import 'package:king_wallet_accounting/screens/receive_screen.dart';
import 'package:king_wallet_accounting/screens/reports_screen.dart';
import 'package:king_wallet_accounting/screens/transfer_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const pathProviderChannel = MethodChannel('plugins.flutter.io/path_provider');
  final supportDir = Directory.systemTemp.createTempSync('kw_screen_flows_');

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
    int maxPumps = 80,
  }) async {
    for (var i = 0; i < maxPumps; i++) {
      await tester.runAsync(
        () async => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump(const Duration(milliseconds: 100));
      if (finder.evaluate().isNotEmpty) {
        return;
      }
    }
    fail('Widget not found in time: $finder');
  }

  Future<List<Txn>> waitForTxnsByKind(
    WidgetTester tester,
    String kind, {
    int minCount = 1,
    int maxPumps = 80,
  }) async {
    for (var i = 0; i < maxPumps; i++) {
      await tester.runAsync(
        () async => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      final txns = (await tester.runAsync(
        () => AppDb.instance.listTxns(kind: kind),
      ))!;
      if (txns.length >= minCount) {
        return txns;
      }
      await tester.pump(const Duration(milliseconds: 100));
    }
    fail('Transactions not found in time. kind=$kind');
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

  testWidgets('receive flow creates pending receive transaction', (
    tester,
  ) async {
    final db = AppDb.instance;
    await tester.runAsync(
      () => db.addWallet(
        name: 'Main Wallet',
        phone: '01010000001',
        openingBalance: 500,
      ),
    );

    AppSession.enterUser();
    await tester.pumpWidget(const MaterialApp(home: ReceiveScreen()));
    await pumpUntilFound(tester, find.byType(TextField));

    final textFields = find.byType(TextField);
    expect(textFields, findsWidgets);

    await tester.enterText(textFields.at(0), 'Customer A');
    await tester.scrollUntilVisible(
      find.byIcon(Icons.play_arrow),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pump(const Duration(milliseconds: 200));
    await tester.tap(find.byIcon(Icons.play_arrow).first);
    await pumpUntilFound(tester, find.byType(AlertDialog));

    final dialog = find.byType(AlertDialog);
    expect(dialog, findsOneWidget);
    final submitInDialog = find.descendant(
      of: dialog,
      matching: find.byType(ElevatedButton),
    );
    await tester.tap(submitInDialog.first);
    final receives = await waitForTxnsByKind(tester, 'receive');
    expect(receives.length, 1);
    expect(receives.first.status, 'pending');
    expect(receives.first.amount, closeTo(1000, 0.0001));
    expect(receives.first.clientFee, closeTo(10, 0.0001));
  });

  testWidgets('transfer flow creates pending transfer and updates available wallet balance', (
    tester,
  ) async {
    final db = AppDb.instance;
    final walletId = (await tester.runAsync(
      () => db.addWallet(
        name: 'Transfer Wallet',
        phone: '01110000001',
        openingBalance: 1000,
      ),
    ))!;

    AppSession.enterUser();
    await tester.pumpWidget(const MaterialApp(home: TransferScreen()));
    await pumpUntilFound(tester, find.byType(TextField));

    final textFields = find.byType(TextField);
    expect(textFields, findsWidgets);

    await tester.enterText(textFields.at(0), 'Customer B');
    await tester.scrollUntilVisible(
      find.byIcon(Icons.play_arrow),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pump(const Duration(milliseconds: 200));
    await tester.tap(find.byIcon(Icons.play_arrow).first);
    await pumpUntilFound(tester, find.byType(AlertDialog));

    final dialog = find.byType(AlertDialog);
    expect(dialog, findsOneWidget);
    final submitInDialog = find.descendant(
      of: dialog,
      matching: find.byType(ElevatedButton),
    );
    await tester.tap(submitInDialog.first);
    final transfers = await waitForTxnsByKind(tester, 'transfer');
    expect(transfers.length, 1);
    expect(transfers.first.status, 'pending');
    expect(transfers.first.amount, closeTo(101, 0.0001));
    expect(transfers.first.clientFee, closeTo(4, 0.0001));
    expect(transfers.first.networkFee, closeTo(1, 0.0001));

    final walletBalance = (await tester.runAsync(
      () => db.getWalletBalance(walletId),
    ))!;
    final walletAvailable = (await tester.runAsync(
      () => db.getWalletAvailableBalance(walletId),
    ))!;
    expect(walletBalance, closeTo(1000, 0.0001));
    expect(walletAvailable, closeTo(899, 0.0001));
  });

  testWidgets('reports screen smoke builds and allows period switching', (
    tester,
  ) async {
    final db = AppDb.instance;
    await tester.runAsync(() async {
      final walletId = await db.addWallet(
        name: 'Reports Wallet',
        phone: '01210000001',
        openingBalance: 1000,
      );
      await db.addTransfer(
        walletId: walletId,
        amount: 100,
        clientFee: 4,
        networkFee: 1,
        transferType: 'type1',
        isPending: false,
        note: 'seed transfer',
        party: 'Customer R',
      );
    });

    AppSession.enterAdmin();
    await tester.pumpWidget(const MaterialApp(home: ReportsScreen()));
    await pumpUntilFound(tester, find.byType(TabBar));
    await pumpUntilFound(tester, find.byType(TabBarView));

    expect(find.byType(TabBar), findsOneWidget);
    expect(find.byType(TabBarView), findsOneWidget);
    expect(find.byType(ChoiceChip), findsNWidgets(3));

    await tester.tap(find.byType(ChoiceChip).at(1));
    await pumpUntilFound(tester, find.byType(TabBarView));

    expect(find.byType(CircularProgressIndicator), findsNothing);
  });
}
