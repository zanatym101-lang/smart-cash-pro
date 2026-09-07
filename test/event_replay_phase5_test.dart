import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:king_wallet_accounting/data/app_db.dart';
import 'package:king_wallet_accounting/data/app_session.dart';
import 'package:king_wallet_accounting/domain/services/accounting_engine.dart';
import 'package:king_wallet_accounting/domain/services/accounting_event_models.dart';
import 'package:king_wallet_accounting/domain/services/accounting_replay_engine.dart';
import 'package:king_wallet_accounting/services/history_replay_service.dart';
import 'package:king_wallet_accounting/services/legacy_history_bridge_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const pathProviderChannel = MethodChannel('plugins.flutter.io/path_provider');
  final supportDir = Directory.systemTemp.createTempSync(
    'kw_event_replay_phase5_',
  );

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

  setUp(seedCleanDb);

  tearDownAll(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProviderChannel, null);
    try {
      if (supportDir.existsSync()) {
        supportDir.deleteSync(recursive: true);
      }
    } catch (_) {}
  });

  test('semantic event replay is deterministic', () {
    final events = _sampleSemanticEvents();
    final replayEngine = const AccountingReplayEngine();

    final first = replayEngine.replay(events);
    final second = replayEngine.replay(events);

    expect(second.accounting.drawer, first.accounting.drawer);
    expect(second.accounting.wallets, first.accounting.wallets);
    expect(
      second.customers.balancesByCustomer,
      first.customers.balancesByCustomer,
    );
    expect(second.wallets.balancesByWalletId, first.wallets.balancesByWalletId);
  });

  test(
    'settlement replay reduces customer balance without duplicate effects',
    () {
      final replay = const AccountingReplayEngine().replay(
        _sampleSemanticEvents(),
      );

      expect(replay.treasury.drawer, closeTo(400, 0.0001));
      expect(replay.wallets.balancesByWalletId[7], closeTo(1000, 0.0001));
      expect(replay.customers.balancesByCustomer['Replay Customer'], 600);
      expect(replay.accounting.pendingReceivable, 600);
    },
  );

  test('rollback and pending cancel replay are safe reversals', () {
    final replay = const AccountingReplayEngine().replay([
      const OpeningBalancesRecorded(drawer: 0, wallets: 1000),
      DeferredTransferEvent(
        transactionId: 'cancel-me',
        walletId: 1,
        walletDebitAmount: 300,
        customerAmount: 300,
        clientFee: 0,
        networkFee: 0,
        customerName: 'Cancel Customer',
      ),
      const WalletDebited(transactionId: 'cancel-me', amount: 300),
      const PendingCancelledEvent(
        transactionId: 'cancel-me',
        kind: PendingKind.deferredTransfer,
        walletDelta: 300,
      ),
      const RollbackEvent(
        transactionId: 'fee-rollback',
        drawerDelta: -10,
        clientFeeDelta: -5,
      ),
    ]);

    expect(replay.accounting.wallets, 1000);
    expect(replay.accounting.drawer, -10);
    expect(replay.accounting.pendingReceivable, 0);
    expect(replay.accounting.profitFromClientFees, -5);
    expect(replay.customers.balancesByCustomer['Cancel Customer'], 0);
  });

  test(
    'legacy bridge emits Phase 5 semantic events with stable ordering',
    () async {
      final db = AppDb.instance;
      final walletId = await db.addWallet(
        name: 'Replay Wallet',
        phone: '01080000001',
        openingBalance: 1000,
      );
      final pendingId = await db.addTransfer(
        walletId: walletId,
        amount: 300,
        clientFee: 5,
        networkFee: 0,
        transferType: 'type1',
        isPending: true,
        party: 'Replay Customer',
      );
      await db.addPendingSettlementForTxn(pendingTxnId: pendingId, amount: 100);
      await db.confirmPending(pendingId);

      final bridge = await const LegacyHistoryBridgeService().bridgeFromAppDb(
        db,
      );

      expect(
        bridge.events.map((event) => event.sequence),
        orderedEquals(
          List<int>.generate(bridge.events.length, (index) => index + 1),
        ),
      );
      expect(
        bridge.cleanEvents.any((event) => event is DeferredTransferEvent),
        isTrue,
      );
      expect(
        bridge.cleanEvents.any((event) => event is ClaimCreatedEvent),
        isTrue,
      );
      expect(
        bridge.cleanEvents.any((event) => event is PendingConfirmedEvent),
        isTrue,
      );
    },
  );

  test('legacy replay snapshot parity report has no drift', () async {
    final db = AppDb.instance;
    final transferWalletId = await db.addWallet(
      name: 'Parity Transfer Wallet',
      phone: '01080000002',
      openingBalance: 2000,
    );
    final receiveWalletId = await db.addWallet(
      name: 'Parity Receive Wallet',
      phone: '01080000003',
      openingBalance: 0,
    );
    await db.drawerDeposit(amount: 1000, note: 'seed');
    await db.addTransfer(
      walletId: transferWalletId,
      amount: 400,
      clientFee: 10,
      networkFee: 2,
      transferType: 'type1',
      isPending: false,
    );
    await db.addReceive(
      walletId: receiveWalletId,
      amount: 250,
      commission: 0,
      receiveType: 'cash',
      isPending: false,
    );
    await db.addExpense(amount: 50, category: 'office');
    await db.addFawry(
      serviceName: 'Electricity',
      amount: 100,
      fee: 5,
      collectionMethod: 'cash',
      isPending: false,
    );
    final claimId = await db.addClaim(
      type: 'receivable',
      party: 'Manual Claim Customer',
      amount: 150,
    );
    await db.settleClaim(claimId: claimId, amount: 25);

    final report = await const HistoryReplayService().verifyLegacyParity(db);

    expect(report.drifts.map((drift) => drift.toJson()).toList(), isEmpty);
    expect(
      report.replay.replaySnapshot.treasury.drawer,
      closeTo((await db.getTreasurySnapshot()).drawerActualBalance, 0.0001),
    );
    expect(
      report.replay.replaySnapshot.claims.receivableOpen,
      closeTo(125, 0.0001),
    );
    expect(report.replay.replaySnapshot.profit.clientFees, closeTo(15, 0.0001));
  });

  test(
    'wallet and customer snapshots are rebuilt from bridged history',
    () async {
      final db = AppDb.instance;
      final walletId = await db.addWallet(
        name: 'Wallet Snapshot',
        phone: '01080000004',
        openingBalance: 1000,
      );
      final pendingId = await db.addTransfer(
        walletId: walletId,
        amount: 500,
        clientFee: 0,
        networkFee: 0,
        transferType: 'type1',
        isPending: true,
        party: 'Snapshot Customer',
      );
      await db.addPendingSettlementForTxn(pendingTxnId: pendingId, amount: 200);

      final replay = await const HistoryReplayService().replayLegacyAppDb(db);

      expect(replay.replaySnapshot.wallets.balancesByWalletId[walletId], 500);
      expect(
        replay.replaySnapshot.customers.balancesByCustomer['Snapshot Customer'],
        300,
      );
      expect(replay.replaySnapshot.customers.totalForUs, 300);
    },
  );
}

List<AccountingEvent> _sampleSemanticEvents() {
  return [
    const OpeningBalancesRecorded(drawer: 0, wallets: 0),
    const WalletFundingEvent(
      transactionId: 'semantic-funding',
      walletId: 7,
      amount: 1400,
    ),
    DeferredTransferEvent(
      transactionId: 'semantic-transfer',
      walletId: 7,
      walletDebitAmount: 400,
      customerAmount: 1000,
      clientFee: 0,
      networkFee: 0,
      customerName: 'Replay Customer',
    ),
    const WalletDebited(transactionId: 'semantic-transfer', amount: 400),
    const SettlementEvent(
      settlement: SettlementEntry(
        id: 'semantic-settlement',
        deferredTransferId: 'semantic-transfer',
        amount: 400,
      ),
      remainingAmount: 600,
      direction: CashFlowDirection.inflow,
    ),
  ];
}
