import 'accounting_engine.dart';

class TransferCreatedEvent extends DeferredTransferCreated {
  TransferCreatedEvent({
    required this.transactionId,
    required this.walletId,
    required this.walletDebitAmount,
    required this.customerAmount,
    required this.clientFee,
    required this.networkFee,
    this.customerName,
    this.posted = true,
  }) : super(
         transaction: DeferredTransfer(
           id: transactionId,
           walletAmount: (customerAmount - clientFee).clamp(0, 1e18).toDouble(),
           clientFee: clientFee,
           networkFee: networkFee,
           originalCustomerAmount: customerAmount,
           status: posted
               ? DeferredTransferStatus.posted
               : DeferredTransferStatus.pending,
         ),
       );

  final String transactionId;
  final int walletId;
  final double walletDebitAmount;
  final double customerAmount;
  final double clientFee;
  final double networkFee;
  final String? customerName;
  final bool posted;
}

class ReceiveCreatedEvent extends DeferredReceiveCreated {
  ReceiveCreatedEvent({
    required this.transactionId,
    required this.walletId,
    required this.walletCreditAmount,
    required this.payableAmount,
    this.commission = 0,
    this.receiveType = 'cash',
    this.customerName,
    this.posted = true,
  }) : super(
         transaction: DeferredReceive(
           id: transactionId,
           walletAmount: walletCreditAmount,
           originalPayableAmount: payableAmount,
           status: posted
               ? DeferredTransferStatus.posted
               : DeferredTransferStatus.pending,
         ),
       );

  final String transactionId;
  final int walletId;
  final double walletCreditAmount;
  final double payableAmount;
  final double commission;
  final String receiveType;
  final String? customerName;
  final bool posted;
}

class DeferredTransferEvent extends TransferCreatedEvent {
  DeferredTransferEvent({
    required super.transactionId,
    required super.walletId,
    required super.walletDebitAmount,
    required super.customerAmount,
    required super.clientFee,
    required super.networkFee,
    super.customerName,
  }) : super(posted: false);
}

class DeferredReceiveEvent extends ReceiveCreatedEvent {
  DeferredReceiveEvent({
    required super.transactionId,
    required super.walletId,
    required super.walletCreditAmount,
    required super.payableAmount,
    super.commission,
    super.receiveType,
    super.customerName,
  }) : super(posted: false);
}

class SettlementEvent extends AccountingEvent {
  const SettlementEvent({
    required this.settlement,
    required this.remainingAmount,
    required this.direction,
    this.note,
  });

  final SettlementEntry settlement;
  final double remainingAmount;
  final CashFlowDirection direction;
  final String? note;
}

class ClaimCreatedEvent extends ClaimOpened {
  ClaimCreatedEvent({
    required this.claimId,
    required this.direction,
    required this.customerName,
    required this.originalAmount,
    required this.remainingAmount,
    this.sourceTransactionId = 'manual',
  }) : super(
         claim: ClaimEntry(
           id: claimId,
           type: direction == ClaimType.receivable
               ? ClaimType.receivable
               : ClaimType.payable,
           sourceDeferredTransferId: sourceTransactionId,
           originalAmount: originalAmount,
           remainingAmount: remainingAmount,
           status: ClaimStatus.open,
         ),
       );

  final String claimId;
  final ClaimType direction;
  final String customerName;
  final double originalAmount;
  final double remainingAmount;
  final String sourceTransactionId;
}

class ClaimSettledEvent extends AccountingEvent {
  const ClaimSettledEvent({
    required this.claimId,
    required this.settledAmount,
    required this.remainingAmount,
    required this.direction,
    this.fullSettlement = false,
  });

  final String claimId;
  final double settledAmount;
  final double remainingAmount;
  final ClaimType direction;
  final bool fullSettlement;
}

class TreasuryDepositEvent extends DrawerAdjusted {
  const TreasuryDepositEvent({
    required super.transactionId,
    required super.amount,
    this.note,
  });

  final String? note;
}

class TreasuryWithdrawEvent extends DrawerAdjusted {
  TreasuryWithdrawEvent({
    required super.transactionId,
    required double amount,
    this.note,
  }) : super(amount: -amount.abs());

  final String? note;
}

class WalletFundingEvent extends WalletCredited {
  const WalletFundingEvent({
    required super.transactionId,
    required this.walletId,
    required super.amount,
    this.note,
  });

  final int walletId;
  final String? note;
}

class FawryBalanceAdjusted extends AccountingEvent {
  const FawryBalanceAdjusted({
    required this.transactionId,
    required this.amount,
    this.note,
  });

  final String transactionId;
  final double amount;
  final String? note;
}

class ExpenseEvent extends DrawerAdjusted {
  ExpenseEvent({
    required super.transactionId,
    required double amount,
    required this.category,
    this.note,
  }) : super(amount: -amount.abs());

  final String category;
  final String? note;
}

class DailyCloseEvent extends AccountingEvent {
  const DailyCloseEvent({
    required this.closeId,
    required this.dateKey,
    required this.closed,
  });

  final String closeId;
  final String dateKey;
  final bool closed;
}

class PendingConfirmedEvent extends PendingConfirmed {
  const PendingConfirmedEvent({
    required super.transactionId,
    required super.kind,
    required super.remainingAmount,
  });
}

class PendingCancelledEvent extends AccountingEvent {
  const PendingCancelledEvent({
    required this.transactionId,
    required this.kind,
    this.walletDelta = 0,
    this.drawerDelta = 0,
  });

  final String transactionId;
  final PendingKind kind;
  final double walletDelta;
  final double drawerDelta;
}

class RollbackEvent extends AccountingEvent {
  const RollbackEvent({
    required this.transactionId,
    this.walletDelta = 0,
    this.drawerDelta = 0,
    this.clientFeeDelta = 0,
    this.networkFeeDelta = 0,
  });

  final String transactionId;
  final double walletDelta;
  final double drawerDelta;
  final double clientFeeDelta;
  final double networkFeeDelta;
}
