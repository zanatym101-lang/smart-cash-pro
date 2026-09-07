enum WriteIntentKind {
  createTransfer,
  createReceive,
  createDeferredTransfer,
  createDeferredReceive,
  createClaim,
  createSettlement,
  createClaimSettlement,
  confirmPending,
  cancelPending,
  rollbackTransaction,
  drawerDeposit,
  drawerWithdraw,
  walletFunding,
  walletAdjustment,
  expense,
  fawry,
  dailyClose,
}

enum SettlementSourceType { deferredTransfer, deferredReceive }

enum ClaimDirection { receivable, payable }

enum RollbackTransactionType { posted, pendingSettlement, claimSettlement }

enum WalletAdjustmentType {
  createWallet,
  updateWallet,
  resetDailyUsage,
  resetMonthlyUsage,
  resetAllDailyUsage,
  resetAllMonthlyUsage,
}

enum ExpenseIntentAction { create, update, delete }

enum DailyCloseAction { close, reopen }

sealed class WriteIntent {
  const WriteIntent();

  WriteIntentKind get kind;
}

class CreateTransferIntent extends WriteIntent {
  const CreateTransferIntent({
    required this.transactionId,
    required this.settlementId,
    required this.claimId,
    required this.walletId,
    required this.amount,
    required this.clientFee,
    required this.networkFee,
    this.transferType = 'type1',
    this.note,
    this.party,
  });

  final String transactionId;
  final String settlementId;
  final String claimId;
  final int walletId;
  final double amount;
  final double clientFee;
  final double networkFee;
  final String transferType;
  final String? note;
  final String? party;

  @override
  WriteIntentKind get kind => WriteIntentKind.createTransfer;
}

class CreateReceiveIntent extends WriteIntent {
  const CreateReceiveIntent({
    required this.transactionId,
    required this.settlementId,
    required this.claimId,
    required this.walletId,
    required this.amount,
    this.commission = 0,
    this.receiveType = 'cash',
    this.note,
    this.party,
  });

  final String transactionId;
  final String settlementId;
  final String claimId;
  final int walletId;
  final double amount;
  final double commission;
  final String receiveType;
  final String? note;
  final String? party;

  @override
  WriteIntentKind get kind => WriteIntentKind.createReceive;
}

class CreateDeferredTransferIntent extends WriteIntent {
  const CreateDeferredTransferIntent({
    required this.transactionId,
    required this.walletId,
    required this.amount,
    required this.clientFee,
    required this.networkFee,
    this.transferType = 'type1',
    this.note,
    this.party,
  });

  final String transactionId;
  final int walletId;
  final double amount;
  final double clientFee;
  final double networkFee;
  final String transferType;
  final String? note;
  final String? party;

  @override
  WriteIntentKind get kind => WriteIntentKind.createDeferredTransfer;
}

class CreateDeferredReceiveIntent extends WriteIntent {
  const CreateDeferredReceiveIntent({
    required this.transactionId,
    required this.walletId,
    required this.amount,
    this.commission = 0,
    this.receiveType = 'cash',
    this.note,
    this.party,
  });

  final String transactionId;
  final int walletId;
  final double amount;
  final double commission;
  final String receiveType;
  final String? note;
  final String? party;

  @override
  WriteIntentKind get kind => WriteIntentKind.createDeferredReceive;
}

class CreateSettlementIntent extends WriteIntent {
  const CreateSettlementIntent({
    required this.itemId,
    required this.settlementId,
    required this.sourceType,
    required this.amount,
    this.fullSettlement = false,
    this.note,
  });

  final String itemId;
  final String settlementId;
  final SettlementSourceType sourceType;
  final double amount;
  final bool fullSettlement;
  final String? note;

  @override
  WriteIntentKind get kind => WriteIntentKind.createSettlement;
}

class CreateClaimIntent extends WriteIntent {
  const CreateClaimIntent({
    required this.claimId,
    required this.type,
    required this.party,
    required this.amount,
    this.note,
    this.phone,
    this.sourceTxnId,
    this.applyDrawerEffect = true,
  });

  final String claimId;
  final ClaimDirection type;
  final String party;
  final double amount;
  final String? note;
  final String? phone;
  final int? sourceTxnId;
  final bool applyDrawerEffect;

  @override
  WriteIntentKind get kind => WriteIntentKind.createClaim;
}

class SettleClaimIntent extends WriteIntent {
  const SettleClaimIntent({
    required this.claimId,
    required this.settlementId,
    required this.amount,
    this.fullSettlement = false,
    this.note,
  });

  final String claimId;
  final String settlementId;
  final double amount;
  final bool fullSettlement;
  final String? note;

  @override
  WriteIntentKind get kind => WriteIntentKind.createClaimSettlement;
}

class CreateClaimSettlementIntent extends SettleClaimIntent {
  const CreateClaimSettlementIntent({
    required super.claimId,
    required super.settlementId,
    required super.amount,
    super.fullSettlement,
    super.note,
  });
}

class ConfirmPendingIntent extends WriteIntent {
  const ConfirmPendingIntent({
    required this.pendingTxnId,
    required this.claimId,
  });

  final String pendingTxnId;
  final String claimId;

  @override
  WriteIntentKind get kind => WriteIntentKind.confirmPending;
}

class CancelPendingIntent extends WriteIntent {
  const CancelPendingIntent({required this.pendingTxnId});

  final String pendingTxnId;

  @override
  WriteIntentKind get kind => WriteIntentKind.cancelPending;
}

class RollbackTransactionIntent extends WriteIntent {
  const RollbackTransactionIntent({
    required this.transactionId,
    this.rollbackType = RollbackTransactionType.posted,
  });

  final String transactionId;
  final RollbackTransactionType rollbackType;

  @override
  WriteIntentKind get kind => WriteIntentKind.rollbackTransaction;
}

class DrawerDepositIntent extends WriteIntent {
  const DrawerDepositIntent({required this.amount, this.note});

  final double amount;
  final String? note;

  @override
  WriteIntentKind get kind => WriteIntentKind.drawerDeposit;
}

class DrawerWithdrawIntent extends WriteIntent {
  const DrawerWithdrawIntent({required this.amount, this.note});

  final double amount;
  final String? note;

  @override
  WriteIntentKind get kind => WriteIntentKind.drawerWithdraw;
}

class WalletFundingIntent extends WriteIntent {
  const WalletFundingIntent({
    required this.walletId,
    required this.amount,
    this.note,
  });

  final int walletId;
  final double amount;
  final String? note;

  @override
  WriteIntentKind get kind => WriteIntentKind.walletFunding;
}

class WalletAdjustmentIntent extends WriteIntent {
  const WalletAdjustmentIntent({
    required this.adjustmentType,
    this.walletId,
    this.name,
    this.phone,
    this.openingBalance = 0,
    this.dailyLimit = 60000,
    this.monthlyLimit = 200000,
    this.lowBalanceThreshold = 0,
    this.allowNegative = false,
  });

  final WalletAdjustmentType adjustmentType;
  final int? walletId;
  final String? name;
  final String? phone;
  final double openingBalance;
  final double dailyLimit;
  final double monthlyLimit;
  final double lowBalanceThreshold;
  final bool allowNegative;

  @override
  WriteIntentKind get kind => WriteIntentKind.walletAdjustment;
}

class ExpenseIntent extends WriteIntent {
  const ExpenseIntent({
    required this.action,
    this.txnId,
    this.amount,
    this.category,
    this.note,
    this.party,
    this.isPending = false,
  });

  final ExpenseIntentAction action;
  final int? txnId;
  final double? amount;
  final String? category;
  final String? note;
  final String? party;
  final bool isPending;

  @override
  WriteIntentKind get kind => WriteIntentKind.expense;
}

class FawryIntent extends WriteIntent {
  const FawryIntent({
    required this.serviceName,
    required this.amount,
    required this.fee,
    required this.collectionMethod,
    this.reference,
    this.party,
    this.note,
    this.isPending = false,
  });

  final String serviceName;
  final String? reference;
  final double amount;
  final double fee;
  final String collectionMethod;
  final String? party;
  final String? note;
  final bool isPending;

  @override
  WriteIntentKind get kind => WriteIntentKind.fawry;
}

class DailyCloseIntent extends WriteIntent {
  const DailyCloseIntent({required this.action, required this.date});

  final DailyCloseAction action;
  final DateTime date;

  @override
  WriteIntentKind get kind => WriteIntentKind.dailyClose;
}
