import 'accounting_engine.dart';
import 'accounting_event_models.dart';
import 'snapshot_builder.dart' as aggregate;

class TreasurySnapshot {
  const TreasurySnapshot({
    required this.drawer,
    required this.wallets,
    required this.fawry,
    required this.availableLiquidityNow,
    required this.realCapitalApproved,
  });

  final double drawer;
  final double wallets;
  final double fawry;
  final double availableLiquidityNow;
  final double realCapitalApproved;
}

class WalletSnapshot {
  const WalletSnapshot({required this.total, required this.balancesByWalletId});

  final double total;
  final Map<int, double> balancesByWalletId;
}

class CustomerSnapshot {
  const CustomerSnapshot({
    required this.totalForUs,
    required this.totalAgainstUs,
    required this.netBalance,
    required this.balancesByCustomer,
  });

  final double totalForUs;
  final double totalAgainstUs;
  final double netBalance;
  final Map<String, double> balancesByCustomer;
}

class ClaimsSnapshot {
  const ClaimsSnapshot({
    required this.receivableOpen,
    required this.payableOpen,
  });

  final double receivableOpen;
  final double payableOpen;
}

class ProfitSnapshot {
  const ProfitSnapshot({required this.clientFees, required this.networkFees});

  final double clientFees;
  final double networkFees;
}

class AccountingReplaySnapshot {
  const AccountingReplaySnapshot({
    required this.accounting,
    required this.treasury,
    required this.wallets,
    required this.customers,
    required this.claims,
    required this.profit,
  });

  final aggregate.AccountingSnapshot accounting;
  final TreasurySnapshot treasury;
  final WalletSnapshot wallets;
  final CustomerSnapshot customers;
  final ClaimsSnapshot claims;
  final ProfitSnapshot profit;
}

class AccountingReplayEngine {
  const AccountingReplayEngine();

  AccountingReplaySnapshot replay(Iterable<AccountingEvent> orderedEvents) {
    final events = orderedEvents.toList(growable: false);
    final accounting = aggregate.buildSnapshot(events);
    final walletBalances = <int, double>{};
    final txWallet = <String, int>{};
    final txCustomer = <String, String>{};
    final claimCustomer = <String, String>{};
    final customerBalances = <String, double>{};

    void addCustomer(String? customer, double delta) {
      final name = customer?.trim();
      if (name == null || name.isEmpty || delta == 0) return;
      customerBalances[name] = (customerBalances[name] ?? 0) + delta;
      if (customerBalances[name]!.abs() < 0.000001) {
        customerBalances[name] = 0;
      }
    }

    void addWalletByTxn(String transactionId, double delta) {
      final walletId = txWallet[transactionId];
      if (walletId == null) return;
      walletBalances[walletId] = (walletBalances[walletId] ?? 0) + delta;
    }

    for (final event in events) {
      switch (event) {
        case TransferCreatedEvent():
          txWallet[event.transactionId] = event.walletId;
          if (event.customerName != null) {
            txCustomer[event.transactionId] = event.customerName!;
            addCustomer(event.customerName, event.customerAmount);
          }
        case ReceiveCreatedEvent():
          txWallet[event.transactionId] = event.walletId;
          if (event.customerName != null) {
            txCustomer[event.transactionId] = event.customerName!;
            addCustomer(event.customerName, -event.payableAmount);
          }
        case WalletDebited():
          addWalletByTxn(event.transactionId, -event.amount);
        case WalletCredited():
          if (event case WalletFundingEvent()) {
            walletBalances[event.walletId] =
                (walletBalances[event.walletId] ?? 0) + event.amount;
          } else {
            addWalletByTxn(event.transactionId, event.amount);
          }
        case PartialCollected():
          final customer = _customerForSettlement(
            event.settlement,
            txCustomer,
            claimCustomer,
          );
          addCustomer(customer, -event.settlement.amount);
        case PartialPaid():
          final customer = _customerForSettlement(
            event.settlement,
            txCustomer,
            claimCustomer,
          );
          addCustomer(customer, event.settlement.amount);
        case SettlementEvent():
          final customer = _customerForSettlement(
            event.settlement,
            txCustomer,
            claimCustomer,
          );
          addCustomer(
            customer,
            event.direction == CashFlowDirection.inflow
                ? -event.settlement.amount
                : event.settlement.amount,
          );
        case ClaimCreatedEvent():
          claimCustomer[event.claimId] = event.customerName;
          if (event.sourceTransactionId.startsWith('manual')) {
            addCustomer(
              event.customerName,
              event.direction == ClaimType.receivable
                  ? event.remainingAmount
                  : -event.remainingAmount,
            );
          }
        case ClaimSettledEvent():
          final customer = claimCustomer[event.claimId];
          addCustomer(
            customer,
            event.direction == ClaimType.receivable
                ? -event.settledAmount
                : event.settledAmount,
          );
        case PendingCancelledEvent():
          addWalletByTxn(event.transactionId, event.walletDelta);
          final customer = txCustomer[event.transactionId];
          addCustomer(customer, _cancelCustomerDelta(event, events));
        case RollbackEvent():
          addWalletByTxn(event.transactionId, event.walletDelta);
        default:
          break;
      }
    }

    final totalForUs = customerBalances.values
        .where((value) => value > 0)
        .fold<double>(0, (sum, value) => sum + value);
    final totalAgainstUs = customerBalances.values
        .where((value) => value < 0)
        .fold<double>(0, (sum, value) => sum + value.abs());

    return AccountingReplaySnapshot(
      accounting: accounting,
      treasury: TreasurySnapshot(
        drawer: accounting.drawer,
        wallets: accounting.wallets,
        fawry: accounting.fawry,
        availableLiquidityNow: accounting.availableLiquidityNow,
        realCapitalApproved: accounting.realCapitalApproved,
      ),
      wallets: WalletSnapshot(
        total: accounting.wallets,
        balancesByWalletId: Map.unmodifiable(walletBalances),
      ),
      customers: CustomerSnapshot(
        totalForUs: totalForUs,
        totalAgainstUs: totalAgainstUs,
        netBalance: totalForUs - totalAgainstUs,
        balancesByCustomer: Map.unmodifiable(customerBalances),
      ),
      claims: ClaimsSnapshot(
        receivableOpen: accounting.openClaimsReceivable,
        payableOpen: accounting.openClaimsPayable,
      ),
      profit: ProfitSnapshot(
        clientFees: accounting.profitFromClientFees,
        networkFees: accounting.networkFeesTotal,
      ),
    );
  }

  String? _customerForSettlement(
    SettlementEntry settlement,
    Map<String, String> txCustomer,
    Map<String, String> claimCustomer,
  ) {
    final deferredTransferId = settlement.deferredTransferId;
    if (deferredTransferId != null) return txCustomer[deferredTransferId];
    final deferredReceiveId = settlement.deferredReceiveId;
    if (deferredReceiveId != null) return txCustomer[deferredReceiveId];
    final claimId = settlement.claimId;
    if (claimId != null) return claimCustomer[claimId];
    return null;
  }

  double _cancelCustomerDelta(
    PendingCancelledEvent cancel,
    List<AccountingEvent> events,
  ) {
    for (final event in events.reversed) {
      if (event is TransferCreatedEvent &&
          event.transactionId == cancel.transactionId) {
        return -event.customerAmount;
      }
      if (event is ReceiveCreatedEvent &&
          event.transactionId == cancel.transactionId) {
        return event.payableAmount;
      }
    }
    return 0;
  }
}
