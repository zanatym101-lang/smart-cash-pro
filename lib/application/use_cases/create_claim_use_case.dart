import '../ports/event_repository.dart';
import '../ports/snapshot_repository.dart';
import '../../domain/services/accounting_engine.dart';
import 'use_case_models.dart';
import 'use_case_support.dart';

class CreateClaimUseCase {
  CreateClaimUseCase({
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

  Future<UseCaseResult> execute(CreateClaimInput input) async {
    final result = _support.engine.openClaim(
      state: await _support.loadState(),
      claimId: input.claimId,
      type: input.type,
      amount: input.amount,
      sourceDeferredTransferId: input.sourceDeferredTransferId,
      applyDrawerEffect: input.applyDrawerEffect,
    );
    return _support.persist(result.events);
  }
}
