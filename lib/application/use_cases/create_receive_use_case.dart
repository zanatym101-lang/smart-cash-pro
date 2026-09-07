import '../ports/event_repository.dart';
import '../ports/snapshot_repository.dart';
import 'confirm_pending_use_case.dart';
import 'create_deferred_receive_use_case.dart';
import 'pay_partial_use_case.dart';
import 'use_case_models.dart';

class CreateReceiveUseCase {
  CreateReceiveUseCase({
    required EventRepository eventRepository,
    required SnapshotRepository snapshotRepository,
  }) : _createDeferredReceiveUseCase = CreateDeferredReceiveUseCase(
         eventRepository: eventRepository,
         snapshotRepository: snapshotRepository,
       ),
       _payPartialUseCase = PayPartialUseCase(
         eventRepository: eventRepository,
         snapshotRepository: snapshotRepository,
       ),
       _confirmPendingUseCase = ConfirmPendingUseCase(
         eventRepository: eventRepository,
         snapshotRepository: snapshotRepository,
       );

  final CreateDeferredReceiveUseCase _createDeferredReceiveUseCase;
  final PayPartialUseCase _payPartialUseCase;
  final ConfirmPendingUseCase _confirmPendingUseCase;

  Future<UseCaseResult> execute(CreateReceiveInput input) async {
    final created = await _createDeferredReceiveUseCase.execute(
      CreateDeferredReceiveInput(
        transactionId: input.transactionId,
        walletAmount: input.walletAmount,
        walletId: input.walletId,
        walletName: input.walletName,
      ),
    );

    final paid = await _payPartialUseCase.execute(
      PayPartialInput(
        deferredReceiveId: input.transactionId,
        settlementId: input.settlementId,
        amount: input.walletAmount,
      ),
    );

    final confirmed = await _confirmPendingUseCase.execute(
      ConfirmPendingInput(
        pendingTransactionId: input.transactionId,
        claimId: input.claimId,
      ),
    );

    return UseCaseResult(
      events: [...created.events, ...paid.events, ...confirmed.events],
      snapshot: confirmed.snapshot,
    );
  }
}
