import '../ports/event_repository.dart';
import '../ports/snapshot_repository.dart';
import '../../domain/services/accounting_engine.dart';
import 'use_case_models.dart';
import 'use_case_support.dart';

class ConfirmPendingUseCase {
  ConfirmPendingUseCase({
    required EventRepository eventRepository,
    required SnapshotRepository snapshotRepository,
    AccountingEngine? engine,
    SnapshotBuilderFn? snapshotBuilder,
  }) : _support = UseCaseSupport(
         eventRepository: eventRepository,
         snapshotRepository: snapshotRepository,
         engine: engine,
         snapshotBuilder: snapshotBuilder,
       );

  final UseCaseSupport _support;

  Future<UseCaseResult> execute(ConfirmPendingInput input) async {
    final result = _support.engine.confirmPending(
      state: await _support.loadState(),
      deferredTransferId: input.pendingTransactionId,
      claimId: input.claimId,
    );
    return _support.persist(result.events);
  }
}
