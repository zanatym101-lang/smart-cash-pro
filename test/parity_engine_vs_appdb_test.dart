import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:king_wallet_accounting/data/app_db.dart';
import 'package:king_wallet_accounting/data/app_session.dart';
import 'package:king_wallet_accounting/domain/services/accounting_engine.dart';
import 'package:king_wallet_accounting/domain/services/snapshot_builder.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const pathProviderChannel = MethodChannel('plugins.flutter.io/path_provider');
  final supportDir = Directory.systemTemp.createTempSync('kw_parity_engine_vs_appdb_');

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

  void expectSnapshotParity(
    TreasurySnapshot oldSnap,
    AccountingSnapshot newSnap,
  ) {
    expect(newSnap.drawer, closeTo(oldSnap.drawerActualBalance, 0.0001));
    expect(newSnap.wallets, closeTo(oldSnap.walletsActualTotal, 0.0001));
    expect(
      newSnap.pendingReceivable,
      closeTo(oldSnap.pendingReceivableOpen, 0.0001),
    );
    expect(
      newSnap.pendingPayable,
      closeTo(oldSnap.pendingPayableOpen, 0.0001),
    );
    expect(
      newSnap.openClaimsReceivable,
      closeTo(oldSnap.claimsReceivableOpen, 0.0001),
    );
    expect(
      newSnap.openClaimsPayable,
      closeTo(oldSnap.claimsPayableOpen, 0.0001),
    );
    expect(
      newSnap.availableLiquidityNow,
      closeTo(oldSnap.availableLiquidityNow, 0.0001),
    );
    expect(
      newSnap.realCapitalApproved,
      closeTo(oldSnap.realCapitalApproved, 0.0001),
    );
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

  group('parity old AppDb vs new accounting engine', () {
    const engine = AccountingEngine();

    test('transfer cash final state parity', () async {
      final db = AppDb.instance;
      final walletId = await db.addWallet(
        name: 'Parity Wallet',
        phone: '01010001001',
        openingBalance: 1000,
      );
      final oldTxnId = await db.addTransfer(
        walletId: walletId,
        amount: 900,
        clientFee: 5,
        networkFee: 0,
        transferType: 'type1',
        isPending: false,
      );
      expect(oldTxnId, greaterThan(0));
      final oldSnap = await db.getTreasurySnapshot();

      final initialState = AccountingEngineState(
        drawerBalance: 0,
        walletBalance: 1000,
      );
      final created = engine.createDeferredTransfer(
        state: initialState,
        transactionId: 'tx-cash-1',
        walletAmount: 900,
        clientFee: 5,
      );
      final collected = engine.collectPartial(
        state: created.newState,
        deferredTransferId: 'tx-cash-1',
        settlementId: 'settlement-cash-1',
        amount: 905,
      );
      final confirmed = engine.confirmPending(
        state: collected.newState,
        deferredTransferId: 'tx-cash-1',
        claimId: 'claim-cash-1',
      );
      final newSnap = buildSnapshot([
        const OpeningBalancesRecorded(drawer: 0, wallets: 1000),
        ...created.events,
        ...collected.events,
        ...confirmed.events,
      ]);

      expectSnapshotParity(oldSnap, newSnap);
    });

    test('receive cash final state parity', () async {
      final db = AppDb.instance;
      await db.drawerDeposit(amount: 1000, note: 'seed drawer');
      final walletId = await db.addWallet(
        name: 'Parity Receive Wallet',
        phone: '01010001002',
        openingBalance: 0,
      );
      await db.addReceive(
        walletId: walletId,
        amount: 1000,
        commission: 0,
        receiveType: 'cash',
        isPending: false,
      );
      final oldSnap = await db.getTreasurySnapshot();

      final initialState = AccountingEngineState(
        drawerBalance: 1000,
        walletBalance: 0,
      );
      final created = engine.createDeferredReceive(
        state: initialState,
        transactionId: 'rx-cash-1',
        walletAmount: 1000,
      );
      final paid = engine.payPartial(
        state: created.newState,
        deferredReceiveId: 'rx-cash-1',
        settlementId: 'pay-cash-1',
        amount: 1000,
      );
      final confirmed = engine.confirmPending(
        state: paid.newState,
        deferredTransferId: 'rx-cash-1',
        claimId: 'claim-receive-cash-1',
      );
      final newSnap = buildSnapshot([
        const OpeningBalancesRecorded(drawer: 1000, wallets: 0),
        ...created.events,
        ...paid.events,
        ...confirmed.events,
      ]);

      expectSnapshotParity(oldSnap, newSnap);
    });

    test('deferred transfer + partial + confirm parity', () async {
      final db = AppDb.instance;
      final walletId = await db.addWallet(
        name: 'Parity Deferred Transfer Wallet',
        phone: '01010001003',
        openingBalance: 2000,
      );
      final pendingTxnId = await db.addTransfer(
        walletId: walletId,
        amount: 900,
        clientFee: 5,
        networkFee: 0,
        transferType: 'type1',
        isPending: true,
        party: 'Parity Transfer Customer',
      );
      await db.addPendingSettlementForTxn(
        pendingTxnId: pendingTxnId,
        amount: 500,
      );
      await db.confirmPending(pendingTxnId);
      final oldSnap = await db.getTreasurySnapshot();

      final initialState = AccountingEngineState(
        drawerBalance: 0,
        walletBalance: 2000,
      );
      final created = engine.createDeferredTransfer(
        state: initialState,
        transactionId: 'tx-def-1',
        walletAmount: 900,
        clientFee: 5,
      );
      final collected = engine.collectPartial(
        state: created.newState,
        deferredTransferId: 'tx-def-1',
        settlementId: 'settlement-def-1',
        amount: 500,
      );
      final confirmed = engine.confirmPending(
        state: collected.newState,
        deferredTransferId: 'tx-def-1',
        claimId: 'claim-def-1',
      );
      final newSnap = buildSnapshot([
        const OpeningBalancesRecorded(drawer: 0, wallets: 2000),
        ...created.events,
        ...collected.events,
        ...confirmed.events,
      ]);

      expectSnapshotParity(oldSnap, newSnap);
    });

    test('deferred receive + partial + confirm parity', () async {
      final db = AppDb.instance;
      await db.drawerDeposit(amount: 1000, note: 'seed drawer');
      final walletId = await db.addWallet(
        name: 'Parity Deferred Receive Wallet',
        phone: '01010001004',
        openingBalance: 0,
      );
      final pendingTxnId = await db.addReceive(
        walletId: walletId,
        amount: 1000,
        commission: 0,
        receiveType: 'cash',
        isPending: true,
        party: 'Parity Receive Customer',
      );
      await db.addPendingSettlementForTxn(
        pendingTxnId: pendingTxnId,
        amount: 400,
      );
      await db.confirmPending(pendingTxnId);
      final oldSnap = await db.getTreasurySnapshot();

      final initialState = AccountingEngineState(
        drawerBalance: 1000,
        walletBalance: 0,
      );
      final created = engine.createDeferredReceive(
        state: initialState,
        transactionId: 'rx-def-1',
        walletAmount: 1000,
      );
      final paid = engine.payPartial(
        state: created.newState,
        deferredReceiveId: 'rx-def-1',
        settlementId: 'pay-def-1',
        amount: 400,
      );
      final confirmed = engine.confirmPending(
        state: paid.newState,
        deferredTransferId: 'rx-def-1',
        claimId: 'claim-payable-def-1',
      );
      final newSnap = buildSnapshot([
        const OpeningBalancesRecorded(drawer: 1000, wallets: 0),
        ...created.events,
        ...paid.events,
        ...confirmed.events,
      ]);

      expectSnapshotParity(oldSnap, newSnap);
    });

    test('full settlement after claim parity', () async {
      final db = AppDb.instance;
      final walletId = await db.addWallet(
        name: 'Parity Full Claim Wallet',
        phone: '01010001005',
        openingBalance: 2000,
      );
      final pendingTxnId = await db.addTransfer(
        walletId: walletId,
        amount: 900,
        clientFee: 5,
        networkFee: 0,
        transferType: 'type1',
        isPending: true,
        party: 'Parity Full Claim Customer',
      );
      await db.addPendingSettlementForTxn(
        pendingTxnId: pendingTxnId,
        amount: 500,
      );
      await db.confirmPending(pendingTxnId);
      final claimId =
          (await db.listClaims(type: 'receivable', status: 'open')).single.id;
      await db.settleClaim(claimId: claimId, amount: 405);
      final oldSnap = await db.getTreasurySnapshot();

      final initialState = AccountingEngineState(
        drawerBalance: 0,
        walletBalance: 2000,
      );
      final created = engine.createDeferredTransfer(
        state: initialState,
        transactionId: 'tx-full-1',
        walletAmount: 900,
        clientFee: 5,
      );
      final collected = engine.collectPartial(
        state: created.newState,
        deferredTransferId: 'tx-full-1',
        settlementId: 'settlement-full-1',
        amount: 500,
      );
      final confirmed = engine.confirmPending(
        state: collected.newState,
        deferredTransferId: 'tx-full-1',
        claimId: 'claim-full-1',
      );
      final settled = engine.settleClaim(
        state: confirmed.newState,
        claimId: 'claim-full-1',
        settlementId: 'claim-settlement-full-1',
        amount: 405,
      );
      final newSnap = buildSnapshot([
        const OpeningBalancesRecorded(drawer: 0, wallets: 2000),
        ...created.events,
        ...collected.events,
        ...confirmed.events,
        ...settled.events,
      ]);

      expectSnapshotParity(oldSnap, newSnap);
    });

    test('mixed scenario parity', () async {
      final db = AppDb.instance;
      await db.drawerDeposit(amount: 1000, note: 'seed drawer');
      final transferWalletId = await db.addWallet(
        name: 'Mixed Transfer Wallet',
        phone: '01010001006',
        openingBalance: 2000,
      );
      final receiveWalletId = await db.addWallet(
        name: 'Mixed Receive Wallet',
        phone: '01010001007',
        openingBalance: 0,
      );

      final transferPendingId = await db.addTransfer(
        walletId: transferWalletId,
        amount: 900,
        clientFee: 5,
        networkFee: 0,
        transferType: 'type1',
        isPending: true,
        party: 'Mixed Transfer Customer',
      );
      await db.addPendingSettlementForTxn(
        pendingTxnId: transferPendingId,
        amount: 500,
      );
      await db.confirmPending(transferPendingId);

      final receivePendingId = await db.addReceive(
        walletId: receiveWalletId,
        amount: 1000,
        commission: 0,
        receiveType: 'cash',
        isPending: true,
        party: 'Mixed Receive Customer',
      );
      await db.addPendingSettlementForTxn(
        pendingTxnId: receivePendingId,
        amount: 400,
      );
      await db.confirmPending(receivePendingId);

      final oldSnap = await db.getTreasurySnapshot();

      final initialState = AccountingEngineState(
        drawerBalance: 1000,
        walletBalance: 2000,
      );
      final transferCreated = engine.createDeferredTransfer(
        state: initialState,
        transactionId: 'mix-tx-1',
        walletAmount: 900,
        clientFee: 5,
      );
      final transferCollected = engine.collectPartial(
        state: transferCreated.newState,
        deferredTransferId: 'mix-tx-1',
        settlementId: 'mix-settlement-1',
        amount: 500,
      );
      final transferConfirmed = engine.confirmPending(
        state: transferCollected.newState,
        deferredTransferId: 'mix-tx-1',
        claimId: 'mix-claim-rec-1',
      );

      final receiveCreated = engine.createDeferredReceive(
        state: transferConfirmed.newState,
        transactionId: 'mix-rx-1',
        walletAmount: 1000,
      );
      final receivePaid = engine.payPartial(
        state: receiveCreated.newState,
        deferredReceiveId: 'mix-rx-1',
        settlementId: 'mix-pay-1',
        amount: 400,
      );
      final receiveConfirmed = engine.confirmPending(
        state: receivePaid.newState,
        deferredTransferId: 'mix-rx-1',
        claimId: 'mix-claim-pay-1',
      );

      final newSnap = buildSnapshot([
        const OpeningBalancesRecorded(drawer: 1000, wallets: 2000),
        ...transferCreated.events,
        ...transferCollected.events,
        ...transferConfirmed.events,
        ...receiveCreated.events,
        ...receivePaid.events,
        ...receiveConfirmed.events,
      ]);

      expectSnapshotParity(oldSnap, newSnap);
    });
  });
}
