import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:king_wallet_accounting/data/app_db.dart';
import 'package:king_wallet_accounting/data/app_session.dart';
import 'package:king_wallet_accounting/domain/services/accounting_engine.dart';
import 'package:king_wallet_accounting/domain/services/snapshot_builder.dart';
import 'package:king_wallet_accounting/screens/customer_account/customer_account_builder.dart';
import 'package:king_wallet_accounting/screens/customer_account/customer_account_models.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const pathProviderChannel = MethodChannel('plugins.flutter.io/path_provider');
  final supportDir = Directory.systemTemp.createTempSync(
    'kw_isolation_migration_safety_',
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

  test(
    'migration safety: snapshot, treasury, customer, and story parity',
    () async {
      final db = AppDb.instance;
      final walletId = await db.addWallet(
        name: 'Isolation Wallet',
        phone: '01099990000',
        openingBalance: 2000,
      );

      final pendingTxnId = await db.addTransfer(
        walletId: walletId,
        amount: 900,
        clientFee: 5,
        networkFee: 0,
        transferType: 'type1',
        isPending: true,
        party: 'Isolation Customer',
        note: '01012345678',
      );
      await db.addPendingSettlementForTxn(
        pendingTxnId: pendingTxnId,
        amount: 500,
      );
      await db.confirmPending(pendingTxnId);

      final appDbSnapshot = await db.getTreasurySnapshot();
      final cleanSnapshot = _cleanDeferredTransferSnapshot();
      _expectTreasuryParity(appDbSnapshot, cleanSnapshot);

      final accounts = CustomerAccountBuilder.fromAppDbData(
        txns: await db.listTxns(),
        claims: await db.listClaims(),
      );
      final account = accounts.singleWhere(
        (item) => item.summary.customerName == 'Isolation Customer',
      );

      expect(account.summary.totalForUs, closeTo(405, 0.0001));
      expect(account.summary.totalAgainstUs, closeTo(0, 0.0001));
      expect(account.summary.netBalance, closeTo(405, 0.0001));
      expect(account.summary.openClaimsForUs, closeTo(405, 0.0001));
      expect(account.summary.openDeferredForUs, closeTo(0, 0.0001));

      final sourceTypes = account.rows.map((row) => row.sourceType).toList();
      expect(sourceTypes, contains(CustomerLedgerSourceType.deferredTransfer));
      expect(sourceTypes, contains(CustomerLedgerSourceType.settlement));
      expect(sourceTypes, contains(CustomerLedgerSourceType.claimReceivable));

      final storyRows = account.rows
          .where((row) => row.storySourceTxnId == pendingTxnId)
          .toList();
      expect(storyRows.map((row) => row.amount), containsAll([905, 500, 405]));
      final original = storyRows.singleWhere(
        (row) => row.sourceType == CustomerLedgerSourceType.deferredTransfer,
      );
      expect(original.amount, closeTo(905, 0.0001));
    },
  );
}

AccountingSnapshot _cleanDeferredTransferSnapshot() {
  const engine = AccountingEngine();
  final initialState = AccountingEngineState(
    drawerBalance: 0,
    walletBalance: 2000,
  );
  final created = engine.createDeferredTransfer(
    state: initialState,
    transactionId: 'clean-transfer',
    walletAmount: 900,
    clientFee: 5,
  );
  final collected = engine.collectPartial(
    state: created.newState,
    deferredTransferId: 'clean-transfer',
    settlementId: 'clean-transfer-collect-1',
    amount: 500,
  );
  final confirmed = engine.confirmPending(
    state: collected.newState,
    deferredTransferId: 'clean-transfer',
    claimId: 'clean-transfer-claim',
  );

  return buildSnapshot([
    const OpeningBalancesRecorded(drawer: 0, wallets: 2000),
    ...created.events,
    ...collected.events,
    ...confirmed.events,
  ]);
}

void _expectTreasuryParity(
  TreasurySnapshot appDbSnapshot,
  AccountingSnapshot cleanSnapshot,
) {
  expect(
    cleanSnapshot.drawer,
    closeTo(appDbSnapshot.drawerActualBalance, 0.0001),
  );
  expect(
    cleanSnapshot.wallets,
    closeTo(appDbSnapshot.walletsActualTotal, 0.0001),
  );
  expect(
    cleanSnapshot.pendingReceivable,
    closeTo(appDbSnapshot.pendingReceivableOpen, 0.0001),
  );
  expect(
    cleanSnapshot.pendingPayable,
    closeTo(appDbSnapshot.pendingPayableOpen, 0.0001),
  );
  expect(
    cleanSnapshot.openClaimsReceivable,
    closeTo(appDbSnapshot.claimsReceivableOpen, 0.0001),
  );
  expect(
    cleanSnapshot.openClaimsPayable,
    closeTo(appDbSnapshot.claimsPayableOpen, 0.0001),
  );
  expect(
    cleanSnapshot.availableLiquidityNow,
    closeTo(appDbSnapshot.availableLiquidityNow, 0.0001),
  );
  expect(
    cleanSnapshot.realCapitalApproved,
    closeTo(appDbSnapshot.realCapitalApproved, 0.0001),
  );
}
