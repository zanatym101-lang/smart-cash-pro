import '../ports/event_repository.dart';
import '../ports/snapshot_repository.dart';
import '../../domain/services/accounting_engine.dart';
import 'use_case_models.dart';
import 'use_case_support.dart';

class CreateDeferredReceiveUseCase {
  CreateDeferredReceiveUseCase({
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

  Future<UseCaseResult> execute(CreateDeferredReceiveInput input) async {
    final result = _support.engine.createDeferredReceive(
      state: await _support.loadState(),
      transactionId: input.transactionId,
      walletAmount: input.walletAmount,
    );
    return _support.persist(result.events);
  }
}
