import '../../domain/services/accounting_engine.dart';
import '../../domain/services/snapshot_builder.dart';

class UseCaseResult {
  const UseCaseResult({required this.events, required this.snapshot});

  final List<AccountingEvent> events;
  final AccountingSnapshot snapshot;
}

typedef SnapshotBuilderFn =
    AccountingSnapshot Function(List<AccountingEvent> events);

class CreateTransferInput {
  const CreateTransferInput({
    required this.transactionId,
    required this.settlementId,
    required this.claimId,
    required this.walletAmount,
    required this.clientFee,
    this.networkFee = 0,
    this.walletId,
    this.walletName,
  });

  final String transactionId;
  final String settlementId;
  final String claimId;
  final double walletAmount;
  final double clientFee;
  final double networkFee;
  final int? walletId;
  final String? walletName;
}

class CreateReceiveInput {
  const CreateReceiveInput({
    required this.transactionId,
    required this.settlementId,
    required this.claimId,
    required this.walletAmount,
    this.walletId,
    this.walletName,
  });

  final String transactionId;
  final String settlementId;
  final String claimId;
  final double walletAmount;
  final int? walletId;
  final String? walletName;
}

class CreateDeferredTransferInput {
  const CreateDeferredTransferInput({
    required this.transactionId,
    required this.walletAmount,
    required this.clientFee,
    this.networkFee = 0,
    this.walletId,
    this.walletName,
  });

  final String transactionId;
  final double walletAmount;
  final double clientFee;
  final double networkFee;
  final int? walletId;
  final String? walletName;
}

class CreateDeferredReceiveInput {
  const CreateDeferredReceiveInput({
    required this.transactionId,
    required this.walletAmount,
    this.walletId,
    this.walletName,
  });

  final String transactionId;
  final double walletAmount;
  final int? walletId;
  final String? walletName;
}

class CollectPartialInput {
  const CollectPartialInput({
    required this.deferredTransferId,
    required this.settlementId,
    required this.amount,
  });

  final String deferredTransferId;
  final String settlementId;
  final double amount;
}

class PayPartialInput {
  const PayPartialInput({
    required this.deferredReceiveId,
    required this.settlementId,
    required this.amount,
  });

  final String deferredReceiveId;
  final String settlementId;
  final double amount;
}

class ConfirmPendingInput {
  const ConfirmPendingInput({
    required this.pendingTransactionId,
    required this.claimId,
  });

  final String pendingTransactionId;
  final String claimId;
}

class SettleClaimInput {
  const SettleClaimInput({
    required this.claimId,
    required this.settlementId,
    required this.amount,
  });

  final String claimId;
  final String settlementId;
  final double amount;
}

class CreateClaimInput {
  const CreateClaimInput({
    required this.claimId,
    required this.type,
    required this.amount,
    this.sourceDeferredTransferId,
    this.applyDrawerEffect = true,
  });

  final String claimId;
  final ClaimType type;
  final double amount;
  final String? sourceDeferredTransferId;
  final bool applyDrawerEffect;
}
