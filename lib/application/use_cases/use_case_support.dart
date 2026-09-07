import '../../application/ports/event_repository.dart';
import '../../application/ports/snapshot_repository.dart';
import '../../domain/services/accounting_engine.dart';
import '../../domain/services/snapshot_builder.dart';
import 'use_case_models.dart';

class UseCaseSupport {
  UseCaseSupport({
    required EventRepository eventRepository,
    required SnapshotRepository snapshotRepository,
    AccountingEngine? engine,
    SnapshotBuilderFn? snapshotBuilder,
  }) : _eventRepository = eventRepository,
       _snapshotRepository = snapshotRepository,
       engine = engine ?? const AccountingEngine(),
       _snapshotBuilder = snapshotBuilder ?? buildSnapshot;

  final EventRepository _eventRepository;
  final SnapshotRepository _snapshotRepository;
  final SnapshotBuilderFn _snapshotBuilder;
  final AccountingEngine engine;

  Future<List<AccountingEvent>> loadHistory() => _eventRepository.loadEvents();

  Future<AccountingEngineState> loadState() async =>
      rebuildStateFromEvents(await loadHistory());

  Future<UseCaseResult> persist(List<AccountingEvent> events) async {
    await _eventRepository.saveEvents(events);
    final history = await _eventRepository.loadEvents();
    final snapshot = _snapshotBuilder(history);
    await _snapshotRepository.saveSnapshot(snapshot);
    return UseCaseResult(events: events, snapshot: snapshot);
  }
}

AccountingEngineState rebuildStateFromEvents(List<AccountingEvent> events) {
  var drawerBalance = 0.0;
  var walletBalance = 0.0;
  final deferredTransfers = <String, DeferredTransfer>{};
  final deferredReceives = <String, DeferredReceive>{};
  final settlements = <SettlementEntry>[];
  final claims = <String, ClaimEntry>{};

  for (final event in events) {
    switch (event) {
      case OpeningBalancesRecorded():
        drawerBalance = event.drawer;
        walletBalance = event.wallets;
      case DeferredTransferCreated():
        deferredTransfers[event.transaction.id] = event.transaction;
      case DeferredReceiveCreated():
        deferredReceives[event.transaction.id] = event.transaction;
      case WalletDebited():
        walletBalance -= event.amount;
      case WalletCredited():
        walletBalance += event.amount;
      case DrawerAdjusted():
        drawerBalance += event.amount;
      case ClientFeeApplied():
      case NetworkFeeApplied():
        break;
      case PartialCollected():
        drawerBalance += event.settlement.amount;
        settlements.add(event.settlement);
      case PartialPaid():
        drawerBalance -= event.settlement.amount;
        settlements.add(event.settlement);
      case PendingConfirmed():
        if (event.kind == PendingKind.deferredTransfer) {
          final existing = deferredTransfers[event.transactionId];
          if (existing != null) {
            deferredTransfers[event.transactionId] = existing.copyWith(
              status: DeferredTransferStatus.posted,
            );
          }
        } else {
          final existing = deferredReceives[event.transactionId];
          if (existing != null) {
            deferredReceives[event.transactionId] = existing.copyWith(
              status: DeferredTransferStatus.posted,
            );
          }
        }
      case ClaimOpened():
        claims[event.claim.id] = event.claim;
      case ClaimPartiallySettled():
        final existing = claims[event.claimId];
        if (existing != null) {
          claims[event.claimId] = existing.copyWith(
            remainingAmount: event.remainingAmount,
            status: ClaimStatus.open,
          );
        }
      case ClaimFullySettled():
        final existing = claims[event.claimId];
        if (existing != null) {
          claims[event.claimId] = existing.copyWith(
            remainingAmount: 0,
            status: ClaimStatus.closed,
          );
        }
      case ClaimClosed():
        final existing = claims[event.claimId];
        if (existing != null) {
          claims[event.claimId] = existing.copyWith(
            remainingAmount: 0,
            status: ClaimStatus.closed,
          );
        }
    }
  }

  return AccountingEngineState(
    drawerBalance: drawerBalance,
    walletBalance: walletBalance,
    deferredTransfers: deferredTransfers.values.toList(growable: false),
    deferredReceives: deferredReceives.values.toList(growable: false),
    settlements: settlements,
    claims: claims.values.toList(growable: false),
  );
}
