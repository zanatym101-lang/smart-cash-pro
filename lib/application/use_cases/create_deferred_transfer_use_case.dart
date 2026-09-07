import '../ports/event_repository.dart';
import '../ports/snapshot_repository.dart';
import '../../domain/services/accounting_engine.dart';
import 'use_case_models.dart';
import 'use_case_support.dart';

class CreateDeferredTransferUseCase {
  CreateDeferredTransferUseCase({
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

  Future<UseCaseResult> execute(CreateDeferredTransferInput input) async {
    final result = _support.engine.createDeferredTransfer(
      state: await _support.loadState(),
      transactionId: input.transactionId,
      walletAmount: input.walletAmount,
      clientFee: input.clientFee,
      networkFee: input.networkFee,
    );
    return _support.persist(result.events);
  }
}
