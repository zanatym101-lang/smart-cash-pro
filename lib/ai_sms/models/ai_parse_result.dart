import 'parsed_transaction_draft.dart';

class AiParseResult {
  const AiParseResult({
    required this.suggestion,
    required this.confidence,
    required this.explanation,
    required this.extractedFields,
  });

  final ParsedTransactionDraft suggestion;
  final ParseConfidence confidence;
  final String explanation;
  final Map<String, Object?> extractedFields;

  Map<String, Object?> toJson() {
    return {
      'suggestion': suggestion.toJson(),
      'confidence': confidence.name,
      'explanation': explanation,
      'extractedFields': extractedFields,
    };
  }
}
