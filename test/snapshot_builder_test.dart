import 'package:flutter_test/flutter_test.dart';
import 'package:king_wallet_accounting/domain/services/accounting_engine.dart';
import 'package:king_wallet_accounting/domain/services/snapshot_builder.dart';

void main() {
  group('buildSnapshot from events', () {
    const engine = AccountingEngine();

    test('deferred transfer + partial collection + confirm builds correct final snapshot', () {
      final opening = <AccountingEvent>[
        const OpeningBalancesRecorded(drawer: 0, wallets: 2000),
      ];
      final initialState = AccountingEngineState(
        drawerBalance: 0,
        walletBalance: 2000,
      );

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

      final snapshot = buildSnapshot([
        ...opening,
        ...created.events,
        ...collected.events,
        ...confirmed.events,
      ]);

      expect(snapshot.drawer, closeTo(500, 0.0001));
      expect(snapshot.wallets, closeTo(1100, 0.0001));
      expect(snapshot.pendingReceivable, closeTo(0, 0.0001));
      expect(snapshot.pendingPayable, closeTo(0, 0.0001));
      expect(snapshot.openClaimsReceivable, closeTo(405, 0.0001));
      expect(snapshot.openClaimsPayable, closeTo(0, 0.0001));
      expect(snapshot.profitFromClientFees, closeTo(5, 0.0001));
      expect(snapshot.networkFeesTotal, closeTo(0, 0.0001));
      expect(snapshot.availableLiquidityNow, closeTo(1600, 0.0001));
      expect(snapshot.realCapitalApproved, closeTo(2005, 0.0001));
    });

    test('snapshot keeps pending out of cash and does not double count on confirm', () {
      final opening = <AccountingEvent>[
        const OpeningBalancesRecorded(drawer: 0, wallets: 2000),
      ];
      final initialState = AccountingEngineState(
        drawerBalance: 0,
        walletBalance: 2000,
      );

      final created = engine.createDeferredTransfer(
        state: initialState,
        transactionId: 'tx-1',
        walletAmount: 900,
        clientFee: 5,
      );
      final afterCreate = buildSnapshot([
        ...opening,
        ...created.events,
      ]);

      final collected = engine.collectPartial(
        state: created.newState,
        deferredTransferId: 'tx-1',
        settlementId: 'settlement-1',
        amount: 500,
      );
      final afterCollect = buildSnapshot([
        ...opening,
        ...created.events,
        ...collected.events,
      ]);

      final confirmed = engine.confirmPending(
        state: collected.newState,
        deferredTransferId: 'tx-1',
        claimId: 'claim-1',
      );
      final afterConfirm = buildSnapshot([
        ...opening,
        ...created.events,
        ...collected.events,
        ...confirmed.events,
      ]);

      expect(afterCreate.drawer, closeTo(0, 0.0001));
      expect(afterCreate.wallets, closeTo(1100, 0.0001));
      expect(afterCreate.pendingReceivable, closeTo(905, 0.0001));
      expect(afterCreate.profitFromClientFees, closeTo(5, 0.0001));
      expect(afterCreate.availableLiquidityNow, closeTo(1100, 0.0001));
      expect(afterCreate.realCapitalApproved, closeTo(2005, 0.0001));

      expect(afterCollect.drawer, closeTo(500, 0.0001));
      expect(afterCollect.wallets, closeTo(1100, 0.0001));
      expect(afterCollect.pendingReceivable, closeTo(405, 0.0001));
      expect(afterCollect.openClaimsReceivable, closeTo(0, 0.0001));
      expect(afterCollect.availableLiquidityNow, closeTo(1600, 0.0001));
      expect(afterCollect.realCapitalApproved, closeTo(2005, 0.0001));

      expect(afterConfirm.drawer, closeTo(500, 0.0001));
      expect(afterConfirm.wallets, closeTo(1100, 0.0001));
      expect(afterConfirm.pendingReceivable, closeTo(0, 0.0001));
      expect(afterConfirm.openClaimsReceivable, closeTo(405, 0.0001));
      expect(afterConfirm.availableLiquidityNow, closeTo(1600, 0.0001));
      expect(afterConfirm.realCapitalApproved, closeTo(2005, 0.0001));
    });

    test('snapshot wallet balance is derived only from wallet events, not implicitly from deferred creation', () {
      final snapshot = buildSnapshot([
        const OpeningBalancesRecorded(drawer: 0, wallets: 2000),
        DeferredTransferCreated(
          transaction: const DeferredTransfer(
            id: 'tx-1',
            walletAmount: 900,
            clientFee: 5,
            networkFee: 0,
            originalCustomerAmount: 905,
            status: DeferredTransferStatus.pending,
          ),
        ),
        const ClientFeeApplied(transactionId: 'tx-1', amount: 5),
      ]);

      expect(snapshot.wallets, closeTo(2000, 0.0001));
      expect(snapshot.pendingReceivable, closeTo(905, 0.0001));
      expect(snapshot.profitFromClientFees, closeTo(5, 0.0001));
      expect(snapshot.availableLiquidityNow, closeTo(2000, 0.0001));
    });

    test('snapshot applies network fee only through explicit wallet and fee events', () {
      final snapshot = buildSnapshot([
        const OpeningBalancesRecorded(drawer: 0, wallets: 2000),
        DeferredTransferCreated(
          transaction: const DeferredTransfer(
            id: 'tx-2',
            walletAmount: 900,
            clientFee: 5,
            networkFee: 2,
            originalCustomerAmount: 905,
            status: DeferredTransferStatus.pending,
          ),
        ),
        const WalletDebited(transactionId: 'tx-2', amount: 902),
        const ClientFeeApplied(transactionId: 'tx-2', amount: 5),
        const NetworkFeeApplied(transactionId: 'tx-2', amount: 2),
      ]);

      expect(snapshot.wallets, closeTo(1098, 0.0001));
      expect(snapshot.pendingReceivable, closeTo(905, 0.0001));
      expect(snapshot.profitFromClientFees, closeTo(5, 0.0001));
      expect(snapshot.networkFeesTotal, closeTo(2, 0.0001));
      expect(snapshot.availableLiquidityNow, closeTo(1098, 0.0001));
      expect(snapshot.realCapitalApproved, closeTo(2003, 0.0001));
    });

    test('snapshot tracks claim partial and full settlement lifecycle from events', () {
      final opening = <AccountingEvent>[
        const OpeningBalancesRecorded(drawer: 0, wallets: 2000),
      ];
      final initialState = AccountingEngineState(
        drawerBalance: 0,
        walletBalance: 2000,
      );

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
      final afterPartialClaim = buildSnapshot([
        ...opening,
        ...created.events,
        ...collected.events,
        ...confirmed.events,
        ...partialClaimSettlement.events,
      ]);

      expect(afterPartialClaim.drawer, closeTo(900, 0.0001));
      expect(afterPartialClaim.wallets, closeTo(1100, 0.0001));
      expect(afterPartialClaim.pendingReceivable, closeTo(0, 0.0001));
      expect(afterPartialClaim.openClaimsReceivable, closeTo(5, 0.0001));
      expect(afterPartialClaim.availableLiquidityNow, closeTo(2000, 0.0001));
      expect(afterPartialClaim.realCapitalApproved, closeTo(2005, 0.0001));

      final fullClaimSettlement = engine.settleClaim(
        state: partialClaimSettlement.newState,
        claimId: 'claim-1',
        settlementId: 'claim-settlement-2',
        amount: 5,
      );
      final afterFullClaim = buildSnapshot([
        ...opening,
        ...created.events,
        ...collected.events,
        ...confirmed.events,
        ...partialClaimSettlement.events,
        ...fullClaimSettlement.events,
      ]);

      expect(afterFullClaim.drawer, closeTo(905, 0.0001));
      expect(afterFullClaim.wallets, closeTo(1100, 0.0001));
      expect(afterFullClaim.openClaimsReceivable, closeTo(0, 0.0001));
      expect(afterFullClaim.availableLiquidityNow, closeTo(2005, 0.0001));
      expect(afterFullClaim.realCapitalApproved, closeTo(2005, 0.0001));
    });

    test('payable side snapshot mirrors receivable behavior after partial pay and confirm', () {
      final opening = <AccountingEvent>[
        const OpeningBalancesRecorded(drawer: 1000, wallets: 0),
      ];
      final initialState = AccountingEngineState(
        drawerBalance: 1000,
        walletBalance: 0,
      );

      final created = engine.createDeferredReceive(
        state: initialState,
        transactionId: 'rx-1',
        walletAmount: 1000,
      );
      final afterCreate = buildSnapshot([
        ...opening,
        ...created.events,
      ]);

      final paid = engine.payPartial(
        state: created.newState,
        deferredReceiveId: 'rx-1',
        settlementId: 'pay-1',
        amount: 400,
      );
      final afterPay = buildSnapshot([
        ...opening,
        ...created.events,
        ...paid.events,
      ]);

      final confirmed = engine.confirmPending(
        state: paid.newState,
        deferredTransferId: 'rx-1',
        claimId: 'claim-payable-1',
      );
      final afterConfirm = buildSnapshot([
        ...opening,
        ...created.events,
        ...paid.events,
        ...confirmed.events,
      ]);

      expect(afterCreate.drawer, closeTo(1000, 0.0001));
      expect(afterCreate.wallets, closeTo(1000, 0.0001));
      expect(afterCreate.pendingPayable, closeTo(1000, 0.0001));
      expect(afterCreate.openClaimsPayable, closeTo(0, 0.0001));
      expect(afterCreate.availableLiquidityNow, closeTo(2000, 0.0001));
      expect(afterCreate.realCapitalApproved, closeTo(1000, 0.0001));

      expect(afterPay.drawer, closeTo(600, 0.0001));
      expect(afterPay.wallets, closeTo(1000, 0.0001));
      expect(afterPay.pendingPayable, closeTo(600, 0.0001));
      expect(afterPay.openClaimsPayable, closeTo(0, 0.0001));
      expect(afterPay.availableLiquidityNow, closeTo(1600, 0.0001));
      expect(afterPay.realCapitalApproved, closeTo(1000, 0.0001));

      expect(afterConfirm.drawer, closeTo(600, 0.0001));
      expect(afterConfirm.wallets, closeTo(1000, 0.0001));
      expect(afterConfirm.pendingPayable, closeTo(0, 0.0001));
      expect(afterConfirm.openClaimsPayable, closeTo(600, 0.0001));
      expect(afterConfirm.availableLiquidityNow, closeTo(1600, 0.0001));
      expect(afterConfirm.realCapitalApproved, closeTo(1000, 0.0001));
    });
  });
}
