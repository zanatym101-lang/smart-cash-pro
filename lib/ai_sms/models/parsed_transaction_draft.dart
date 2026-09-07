enum ParsedOperationType { transfer, receive, unknown }

enum ParseConfidence { high, medium, low }

enum TransactionMode { instant, deferred }

class ParsedTransactionDraft {
  final ParsedOperationType operationType;
  final double? amount;
  final String sender;
  final DateTime effectiveDate;
  final String? reference;
  final String? provider;
  final String? customerName;
  final int? walletId;
  final String? walletName;
  final String? walletLabel;
  final String? note;
  final ParseConfidence confidence;
  final List<String> warnings;
  final String rawMessage;
  final bool aiSuggested;
  final TransactionMode transactionMode;

  const ParsedTransactionDraft({
    required this.operationType,
    required this.amount,
    required this.sender,
    required this.effectiveDate,
    required this.reference,
    required this.provider,
    this.customerName,
    this.walletId,
    this.walletName,
    this.walletLabel,
    this.note,
    required this.confidence,
    required this.warnings,
    required this.rawMessage,
    this.aiSuggested = false,
    this.transactionMode = TransactionMode.instant,
  });

  ParsedTransactionDraft copyWith({
    ParsedOperationType? operationType,
    double? amount,
    String? sender,
    DateTime? effectiveDate,
    String? reference,
    String? provider,
    String? customerName,
    int? walletId,
    String? walletName,
    String? walletLabel,
    String? note,
    ParseConfidence? confidence,
    List<String>? warnings,
    String? rawMessage,
    bool? aiSuggested,
    TransactionMode? transactionMode,
  }) {
    return ParsedTransactionDraft(
      operationType: operationType ?? this.operationType,
      amount: amount ?? this.amount,
      sender: sender ?? this.sender,
      effectiveDate: effectiveDate ?? this.effectiveDate,
      reference: reference ?? this.reference,
      provider: provider ?? this.provider,
      customerName: customerName ?? this.customerName,
      walletId: walletId ?? this.walletId,
      walletName: walletName ?? this.walletName,
      walletLabel: walletLabel ?? this.walletLabel,
      note: note ?? this.note,
      confidence: confidence ?? this.confidence,
      warnings: warnings ?? this.warnings,
      rawMessage: rawMessage ?? this.rawMessage,
      aiSuggested: aiSuggested ?? this.aiSuggested,
      transactionMode: transactionMode ?? this.transactionMode,
    );
  }

  Map<String, Object?> toJson() {
    return {
      'operationType': operationType.name,
      'amount': amount,
      'sender': sender,
      'effectiveDate': effectiveDate.toIso8601String(),
      'reference': reference,
      'provider': provider,
      'customerName': customerName,
      'walletId': walletId,
      'walletName': walletName,
      'walletLabel': walletLabel,
      'note': note,
      'confidence': confidence.name,
      'warnings': warnings,
      'rawMessage': rawMessage,
      'aiSuggested': aiSuggested,
      'transactionMode': transactionMode.name,
    };
  }
}
