import 'package:flutter_test/flutter_test.dart';
import 'package:king_wallet_accounting/application/use_cases/collect_partial_use_case.dart';
import 'package:king_wallet_accounting/application/use_cases/confirm_pending_use_case.dart';
import 'package:king_wallet_accounting/application/use_cases/create_deferred_receive_use_case.dart';
import 'package:king_wallet_accounting/application/use_cases/create_deferred_transfer_use_case.dart';
import 'package:king_wallet_accounting/application/use_cases/create_receive_use_case.dart';
import 'package:king_wallet_accounting/application/use_cases/create_transfer_use_case.dart';
import 'package:king_wallet_accounting/application/use_cases/pay_partial_use_case.dart';
import 'package:king_wallet_accounting/application/use_cases/settle_claim_use_case.dart';
import 'package:king_wallet_accounting/application/use_cases/use_case_models.dart';
import 'package:king_wallet_accounting/domain/services/accounting_engine.dart';
import 'package:king_wallet_accounting/infrastructure/adapters/in_memory_event_repository.dart';
import 'package:king_wallet_accounting/infrastructure/adapters/in_memory_snapshot_repository.dart';

void main() {
  group('Application use cases with repositories', () {
    late InMemoryEventRepository eventRepository;
    late InMemorySnapshotRepository snapshotRepository;

    setUp(() {
      eventRepository = InMemoryEventRepository([
        const OpeningBalancesRecorded(drawer: 0, wallets: 2000),
      ]);
      snapshotRepository = InMemorySnapshotRepository();
    });

    test(
      'CreateDeferredTransferUseCase persists events and snapshot reflects pending only',
      () async {
        final useCase = CreateDeferredTransferUseCase(
          eventRepository: eventRepository,
          snapshotRepository: snapshotRepository,
        );
        final result = await useCase.execute(
          const CreateDeferredTransferInput(
            transactionId: 'tx-1',
            walletAmount: 900,
            clientFee: 5,
          ),
        );

        expect(
          result.events.whereType<DeferredTransferCreated>(),
          hasLength(1),
        );
        expect(result.events.whereType<WalletDebited>(), hasLength(1));
        expect(result.events.whereType<ClientFeeApplied>(), hasLength(1));
        expect(await eventRepository.loadEvents(), hasLength(4));
        expect(await snapshotRepository.loadSnapshot(), isNotNull);
        expect(result.snapshot.drawer, closeTo(0, 0.0001));
        expect(result.snapshot.wallets, closeTo(1100, 0.0001));
        expect(result.snapshot.pendingReceivable, closeTo(905, 0.0001));
        expect(result.snapshot.availableLiquidityNow, closeTo(1100, 0.0001));
        expect(result.snapshot.realCapitalApproved, closeTo(2005, 0.0001));
      },
    );

    test(
      'CollectPartialUseCase reloads from repository and adds only cash while keeping remaining pending open',
      () async {
        await CreateDeferredTransferUseCase(
          eventRepository: eventRepository,
          snapshotRepository: snapshotRepository,
        ).execute(
          const CreateDeferredTransferInput(
            transactionId: 'tx-1',
            walletAmount: 900,
            clientFee: 5,
          ),
        );

        final collected =
            await CollectPartialUseCase(
              eventRepository: eventRepository,
              snapshotRepository: snapshotRepository,
            ).execute(
              const CollectPartialInput(
                deferredTransferId: 'tx-1',
                settlementId: 'st-1',
                amount: 500,
              ),
            );

        expect(collected.events.single, isA<PartialCollected>());
        expect(await eventRepository.loadEvents(), hasLength(5));
        expect(collected.snapshot.drawer, closeTo(500, 0.0001));
        expect(collected.snapshot.wallets, closeTo(1100, 0.0001));
        expect(collected.snapshot.pendingReceivable, closeTo(405, 0.0001));
        expect(collected.snapshot.openClaimsReceivable, closeTo(0, 0.0001));
      },
    );

    test(
      'ConfirmPendingUseCase rebuilds from repository and moves only remaining to claim with no extra cash',
      () async {
        await CreateDeferredTransferUseCase(
          eventRepository: eventRepository,
          snapshotRepository: snapshotRepository,
        ).execute(
          const CreateDeferredTransferInput(
            transactionId: 'tx-1',
            walletAmount: 900,
            clientFee: 5,
          ),
        );
        await CollectPartialUseCase(
          eventRepository: eventRepository,
          snapshotRepository: snapshotRepository,
        ).execute(
          const CollectPartialInput(
            deferredTransferId: 'tx-1',
            settlementId: 'st-1',
            amount: 500,
          ),
        );

        final confirmed =
            await ConfirmPendingUseCase(
              eventRepository: eventRepository,
              snapshotRepository: snapshotRepository,
            ).execute(
              const ConfirmPendingInput(
                pendingTransactionId: 'tx-1',
                claimId: 'claim-1',
              ),
            );

        expect(confirmed.events.whereType<PendingConfirmed>(), hasLength(1));
        expect(confirmed.events.whereType<ClaimOpened>(), hasLength(1));
        expect(await eventRepository.loadEvents(), hasLength(7));
        expect(confirmed.snapshot.drawer, closeTo(500, 0.0001));
        expect(confirmed.snapshot.wallets, closeTo(1100, 0.0001));
        expect(confirmed.snapshot.pendingReceivable, closeTo(0, 0.0001));
        expect(confirmed.snapshot.openClaimsReceivable, closeTo(405, 0.0001));
        expect(confirmed.snapshot.availableLiquidityNow, closeTo(1600, 0.0001));
        expect(confirmed.snapshot.realCapitalApproved, closeTo(2005, 0.0001));
      },
    );

    test(
      'CreateTransferUseCase orchestrates and persists final posted snapshot',
      () async {
        final result =
            await CreateTransferUseCase(
              eventRepository: eventRepository,
              snapshotRepository: snapshotRepository,
            ).execute(
              const CreateTransferInput(
                transactionId: 'tx-1',
                settlementId: 'st-1',
                claimId: 'claim-1',
                walletAmount: 900,
                clientFee: 5,
              ),
            );

        expect(
          result.events.whereType<DeferredTransferCreated>(),
          hasLength(1),
        );
        expect(result.events.whereType<PartialCollected>(), hasLength(1));
        expect(result.events.whereType<PendingConfirmed>(), hasLength(1));
        expect(result.events.whereType<ClaimOpened>(), isEmpty);
        expect(await eventRepository.loadEvents(), hasLength(6));
        expect(await snapshotRepository.loadSnapshot(), isNotNull);
        expect(result.snapshot.drawer, closeTo(905, 0.0001));
        expect(result.snapshot.wallets, closeTo(1100, 0.0001));
        expect(result.snapshot.pendingReceivable, closeTo(0, 0.0001));
        expect(result.snapshot.openClaimsReceivable, closeTo(0, 0.0001));
        expect(result.snapshot.availableLiquidityNow, closeTo(2005, 0.0001));
        expect(result.snapshot.realCapitalApproved, closeTo(2005, 0.0001));
      },
    );

    test(
      'CreateDeferredReceiveUseCase persists payable-side pending snapshot',
      () async {
        eventRepository = InMemoryEventRepository([
          const OpeningBalancesRecorded(drawer: 1000, wallets: 0),
        ]);
        final useCase = CreateDeferredReceiveUseCase(
          eventRepository: eventRepository,
          snapshotRepository: snapshotRepository,
        );

        final result = await useCase.execute(
          const CreateDeferredReceiveInput(
            transactionId: 'rx-1',
            walletAmount: 1000,
          ),
        );

        expect(result.events.whereType<DeferredReceiveCreated>(), hasLength(1));
        expect(result.events.whereType<WalletCredited>(), hasLength(1));
        expect(await eventRepository.loadEvents(), hasLength(3));
        expect(result.snapshot.drawer, closeTo(1000, 0.0001));
        expect(result.snapshot.wallets, closeTo(1000, 0.0001));
        expect(result.snapshot.pendingPayable, closeTo(1000, 0.0001));
        expect(result.snapshot.realCapitalApproved, closeTo(1000, 0.0001));
      },
    );

    test(
      'PayPartialUseCase decreases drawer only and keeps payable pending remaining from repository state',
      () async {
        eventRepository = InMemoryEventRepository([
          const OpeningBalancesRecorded(drawer: 1000, wallets: 0),
        ]);
        await CreateDeferredReceiveUseCase(
          eventRepository: eventRepository,
          snapshotRepository: snapshotRepository,
        ).execute(
          const CreateDeferredReceiveInput(
            transactionId: 'rx-1',
            walletAmount: 1000,
          ),
        );

        final paid =
            await PayPartialUseCase(
              eventRepository: eventRepository,
              snapshotRepository: snapshotRepository,
            ).execute(
              const PayPartialInput(
                deferredReceiveId: 'rx-1',
                settlementId: 'pay-1',
                amount: 400,
              ),
            );

        expect(paid.events.single, isA<PartialPaid>());
        expect(await eventRepository.loadEvents(), hasLength(4));
        expect(paid.snapshot.drawer, closeTo(600, 0.0001));
        expect(paid.snapshot.wallets, closeTo(1000, 0.0001));
        expect(paid.snapshot.pendingPayable, closeTo(600, 0.0001));
        expect(paid.snapshot.openClaimsPayable, closeTo(0, 0.0001));
      },
    );

    test(
      'CreateReceiveUseCase orchestrates payable flow into final posted snapshot',
      () async {
        eventRepository = InMemoryEventRepository([
          const OpeningBalancesRecorded(drawer: 1000, wallets: 0),
        ]);
        final result =
            await CreateReceiveUseCase(
              eventRepository: eventRepository,
              snapshotRepository: snapshotRepository,
            ).execute(
              const CreateReceiveInput(
                transactionId: 'rx-1',
                settlementId: 'pay-1',
                claimId: 'claim-pay-1',
                walletAmount: 1000,
              ),
            );

        expect(result.events.whereType<DeferredReceiveCreated>(), hasLength(1));
        expect(result.events.whereType<PartialPaid>(), hasLength(1));
        expect(result.events.whereType<PendingConfirmed>(), hasLength(1));
        expect(result.events.whereType<ClaimOpened>(), isEmpty);
        expect(await eventRepository.loadEvents(), hasLength(5));
        expect(result.snapshot.drawer, closeTo(0, 0.0001));
        expect(result.snapshot.wallets, closeTo(1000, 0.0001));
        expect(result.snapshot.pendingPayable, closeTo(0, 0.0001));
        expect(result.snapshot.openClaimsPayable, closeTo(0, 0.0001));
        expect(result.snapshot.availableLiquidityNow, closeTo(1000, 0.0001));
        expect(result.snapshot.realCapitalApproved, closeTo(1000, 0.0001));
      },
    );

    test(
      'SettleClaimUseCase persists claim settlement and rebuilds snapshot from repository',
      () async {
        await CreateDeferredTransferUseCase(
          eventRepository: eventRepository,
          snapshotRepository: snapshotRepository,
        ).execute(
          const CreateDeferredTransferInput(
            transactionId: 'tx-1',
            walletAmount: 900,
            clientFee: 5,
          ),
        );
        await CollectPartialUseCase(
          eventRepository: eventRepository,
          snapshotRepository: snapshotRepository,
        ).execute(
          const CollectPartialInput(
            deferredTransferId: 'tx-1',
            settlementId: 'st-1',
            amount: 500,
          ),
        );
        await ConfirmPendingUseCase(
          eventRepository: eventRepository,
          snapshotRepository: snapshotRepository,
        ).execute(
          const ConfirmPendingInput(
            pendingTransactionId: 'tx-1',
            claimId: 'claim-1',
          ),
        );

        final settled =
            await SettleClaimUseCase(
              eventRepository: eventRepository,
              snapshotRepository: snapshotRepository,
            ).execute(
              const SettleClaimInput(
                claimId: 'claim-1',
                settlementId: 'claim-st-1',
                amount: 405,
              ),
            );

        expect(settled.events.whereType<PartialCollected>(), hasLength(1));
        expect(settled.events.whereType<ClaimFullySettled>(), hasLength(1));
        expect(settled.events.whereType<ClaimClosed>(), hasLength(1));
        expect(await eventRepository.loadEvents(), hasLength(10));
        expect(settled.snapshot.drawer, closeTo(905, 0.0001));
        expect(settled.snapshot.wallets, closeTo(1100, 0.0001));
        expect(settled.snapshot.openClaimsReceivable, closeTo(0, 0.0001));
        expect(settled.snapshot.realCapitalApproved, closeTo(2005, 0.0001));
      },
    );
  });
}
