import '../ports/event_repository.dart';
import '../ports/snapshot_repository.dart';
import 'collect_partial_use_case.dart';
import 'confirm_pending_use_case.dart';
import 'create_deferred_transfer_use_case.dart';
import 'use_case_models.dart';

class CreateTransferUseCase {
  CreateTransferUseCase({
    required EventRepository eventRepository,
    required SnapshotRepository snapshotRepository,
  }) : _createDeferredTransferUseCase = CreateDeferredTransferUseCase(
         eventRepository: eventRepository,
         snapshotRepository: snapshotRepository,
       ),
       _collectPartialUseCase = CollectPartialUseCase(
         eventRepository: eventRepository,
         snapshotRepository: snapshotRepository,
       ),
       _confirmPendingUseCase = ConfirmPendingUseCase(
         eventRepository: eventRepository,
         snapshotRepository: snapshotRepository,
       );

  final CreateDeferredTransferUseCase _createDeferredTransferUseCase;
  final CollectPartialUseCase _collectPartialUseCase;
  final ConfirmPendingUseCase _confirmPendingUseCase;

  Future<UseCaseResult> execute(CreateTransferInput input) async {
    final created = await _createDeferredTransferUseCase.execute(
      CreateDeferredTransferInput(
        transactionId: input.transactionId,
        walletAmount: input.walletAmount,
        clientFee: input.clientFee,
        networkFee: input.networkFee,
        walletId: input.walletId,
        walletName: input.walletName,
      ),
    );

    final collected = await _collectPartialUseCase.execute(
      CollectPartialInput(
        deferredTransferId: input.transactionId,
        settlementId: input.settlementId,
        amount: input.walletAmount + input.clientFee,
      ),
    );

    final confirmed = await _confirmPendingUseCase.execute(
      ConfirmPendingInput(
        pendingTransactionId: input.transactionId,
        claimId: input.claimId,
      ),
    );

    return UseCaseResult(
      events: [...created.events, ...collected.events, ...confirmed.events],
      snapshot: confirmed.snapshot,
    );
  }
}
