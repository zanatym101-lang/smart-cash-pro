import 'accounting_engine.dart';
import 'accounting_event_models.dart';

class AccountingSnapshot {
  const AccountingSnapshot({
    required this.drawer,
    required this.wallets,
    this.fawry = 0,
    required this.pendingReceivable,
    required this.pendingPayable,
    required this.openClaimsReceivable,
    required this.openClaimsPayable,
    required this.profitFromClientFees,
    required this.networkFeesTotal,
    required this.availableLiquidityNow,
    required this.realCapitalApproved,
  });

  final double drawer;
  final double wallets;
  final double fawry;
  final double pendingReceivable;
  final double pendingPayable;
  final double openClaimsReceivable;
  final double openClaimsPayable;
  final double profitFromClientFees;
  final double networkFeesTotal;
  final double availableLiquidityNow;
  final double realCapitalApproved;
}

AccountingSnapshot buildSnapshot(List<AccountingEvent> events) {
  var drawer = 0.0;
  var wallets = 0.0;
  var fawry = 0.0;

  final deferredReceivableRemaining = <String, double>{};
  final deferredPayableRemaining = <String, double>{};
  final openClaims = <String, ClaimEntry>{};
  var profitFromClientFees = 0.0;
  var networkFeesTotal = 0.0;

  for (final event in events) {
    switch (event) {
      case OpeningBalancesRecorded():
        drawer = event.drawer;
        wallets = event.wallets;
      case DeferredTransferCreated():
        deferredReceivableRemaining[event.transaction.id] =
            event.transaction.originalCustomerAmount;
      case DeferredReceiveCreated():
        deferredPayableRemaining[event.transaction.id] =
            event.transaction.originalPayableAmount;
      case WalletDebited():
        wallets -= event.amount;
      case WalletCredited():
        wallets += event.amount;
      case FawryBalanceAdjusted():
        fawry += event.amount;
      case DrawerAdjusted():
        drawer += event.amount;
      case ClientFeeApplied():
        profitFromClientFees += event.amount;
      case NetworkFeeApplied():
        networkFeesTotal += event.amount;
      case SettlementEvent():
        if (event.direction == CashFlowDirection.inflow) {
          drawer += event.settlement.amount;
          final deferredId = event.settlement.deferredTransferId;
          if (deferredId != null) {
            final current = deferredReceivableRemaining[deferredId] ?? 0;
            deferredReceivableRemaining[deferredId] = _clampToZero(
              current - event.settlement.amount,
            );
          }
        } else {
          drawer -= event.settlement.amount;
          final deferredId = event.settlement.deferredReceiveId;
          if (deferredId != null) {
            final current = deferredPayableRemaining[deferredId] ?? 0;
            deferredPayableRemaining[deferredId] = _clampToZero(
              current - event.settlement.amount,
            );
          }
        }
      case PartialCollected():
        drawer += event.settlement.amount;
        final deferredId = event.settlement.deferredTransferId;
        if (deferredId != null) {
          final current = deferredReceivableRemaining[deferredId] ?? 0;
          deferredReceivableRemaining[deferredId] = _clampToZero(
            current - event.settlement.amount,
          );
        }
      case PartialPaid():
        drawer -= event.settlement.amount;
        final deferredId = event.settlement.deferredReceiveId;
        if (deferredId != null) {
          final current = deferredPayableRemaining[deferredId] ?? 0;
          deferredPayableRemaining[deferredId] = _clampToZero(
            current - event.settlement.amount,
          );
        }
      case PendingConfirmed():
        if (event.kind == PendingKind.deferredTransfer &&
            deferredReceivableRemaining.containsKey(event.transactionId)) {
          deferredReceivableRemaining[event.transactionId] = 0;
        }
        if (event.kind == PendingKind.deferredReceive &&
            deferredPayableRemaining.containsKey(event.transactionId)) {
          deferredPayableRemaining[event.transactionId] = 0;
        }
      case ClaimOpened():
        openClaims[event.claim.id] = event.claim;
      case ClaimPartiallySettled():
        final existing = openClaims[event.claimId];
        if (existing != null) {
          openClaims[event.claimId] = existing.copyWith(
            remainingAmount: event.remainingAmount,
            status: ClaimStatus.open,
          );
        }
      case ClaimSettledEvent():
        drawer += event.direction == ClaimType.receivable
            ? event.settledAmount
            : -event.settledAmount;
        final existing = openClaims[event.claimId];
        if (existing != null) {
          openClaims[event.claimId] = existing.copyWith(
            remainingAmount: event.remainingAmount,
            status: event.fullSettlement || event.remainingAmount <= 0
                ? ClaimStatus.closed
                : ClaimStatus.open,
          );
        }
      case ClaimFullySettled():
        final existing = openClaims[event.claimId];
        if (existing != null) {
          openClaims[event.claimId] = existing.copyWith(
            remainingAmount: 0,
            status: ClaimStatus.closed,
          );
        }
      case ClaimClosed():
        final existing = openClaims[event.claimId];
        if (existing != null) {
          openClaims[event.claimId] = existing.copyWith(
            remainingAmount: 0,
            status: ClaimStatus.closed,
          );
        }
      case PendingCancelledEvent():
        drawer += event.drawerDelta;
        wallets += event.walletDelta;
        if (event.kind == PendingKind.deferredTransfer &&
            deferredReceivableRemaining.containsKey(event.transactionId)) {
          deferredReceivableRemaining[event.transactionId] = 0;
        }
        if (event.kind == PendingKind.deferredReceive &&
            deferredPayableRemaining.containsKey(event.transactionId)) {
          deferredPayableRemaining[event.transactionId] = 0;
        }
      case RollbackEvent():
        drawer += event.drawerDelta;
        wallets += event.walletDelta;
        profitFromClientFees += event.clientFeeDelta;
        networkFeesTotal += event.networkFeeDelta;
      case DailyCloseEvent():
        break;
    }
  }

  final pendingReceivable = deferredReceivableRemaining.values.fold<double>(
    0,
    (sum, value) => sum + value,
  );
  final pendingPayable = deferredPayableRemaining.values.fold<double>(
    0,
    (sum, value) => sum + value,
  );

  var openClaimsReceivable = 0.0;
  var openClaimsPayable = 0.0;

  for (final claim in openClaims.values) {
    if (claim.status != ClaimStatus.open) continue;
    if (claim.type == ClaimType.receivable) {
      openClaimsReceivable += claim.remainingAmount;
    } else {
      openClaimsPayable += claim.remainingAmount;
    }
  }

  final availableLiquidityNow = drawer + wallets + fawry;
  final realCapitalApproved =
      availableLiquidityNow +
      (openClaimsReceivable + pendingReceivable) -
      (openClaimsPayable + pendingPayable);

  return AccountingSnapshot(
    drawer: drawer,
    wallets: wallets,
    fawry: fawry,
    pendingReceivable: pendingReceivable,
    pendingPayable: pendingPayable,
    openClaimsReceivable: openClaimsReceivable,
    openClaimsPayable: openClaimsPayable,
    profitFromClientFees: profitFromClientFees,
    networkFeesTotal: networkFeesTotal,
    availableLiquidityNow: availableLiquidityNow,
    realCapitalApproved: realCapitalApproved,
  );
}

double _clampToZero(double value) => value < 0 ? 0 : value;
