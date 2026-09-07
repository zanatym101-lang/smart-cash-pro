import '../data/app_db.dart';
import '../domain/services/accounting_engine.dart';
import '../domain/services/accounting_event_models.dart';
import '../models/claim.dart';
import '../models/daily_close.dart';
import '../models/transaction.dart';

class BridgeEventMetadata {
  const BridgeEventMetadata({
    required this.source,
    required this.migratedAt,
    required this.originalLegacyId,
    required this.originalLegacyTable,
    required this.originalLegacyKind,
  });

  final String source;
  final DateTime migratedAt;
  final String originalLegacyId;
  final String originalLegacyTable;
  final String originalLegacyKind;

  Map<String, Object?> toJson() => {
    'source': source,
    'migratedAt': migratedAt.toIso8601String(),
    'originalLegacyId': originalLegacyId,
    'originalLegacyTable': originalLegacyTable,
    'originalLegacyKind': originalLegacyKind,
  };
}

class BridgedAccountingEvent {
  const BridgedAccountingEvent({
    required this.event,
    required this.metadata,
    required this.sequence,
  });

  final AccountingEvent event;
  final BridgeEventMetadata metadata;
  final int sequence;
}

class LegacyHistoryBridgeResult {
  const LegacyHistoryBridgeResult({
    required this.events,
    required this.migratedAt,
  });

  final List<BridgedAccountingEvent> events;
  final DateTime migratedAt;

  List<AccountingEvent> get cleanEvents =>
      events.map((item) => item.event).toList(growable: false);
}

class LegacyHistoryBridgeService {
  const LegacyHistoryBridgeService();

  Future<LegacyHistoryBridgeResult> bridgeFromAppDb(AppDb db) async {
    final migratedAt = DateTime.now().toUtc();
    final txns = await db.listTxns();
    final claims = await db.listClaims();
    final dailyCloses = await db.listDailyCloses();
    return bridge(
      txns: txns,
      claims: claims,
      dailyCloses: dailyCloses,
      migratedAt: migratedAt,
    );
  }

  LegacyHistoryBridgeResult bridge({
    required List<Txn> txns,
    required List<Claim> claims,
    List<DailyClose> dailyCloses = const [],
    DateTime? migratedAt,
  }) {
    final effectiveMigratedAt = migratedAt ?? DateTime.now().toUtc();
    final items = <_PendingBridgeEvent>[];
    final activeTxns = txns
        .where((txn) => txn.status != 'rolled_back' && txn.status != 'canceled')
        .toList(growable: false);
    final txnById = {for (final txn in activeTxns) txn.id: txn};
    final pendingSettlements = _pendingSettlementsByTxn(activeTxns);
    final claimSettlements = _claimSettlementsByClaim(activeTxns);

    void add({
      required AccountingEvent event,
      required DateTime date,
      required int order,
      required String legacyId,
      required String table,
      required String kind,
    }) {
      items.add(
        _PendingBridgeEvent(
          event: event,
          date: date,
          order: order,
          metadata: BridgeEventMetadata(
            source: 'legacy_appdb',
            migratedAt: effectiveMigratedAt,
            originalLegacyId: legacyId,
            originalLegacyTable: table,
            originalLegacyKind: kind,
          ),
        ),
      );
    }

    add(
      event: const OpeningBalancesRecorded(drawer: 0, wallets: 0),
      date: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      order: 0,
      legacyId: 'synthetic-opening',
      table: 'synthetic',
      kind: 'opening_balances',
    );

    for (final txn in activeTxns) {
      _addTxnEvents(
        txn: txn,
        hasPendingSettlement: pendingSettlements.containsKey(txn.id),
        hasSourceClaim: claims.any((claim) => claim.sourceTxnId == txn.id),
        add: add,
      );
    }

    for (final claim in claims) {
      final sourceTxn = claim.sourceTxnId == null
          ? null
          : txnById[claim.sourceTxnId];
      final settlements = claimSettlements[claim.id] ?? const <Txn>[];
      final originalAmount = _claimOriginalAmount(claim, settlements);
      final claimId = _claimId(claim.id);
      final type = claim.type == 'payable'
          ? ClaimType.payable
          : ClaimType.receivable;

      if (sourceTxn != null &&
          (sourceTxn.kind == 'transfer' || sourceTxn.kind == 'receive') &&
          sourceTxn.status == 'posted') {
        add(
          event: PendingConfirmedEvent(
            transactionId: _txnId(sourceTxn.id),
            kind: sourceTxn.kind == 'receive'
                ? PendingKind.deferredReceive
                : PendingKind.deferredTransfer,
            remainingAmount: originalAmount,
          ),
          date: claim.entryDate,
          order: 25,
          legacyId: sourceTxn.id.toString(),
          table: 'txns',
          kind: '${sourceTxn.kind}_confirm',
        );
      }

      add(
        event: ClaimCreatedEvent(
          claimId: claimId,
          direction: type,
          customerName: claim.party,
          sourceTransactionId: sourceTxn == null
              ? 'manual-claim:$claimId'
              : _txnId(sourceTxn.id),
          originalAmount: originalAmount,
          remainingAmount: originalAmount,
        ),
        date: claim.entryDate,
        order: 30,
        legacyId: claim.id.toString(),
        table: 'claims',
        kind: claim.type,
      );

      final isDirectClaim = sourceTxn == null ||
          sourceTxn.kind == 'claim_open_receivable' ||
          sourceTxn.kind == 'claim_open_payable';
      if (isDirectClaim && originalAmount > 0) {
        final drawerEffect = sourceTxn != null
            ? (type == ClaimType.receivable
                ? -sourceTxn.amount
                : sourceTxn.amount)
            : (type == ClaimType.receivable
                ? -originalAmount
                : originalAmount);
        add(
          event: DrawerAdjusted(
            transactionId: claimId,
            amount: drawerEffect,
          ),
          date: claim.entryDate,
          order: 31,
          legacyId: claim.id.toString(),
          table: 'claims',
          kind: '${claim.type}_drawer_effect',
        );
      }

      _addClaimSettlementEvents(
        claim: claim,
        originalAmount: originalAmount,
        settlements: settlements,
        add: add,
      );
    }

    for (final entry in pendingSettlements.entries) {
      final sourceTxn = txnById[entry.key];
      if (sourceTxn == null || sourceTxn.status != 'posted') continue;
      final hasSourceClaim = claims.any(
        (claim) => claim.sourceTxnId == entry.key,
      );
      if (hasSourceClaim) continue;
      final latestSettlementDate = entry.value
          .map((txn) => txn.entryDate)
          .fold<DateTime>(sourceTxn.entryDate, (latest, date) {
            return date.isAfter(latest) ? date : latest;
          });
      add(
        event: PendingConfirmedEvent(
          transactionId: _txnId(sourceTxn.id),
          kind: sourceTxn.kind == 'receive'
              ? PendingKind.deferredReceive
              : PendingKind.deferredTransfer,
          remainingAmount: 0,
        ),
        date: latestSettlementDate,
        order: 25,
        legacyId: sourceTxn.id.toString(),
        table: 'txns',
        kind: '${sourceTxn.kind}_confirm',
      );
    }

    for (final close in dailyCloses) {
      add(
        event: DailyCloseEvent(
          closeId: 'legacy-close-${close.id}',
          dateKey: close.dateKey,
          closed: true,
        ),
        date: close.closedAt,
        order: 60,
        legacyId: close.id.toString(),
        table: 'daily_closes',
        kind: 'daily_close',
      );
    }

    items.sort((a, b) {
      final date = a.date.compareTo(b.date);
      if (date != 0) return date;
      final order = a.order.compareTo(b.order);
      if (order != 0) return order;
      return a.metadata.originalLegacyId.compareTo(b.metadata.originalLegacyId);
    });

    final bridged = <BridgedAccountingEvent>[];
    for (var i = 0; i < items.length; i++) {
      bridged.add(
        BridgedAccountingEvent(
          event: items[i].event,
          metadata: items[i].metadata,
          sequence: i + 1,
        ),
      );
    }

    return LegacyHistoryBridgeResult(
      events: List.unmodifiable(bridged),
      migratedAt: effectiveMigratedAt,
    );
  }

  void _addTxnEvents({
    required Txn txn,
    required bool hasPendingSettlement,
    required bool hasSourceClaim,
    required _AddBridgeEvent add,
  }) {
    switch (txn.kind) {
      case 'transfer':
        _addTransferEvents(
          txn: txn,
          hasPendingSettlement: hasPendingSettlement,
          hasSourceClaim: hasSourceClaim,
          add: add,
        );
      case 'receive':
        _addReceiveEvents(
          txn: txn,
          hasPendingSettlement: hasPendingSettlement,
          hasSourceClaim: hasSourceClaim,
          add: add,
        );
      case 'claim_collect':
      case 'claim_pay':
        final pendingRef = _extractPendingSettlementRef(txn.note);
        if (pendingRef != null) {
          add(
            event: txn.kind == 'claim_collect'
                ? PartialCollected(
                    settlement: SettlementEntry(
                      id: _settlementId(txn.id),
                      deferredTransferId: _txnId(pendingRef),
                      amount: txn.amount,
                    ),
                    remainingAmount: 0,
                  )
                : PartialPaid(
                    settlement: SettlementEntry(
                      id: _settlementId(txn.id),
                      deferredReceiveId: _txnId(pendingRef),
                      amount: txn.amount,
                    ),
                    remainingAmount: 0,
                  ),
            date: txn.entryDate,
            order: 20,
            legacyId: txn.id.toString(),
            table: 'txns',
            kind: txn.kind,
          );
        }
      case 'external_funding':
        add(
          event: txn.walletToId == null
              ? WalletCredited(
                  transactionId: _txnId(txn.id),
                  amount: txn.amount,
                )
              : WalletFundingEvent(
                  transactionId: _txnId(txn.id),
                  walletId: txn.walletToId!,
                  amount: txn.amount,
                  note: txn.note,
                ),
          date: txn.entryDate,
          order: 10,
          legacyId: txn.id.toString(),
          table: 'txns',
          kind: txn.kind,
        );
      case 'drawer_deposit':
        add(
          event: txn.amount >= 0
              ? TreasuryDepositEvent(
                  transactionId: _txnId(txn.id),
                  amount: txn.amount,
                  note: txn.note,
                )
              : TreasuryWithdrawEvent(
                  transactionId: _txnId(txn.id),
                  amount: txn.amount.abs(),
                  note: txn.note,
                ),
          date: txn.entryDate,
          order: 10,
          legacyId: txn.id.toString(),
          table: 'txns',
          kind: txn.kind,
        );
      case 'pending_settlement_adjust':
        add(
          event: DrawerAdjusted(
            transactionId: _txnId(txn.id),
            amount: txn.amount,
          ),
          date: txn.entryDate,
          order: 10,
          legacyId: txn.id.toString(),
          table: 'txns',
          kind: txn.kind,
        );
      case 'fawry_cash':
        add(
          event: DrawerAdjusted(
            transactionId: _txnId(txn.id),
            amount: txn.amount + txn.clientFee,
          ),
          date: txn.entryDate,
          order: 10,
          legacyId: txn.id.toString(),
          table: 'txns',
          kind: txn.kind,
        );
        add(
          event: FawryBalanceAdjusted(
            transactionId: _txnId(txn.id),
            amount: -txn.amount,
            note: txn.note,
          ),
          date: txn.entryDate,
          order: 11,
          legacyId: txn.id.toString(),
          table: 'txns',
          kind: '${txn.kind}_fawry',
        );
        _addClientFee(txn: txn, add: add);
      case 'fawry_credit':
        add(
          event: FawryBalanceAdjusted(
            transactionId: _txnId(txn.id),
            amount: -txn.amount,
            note: txn.note,
          ),
          date: txn.entryDate,
          order: 10,
          legacyId: txn.id.toString(),
          table: 'txns',
          kind: '${txn.kind}_fawry',
        );
        _addClientFee(txn: txn, add: add);
      case 'expense':
        add(
          event: ExpenseEvent(
            transactionId: _txnId(txn.id),
            amount: txn.amount,
            category: txn.mode,
            note: txn.note,
          ),
          date: txn.entryDate,
          order: 10,
          legacyId: txn.id.toString(),
          table: 'txns',
          kind: txn.kind,
        );
      case 'fawry_fund_drawer':
        add(
          event: TreasuryWithdrawEvent(
            transactionId: _txnId(txn.id),
            amount: txn.amount,
            note: txn.note,
          ),
          date: txn.entryDate,
          order: 10,
          legacyId: txn.id.toString(),
          table: 'txns',
          kind: txn.kind,
        );
        add(
          event: FawryBalanceAdjusted(
            transactionId: _txnId(txn.id),
            amount: txn.amount,
            note: txn.note,
          ),
          date: txn.entryDate,
          order: 11,
          legacyId: txn.id.toString(),
          table: 'txns',
          kind: '${txn.kind}_fawry',
        );
      case 'claim_open_receivable':
      case 'claim_open_payable':
        break;
      default:
        break;
    }
  }

  void _addTransferEvents({
    required Txn txn,
    required bool hasPendingSettlement,
    required bool hasSourceClaim,
    required _AddBridgeEvent add,
  }) {
    final due = _transferDue(txn);
    final wasDeferred =
        txn.status != 'posted' || hasPendingSettlement || hasSourceClaim;
    add(
      event: wasDeferred
          ? DeferredTransferEvent(
              transactionId: _txnId(txn.id),
              walletId: txn.walletFromId ?? 0,
              walletDebitAmount: txn.amount,
              customerAmount: due,
              clientFee: txn.clientFee,
              networkFee: txn.networkFee,
              customerName: txn.party,
            )
          : TransferCreatedEvent(
              transactionId: _txnId(txn.id),
              walletId: txn.walletFromId ?? 0,
              walletDebitAmount: txn.amount,
              customerAmount: due,
              clientFee: txn.clientFee,
              networkFee: txn.networkFee,
              customerName: txn.party,
            ),
      date: txn.entryDate,
      order: 10,
      legacyId: txn.id.toString(),
      table: 'txns',
      kind: txn.kind,
    );
    add(
      event: WalletDebited(transactionId: _txnId(txn.id), amount: txn.amount),
      date: txn.entryDate,
      order: 11,
      legacyId: txn.id.toString(),
      table: 'txns',
      kind: '${txn.kind}_wallet',
    );
    _addClientFee(txn: txn, add: add);
    if (txn.networkFee > 0) {
      add(
        event: NetworkFeeApplied(
          transactionId: _txnId(txn.id),
          amount: txn.networkFee,
        ),
        date: txn.entryDate,
        order: 13,
        legacyId: txn.id.toString(),
        table: 'txns',
        kind: '${txn.kind}_network_fee',
      );
    }
    if (txn.status == 'posted' && !hasPendingSettlement && !hasSourceClaim) {
      add(
        event: DrawerAdjusted(transactionId: _txnId(txn.id), amount: due),
        date: txn.entryDate,
        order: 30,
        legacyId: txn.id.toString(),
        table: 'txns',
        kind: '${txn.kind}_drawer',
      );
      add(
        event: PendingConfirmedEvent(
          transactionId: _txnId(txn.id),
          kind: PendingKind.deferredTransfer,
          remainingAmount: 0,
        ),
        date: txn.entryDate,
        order: 31,
        legacyId: txn.id.toString(),
        table: 'txns',
        kind: '${txn.kind}_confirm',
      );
    }
  }

  void _addReceiveEvents({
    required Txn txn,
    required bool hasPendingSettlement,
    required bool hasSourceClaim,
    required _AddBridgeEvent add,
  }) {
    final due = _receiveDue(txn);
    final wasDeferred =
        txn.status != 'posted' || hasPendingSettlement || hasSourceClaim;
    add(
      event: wasDeferred
          ? DeferredReceiveEvent(
              transactionId: _txnId(txn.id),
              walletId: txn.walletToId ?? 0,
              walletCreditAmount: txn.amount,
              payableAmount: due,
              commission: txn.clientFee,
              receiveType: txn.mode,
              customerName: txn.party,
            )
          : ReceiveCreatedEvent(
              transactionId: _txnId(txn.id),
              walletId: txn.walletToId ?? 0,
              walletCreditAmount: txn.amount,
              payableAmount: due,
              commission: txn.clientFee,
              receiveType: txn.mode,
              customerName: txn.party,
            ),
      date: txn.entryDate,
      order: 10,
      legacyId: txn.id.toString(),
      table: 'txns',
      kind: txn.kind,
    );
    add(
      event: WalletCredited(transactionId: _txnId(txn.id), amount: txn.amount),
      date: txn.entryDate,
      order: 11,
      legacyId: txn.id.toString(),
      table: 'txns',
      kind: '${txn.kind}_wallet',
    );
    if (txn.status == 'posted') {
      _addClientFee(txn: txn, add: add);
    }
    if (txn.status == 'posted' && !hasPendingSettlement && !hasSourceClaim) {
      add(
        event: DrawerAdjusted(
          transactionId: _txnId(txn.id),
          amount: -(txn.amount - txn.clientFee),
        ),
        date: txn.entryDate,
        order: 30,
        legacyId: txn.id.toString(),
        table: 'txns',
        kind: '${txn.kind}_drawer',
      );
      add(
        event: PendingConfirmedEvent(
          transactionId: _txnId(txn.id),
          kind: PendingKind.deferredReceive,
          remainingAmount: 0,
        ),
        date: txn.entryDate,
        order: 31,
        legacyId: txn.id.toString(),
        table: 'txns',
        kind: '${txn.kind}_confirm',
      );
    }
  }

  void _addClientFee({required Txn txn, required _AddBridgeEvent add}) {
    if (txn.clientFee <= 0 || txn.status != 'posted') return;
    add(
      event: ClientFeeApplied(
        transactionId: _txnId(txn.id),
        amount: txn.clientFee,
      ),
      date: txn.entryDate,
      order: 12,
      legacyId: txn.id.toString(),
      table: 'txns',
      kind: '${txn.kind}_client_fee',
    );
  }

  void _addClaimSettlementEvents({
    required Claim claim,
    required double originalAmount,
    required List<Txn> settlements,
    required _AddBridgeEvent add,
  }) {
    var remaining = originalAmount;
    final claimId = _claimId(claim.id);
    final sorted = [...settlements]..sort(_txnOldestFirst);

    for (final settlement in sorted) {
      remaining = (remaining - settlement.amount).clamp(0, 1e18).toDouble();
      final isReceivable = claim.type == 'receivable';
      add(
        event: isReceivable
            ? PartialCollected(
                settlement: SettlementEntry(
                  id: _settlementId(settlement.id),
                  claimId: claimId,
                  amount: settlement.amount,
                ),
                remainingAmount: remaining,
              )
            : PartialPaid(
                settlement: SettlementEntry(
                  id: _settlementId(settlement.id),
                  claimId: claimId,
                  amount: settlement.amount,
                ),
                remainingAmount: remaining,
              ),
        date: settlement.entryDate,
        order: 40,
        legacyId: settlement.id.toString(),
        table: 'txns',
        kind: settlement.kind,
      );
      add(
        event: remaining > 0
            ? ClaimPartiallySettled(
                claimId: claimId,
                settledAmount: settlement.amount,
                remainingAmount: remaining,
              )
            : ClaimFullySettled(
                claimId: claimId,
                settledAmount: settlement.amount,
              ),
        date: settlement.entryDate,
        order: 41,
        legacyId: settlement.id.toString(),
        table: 'txns',
        kind: '${settlement.kind}_claim_status',
      );
      if (remaining <= 0) {
        add(
          event: ClaimClosed(claimId: claimId),
          date: settlement.entryDate,
          order: 42,
          legacyId: settlement.id.toString(),
          table: 'txns',
          kind: '${settlement.kind}_claim_closed',
        );
      }
    }
  }

  static Map<int, List<Txn>> _pendingSettlementsByTxn(List<Txn> txns) {
    final result = <int, List<Txn>>{};
    for (final txn in txns) {
      if (txn.kind != 'claim_collect' && txn.kind != 'claim_pay') continue;
      final ref = _extractPendingSettlementRef(txn.note);
      if (ref == null) continue;
      result.putIfAbsent(ref, () => []).add(txn);
    }
    return result;
  }

  static Map<int, List<Txn>> _claimSettlementsByClaim(List<Txn> txns) {
    final result = <int, List<Txn>>{};
    for (final txn in txns) {
      if (txn.kind != 'claim_collect' && txn.kind != 'claim_pay') continue;
      final ref = _extractClaimIdFromNote(txn.note);
      if (ref == null) continue;
      result.putIfAbsent(ref, () => []).add(txn);
    }
    return result;
  }

  static double _claimOriginalAmount(Claim claim, List<Txn> settlements) {
    return claim.amount +
        settlements.fold<double>(0, (sum, txn) => sum + txn.amount);
  }

  static double _transferDue(Txn txn) {
    if (txn.mode == 'type2_v2' || txn.mode == 'type2') return txn.amount + txn.clientFee;
    final base = txn.amount - txn.networkFee;
    if (txn.mode == 'type1') return base + txn.clientFee;
    return base;
  }

  static double _receiveDue(Txn txn) {
    if (txn.mode == 'deduct') {
      return (txn.amount - txn.clientFee).clamp(0, 1e18).toDouble();
    }
    if (txn.mode == 'electronic') return 0;
    return txn.amount;
  }

  static int? _extractPendingSettlementRef(String? note) {
    if (note == null || note.trim().isEmpty) return null;
    final match = RegExp(r'pending_txn:(\d+)').firstMatch(note);
    if (match == null) return null;
    return int.tryParse(match.group(1) ?? '');
  }

  static int? _extractClaimIdFromNote(String? note) {
    if (note == null || note.trim().isEmpty) return null;
    final match = RegExp(r'claim_id:(\d+)').firstMatch(note);
    if (match == null) return null;
    return int.tryParse(match.group(1) ?? '');
  }

  static int _txnOldestFirst(Txn a, Txn b) {
    final date = a.entryDate.compareTo(b.entryDate);
    if (date != 0) return date;
    return a.id.compareTo(b.id);
  }

  static String _txnId(int id) => 'legacy-txn-$id';
  static String _claimId(int id) => 'legacy-claim-$id';
  static String _settlementId(int id) => 'legacy-settlement-$id';
}

typedef _AddBridgeEvent =
    void Function({
      required AccountingEvent event,
      required DateTime date,
      required int order,
      required String legacyId,
      required String table,
      required String kind,
    });

class _PendingBridgeEvent {
  const _PendingBridgeEvent({
    required this.event,
    required this.date,
    required this.order,
    required this.metadata,
  });

  final AccountingEvent event;
  final DateTime date;
  final int order;
  final BridgeEventMetadata metadata;
}
