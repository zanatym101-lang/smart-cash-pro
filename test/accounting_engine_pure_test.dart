import 'package:flutter_test/flutter_test.dart';
import 'package:king_wallet_accounting/domain/services/accounting_engine.dart';

void main() {
  group('AccountingEngine deferred transfer flow', () {
    const engine = AccountingEngine();
    final initialState = AccountingEngineState(
      drawerBalance: 0,
      walletBalance: 2000,
    );

    test('openClaim emits claim open and explicit drawer adjustment', () {
      final result = engine.openClaim(
        state: initialState,
        claimId: 'claim-open-1',
        type: ClaimType.receivable,
        amount: 200,
      );

      expect(result.events, hasLength(2));
      expect(result.events.first, isA<ClaimOpened>());
      expect(result.events.last, isA<DrawerAdjusted>());

      final claimEvent = result.events.first as ClaimOpened;
      final drawerEvent = result.events.last as DrawerAdjusted;

      expect(claimEvent.claim.remainingAmount, closeTo(200, 0.0001));
      expect(drawerEvent.amount, closeTo(-200, 0.0001));
      expect(result.newState.drawerBalance, closeTo(-200, 0.0001));
      expect(result.newState.walletBalance, closeTo(2000, 0.0001));
    });

    test('createDeferredTransfer emits event, preserves original amount, and does not touch drawer', () {
      final result = engine.createDeferredTransfer(
        state: initialState,
        transactionId: 'tx-1',
        walletAmount: 900,
        clientFee: 5,
      );

      final event = result.events.first as DeferredTransferCreated;
      final walletEvent = result.events[1] as WalletDebited;
      final feeEvent = result.events[2] as ClientFeeApplied;

      expect(event.transaction.originalCustomerAmount, closeTo(905, 0.0001));
      expect(event.transaction.status, DeferredTransferStatus.pending);
      expect(result.events, hasLength(3));
      expect(walletEvent.amount, closeTo(900, 0.0001));
      expect(feeEvent.amount, closeTo(5, 0.0001));
      expect(result.newState.drawerBalance, closeTo(0, 0.0001));
      expect(result.newState.walletBalance, closeTo(1100, 0.0001));
      expect(result.newState.deferredTransfers, hasLength(1));
      expect(result.newState.settlements, isEmpty);
      expect(initialState.drawerBalance, closeTo(0, 0.0001));
      expect(initialState.walletBalance, closeTo(2000, 0.0001));
      expect(
        engine.remainingAmountFor(
          state: result.newState,
          deferredTransferId: 'tx-1',
        ),
        closeTo(905, 0.0001),
      );
    });

    test('createDeferredTransfer emits separated fee events with no implicit wallet math', () {
      final result = engine.createDeferredTransfer(
        state: initialState,
        transactionId: 'tx-2',
        walletAmount: 900,
        clientFee: 5,
        networkFee: 2,
      );

      expect(result.events.whereType<WalletDebited>(), hasLength(1));
      expect(result.events.whereType<ClientFeeApplied>(), hasLength(1));
      expect(result.events.whereType<NetworkFeeApplied>(), hasLength(1));
      expect(
        result.events.whereType<WalletDebited>().single.amount,
        closeTo(902, 0.0001),
      );
      expect(
        result.events.whereType<ClientFeeApplied>().single.amount,
        closeTo(5, 0.0001),
      );
      expect(
        result.events.whereType<NetworkFeeApplied>().single.amount,
        closeTo(2, 0.0001),
      );
      expect(result.newState.walletBalance, closeTo(1098, 0.0001));
      expect(
        result.newState.deferredTransfers.single.originalCustomerAmount,
        closeTo(905, 0.0001),
      );
    });

    test('collectPartial emits event, increases drawer only, and keeps original transaction untouched', () {
      final created = engine.createDeferredTransfer(
        state: initialState,
        transactionId: 'tx-1',
        walletAmount: 900,
        clientFee: 5,
      );

      final collected = engine.collectPartial(
        state: created.newState,
        deferredTransferId: 'tx-1',
        settlementId: 'settlement-1',
        amount: 500,
      );

      final event = collected.events.single as PartialCollected;

      expect(
        created.newState.deferredTransfers.single.originalCustomerAmount,
        closeTo(905, 0.0001),
      );
      expect(collected.newState.drawerBalance, closeTo(500, 0.0001));
      expect(collected.newState.walletBalance, closeTo(1100, 0.0001));
      expect(
        collected.newState.deferredTransfers.single.originalCustomerAmount,
        closeTo(905, 0.0001),
      );
      expect(collected.newState.settlements, hasLength(1));
      expect(collected.newState.settlements.single.amount, closeTo(500, 0.0001));
      expect(event.settlement.amount, closeTo(500, 0.0001));
      expect(event.remainingAmount, closeTo(405, 0.0001));
      expect(
        engine.remainingAmountFor(
          state: collected.newState,
          deferredTransferId: 'tx-1',
        ),
        closeTo(405, 0.0001),
      );
    });

    test('confirmPending emits confirm + claim events, creates only remaining claim, and no duplicate cash effect', () {
      final created = engine.createDeferredTransfer(
        state: initialState,
        transactionId: 'tx-1',
        walletAmount: 900,
        clientFee: 5,
      );
      final collected = engine.collectPartial(
        state: created.newState,
        deferredTransferId: 'tx-1',
        settlementId: 'settlement-1',
        amount: 500,
      );

      final confirmed = engine.confirmPending(
        state: collected.newState,
        deferredTransferId: 'tx-1',
        claimId: 'claim-1',
      );

      final confirmEvent = confirmed.events.first as PendingConfirmed;
      final claimEvent = confirmed.events.last as ClaimOpened;

      expect(confirmed.events, hasLength(2));
      expect(confirmEvent.transactionId, 'tx-1');
      expect(confirmEvent.kind, PendingKind.deferredTransfer);
      expect(confirmEvent.remainingAmount, closeTo(405, 0.0001));
      expect(claimEvent.claim.remainingAmount, closeTo(405, 0.0001));
      expect(confirmed.newState.drawerBalance, closeTo(500, 0.0001));
      expect(confirmed.newState.walletBalance, closeTo(1100, 0.0001));
      expect(confirmed.newState.settlements, hasLength(1));
      expect(confirmed.newState.settlements.single.amount, closeTo(500, 0.0001));
      expect(confirmed.newState.claims, hasLength(1));
      expect(confirmed.newState.claims.single.remainingAmount, closeTo(405, 0.0001));
      expect(
        confirmed.newState.deferredTransfers.single.originalCustomerAmount,
        closeTo(905, 0.0001),
      );
      expect(
        confirmed.newState.deferredTransfers.single.status,
        DeferredTransferStatus.posted,
      );
    });

    test('confirmPending is idempotent once transaction is already posted', () {
      final created = engine.createDeferredTransfer(
        state: initialState,
        transactionId: 'tx-1',
        walletAmount: 900,
        clientFee: 5,
      );
      final collected = engine.collectPartial(
        state: created.newState,
        deferredTransferId: 'tx-1',
        settlementId: 'settlement-1',
        amount: 500,
      );
      final firstConfirm = engine.confirmPending(
        state: collected.newState,
        deferredTransferId: 'tx-1',
        claimId: 'claim-1',
      );

      final secondConfirm = engine.confirmPending(
        state: firstConfirm.newState,
        deferredTransferId: 'tx-1',
        claimId: 'claim-1-duplicate',
      );

      expect(secondConfirm.events, isEmpty);
      expect(secondConfirm.newState.drawerBalance, closeTo(500, 0.0001));
      expect(secondConfirm.newState.walletBalance, closeTo(1100, 0.0001));
      expect(secondConfirm.newState.claims, hasLength(1));
      expect(secondConfirm.newState.claims.single.id, equals('claim-1'));
      expect(
        secondConfirm.newState.deferredTransfers.single.status,
        DeferredTransferStatus.posted,
      );
    });

    test('claim settlement emits partial then full lifecycle events with correct directions', () {
      final created = engine.createDeferredTransfer(
        state: initialState,
        transactionId: 'tx-1',
        walletAmount: 900,
        clientFee: 5,
      );
      final collected = engine.collectPartial(
        state: created.newState,
        deferredTransferId: 'tx-1',
        settlementId: 'settlement-1',
        amount: 500,
      );
      final confirmed = engine.confirmPending(
        state: collected.newState,
        deferredTransferId: 'tx-1',
        claimId: 'claim-1',
      );

      final partialClaimSettlement = engine.settleClaim(
        state: confirmed.newState,
        claimId: 'claim-1',
        settlementId: 'claim-settlement-1',
        amount: 400,
      );

      expect(partialClaimSettlement.events, hasLength(2));
      final partialCashEvent =
          partialClaimSettlement.events.first as PartialCollected;
      final partialClaimEvent =
          partialClaimSettlement.events.last as ClaimPartiallySettled;
      expect(partialCashEvent.direction, CashFlowDirection.inflow);
      expect(partialCashEvent.settlement.claimId, 'claim-1');
      expect(partialClaimEvent.remainingAmount, closeTo(5, 0.0001));
      expect(
        partialClaimSettlement.newState.claims.single.remainingAmount,
        closeTo(5, 0.0001),
      );
      expect(
        partialClaimSettlement.newState.claims.single.status,
        ClaimStatus.open,
      );

      final fullClaimSettlement = engine.settleClaim(
        state: partialClaimSettlement.newState,
        claimId: 'claim-1',
        settlementId: 'claim-settlement-2',
        amount: 5,
      );

      expect(fullClaimSettlement.events, hasLength(3));
      final fullCashEvent = fullClaimSettlement.events.first as PartialCollected;
      final fullClaimEvent =
          fullClaimSettlement.events[1] as ClaimFullySettled;
      expect(fullCashEvent.direction, CashFlowDirection.inflow);
      expect(fullClaimEvent.claimId, 'claim-1');
      expect(
        fullClaimSettlement.newState.claims.single.remainingAmount,
        closeTo(0, 0.0001),
      );
      expect(
        fullClaimSettlement.newState.claims.single.status,
        ClaimStatus.closed,
      );
      expect(fullClaimSettlement.newState.drawerBalance, closeTo(905, 0.0001));
      expect(fullClaimSettlement.newState.walletBalance, closeTo(1100, 0.0001));
    });

    test('createDeferredReceive + payPartial + confirmPending mirrors payable side correctly', () {
      final payableInitialState = AccountingEngineState(
        drawerBalance: 1000,
        walletBalance: 0,
      );

      final created = engine.createDeferredReceive(
        state: payableInitialState,
        transactionId: 'rx-1',
        walletAmount: 1000,
      );

      expect(created.events, hasLength(2));
      expect(created.events.first, isA<DeferredReceiveCreated>());
      expect(created.events.last, isA<WalletCredited>());
      expect(created.newState.drawerBalance, closeTo(1000, 0.0001));
      expect(created.newState.walletBalance, closeTo(1000, 0.0001));
      expect(created.newState.deferredReceives, hasLength(1));
      expect(
        engine.remainingPayableAmountFor(
          state: created.newState,
          deferredReceiveId: 'rx-1',
        ),
        closeTo(1000, 0.0001),
      );

      final paid = engine.payPartial(
        state: created.newState,
        deferredReceiveId: 'rx-1',
        settlementId: 'pay-1',
        amount: 400,
      );

      final payEvent = paid.events.single as PartialPaid;
      expect(payEvent.direction, CashFlowDirection.outflow);
      expect(paid.newState.drawerBalance, closeTo(600, 0.0001));
      expect(paid.newState.walletBalance, closeTo(1000, 0.0001));
      expect(
        engine.remainingPayableAmountFor(
          state: paid.newState,
          deferredReceiveId: 'rx-1',
        ),
        closeTo(600, 0.0001),
      );

      final confirmed = engine.confirmPending(
        state: paid.newState,
        deferredTransferId: 'rx-1',
        claimId: 'claim-payable-1',
      );

      final confirmEvent = confirmed.events.first as PendingConfirmed;
      final claimEvent = confirmed.events.last as ClaimOpened;
      expect(confirmEvent.kind, PendingKind.deferredReceive);
      expect(confirmEvent.remainingAmount, closeTo(600, 0.0001));
      expect(claimEvent.claim.type, ClaimType.payable);
      expect(claimEvent.claim.remainingAmount, closeTo(600, 0.0001));
      expect(confirmed.newState.drawerBalance, closeTo(600, 0.0001));
      expect(confirmed.newState.walletBalance, closeTo(1000, 0.0001));
      expect(confirmed.newState.deferredReceives.single.status, DeferredTransferStatus.posted);
      expect(confirmed.newState.claims.single.type, ClaimType.payable);
      expect(confirmed.newState.claims.single.remainingAmount, closeTo(600, 0.0001));
    });
  });
}
