import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:king_wallet_accounting/application/write_gateway/clean_write_gateway.dart';
import 'package:king_wallet_accounting/application/write_gateway/write_intents.dart';
import 'package:king_wallet_accounting/data/app_db.dart';
import 'package:king_wallet_accounting/data/app_session.dart';
import 'package:king_wallet_accounting/data/sqlite/app_database.dart';
import 'package:king_wallet_accounting/domain/services/accounting_engine.dart';
import 'package:king_wallet_accounting/domain/services/accounting_event_models.dart';
import 'package:king_wallet_accounting/domain/services/accounting_replay_engine.dart';
import 'package:king_wallet_accounting/infrastructure/adapters/drift_event_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const pathProviderChannel = MethodChannel('plugins.flutter.io/path_provider');
  final supportDir = Directory.systemTemp.createTempSync('kw_phase6_');

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
    'gateway persists semantic events with deterministic ordering',
    () async {
      final dbPath = '${supportDir.path}/phase6_gateway_events.sqlite';
      final eventDb = AppDatabase(customPath: dbPath);
      final repo = DriftEventRepository(eventDb, storePath: dbPath);
      addTearDown(repo.close);

      final walletId = await AppDb.instance.addWallet(
        name: 'Persist Wallet',
        phone: '01090000001',
        openingBalance: 1000,
      );
      await CleanWriteGateway.appDbBridge(shadowEventRepository: repo).execute(
        CreateTransferIntent(
          transactionId: 'intent-transfer',
          settlementId: 'intent-transfer-settlement',
          claimId: 'intent-transfer-claim',
          walletId: walletId,
          amount: 300,
          clientFee: 5,
          networkFee: 2,
          party: 'Persist Customer',
        ),
      );

      final records = await repo.loadStoredEventRecords();
      expect(
        records.map((record) => record.sequence),
        orderedEquals([1, 2, 3, 4, 5, 6]),
      );
      expect(
        records.every((record) => record.checksum?.isNotEmpty ?? false),
        isTrue,
      );
      expect(await repo.verifyIntegrity(), isTrue);
      expect(
        (await repo.loadEvents()).any((event) => event is TransferCreatedEvent),
        isTrue,
      );
    },
  );

  test(
    'persisted events replay after restart with checksum integrity',
    () async {
      final dbPath = '${supportDir.path}/phase6_restart_events.sqlite';
      final eventDb = AppDatabase(customPath: dbPath);
      final repo = DriftEventRepository(eventDb, storePath: dbPath);
      await repo.saveEvents([
        const OpeningBalancesRecorded(drawer: 0, wallets: 0),
        const WalletFundingEvent(
          transactionId: 'funding-1',
          walletId: 1,
          amount: 1000,
        ),
        DeferredTransferEvent(
          transactionId: 'deferred-1',
          walletId: 1,
          walletDebitAmount: 400,
          customerAmount: 400,
          clientFee: 0,
          networkFee: 0,
          customerName: 'Restart Customer',
        ),
        const WalletDebited(transactionId: 'deferred-1', amount: 400),
      ]);
      await repo.close();

      final reopenedDb = AppDatabase(customPath: dbPath);
      final reopened = DriftEventRepository(reopenedDb, storePath: dbPath);
      addTearDown(reopened.close);
      final replay = const AccountingReplayEngine().replay(
        await reopened.loadEvents(),
      );

      expect(await reopened.verifyIntegrity(), isTrue);
      expect(replay.wallets.balancesByWalletId[1], 600);
      expect(replay.customers.balancesByCustomer['Restart Customer'], 400);
    },
  );

  test('checksum integrity detects corrupted persisted events', () async {
    final dbPath = '${supportDir.path}/phase6_corrupt_events.sqlite';
    final eventDb = AppDatabase(customPath: dbPath);
    final repo = DriftEventRepository(eventDb, storePath: dbPath);
    addTearDown(repo.close);

    await repo.saveEvents([
      const WalletFundingEvent(
        transactionId: 'funding-1',
        walletId: 1,
        amount: 100,
      ),
    ]);
    await eventDb.customStatement(
      "UPDATE accounting_events SET payload = '{\"amount\":999}' WHERE seq = 1",
    );

    expect(await repo.verifyIntegrity(), isFalse);
  });

  test(
    'rollback replay integrity is preserved from persisted events',
    () async {
      final dbPath = '${supportDir.path}/phase6_rollback_events.sqlite';
      final eventDb = AppDatabase(customPath: dbPath);
      final repo = DriftEventRepository(eventDb, storePath: dbPath);
      addTearDown(repo.close);

      await repo.saveEvents([
        const OpeningBalancesRecorded(drawer: 0, wallets: 1000),
        DeferredTransferEvent(
          transactionId: 'rollback-tx',
          walletId: 1,
          walletDebitAmount: 300,
          customerAmount: 300,
          clientFee: 0,
          networkFee: 0,
          customerName: 'Rollback Customer',
        ),
        const WalletDebited(transactionId: 'rollback-tx', amount: 300),
        const PendingCancelledEvent(
          transactionId: 'rollback-tx',
          kind: PendingKind.deferredTransfer,
          walletDelta: 300,
        ),
        const RollbackEvent(transactionId: 'rollback-tx'),
      ]);

      final replay = const AccountingReplayEngine().replay(
        await repo.loadEvents(),
      );
      expect(replay.accounting.wallets, 1000);
      expect(replay.accounting.pendingReceivable, 0);
      expect(replay.customers.balancesByCustomer['Rollback Customer'], 0);
    },
  );



}

