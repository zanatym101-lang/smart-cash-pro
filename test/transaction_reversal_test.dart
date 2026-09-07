import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:king_wallet_accounting/data/app_db.dart';
import 'package:king_wallet_accounting/data/app_session.dart';
import 'package:king_wallet_accounting/domain/services/accounting_engine.dart';
import 'package:king_wallet_accounting/models/claim.dart';
import 'package:king_wallet_accounting/models/transaction.dart';
import 'package:king_wallet_accounting/screens/customer_account/customer_account_builder.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const pathProviderChannel = MethodChannel('plugins.flutter.io/path_provider');
  final supportDir = Directory.systemTemp.createTempSync('kw_reversal_test_');

  Future<void> seedCleanDb() async {
    AppSession.enterAdmin();
    final db = AppDb.instance;
    final info = await db.getLicenseInfo();
    final activationCode = db.generateActivationCodeForDeviceCode(
      info.deviceCode,
    );
    await db.activateWithCode(activationCode);
    await db.resetEncryptedRestoreGuard();
    await db.resetDatabaseEmpty();
  }

  setUpAll(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProviderChannel, (call) async {
          if (call.method.endsWith('Paths')) {
            return <String>[supportDir.path];
          }
          return supportDir.path;
        });
    await seedCleanDb();
  });

  setUp(() async {
    await seedCleanDb();
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

  group('Pure AccountingEngine Reversal', () {
    const engine = AccountingEngine();

    test('reversing Send Cash restores wallet, debits drawer, reverses profit', () {
      final initialState = AccountingEngineState(
        drawerBalance: 1000,
        walletBalance: 2000,
      );

      final transfer = engine.createDeferredTransfer(
        state: initialState,
        transactionId: 'tx-send-1',
        walletAmount: 500,
        clientFee: 20,
      );
      // Drawer collected 520
      final collected = engine.collectPartial(
        state: transfer.newState,
        deferredTransferId: 'tx-send-1',
        settlementId: 'set-1',
        amount: 520,
      );

      expect(collected.newState.walletBalance, closeTo(1500, 0.0001));
      expect(collected.newState.drawerBalance, closeTo(1520, 0.0001));

      // Now reverse the transaction
      final reversed = engine.reverseTransaction(
        state: collected.newState,
        transactionId: 'tx-send-1',
        reason: 'Customer cancelled',
      );

      // Wallet restored to 2000, Drawer debited back by 520 to 1000
      expect(reversed.newState.walletBalance, closeTo(2000, 0.0001));
      expect(reversed.newState.drawerBalance, closeTo(1000, 0.0001));
      expect(
        reversed.events.any((e) => e is TransactionReversed),
        isTrue,
      );
    });

    test('reversing Receive Cash throws StateError when wallet balance is insufficient', () {
      final initialState = AccountingEngineState(
        drawerBalance: 1000,
        walletBalance: 0,
      );

      final receive = engine.createDeferredReceive(
        state: initialState,
        transactionId: 'tx-rec-1',
        walletAmount: 500,
      );
      // Wallet now has 500
      expect(receive.newState.walletBalance, closeTo(500, 0.0001));

      // Artificially simulate wallet balance being spent down to 100
      final lowBalanceState = receive.newState.copyWith(
        walletBalance: 100,
      );

      // Attempt reversal - must reject because wallet would go below 0 (100 - 500 = -400)
      expect(
        () => engine.reverseTransaction(
          state: lowBalanceState,
          transactionId: 'tx-rec-1',
          reason: 'Attempted reversal on drained wallet',
        ),
        throwsA(isA<StateError>()),
      );
    });
  });

  group('AppDb One-Click Transaction Reversal', () {
    test('reversal of Send Cash (Transfer) restores wallet, debits drawer, logs audit', () async {
      final db = AppDb.instance;
      final walletId = await db.addWallet(
        name: 'Test Send Wallet',
        phone: '01011112222',
        openingBalance: 1000,
      );
      await db.drawerDeposit(amount: 500, note: 'Initial drawer');

      // Add Send Cash (Transfer)
      final txnId = await db.addTransfer(
        walletId: walletId,
        amount: 200,
        clientFee: 10,
        networkFee: 0,
        transferType: 'type1',
        isPending: false,
      );

      var snap = await db.getTreasurySnapshot();
      expect(snap.walletsActualTotal, closeTo(800, 0.0001));
      expect(snap.drawerActualBalance, closeTo(710, 0.0001)); // 500 + 210

      // Execute reversal
      await db.reverseTransaction(txnId.toString(), reason: 'خطأ في رقم المستلم');

      snap = await db.getTreasurySnapshot();
      // Wallet restored to 1000, Drawer restored to 500
      expect(snap.walletsActualTotal, closeTo(1000, 0.0001));
      expect(snap.drawerActualBalance, closeTo(500, 0.0001));

      // Verify original transaction flagged as reversed
      final txns = await db.listTxns();
      final orig = txns.firstWhere((t) => t.id == txnId);
      expect(orig.status, 'reversed');
      expect(orig.isReversed, isTrue);

      // Verify reverse entry exists
      final reverseEntries = txns.where((t) => t.status == 'reverse_entry');
      expect(reverseEntries, isNotEmpty);
      expect(reverseEntries.first.reference, txnId.toString());

      // Verify audit log entry
      final audits = await db.listAudit();
      expect(
        audits.any((a) => a['type'] == 'txn_reverse' && a['txnId'] == txnId),
        isTrue,
      );
    });

    test('reversal of Receive Cash rejects when wallet balance would become negative', () async {
      final db = AppDb.instance;
      final walletId = await db.addWallet(
        name: 'Test Receive Wallet',
        phone: '01033334444',
        openingBalance: 0,
      );
      await db.drawerDeposit(amount: 1000, note: 'Seed drawer');

      // Add Receive Cash
      final rxId = await db.addReceive(
        walletId: walletId,
        amount: 500,
        commission: 0,
        receiveType: 'cash',
        isPending: false,
      );

      var snap = await db.getTreasurySnapshot();
      expect(snap.walletsActualTotal, closeTo(500, 0.0001));
      expect(snap.drawerActualBalance, closeTo(500, 0.0001));

      // Drain wallet balance via a transfer of 400
      await db.addTransfer(
        walletId: walletId,
        amount: 400,
        clientFee: 0,
        networkFee: 0,
        transferType: 'type1',
        isPending: false,
      );

      // Wallet now has 100, but rxId added 500!
      snap = await db.getTreasurySnapshot();
      expect(snap.walletsActualTotal, closeTo(100, 0.0001));

      // Attempt reversal of rxId (needs to debit 500 from wallet, which has only 100)
      expect(
        () => db.reverseTransaction(rxId.toString()),
        throwsA(isA<Exception>()),
      );

      // Assert state remains intact and safe
      snap = await db.getTreasurySnapshot();
      expect(snap.walletsActualTotal, closeTo(100, 0.0001));
    });

    test('customer account ledger excludes reversed transactions and cancelled claims', () {
      final baseDate = DateTime(2026, 9, 1, 10);
      const customer = 'عميل تجريبي';

      final tx1 = Txn(
        id: 1,
        kind: 'transfer',
        status: 'reversed',
        isReversed: true,
        entryDate: baseDate,
        amount: 500,
        clientFee: 10,
        networkFee: 0,
        mode: 'type1',
        party: customer,
        createdBy: 'test',
        createdRole: 'admin',
        createdAt: baseDate,
      );

      final claim1 = Claim(
        id: 1,
        type: 'receivable',
        party: customer,
        amount: 510,
        status: 'reversed',
        entryDate: baseDate,
        sourceTxnId: 1,
      );

      final accounts = CustomerAccountBuilder.fromAppDbData(
        txns: [tx1],
        claims: [claim1],
      );

      expect(accounts, isEmpty);
    });
  });
}
