import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:king_wallet_accounting/application/ports/event_repository.dart';
import 'package:king_wallet_accounting/application/ports/snapshot_repository.dart';
import 'package:king_wallet_accounting/data/sqlite/app_database.dart';
import 'package:king_wallet_accounting/domain/services/accounting_engine.dart';
import 'package:king_wallet_accounting/domain/services/snapshot_builder.dart';
import 'package:king_wallet_accounting/infrastructure/adapters/drift_event_repository.dart';
import 'package:king_wallet_accounting/infrastructure/adapters/in_memory_event_repository.dart';
import 'package:king_wallet_accounting/infrastructure/adapters/in_memory_snapshot_repository.dart';

typedef EventRepositoryFactory = Future<EventRepository> Function();
typedef EventRepositoryDisposer = Future<void> Function(EventRepository repo);
typedef SnapshotRepositoryFactory = Future<SnapshotRepository> Function();
typedef SnapshotRepositoryDisposer =
    Future<void> Function(SnapshotRepository repo);

void runEventRepositoryContractTests(
  String description,
  EventRepositoryFactory createRepository, {
  EventRepositoryDisposer? disposeRepository,
}) {
  group(description, () {
    late EventRepository repository;

    setUp(() async {
      repository = await createRepository();
    });

    tearDown(() async {
      if (disposeRepository != null) {
        await disposeRepository(repository);
      }
    });

    test('saveEvents persists events', () async {
      final events = <AccountingEvent>[
        const OpeningBalancesRecorded(drawer: 10, wallets: 20),
        const WalletDebited(transactionId: 'tx-1', amount: 5),
      ];

      await repository.saveEvents(events);

      expect(await repository.loadEvents(), hasLength(2));
    });

    test('loadEvents returns same events', () async {
      final events = <AccountingEvent>[
        const OpeningBalancesRecorded(drawer: 10, wallets: 20),
        const ClientFeeApplied(transactionId: 'tx-1', amount: 5),
      ];

      await repository.saveEvents(events);
      final loaded = await repository.loadEvents();

      expect(loaded, hasLength(2));
      _expectEventEquivalent(loaded.first, events.first);
      _expectEventEquivalent(loaded.last, events.last);
    });

    test('ordering is preserved', () async {
      final events = <AccountingEvent>[
        const OpeningBalancesRecorded(drawer: 0, wallets: 100),
        const WalletDebited(transactionId: 'tx-1', amount: 50),
        const ClientFeeApplied(transactionId: 'tx-1', amount: 5),
        const PendingConfirmed(
          transactionId: 'tx-1',
          kind: PendingKind.deferredTransfer,
          remainingAmount: 0,
        ),
      ];

      await repository.saveEvents(events);
      final loaded = await repository.loadEvents();

      expect(loaded, hasLength(4));
      for (var i = 0; i < loaded.length; i++) {
        _expectEventEquivalent(loaded[i], events[i]);
      }
    });

    test('multiple saves append correctly', () async {
      final firstBatch = <AccountingEvent>[
        const OpeningBalancesRecorded(drawer: 0, wallets: 100),
        const WalletCredited(transactionId: 'rx-1', amount: 100),
      ];
      final secondBatch = <AccountingEvent>[
        const PartialPaid(
          settlement: SettlementEntry(
            id: 'st-1',
            deferredReceiveId: 'rx-1',
            amount: 40,
          ),
          remainingAmount: 60,
        ),
        const PendingConfirmed(
          transactionId: 'rx-1',
          kind: PendingKind.deferredReceive,
          remainingAmount: 60,
        ),
      ];

      await repository.saveEvents(firstBatch);
      await repository.saveEvents(secondBatch);

      final loaded = await repository.loadEvents();
      expect(loaded, hasLength(4));
      _expectEventEquivalent(loaded[0], firstBatch[0]);
      _expectEventEquivalent(loaded[1], firstBatch[1]);
      _expectEventEquivalent(loaded[2], secondBatch[0]);
      _expectEventEquivalent(loaded[3], secondBatch[1]);
    });

    test('no data loss across repeated loads', () async {
      final events = <AccountingEvent>[
        const OpeningBalancesRecorded(drawer: 25, wallets: 75),
        const DeferredTransferCreated(
          transaction: DeferredTransfer(
            id: 'tx-1',
            walletAmount: 50,
            clientFee: 5,
            networkFee: 0,
            originalCustomerAmount: 55,
            status: DeferredTransferStatus.pending,
          ),
        ),
        const WalletDebited(transactionId: 'tx-1', amount: 50),
      ];

      await repository.saveEvents(events);

      final firstLoad = await repository.loadEvents();
      final secondLoad = await repository.loadEvents();

      expect(firstLoad, hasLength(3));
      expect(secondLoad, hasLength(3));
      for (var i = 0; i < firstLoad.length; i++) {
        _expectEventEquivalent(firstLoad[i], secondLoad[i]);
      }
    });
  });
}

void runSnapshotRepositoryContractTests(
  String description,
  SnapshotRepositoryFactory createRepository, {
  SnapshotRepositoryDisposer? disposeRepository,
}) {
  group(description, () {
    late SnapshotRepository repository;

    setUp(() async {
      repository = await createRepository();
    });

    tearDown(() async {
      if (disposeRepository != null) {
        await disposeRepository(repository);
      }
    });

    test('saveSnapshot then loadSnapshot returns same values', () async {
      const snapshot = AccountingSnapshot(
        drawer: 500,
        wallets: 1100,
        pendingReceivable: 405,
        pendingPayable: 0,
        openClaimsReceivable: 0,
        openClaimsPayable: 0,
        profitFromClientFees: 5,
        networkFeesTotal: 0,
        availableLiquidityNow: 1600,
        realCapitalApproved: 2005,
      );

      await repository.saveSnapshot(snapshot);
      final loaded = await repository.loadSnapshot();

      expect(loaded, isNotNull);
      expect(loaded!.drawer, closeTo(500, 0.0001));
      expect(loaded.wallets, closeTo(1100, 0.0001));
      expect(loaded.pendingReceivable, closeTo(405, 0.0001));
      expect(loaded.pendingPayable, closeTo(0, 0.0001));
      expect(loaded.openClaimsReceivable, closeTo(0, 0.0001));
      expect(loaded.openClaimsPayable, closeTo(0, 0.0001));
      expect(loaded.profitFromClientFees, closeTo(5, 0.0001));
      expect(loaded.networkFeesTotal, closeTo(0, 0.0001));
      expect(loaded.availableLiquidityNow, closeTo(1600, 0.0001));
      expect(loaded.realCapitalApproved, closeTo(2005, 0.0001));
    });

    test(
      'latest saveSnapshot overwrites previous snapshot consistently',
      () async {
        const first = AccountingSnapshot(
          drawer: 100,
          wallets: 200,
          pendingReceivable: 300,
          pendingPayable: 0,
          openClaimsReceivable: 50,
          openClaimsPayable: 0,
          profitFromClientFees: 5,
          networkFeesTotal: 1,
          availableLiquidityNow: 300,
          realCapitalApproved: 650,
        );
        const second = AccountingSnapshot(
          drawer: 500,
          wallets: 1100,
          pendingReceivable: 0,
          pendingPayable: 600,
          openClaimsReceivable: 405,
          openClaimsPayable: 600,
          profitFromClientFees: 5,
          networkFeesTotal: 0,
          availableLiquidityNow: 1600,
          realCapitalApproved: 1405,
        );

        await repository.saveSnapshot(first);
        await repository.saveSnapshot(second);
        final loaded = await repository.loadSnapshot();

        expect(loaded, isNotNull);
        expect(loaded!.drawer, closeTo(second.drawer, 0.0001));
        expect(loaded.wallets, closeTo(second.wallets, 0.0001));
        expect(
          loaded.pendingReceivable,
          closeTo(second.pendingReceivable, 0.0001),
        );
        expect(loaded.pendingPayable, closeTo(second.pendingPayable, 0.0001));
        expect(
          loaded.openClaimsReceivable,
          closeTo(second.openClaimsReceivable, 0.0001),
        );
        expect(
          loaded.openClaimsPayable,
          closeTo(second.openClaimsPayable, 0.0001),
        );
        expect(
          loaded.availableLiquidityNow,
          closeTo(second.availableLiquidityNow, 0.0001),
        );
        expect(
          loaded.realCapitalApproved,
          closeTo(second.realCapitalApproved, 0.0001),
        );
      },
    );
  });
}

void _expectEventEquivalent(AccountingEvent actual, AccountingEvent expected) {
  expect(actual.runtimeType, equals(expected.runtimeType));
  switch ((actual, expected)) {
    case (OpeningBalancesRecorded a, OpeningBalancesRecorded e):
      expect(a.drawer, closeTo(e.drawer, 0.0001));
      expect(a.wallets, closeTo(e.wallets, 0.0001));
    case (WalletDebited a, WalletDebited e):
      expect(a.transactionId, e.transactionId);
      expect(a.amount, closeTo(e.amount, 0.0001));
    case (WalletCredited a, WalletCredited e):
      expect(a.transactionId, e.transactionId);
      expect(a.amount, closeTo(e.amount, 0.0001));
    case (ClientFeeApplied a, ClientFeeApplied e):
      expect(a.transactionId, e.transactionId);
      expect(a.amount, closeTo(e.amount, 0.0001));
    case (NetworkFeeApplied a, NetworkFeeApplied e):
      expect(a.transactionId, e.transactionId);
      expect(a.amount, closeTo(e.amount, 0.0001));
    case (PendingConfirmed a, PendingConfirmed e):
      expect(a.transactionId, e.transactionId);
      expect(a.kind, e.kind);
      expect(a.remainingAmount, closeTo(e.remainingAmount, 0.0001));
    case (PartialPaid a, PartialPaid e):
      expect(a.direction, e.direction);
      expect(a.remainingAmount, closeTo(e.remainingAmount, 0.0001));
      _expectSettlementEquivalent(a.settlement, e.settlement);
    case (PartialCollected a, PartialCollected e):
      expect(a.direction, e.direction);
      expect(a.remainingAmount, closeTo(e.remainingAmount, 0.0001));
      _expectSettlementEquivalent(a.settlement, e.settlement);
    case (DeferredTransferCreated a, DeferredTransferCreated e):
      _expectDeferredTransferEquivalent(a.transaction, e.transaction);
    case (DeferredReceiveCreated a, DeferredReceiveCreated e):
      _expectDeferredReceiveEquivalent(a.transaction, e.transaction);
    case _:
      fail('Unhandled event comparison for ${actual.runtimeType}');
  }
}

void _expectSettlementEquivalent(
  SettlementEntry actual,
  SettlementEntry expected,
) {
  expect(actual.id, expected.id);
  expect(actual.deferredTransferId, expected.deferredTransferId);
  expect(actual.deferredReceiveId, expected.deferredReceiveId);
  expect(actual.claimId, expected.claimId);
  expect(actual.amount, closeTo(expected.amount, 0.0001));
}

void _expectDeferredTransferEquivalent(
  DeferredTransfer actual,
  DeferredTransfer expected,
) {
  expect(actual.id, expected.id);
  expect(actual.walletAmount, closeTo(expected.walletAmount, 0.0001));
  expect(actual.clientFee, closeTo(expected.clientFee, 0.0001));
  expect(actual.networkFee, closeTo(expected.networkFee, 0.0001));
  expect(
    actual.originalCustomerAmount,
    closeTo(expected.originalCustomerAmount, 0.0001),
  );
  expect(actual.status, expected.status);
}

void _expectDeferredReceiveEquivalent(
  DeferredReceive actual,
  DeferredReceive expected,
) {
  expect(actual.id, expected.id);
  expect(actual.walletAmount, closeTo(expected.walletAmount, 0.0001));
  expect(
    actual.originalPayableAmount,
    closeTo(expected.originalPayableAmount, 0.0001),
  );
  expect(actual.status, expected.status);
}

Future<DriftEventRepository> _createDriftEventRepository() async {
  final dir = await Directory.systemTemp.createTemp('smart-cash-events-');
  final path = '${dir.path}${Platform.pathSeparator}event_store.db';
  final db = AppDatabase(customPath: path, hardenRuntimePragmas: false);
  return DriftEventRepository(db, storePath: path);
}

void main() {
  runEventRepositoryContractTests(
    'InMemoryEventRepository contract',
    () async => InMemoryEventRepository(),
  );

  runEventRepositoryContractTests(
    'DriftEventRepository contract',
    _createDriftEventRepository,
    disposeRepository: (repo) async {
      if (repo is DriftEventRepository) {
        await repo.close();
        final file = File(repo.storePath);
        if (await file.exists()) {
          await file.delete();
        }
        final walFile = File('${repo.storePath}-wal');
        if (await walFile.exists()) {
          await walFile.delete();
        }
        final shmFile = File('${repo.storePath}-shm');
        if (await shmFile.exists()) {
          await shmFile.delete();
        }
      }
    },
  );

  runSnapshotRepositoryContractTests(
    'InMemorySnapshotRepository contract',
    () async => InMemorySnapshotRepository(),
  );
}
