import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:king_wallet_accounting/data/app_db.dart';
import 'package:king_wallet_accounting/data/app_session.dart';
import 'package:king_wallet_accounting/models/transaction.dart';
import 'package:king_wallet_accounting/models/quick_action_item.dart';
import 'package:king_wallet_accounting/models/wallet.dart';
import 'package:king_wallet_accounting/screens/assistant_screen.dart';
import 'package:king_wallet_accounting/screens/audit_log_screen.dart';
import 'package:king_wallet_accounting/screens/claims_screen.dart';
import 'package:king_wallet_accounting/screens/customer_report_screen.dart';
import 'package:king_wallet_accounting/screens/customers_screen.dart';
import 'package:king_wallet_accounting/screens/dashboard_screen.dart';
import 'package:king_wallet_accounting/screens/developer_tools_screen.dart';
import 'package:king_wallet_accounting/screens/drive_backup_screen.dart';
import 'package:king_wallet_accounting/screens/expenses_screen.dart';
import 'package:king_wallet_accounting/screens/admin_settings_screen.dart';
import 'package:king_wallet_accounting/screens/reports_screen.dart';
import 'package:king_wallet_accounting/screens/fawry_screen.dart';
import 'package:king_wallet_accounting/screens/quick_actions_order_screen.dart';
import 'package:king_wallet_accounting/screens/pending_screen.dart';
import 'package:king_wallet_accounting/screens/sync_outbox_screen.dart';
import 'package:king_wallet_accounting/screens/treasury_screen.dart';
import 'package:king_wallet_accounting/screens/ledger_screen.dart';
import 'package:king_wallet_accounting/screens/tx_details_screen.dart';
import 'package:king_wallet_accounting/screens/wallet_funding_screen.dart';
import 'package:king_wallet_accounting/screens/wallets_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const pathProviderChannel = MethodChannel('plugins.flutter.io/path_provider');
  final supportDir = Directory.systemTemp.createTempSync(
    'kw_screen_heavy_smoke_',
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

  Future<void> pumpFrames(WidgetTester tester, {int count = 20}) async {
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

  testWidgets('dashboard smoke renders quick actions with seeded values', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1080, 2200));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final db = AppDb.instance;
    await tester.runAsync(() async {
      await db.addWallet(
        name: 'Smoke Wallet',
        phone: '01010000001',
        openingBalance: 1000,
      );
      await db.addClaim(
        type: 'receivable',
        party: 'Customer Smoke',
        amount: 150,
        note: 'seed receivable',
      );
      await db.addClaim(
        type: 'payable',
        party: 'Vendor Smoke',
        amount: 50,
        note: 'seed payable',
      );
    });

    AppSession.enterAdmin();
    await tester.pumpWidget(const MaterialApp(home: DashboardScreen()));
    await pumpUntilFound(tester, find.byType(GridView));

    expect(find.byIcon(Icons.account_balance_wallet), findsWidgets);
    expect(find.byIcon(Icons.people_alt_outlined), findsWidgets);
    expect(find.byIcon(Icons.account_balance), findsWidgets);
    expect(find.byIcon(Icons.request_quote), findsWidgets);
    expect(find.text('1000.00'), findsWidgets);
  });

  testWidgets('wallets and customers screens smoke + customer report entry', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1080, 2200));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final db = AppDb.instance;
    await tester.runAsync(() async {
      final walletId = await db.addWallet(
        name: 'Primary Wallet',
        phone: '01110000001',
        openingBalance: 900,
      );
      await db.addTransfer(
        walletId: walletId,
        amount: 100,
        clientFee: 4,
        networkFee: 1,
        transferType: 'type1',
        isPending: true,
        party: 'Customer A',
        note: '01111111111',
      );
      await db.addClaim(type: 'receivable', party: 'Customer A', amount: 70);
      await db.addClaim(type: 'payable', party: 'Supplier B', amount: 30);
    });

    AppSession.enterAdmin();

    await tester.pumpWidget(const MaterialApp(home: WalletsScreen()));
    await pumpUntilFound(tester, find.text('Primary Wallet'));
    await tester.tap(find.byType(FloatingActionButton));
    await pumpUntilFound(tester, find.byType(AlertDialog));
    await tester.tap(find.byType(TextButton).first);
    await pumpFrames(tester);

    await tester.pumpWidget(const MaterialApp(home: CustomersScreen()));
    await pumpUntilFound(tester, find.text('Customer A'));
    await tester.tap(find.text('Customer A').first);
    await pumpFrames(tester);
    await pumpUntilFound(tester, find.byIcon(Icons.assessment_outlined));
    await tester.ensureVisible(find.byIcon(Icons.assessment_outlined).first);
    await tester.tap(
      find.byIcon(Icons.assessment_outlined).first,
      warnIfMissed: false,
    );
    await pumpFrames(tester);
    await pumpUntilFound(tester, find.byType(ChoiceChip));
    await tester.ensureVisible(find.byType(ChoiceChip).at(1));
    await tester.tap(find.byType(ChoiceChip).at(1), warnIfMissed: false);
    await pumpFrames(tester, count: 10);
  });

  testWidgets('customer ledger shows datetime rows and unsigned amounts', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1080, 2200));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final db = AppDb.instance;
    await tester.runAsync(() async {
      final claimId = await db.addClaim(
        type: 'receivable',
        party: 'Ledger Pattern Customer',
        amount: 70,
      );
      await db.settleClaim(claimId: claimId, amount: 30);
    });

    AppSession.enterAdmin();
    await tester.pumpWidget(const MaterialApp(home: CustomersScreen()));
    await pumpUntilFound(tester, find.text('Ledger Pattern Customer'));
    await tester.tap(find.text('Ledger Pattern Customer').first);
    await pumpFrames(tester, count: 12);
    await pumpUntilFound(tester, find.text('الرصيد'));

    final dateTimeCell = find.byWidgetPredicate((widget) {
      if (widget is! Text) return false;
      final value = widget.data?.trim() ?? '';
      return RegExp(r'^\d{4}-\d{2}-\d{2} \d{2}:\d{2}$').hasMatch(value);
    });

    expect(dateTimeCell, findsWidgets);
    expect(find.text('+70.00'), findsNothing);
    expect(find.text('-30.00'), findsNothing);
    expect(find.text('70.00'), findsWidgets);
    expect(find.text('30.00'), findsWidgets);
    expect(find.text('مستحق'), findsWidgets);
    expect(find.text('تحصيل'), findsWidgets);
    expect(find.textContaining('متبقي 40.00'), findsOneWidget);
    expect(find.textContaining('المبلغ: 30.00'), findsNothing);
  });

  testWidgets(
    'customer batch partial settlement total includes claims and deferred rows',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1080, 2200));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final db = AppDb.instance;
      await tester.runAsync(() async {
        final walletId = await db.addWallet(
          name: 'Batch Settlement Wallet',
          phone: '01090909090',
          openingBalance: 1000,
        );
        await db.addClaim(
          type: 'receivable',
          party: 'Batch Settlement Customer',
          amount: 70,
          entryDate: DateTime.now().subtract(const Duration(days: 1)),
        );
        await db.addTransfer(
          walletId: walletId,
          amount: 100,
          clientFee: 10,
          networkFee: 0,
          transferType: 'type1',
          isPending: true,
          party: 'Batch Settlement Customer',
          note: 'batch deferred transfer',
        );
      });

      AppSession.enterAdmin();
      await tester.pumpWidget(const MaterialApp(home: CustomersScreen()));
      await pumpUntilFound(tester, find.text('Batch Settlement Customer'));
      await tester.tap(find.text('Batch Settlement Customer').first);
      await pumpFrames(tester, count: 12);

      await tester.tap(find.byIcon(Icons.expand_more).first);
      await pumpFrames(tester, count: 8);

      final partialButton = find.text('تسوية جزئية من الإجمالي');
      await pumpUntilFound(tester, partialButton);
      final partialAction = find.ancestor(
        of: partialButton,
        matching: find.byWidgetPredicate(
          (widget) => widget is ButtonStyleButton,
        ),
      );
      await tester.ensureVisible(partialAction.first);
      await tester.tap(partialAction.first);
      await pumpUntilFound(tester, find.byType(AlertDialog));
      expect(find.textContaining('180.00'), findsWidgets);
    },
  );

  testWidgets(
    'customer ledger keeps original claim row after full settlement',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1080, 2200));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final db = AppDb.instance;
      await tester.runAsync(() async {
        final claimId = await db.addClaim(
          type: 'receivable',
          party: 'Closed Claim History Customer',
          amount: 500,
        );
        await db.settleClaim(claimId: claimId, amount: 500);
        await db.addClaim(
          type: 'payable',
          party: 'Closed Claim History Customer',
          amount: 1,
        );
      });

      AppSession.enterAdmin();
      await tester.pumpWidget(const MaterialApp(home: CustomersScreen()));
      await pumpUntilFound(tester, find.text('Closed Claim History Customer'));
      await tester.tap(find.text('Closed Claim History Customer').first);
      await pumpFrames(tester, count: 12);

      expect(find.text('مستحق'), findsWidgets);
      expect(find.text('تحصيل'), findsWidgets);
      expect(find.text('500.00'), findsAtLeastNWidgets(2));
      expect(find.textContaining('المتبقي: 0.00'), findsWidgets);
    },
  );

  testWidgets('customer opposite deferred settlement creates offset rows', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1080, 2200));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final db = AppDb.instance;
    late int transferId;
    late int receiveId;
    await tester.runAsync(() async {
      final walletId = await db.addWallet(
        name: 'Opposite Deferred Wallet',
        phone: '01030303030',
        openingBalance: 1000,
      );
      transferId = await db.addTransfer(
        walletId: walletId,
        amount: 300,
        clientFee: 0,
        networkFee: 0,
        transferType: 'type1',
        isPending: true,
        party: 'Opposite Deferred Customer',
        note: 'opposite transfer',
      );
      receiveId = await db.addReceive(
        walletId: walletId,
        amount: 200,
        commission: 0,
        receiveType: 'cash',
        isPending: true,
        party: 'Opposite Deferred Customer',
        note: 'opposite receive',
      );
    });

    AppSession.enterAdmin();
    await tester.pumpWidget(const MaterialApp(home: CustomersScreen()));
    await pumpUntilFound(tester, find.text('Opposite Deferred Customer'));
    await tester.tap(find.text('Opposite Deferred Customer').first);
    await pumpFrames(tester, count: 12);

    await tester.tap(find.byIcon(Icons.expand_more).first);
    await pumpFrames(tester, count: 8);

    final action = find.text('تسوية الآجل المتقابل');
    await pumpUntilFound(tester, action);
    final actionButton = find.ancestor(
      of: action,
      matching: find.byWidgetPredicate((widget) => widget is ButtonStyleButton),
    );
    await tester.ensureVisible(actionButton.first);
    await tester.tap(actionButton.first);
    await pumpUntilFound(tester, find.byType(AlertDialog));
    expect(find.textContaining('200.00'), findsWidgets);

    final cancelButton = find.descendant(
      of: find.byType(AlertDialog),
      matching: find.byWidgetPredicate((widget) => widget is TextButton),
    );
    await tester.tap(cancelButton.first);
    await pumpFrames(tester, count: 8);

    await tester.runAsync(() async {
      await db.addPendingSettlementForTxn(
        pendingTxnId: transferId,
        amount: 200,
        note: 'تسوية آجل متقابل',
      );
      await db.addPendingSettlementForTxn(
        pendingTxnId: receiveId,
        amount: 200,
        note: 'تسوية آجل متقابل',
      );
    });

    final txns = await tester.runAsync(() => db.listTxns());
    final reciprocal = txns!
        .where(
          (t) =>
              t.mode == 'pending_settlement' && (t.amount - 200).abs() < 0.0001,
        )
        .toList();
    expect(reciprocal.where((t) => t.kind == 'claim_collect').length, 1);
    expect(reciprocal.where((t) => t.kind == 'claim_pay').length, 1);
  });

  testWidgets('wallets screen add and edit wallet flow', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1080, 2200));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    AppSession.enterAdmin();
    await tester.pumpWidget(const MaterialApp(home: WalletsScreen()));
    await pumpUntilFound(tester, find.byIcon(Icons.add));

    await tester.tap(find.byType(FloatingActionButton));
    await pumpUntilFound(tester, find.byType(AlertDialog));

    await tester.enterText(find.byType(TextField).at(0), 'Coverage Wallet');
    await tester.enterText(find.byType(TextField).at(1), '01012345670');
    await tester.enterText(find.byType(TextField).at(2), '60000');
    await tester.enterText(find.byType(TextField).at(3), '200000');
    await tester.enterText(find.byType(TextField).at(4), '50');
    await tester.enterText(find.byType(TextField).at(5), '300');
    final saveAdd = find.descendant(
      of: find.byType(AlertDialog),
      matching: find.byType(ElevatedButton),
    );
    await tester.tap(saveAdd.first);
    await pumpFrames(tester, count: 24);

    await pumpUntilFound(tester, find.text('Coverage Wallet'));
    await tester.tap(find.text('Coverage Wallet').first);
    await pumpUntilFound(tester, find.byType(AlertDialog));

    await tester.enterText(find.byType(TextField).at(0), 'Coverage Wallet 2');
    final saveEdit = find.descendant(
      of: find.byType(AlertDialog),
      matching: find.byType(ElevatedButton),
    );
    await tester.tap(saveEdit.first);
    await pumpFrames(tester, count: 24);

    await pumpUntilFound(tester, find.text('Coverage Wallet 2'));
  });

  testWidgets('claims screen smoke and settlement dialog opens', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1080, 2200));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final db = AppDb.instance;
    await tester.runAsync(() async {
      await db.addClaim(
        type: 'receivable',
        party: 'Claim Customer',
        amount: 80,
      );
      await db.addClaim(type: 'payable', party: 'Claim Supplier', amount: 25);
    });

    AppSession.enterAdmin();
    await tester.pumpWidget(const MaterialApp(home: ClaimsScreen()));
    await pumpUntilFound(tester, find.byType(TabBar));
    await tester.tap(find.byType(Tab).at(1));
    await pumpFrames(tester, count: 8);
    await pumpUntilFound(tester, find.byIcon(Icons.check));
    await tester.tap(find.byIcon(Icons.check).first);
    await pumpUntilFound(tester, find.byType(AlertDialog));
    await tester.tap(find.byType(TextButton).first);
    await pumpFrames(tester);
  });

  testWidgets('tx details screen smoke for pending transaction', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1080, 2200));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    AppSession.enterAdmin();
    final pendingTxn = Txn(
      id: 77,
      kind: 'transfer',
      status: 'pending',
      entryDate: DateTime.now(),
      walletFromId: 1,
      amount: 101,
      clientFee: 4,
      networkFee: 1,
      mode: 'type1',
      note: 'smoke note',
      party: 'Smoke Party',
      createdBy: 'admin',
      createdRole: 'admin',
      createdAt: DateTime.now(),
    );
    final wallets = [
      Wallet(
        id: 1,
        name: 'Smoke Wallet',
        phone: '01210000001',
        dailyLimit: 60000,
        monthlyLimit: 200000,
        lowBalanceThreshold: 0,
      ),
    ];
    await tester.pumpWidget(
      MaterialApp(
        home: TxDetailsScreen(txn: pendingTxn, wallets: wallets),
      ),
    );
    await pumpUntilFound(tester, find.byIcon(Icons.check));
    await tester.tap(find.byIcon(Icons.check).first);
    await pumpFrames(tester, count: 6);
  });

  testWidgets('customer report screen smoke builds and switches period', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1080, 2200));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final db = AppDb.instance;
    await tester.runAsync(() async {
      final walletId = await db.addWallet(
        name: 'Report Wallet',
        phone: '01510000001',
        openingBalance: 1000,
      );
      await db.addTransfer(
        walletId: walletId,
        amount: 120,
        clientFee: 6,
        networkFee: 1,
        transferType: 'type1',
        isPending: false,
        party: 'Report Customer',
      );
      await db.addClaim(
        type: 'receivable',
        party: 'Report Customer',
        amount: 40,
      );
    });

    AppSession.enterAdmin();
    await tester.pumpWidget(
      const MaterialApp(
        home: CustomerReportScreen(customerName: 'Report Customer'),
      ),
    );
    await pumpUntilFound(tester, find.byType(ChoiceChip));
    expect(find.byType(ChoiceChip), findsNWidgets(3));
    await tester.tap(find.byType(ChoiceChip).at(1));
    await pumpFrames(tester, count: 12);
  });

  testWidgets('reports screen smoke builds and switches tabs/period', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1080, 2200));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final db = AppDb.instance;
    await tester.runAsync(() async {
      final walletId = await db.addWallet(
        name: 'Reports Seed Wallet',
        phone: '01033333333',
        openingBalance: 1200,
      );
      await db.addTransfer(
        walletId: walletId,
        amount: 100,
        clientFee: 5,
        networkFee: 1,
        transferType: 'type1',
        isPending: false,
        party: 'Reports Party',
      );
      await db.addReceive(
        walletId: walletId,
        amount: 80,
        commission: 4,
        receiveType: 'cash',
        isPending: false,
        party: 'Reports Party',
      );
    });

    AppSession.enterAdmin();
    await tester.pumpWidget(const MaterialApp(home: ReportsScreen()));
    await pumpUntilFound(tester, find.byType(TabBar));
    await pumpUntilFound(tester, find.byType(ChoiceChip));

    await tester.tap(find.byType(ChoiceChip).at(1));
    await pumpFrames(tester, count: 8);
    await tester.tap(find.byType(Tab).at(2));
    await pumpFrames(tester, count: 8);
    await tester.tap(find.byType(Tab).at(5));
    await pumpFrames(tester, count: 8);
  });

  testWidgets('reports screen daily close and reopen flow works', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1080, 2200));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.runAsync(() async {
      final walletId = await AppDb.instance.addWallet(
        name: 'Close Wallet',
        phone: '01044444444',
        openingBalance: 900,
      );
      await AppDb.instance.addTransfer(
        walletId: walletId,
        amount: 100,
        clientFee: 5,
        networkFee: 1,
        transferType: 'type1',
        isPending: false,
        party: 'Close Customer',
      );
    });

    AppSession.enterAdmin();
    await tester.pumpWidget(const MaterialApp(home: ReportsScreen()));
    await pumpUntilFound(tester, find.byType(TabBar));
    await tester.ensureVisible(find.byType(Tab).at(7));
    await tester.tap(find.byType(Tab).at(7), warnIfMissed: false);
    await pumpFrames(tester, count: 12);
    await pumpUntilFound(tester, find.byIcon(Icons.lock));
    await tester.tap(find.byIcon(Icons.lock).first);
    await pumpFrames(tester, count: 24);

    await pumpUntilFound(tester, find.byIcon(Icons.undo));
    await tester.tap(find.byIcon(Icons.undo).first);
    await pumpUntilFound(tester, find.byType(AlertDialog));
    final confirmReopen = find.descendant(
      of: find.byType(AlertDialog),
      matching: find.byType(ElevatedButton),
    );
    await tester.tap(confirmReopen.first);
    await pumpFrames(tester, count: 24);

    await pumpUntilFound(tester, find.byIcon(Icons.lock));
  });

  testWidgets('admin settings screen smoke opens dialogs and saves settings', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1080, 2200));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    AppSession.enterAdmin();
    await tester.pumpWidget(const MaterialApp(home: AdminSettingsScreen()));
    await pumpUntilFound(tester, find.byType(TextField));

    await tester.tap(find.byIcon(Icons.save).first);
    await pumpFrames(tester, count: 10);

    await tester.tap(find.byIcon(Icons.delete_forever).first);
    await pumpUntilFound(tester, find.byType(AlertDialog));
    await tester.tap(find.byType(TextButton).first);
    await pumpFrames(tester);

    await tester.tap(find.byIcon(Icons.delete_sweep).first);
    await pumpUntilFound(tester, find.byType(AlertDialog));
    await tester.tap(find.byType(TextButton).first);
    await pumpFrames(tester);

    await pumpUntilFound(tester, find.byIcon(Icons.verified_user));
    await tester.tap(find.byIcon(Icons.verified_user).first);
    await pumpFrames(tester, count: 8);
  });

  testWidgets('admin settings navigation opens audit/sync/drive screens', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1080, 2200));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    AppSession.enterAdmin();
    await tester.pumpWidget(const MaterialApp(home: AdminSettingsScreen()));
    await pumpUntilFound(tester, find.byType(TextField));
    final settingsScrollable = find.byType(Scrollable).first;

    await tester.scrollUntilVisible(
      find.byIcon(Icons.cloud).first,
      200,
      scrollable: settingsScrollable,
    );
    await tester.tap(find.byIcon(Icons.cloud).first);
    await pumpFrames(tester, count: 12);
    await pumpUntilFound(tester, find.byType(DriveBackupScreen));
    Navigator.of(tester.element(find.byType(DriveBackupScreen))).pop();
    await pumpFrames(tester, count: 10);

    await tester.scrollUntilVisible(
      find.byIcon(Icons.receipt_long).first,
      200,
      scrollable: settingsScrollable,
    );
    await tester.tap(find.byIcon(Icons.receipt_long).first);
    await pumpFrames(tester, count: 12);
    await pumpUntilFound(tester, find.byType(AuditLogScreen));
    Navigator.of(tester.element(find.byType(AuditLogScreen))).pop();
    await pumpFrames(tester, count: 10);

    await tester.scrollUntilVisible(
      find.byIcon(Icons.sync_alt).first,
      200,
      scrollable: settingsScrollable,
    );
    await tester.tap(find.byIcon(Icons.sync_alt).first);
    await pumpFrames(tester, count: 12);
    await pumpUntilFound(tester, find.byType(SyncOutboxScreen));
  });

  testWidgets(
    'fawry credit user flow creates pending and opens pending screen',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1080, 2200));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      AppSession.enterUser();
      await tester.pumpWidget(
        const MaterialApp(
          home: FawryScreen(
            initialParty: 'Fawry Client',
            initialPhone: '01077777777',
            startCredit: true,
          ),
        ),
      );
      await pumpUntilFound(tester, find.byType(TextField));

      final fields = find.byType(TextField);
      await tester.enterText(fields.at(0), 'Electricity');
      await tester.enterText(fields.at(2), 'Fawry Client');
      await tester.enterText(fields.at(4), '1000');
      await tester.enterText(fields.at(5), '10');
      await tester.tap(find.byIcon(Icons.send).first);
      await pumpFrames(tester, count: 14);

      await pumpUntilFound(tester, find.byType(PendingScreen));
      final fawryTxns = (await tester.runAsync(
        () => AppDb.instance.listTxns(kind: 'fawry_credit'),
      ))!;
      expect(fawryTxns.isNotEmpty, isTrue);
      expect(fawryTxns.first.status, 'pending');
    },
  );

  testWidgets('pending screen approve flow posts transaction', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1080, 2200));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final db = AppDb.instance;
    final walletId = (await tester.runAsync(
      () => db.addWallet(
        name: 'Pending Wallet',
        phone: '01055555555',
        openingBalance: 1000,
      ),
    ))!;
    final txId = (await tester.runAsync(
      () => db.addTransfer(
        walletId: walletId,
        amount: 100,
        clientFee: 4,
        networkFee: 1,
        transferType: 'type1',
        isPending: true,
        party: 'Pending Customer',
      ),
    ))!;

    AppSession.enterAdmin();
    await tester.pumpWidget(const MaterialApp(home: PendingScreen()));
    await pumpUntilFound(tester, find.textContaining('#$txId'));

    await tester.tap(find.text('اعتماد').first);
    await pumpUntilFound(tester, find.byType(AlertDialog));
    final dialogApprove = find.descendant(
      of: find.byType(AlertDialog),
      matching: find.text('اعتماد'),
    );
    await tester.tap(dialogApprove.first);
    await pumpFrames(tester, count: 18);

    final posted = (await tester.runAsync(
      () => db.listTxns(status: 'posted'),
    ))!;
    expect(posted.any((t) => t.id == txId), isTrue);
  });

  testWidgets('ledger screen smoke opens details (ignore known overflow)', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1080, 2200));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final originalOnError = FlutterError.onError;
    FlutterError.onError = (details) {
      final msg = details.exceptionAsString();
      if (msg.contains('A RenderFlex overflowed by')) return;
      originalOnError?.call(details);
    };
    addTearDown(() => FlutterError.onError = originalOnError);

    final db = AppDb.instance;
    await tester.runAsync(() async {
      final walletId = await db.addWallet(
        name: 'Ledger Wallet',
        phone: '01288888888',
        openingBalance: 1000,
      );
      await db.addTransfer(
        walletId: walletId,
        amount: 100,
        clientFee: 4,
        networkFee: 1,
        transferType: 'type1',
        isPending: false,
        party: 'Ledger Customer',
      );
    });

    AppSession.enterAdmin();
    await tester.pumpWidget(const MaterialApp(home: LedgerScreen()));
    await pumpUntilFound(tester, find.byType(ListTile));
    await tester.tap(find.byType(ListTile).first);
    await pumpFrames(tester, count: 12);
    await pumpUntilFound(tester, find.byType(TxDetailsScreen));
  });

  testWidgets('audit log screen smoke verifies chain and filters list', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1080, 2200));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.runAsync(() async {
      final walletId = await AppDb.instance.addWallet(
        name: 'Audit Wallet',
        phone: '01099999999',
        openingBalance: 600,
      );
      await AppDb.instance.addExpense(
        amount: 25,
        category: 'Seed',
        isPending: false,
        party: 'Audit Party',
        note: 'audit seed',
      );
      expect(walletId, greaterThan(0));
    });

    AppSession.enterAdmin();
    await tester.pumpWidget(const MaterialApp(home: AuditLogScreen()));
    await pumpUntilFound(tester, find.byIcon(Icons.shield));
    await pumpFrames(tester, count: 10);

    await tester.tap(find.byIcon(Icons.shield));
    await pumpFrames(tester, count: 10);
    await tester.enterText(find.byType(TextField).first, 'wallet_add');
    await pumpFrames(tester, count: 6);
  });

  testWidgets('sync outbox screen smoke opens admin actions dialogs', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1080, 2200));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.runAsync(() async {
      final walletId = await AppDb.instance.addWallet(
        name: 'Outbox Wallet',
        phone: '01199999999',
        openingBalance: 700,
      );
      await AppDb.instance.addTransfer(
        walletId: walletId,
        amount: 100,
        clientFee: 4,
        networkFee: 1,
        transferType: 'type1',
        isPending: true,
        party: 'Outbox Customer',
      );
    });

    AppSession.enterAdmin();
    await tester.pumpWidget(const MaterialApp(home: SyncOutboxScreen()));
    await pumpUntilFound(tester, find.byIcon(Icons.check_circle_outline));

    await tester.tap(find.byIcon(Icons.check_circle_outline));
    await pumpUntilFound(tester, find.byType(AlertDialog));
    await tester.tap(find.byType(TextButton).first);
    await pumpFrames(tester, count: 6);

    await tester.tap(find.byIcon(Icons.delete_outline).last);
    await pumpUntilFound(tester, find.byType(AlertDialog));
    await tester.tap(find.byType(TextButton).first);
    await pumpFrames(tester, count: 6);
  });

  testWidgets('treasury screen smoke opens drawer adjust dialog', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1080, 2200));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    AppSession.enterAdmin();
    await tester.pumpWidget(const MaterialApp(home: TreasuryScreen()));
    await pumpUntilFound(tester, find.byIcon(Icons.edit_note));

    await tester.tap(find.byIcon(Icons.edit_note));
    await pumpUntilFound(tester, find.byType(AlertDialog));
    final cancelButton = find.descendant(
      of: find.byType(AlertDialog),
      matching: find.byType(TextButton),
    );
    await tester.tap(cancelButton.first);
    await pumpFrames(tester, count: 8);
  });

  testWidgets('wallet funding screen smoke renders data entry form', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1080, 2200));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.runAsync(
      () => AppDb.instance.addWallet(
        name: 'Funding Wallet',
        phone: '01299999999',
        openingBalance: 100,
      ),
    );

    AppSession.enterAdmin();
    await tester.pumpWidget(const MaterialApp(home: WalletFundingScreen()));
    await pumpUntilFound(tester, find.byIcon(Icons.add_card));
    expect(find.byType(DropdownButtonFormField<int>), findsOneWidget);
    expect(find.byType(TextField), findsNWidgets(2));
    await tester.tap(find.byIcon(Icons.refresh));
    await pumpFrames(tester, count: 8);
  });

  testWidgets('expenses screen smoke fills fields and switches category', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1080, 2200));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    AppSession.enterAdmin();
    await tester.pumpWidget(const MaterialApp(home: ExpensesScreen()));
    await pumpUntilFound(tester, find.byType(TextField));

    await tester.enterText(find.byType(TextField).at(0), 'Expense Party');
    await tester.enterText(find.byType(TextField).at(2), '30');
    await tester.tap(find.byType(DropdownButtonFormField<String>).first);
    await pumpFrames(tester, count: 6);
    expect(find.byType(DropdownMenuItem<String>), findsWidgets);
    await tester.tapAt(const Offset(40, 40));
    await pumpFrames(tester, count: 8);
  });

  testWidgets('developer tools screen smoke generates and copies code', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1080, 2200));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    AppSession.enterAdmin();
    await tester.pumpWidget(const MaterialApp(home: DeveloperToolsScreen()));
    await pumpUntilFound(tester, find.byType(TextField));

    final legacyGenerate = find.byIcon(Icons.auto_fix_high);
    if (legacyGenerate.evaluate().isNotEmpty) {
      await tester.enterText(find.byType(TextField).first, 'DEV-ABC-123');
      await tester.tap(legacyGenerate.first);
      await pumpFrames(tester, count: 8);
      await pumpUntilFound(tester, find.byIcon(Icons.copy));
      await tester.tap(find.byIcon(Icons.copy).first);
      await pumpFrames(tester, count: 6);
    } else {
      // Cloud-only mode: local code generator is intentionally hidden.
      expect(find.byIcon(Icons.copy), findsNothing);
      expect(find.byIcon(Icons.save), findsOneWidget);
    }
  });

  testWidgets('assistant screen smoke asks and receives a balance answer', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1080, 2200));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.runAsync(() async {
      await AppDb.instance.addWallet(
        name: 'Assistant Wallet',
        phone: '01599999999',
        openingBalance: 1000,
      );
    });

    AppSession.enterAdmin();
    await tester.pumpWidget(const MaterialApp(home: AssistantScreen()));
    await pumpUntilFound(tester, find.byType(TextField));

    await tester.enterText(find.byType(TextField).first, 'السيولة');
    await tester.tap(find.byIcon(Icons.send));
    await pumpFrames(tester, count: 20);
    for (var i = 0; i < 80; i++) {
      await tester.pump(const Duration(milliseconds: 80));
      if (find.byType(CircularProgressIndicator).evaluate().isEmpty) break;
    }
    expect(find.text('السيولة'), findsOneWidget);
  });

  testWidgets('quick actions order screen save returns ordered ids', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1080, 2200));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final items = <QuickActionItem>[
      const QuickActionItem(
        id: 'a',
        title: 'One',
        icon: Icons.looks_one,
        color: Colors.blue,
      ),
      const QuickActionItem(
        id: 'b',
        title: 'Two',
        icon: Icons.looks_two,
        color: Colors.green,
      ),
      const QuickActionItem(
        id: 'c',
        title: 'Three',
        icon: Icons.looks_3,
        color: Colors.orange,
      ),
    ];

    List<String>? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () async {
                  result = await Navigator.of(context).push<List<String>>(
                    MaterialPageRoute(
                      builder: (_) => QuickActionsOrderScreen(items: items),
                    ),
                  );
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await pumpFrames(tester, count: 12);
    await pumpUntilFound(tester, find.byIcon(Icons.drag_handle));
    await tester.tap(find.text('حفظ'));
    await pumpFrames(tester, count: 8);

    expect(result, equals(const <String>['a', 'b', 'c']));
  });
}
