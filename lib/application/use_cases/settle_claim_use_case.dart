import '../ports/event_repository.dart';
import '../ports/snapshot_repository.dart';
import '../../domain/services/accounting_engine.dart';
import 'use_case_models.dart';
import 'use_case_support.dart';

class SettleClaimUseCase {
  SettleClaimUseCase({
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

  Future<UseCaseResult> execute(SettleClaimInput input) async {
    final result = _support.engine.settleClaim(
      state: await _support.loadState(),
      claimId: input.claimId,
      settlementId: input.settlementId,
      amount: input.amount,
    );
    return _support.persist(result.events);
  }
}
