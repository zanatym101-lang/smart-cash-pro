import '../../domain/services/accounting_engine.dart';
import '../../domain/services/accounting_event_models.dart';
import '../../domain/services/snapshot_builder.dart';
import '../../infrastructure/adapters/in_memory_event_repository.dart';
import '../../infrastructure/adapters/in_memory_snapshot_repository.dart';
import '../../infrastructure/write_gateway/app_db_bridge_writer.dart';
import '../ports/event_repository.dart';
import '../ports/snapshot_repository.dart';
import '../use_cases/collect_partial_use_case.dart';
import '../use_cases/confirm_pending_use_case.dart';
import '../use_cases/create_claim_use_case.dart';
import '../use_cases/create_deferred_receive_use_case.dart';
import '../use_cases/create_deferred_transfer_use_case.dart';
import '../use_cases/create_receive_use_case.dart';
import '../use_cases/create_transfer_use_case.dart';
import '../use_cases/pay_partial_use_case.dart';
import '../use_cases/settle_claim_use_case.dart';
import '../use_cases/use_case_models.dart';
import 'write_intents.dart';
import '../../domain/services/customer_validation_service.dart';
import '../../ai_sms/customer_matching_service.dart';
import '../../data/app_db.dart';

typedef CleanBaselineEventsProvider = Future<List<AccountingEvent>> Function();

class CleanWriteResult {
  const CleanWriteResult({
    required this.intent,
    this.cleanResult,
    this.bridgeResult,
    this.cleanSkippedReason,
  });

  final WriteIntent intent;
  final UseCaseResult? cleanResult;
  final AppDbBridgeWriteResult? bridgeResult;
  final String? cleanSkippedReason;

  int? get legacyId => bridgeResult?.legacyId;

  List<AccountingEvent> get cleanEvents => cleanResult?.events ?? const [];
}

class CleanWriteGateway {
  CleanWriteGateway({
    required EventRepository eventRepository,
    required SnapshotRepository snapshotRepository,
    AppDbBridgeWriter? bridgeWriter,
    CleanBaselineEventsProvider? baselineEventsProvider,
    bool bridgeOnlyItemSpecificIntents = false,
    EventRepository? shadowEventRepository,
    this.customerValidationService,
    this.existingCustomersProvider,
  }) : _eventRepository = eventRepository,
       _snapshotRepository = snapshotRepository,
       _bridgeWriter = bridgeWriter,
       _baselineEventsProvider = baselineEventsProvider,
       _bridgeOnlyItemSpecificIntents = bridgeOnlyItemSpecificIntents,
       _shadowEventRepository = shadowEventRepository;

  factory CleanWriteGateway.appDbBridge({
    AppDbBridgeWriter? bridgeWriter,
    EventRepository? shadowEventRepository,
  }) {
    final writer = bridgeWriter ?? const AppDbBridgeWriter();
    return CleanWriteGateway(
      eventRepository: InMemoryEventRepository(),
      snapshotRepository: InMemorySnapshotRepository(),
      bridgeWriter: writer,
      bridgeOnlyItemSpecificIntents: true,
      shadowEventRepository: shadowEventRepository,
      customerValidationService: const CustomerValidationService(),
      existingCustomersProvider: () => AppDb.instance.listCustomerCandidates(),
      baselineEventsProvider: () async {
        final snapshot = await writer.currentTreasurySnapshot();
        return _baselineEventsFromTreasury(snapshot);
      },
    );
  }

  final EventRepository _eventRepository;
  final SnapshotRepository _snapshotRepository;
  final AppDbBridgeWriter? _bridgeWriter;
  final CleanBaselineEventsProvider? _baselineEventsProvider;
  final bool _bridgeOnlyItemSpecificIntents;
  final EventRepository? _shadowEventRepository;
  final CustomerValidationService? customerValidationService;
  final Future<List<CustomerMatchCandidate>> Function()? existingCustomersProvider;

  Future<CleanWriteResult> execute(WriteIntent intent) async {
    if (customerValidationService != null && existingCustomersProvider != null) {
      final validationResult = await _validateCustomer(intent);
      if (validationResult != null && validationResult.isError) {
        return CleanWriteResult(
          intent: intent,
          cleanSkippedReason: validationResult.message,
        );
      }
    }

    final unsupportedReason = _cleanUnsupportedReason(intent);
    UseCaseResult? cleanResult;
    if (unsupportedReason == null) {
      await _seedBaselineIfEmpty();
      cleanResult = await _executeClean(intent);
    }

    final bridgeResult = _bridgeWriter == null
        ? null
        : await _bridgeWriter.mirror(intent);
    await _persistShadowEvents(intent, bridgeResult);

    return CleanWriteResult(
      intent: intent,
      cleanResult: cleanResult,
      bridgeResult: bridgeResult,
      cleanSkippedReason: unsupportedReason,
    );
  }

  Future<void> _persistShadowEvents(
    WriteIntent intent,
    AppDbBridgeWriteResult? bridgeResult,
  ) async {
    final repository = _shadowEventRepository;
    if (repository == null || bridgeResult == null) return;
    final events = _semanticEventsForIntent(intent, bridgeResult);
    if (events.isEmpty) return;
    await repository.saveEvents(events);
  }

  Future<void> _seedBaselineIfEmpty() async {
    final provider = _baselineEventsProvider;
    if (provider == null) return;
    final existing = await _eventRepository.loadEvents();
    if (existing.isNotEmpty) return;
    final baseline = await provider();
    if (baseline.isEmpty) return;
    await _eventRepository.saveEvents(baseline);
    await _snapshotRepository.saveSnapshot(buildSnapshot(baseline));
  }

  Future<UseCaseResult> _executeClean(WriteIntent intent) {
    return switch (intent) {
      CreateTransferIntent() =>
        CreateTransferUseCase(
          eventRepository: _eventRepository,
          snapshotRepository: _snapshotRepository,
        ).execute(
          CreateTransferInput(
            transactionId: intent.transactionId,
            settlementId: intent.settlementId,
            claimId: intent.claimId,
            walletAmount: intent.amount,
            clientFee: intent.clientFee,
            networkFee: intent.networkFee,
            walletId: intent.walletId,
          ),
        ),
      CreateDeferredTransferIntent() =>
        CreateDeferredTransferUseCase(
          eventRepository: _eventRepository,
          snapshotRepository: _snapshotRepository,
        ).execute(
          CreateDeferredTransferInput(
            transactionId: intent.transactionId,
            walletAmount: intent.amount,
            clientFee: intent.clientFee,
            networkFee: intent.networkFee,
            walletId: intent.walletId,
          ),
        ),
      CreateReceiveIntent() =>
        CreateReceiveUseCase(
          eventRepository: _eventRepository,
          snapshotRepository: _snapshotRepository,
        ).execute(
          CreateReceiveInput(
            transactionId: intent.transactionId,
            settlementId: intent.settlementId,
            claimId: intent.claimId,
            walletAmount: intent.amount,
            walletId: intent.walletId,
          ),
        ),
      CreateDeferredReceiveIntent() =>
        CreateDeferredReceiveUseCase(
          eventRepository: _eventRepository,
          snapshotRepository: _snapshotRepository,
        ).execute(
          CreateDeferredReceiveInput(
            transactionId: intent.transactionId,
            walletAmount: intent.amount,
            walletId: intent.walletId,
          ),
        ),
      CreateSettlementIntent() =>
        intent.sourceType == SettlementSourceType.deferredTransfer
            ? CollectPartialUseCase(
                eventRepository: _eventRepository,
                snapshotRepository: _snapshotRepository,
              ).execute(
                CollectPartialInput(
                  deferredTransferId: intent.itemId,
                  settlementId: intent.settlementId,
                  amount: intent.amount,
                ),
              )
            : PayPartialUseCase(
                eventRepository: _eventRepository,
                snapshotRepository: _snapshotRepository,
              ).execute(
                PayPartialInput(
                  deferredReceiveId: intent.itemId,
                  settlementId: intent.settlementId,
                  amount: intent.amount,
                ),
              ),
      CreateClaimIntent() =>
        CreateClaimUseCase(
          eventRepository: _eventRepository,
          snapshotRepository: _snapshotRepository,
        ).execute(
          CreateClaimInput(
            claimId: intent.claimId,
            type: intent.type == ClaimDirection.receivable
                ? ClaimType.receivable
                : ClaimType.payable,
            amount: intent.amount,
            sourceDeferredTransferId: intent.sourceTxnId?.toString(),
            applyDrawerEffect: intent.applyDrawerEffect,
          ),
        ),
      SettleClaimIntent() =>
        SettleClaimUseCase(
          eventRepository: _eventRepository,
          snapshotRepository: _snapshotRepository,
        ).execute(
          SettleClaimInput(
            claimId: intent.claimId,
            settlementId: intent.settlementId,
            amount: intent.amount,
          ),
        ),
      ConfirmPendingIntent() =>
        ConfirmPendingUseCase(
          eventRepository: _eventRepository,
          snapshotRepository: _snapshotRepository,
        ).execute(
          ConfirmPendingInput(
            pendingTransactionId: intent.pendingTxnId,
            claimId: intent.claimId,
          ),
        ),
      CancelPendingIntent() => Future.error(
        UnsupportedError('cancel_pending_clean_events_not_migrated_yet'),
      ),
      RollbackTransactionIntent() => Future.error(
        UnsupportedError('rollback_clean_events_not_migrated_yet'),
      ),
      DrawerDepositIntent() ||
      DrawerWithdrawIntent() ||
      WalletFundingIntent() ||
      WalletAdjustmentIntent() ||
      ExpenseIntent() ||
      FawryIntent() ||
      DailyCloseIntent() => Future.error(
        UnsupportedError('treasury_wallet_clean_events_not_migrated_yet'),
      ),
    };
  }

  Future<CustomerValidationResult?> _validateCustomer(WriteIntent intent) async {
    String? party;
    String? note;
    if (intent is CreateTransferIntent) {
      party = intent.party;
      note = intent.note;
    } else if (intent is CreateReceiveIntent) {
      party = intent.party;
      note = intent.note;
    } else if (intent is CreateDeferredTransferIntent) {
      party = intent.party;
      note = intent.note;
    } else if (intent is CreateDeferredReceiveIntent) {
      party = intent.party;
      note = intent.note;
    } else if (intent is CreateClaimIntent) {
      party = intent.party;
      note = intent.note;
    }

    if (party == null || party.trim().isEmpty) return null;

    final existingCustomers = await existingCustomersProvider!();
    return customerValidationService!.validateCustomer(
      name: party,
      note: note,
      existingCustomers: existingCustomers,
    );
  }

  String? _cleanUnsupportedReason(WriteIntent intent) {
    if (_bridgeOnlyItemSpecificIntents &&
        (intent is CreateSettlementIntent ||
            intent is SettleClaimIntent ||
            intent is ConfirmPendingIntent ||
            intent is CancelPendingIntent ||
            intent is RollbackTransactionIntent)) {
      return 'clean_gateway_item_specific_bridge_history_not_loaded_yet';
    }
    return switch (intent) {
      CreateTransferIntent() =>
        intent.transferType == 'type1'
            ? null
            : 'clean_gateway_transfer_type_not_migrated',
      CreateDeferredTransferIntent() =>
        intent.transferType == 'type1'
            ? null
            : 'clean_gateway_transfer_type_not_migrated',
      CreateReceiveIntent() =>
        intent.receiveType == 'cash' && intent.commission == 0
            ? null
            : 'clean_gateway_receive_variant_not_migrated',
      CreateDeferredReceiveIntent() =>
        intent.receiveType == 'cash' && intent.commission == 0
            ? null
            : 'clean_gateway_receive_variant_not_migrated',
      CreateSettlementIntent() => null,
      CreateClaimIntent() => null,
      SettleClaimIntent() => null,
      ConfirmPendingIntent() => null,
      CancelPendingIntent() => 'clean_gateway_cancel_pending_not_migrated_yet',
      RollbackTransactionIntent() => 'clean_gateway_rollback_not_migrated_yet',
      DrawerDepositIntent() ||
      DrawerWithdrawIntent() ||
      WalletFundingIntent() ||
      WalletAdjustmentIntent() ||
      ExpenseIntent() ||
      FawryIntent() ||
      DailyCloseIntent() => 'clean_gateway_treasury_wallet_bridge_only',
    };
  }

  List<AccountingEvent> _semanticEventsForIntent(
    WriteIntent intent,
    AppDbBridgeWriteResult bridgeResult,
  ) {
    final legacyId = bridgeResult.legacyId?.toString();
    final transactionId = legacyId == null ? null : 'legacy-txn-$legacyId';
    return switch (intent) {
      CreateTransferIntent() =>
        transactionId == null
            ? const []
            : [
                TransferCreatedEvent(
                  transactionId: transactionId,
                  walletId: intent.walletId,
                  walletDebitAmount: _transferWalletDebit(intent),
                  customerAmount: _transferCustomerAmount(intent),
                  clientFee: intent.clientFee,
                  networkFee: intent.networkFee,
                  customerName: intent.party,
                ),
                WalletDebited(
                  transactionId: transactionId,
                  amount: _transferWalletDebit(intent),
                ),
                if (intent.clientFee > 0)
                  ClientFeeApplied(
                    transactionId: transactionId,
                    amount: intent.clientFee,
                  ),
                if (intent.networkFee > 0)
                  NetworkFeeApplied(
                    transactionId: transactionId,
                    amount: intent.networkFee,
                  ),
                DrawerAdjusted(
                  transactionId: transactionId,
                  amount: _transferCustomerAmount(intent),
                ),
                PendingConfirmedEvent(
                  transactionId: transactionId,
                  kind: PendingKind.deferredTransfer,
                  remainingAmount: 0,
                ),
              ],
      CreateDeferredTransferIntent() =>
        transactionId == null
            ? const []
            : [
                DeferredTransferEvent(
                  transactionId: transactionId,
                  walletId: intent.walletId,
                  walletDebitAmount: _deferredTransferWalletDebit(intent),
                  customerAmount: _deferredTransferCustomerAmount(intent),
                  clientFee: intent.clientFee,
                  networkFee: intent.networkFee,
                  customerName: intent.party,
                ),
                WalletDebited(
                  transactionId: transactionId,
                  amount: _deferredTransferWalletDebit(intent),
                ),
                if (intent.clientFee > 0)
                  ClientFeeApplied(
                    transactionId: transactionId,
                    amount: intent.clientFee,
                  ),
                if (intent.networkFee > 0)
                  NetworkFeeApplied(
                    transactionId: transactionId,
                    amount: intent.networkFee,
                  ),
              ],
      CreateReceiveIntent() =>
        transactionId == null
            ? const []
            : [
                ReceiveCreatedEvent(
                  transactionId: transactionId,
                  walletId: intent.walletId,
                  walletCreditAmount: intent.amount,
                  payableAmount: _receivePayableAmount(
                    intent.amount,
                    intent.commission,
                    intent.receiveType,
                  ),
                  commission: intent.commission,
                  receiveType: intent.receiveType,
                  customerName: intent.party,
                ),
                WalletCredited(
                  transactionId: transactionId,
                  amount: intent.amount,
                ),
                if (intent.commission > 0)
                  ClientFeeApplied(
                    transactionId: transactionId,
                    amount: intent.commission,
                  ),
                DrawerAdjusted(
                  transactionId: transactionId,
                  amount: -_receiveDrawerAmount(
                    intent.amount,
                    intent.commission,
                    intent.receiveType,
                  ),
                ),
                PendingConfirmedEvent(
                  transactionId: transactionId,
                  kind: PendingKind.deferredReceive,
                  remainingAmount: 0,
                ),
              ],
      CreateDeferredReceiveIntent() =>
        transactionId == null
            ? const []
            : [
                DeferredReceiveEvent(
                  transactionId: transactionId,
                  walletId: intent.walletId,
                  walletCreditAmount: intent.amount,
                  payableAmount: _receivePayableAmount(
                    intent.amount,
                    intent.commission,
                    intent.receiveType,
                  ),
                  commission: intent.commission,
                  receiveType: intent.receiveType,
                  customerName: intent.party,
                ),
                WalletCredited(
                  transactionId: transactionId,
                  amount: intent.amount,
                ),
              ],
      CreateSettlementIntent() => [
        SettlementEvent(
          settlement: SettlementEntry(
            id: intent.settlementId,
            deferredTransferId:
                intent.sourceType == SettlementSourceType.deferredTransfer
                ? intent.itemId
                : null,
            deferredReceiveId:
                intent.sourceType == SettlementSourceType.deferredReceive
                ? intent.itemId
                : null,
            amount: intent.amount,
          ),
          remainingAmount: 0,
          direction: intent.sourceType == SettlementSourceType.deferredTransfer
              ? CashFlowDirection.inflow
              : CashFlowDirection.outflow,
          note: intent.note,
        ),
      ],
      CreateClaimIntent() => [
        ClaimCreatedEvent(
          claimId: legacyId == null ? intent.claimId : 'legacy-claim-$legacyId',
          direction: intent.type == ClaimDirection.receivable
              ? ClaimType.receivable
              : ClaimType.payable,
          customerName: intent.party,
          originalAmount: intent.amount,
          remainingAmount: intent.amount,
          sourceTransactionId: intent.sourceTxnId == null
              ? 'manual'
              : 'legacy-txn-${intent.sourceTxnId}',
        ),
        if (intent.applyDrawerEffect)
          DrawerAdjusted(
            transactionId: legacyId == null
                ? intent.claimId
                : 'legacy-claim-$legacyId',
            amount: intent.type == ClaimDirection.receivable
                ? -intent.amount
                : intent.amount,
          ),
      ],
      SettleClaimIntent() => const [],
      ConfirmPendingIntent() => [
        PendingConfirmedEvent(
          transactionId: intent.pendingTxnId,
          kind: PendingKind.deferredTransfer,
          remainingAmount: 0,
        ),
      ],
      CancelPendingIntent() => [
        PendingCancelledEvent(
          transactionId: intent.pendingTxnId,
          kind: PendingKind.deferredTransfer,
        ),
      ],
      RollbackTransactionIntent() => [
        RollbackEvent(transactionId: intent.transactionId),
      ],
      DrawerDepositIntent() =>
        transactionId == null
            ? const []
            : [
                TreasuryDepositEvent(
                  transactionId: transactionId,
                  amount: intent.amount,
                  note: intent.note,
                ),
              ],
      DrawerWithdrawIntent() =>
        transactionId == null
            ? const []
            : [
                TreasuryWithdrawEvent(
                  transactionId: transactionId,
                  amount: intent.amount,
                  note: intent.note,
                ),
              ],
      WalletFundingIntent() =>
        transactionId == null
            ? const []
            : [
                WalletFundingEvent(
                  transactionId: transactionId,
                  walletId: intent.walletId,
                  amount: intent.amount,
                  note: intent.note,
                ),
              ],
      WalletAdjustmentIntent() => const [],
      ExpenseIntent() =>
        intent.action == ExpenseIntentAction.create &&
                transactionId != null &&
                intent.amount != null &&
                intent.category != null
            ? [
                ExpenseEvent(
                  transactionId: transactionId,
                  amount: intent.amount!,
                  category: intent.category!,
                  note: intent.note,
                ),
              ]
            : const [],
      FawryIntent() =>
        transactionId == null
            ? const []
            : [
                DrawerAdjusted(
                  transactionId: transactionId,
                  amount: intent.collectionMethod == 'cash'
                      ? intent.amount + intent.fee
                      : 0,
                ),
                FawryBalanceAdjusted(
                  transactionId: transactionId,
                  amount: -intent.amount,
                  note: intent.note,
                ),
                if (intent.fee > 0)
                  ClientFeeApplied(
                    transactionId: transactionId,
                    amount: intent.fee,
                  ),
              ],
      DailyCloseIntent() => [
        DailyCloseEvent(
          closeId: legacyId ?? intent.date.toIso8601String(),
          dateKey: _dateKey(intent.date),
          closed: intent.action == DailyCloseAction.close,
        ),
      ],
    };
  }

  double _transferWalletDebit(CreateTransferIntent intent) =>
      intent.transferType == 'type2'
      ? intent.amount - intent.clientFee
      : intent.amount + intent.networkFee;

  double _transferCustomerAmount(CreateTransferIntent intent) =>
      intent.transferType == 'type2'
      ? intent.amount
      : intent.amount + intent.clientFee;

  double _deferredTransferWalletDebit(CreateDeferredTransferIntent intent) =>
      intent.transferType == 'type2'
      ? intent.amount - intent.clientFee
      : intent.amount + intent.networkFee;

  double _deferredTransferCustomerAmount(CreateDeferredTransferIntent intent) =>
      intent.transferType == 'type2'
      ? intent.amount
      : intent.amount + intent.clientFee;

  double _receivePayableAmount(double amount, double commission, String type) {
    if (type == 'deduct') {
      return (amount - commission).clamp(0, 1e18).toDouble();
    }
    if (type == 'electronic') return 0;
    return amount;
  }

  double _receiveDrawerAmount(double amount, double commission, String type) {
    if (type == 'deduct') return amount - commission;
    if (type == 'electronic') return 0;
    return amount;
  }

  String _dateKey(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

  static List<AccountingEvent> _baselineEventsFromTreasury(dynamic snapshot) {
    final events = <AccountingEvent>[
      OpeningBalancesRecorded(
        drawer: snapshot.drawerActualBalance as double,
        wallets: snapshot.walletsActualTotal as double,
      ),
    ];
    final pendingReceivable = snapshot.pendingReceivableOpen as double;
    final pendingPayable = snapshot.pendingPayableOpen as double;
    final claimsReceivable = snapshot.claimsReceivableOpen as double;
    final claimsPayable = snapshot.claimsPayableOpen as double;

    if (pendingReceivable > 0) {
      events.add(
        DeferredTransferCreated(
          transaction: DeferredTransfer(
            id: 'baseline-pending-receivable',
            walletAmount: 0,
            clientFee: pendingReceivable,
            networkFee: 0,
            originalCustomerAmount: pendingReceivable,
            status: DeferredTransferStatus.pending,
          ),
        ),
      );
    }
    if (pendingPayable > 0) {
      events.add(
        DeferredReceiveCreated(
          transaction: DeferredReceive(
            id: 'baseline-pending-payable',
            walletAmount: pendingPayable,
            originalPayableAmount: pendingPayable,
            status: DeferredTransferStatus.pending,
          ),
        ),
      );
    }
    if (claimsReceivable > 0) {
      events.add(
        ClaimOpened(
          claim: ClaimEntry(
            id: 'baseline-claim-receivable',
            type: ClaimType.receivable,
            sourceDeferredTransferId: 'baseline',
            originalAmount: claimsReceivable,
            remainingAmount: claimsReceivable,
            status: ClaimStatus.open,
          ),
        ),
      );
    }
    if (claimsPayable > 0) {
      events.add(
        ClaimOpened(
          claim: ClaimEntry(
            id: 'baseline-claim-payable',
            type: ClaimType.payable,
            sourceDeferredTransferId: 'baseline',
            originalAmount: claimsPayable,
            remainingAmount: claimsPayable,
            status: ClaimStatus.open,
          ),
        ),
      );
    }
    return events;
  }
}
