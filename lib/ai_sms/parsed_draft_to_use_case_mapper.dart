import '../application/use_cases/use_case_models.dart';
import 'models/parsed_transaction_draft.dart';

enum SmsExecutionMode { immediate, pending }

enum SmsUseCaseKind { transfer, receive, deferredTransfer, deferredReceive }

class ParsedDraftUseCasePlan {
  const ParsedDraftUseCasePlan({
    required this.kind,
    required this.mode,
    required this.transactionId,
    this.settlementId,
    this.claimId,
    this.transferInput,
    this.receiveInput,
    this.deferredTransferInput,
    this.deferredReceiveInput,
  });

  final SmsUseCaseKind kind;
  final SmsExecutionMode mode;
  final String transactionId;
  final String? settlementId;
  final String? claimId;
  final CreateTransferInput? transferInput;
  final CreateReceiveInput? receiveInput;
  final CreateDeferredTransferInput? deferredTransferInput;
  final CreateDeferredReceiveInput? deferredReceiveInput;

  String get useCaseName {
    switch (kind) {
      case SmsUseCaseKind.transfer:
        return 'CreateTransferUseCase';
      case SmsUseCaseKind.receive:
        return 'CreateReceiveUseCase';
      case SmsUseCaseKind.deferredTransfer:
        return 'CreateDeferredTransferUseCase';
      case SmsUseCaseKind.deferredReceive:
        return 'CreateDeferredReceiveUseCase';
    }
  }
}

class ParsedDraftToUseCaseMapper {
  ParsedDraftToUseCaseMapper({String Function()? idGenerator})
    : _idGenerator = idGenerator ?? _defaultIdGenerator;

  final String Function() _idGenerator;

  ParsedDraftUseCasePlan map({
    required ParsedTransactionDraft draft,
    SmsExecutionMode mode = SmsExecutionMode.immediate,
  }) {
    final effectiveMode = draft.transactionMode == TransactionMode.deferred
        ? SmsExecutionMode.pending
        : mode;
    final amount = draft.amount;
    if (amount == null || amount <= 0) {
      throw ArgumentError.value(
        amount,
        'draft.amount',
        'Amount must be a positive number.',
      );
    }
    if (draft.operationType == ParsedOperationType.unknown) {
      throw ArgumentError('Operation type must be explicit.');
    }
    if (effectiveMode == SmsExecutionMode.pending &&
        (draft.customerName == null || draft.customerName!.trim().isEmpty)) {
      throw ArgumentError('Customer must be selected for pending drafts.');
    }

    final transactionId = _buildId('sms-tx', draft);
    final settlementId = '$transactionId-settlement-${_idGenerator()}';
    final claimId = '$transactionId-claim-${_idGenerator()}';

    if (draft.operationType == ParsedOperationType.transfer) {
      if (effectiveMode == SmsExecutionMode.pending) {
        return ParsedDraftUseCasePlan(
          kind: SmsUseCaseKind.deferredTransfer,
          mode: effectiveMode,
          transactionId: transactionId,
          claimId: claimId,
          deferredTransferInput: CreateDeferredTransferInput(
            transactionId: transactionId,
            walletAmount: amount,
            clientFee: 0,
            networkFee: 0,
            walletId: draft.walletId,
            walletName: draft.walletName,
          ),
        );
      }
      return ParsedDraftUseCasePlan(
        kind: SmsUseCaseKind.transfer,
        mode: effectiveMode,
        transactionId: transactionId,
        settlementId: settlementId,
        claimId: claimId,
        transferInput: CreateTransferInput(
          transactionId: transactionId,
          settlementId: settlementId,
          claimId: claimId,
          walletAmount: amount,
          clientFee: 0,
          networkFee: 0,
          walletId: draft.walletId,
          walletName: draft.walletName,
        ),
      );
    }

    if (effectiveMode == SmsExecutionMode.pending) {
      return ParsedDraftUseCasePlan(
        kind: SmsUseCaseKind.deferredReceive,
        mode: effectiveMode,
        transactionId: transactionId,
        claimId: claimId,
        deferredReceiveInput: CreateDeferredReceiveInput(
          transactionId: transactionId,
          walletAmount: amount,
          walletId: draft.walletId,
          walletName: draft.walletName,
        ),
      );
    }

    return ParsedDraftUseCasePlan(
      kind: SmsUseCaseKind.receive,
      mode: effectiveMode,
      transactionId: transactionId,
      settlementId: settlementId,
      claimId: claimId,
      receiveInput: CreateReceiveInput(
        transactionId: transactionId,
        settlementId: settlementId,
        claimId: claimId,
        walletAmount: amount,
        walletId: draft.walletId,
        walletName: draft.walletName,
      ),
    );
  }

  String _buildId(String prefix, ParsedTransactionDraft draft) {
    final reference = draft.reference
        ?.replaceAll(RegExp(r'[^A-Za-z0-9]+'), '-')
        .replaceAll(RegExp(r'-+'), '-')
        .trim();
    final token = (reference != null && reference.isNotEmpty)
        ? reference.toLowerCase()
        : _idGenerator();
    return '$prefix-$token';
  }

  static String _defaultIdGenerator() =>
      DateTime.now().microsecondsSinceEpoch.toString();
}
