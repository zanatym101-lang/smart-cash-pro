import 'parsed_transaction_draft.dart';

class DuplicateCheckResult {
  final bool isDuplicate;
  final String reason;
  final String? matchedReference;
  final ParseConfidence confidence;

  const DuplicateCheckResult({
    required this.isDuplicate,
    required this.reason,
    required this.matchedReference,
    required this.confidence,
  });

  Map<String, Object?> toJson() {
    return {
      'isDuplicate': isDuplicate,
      'reason': reason,
      'matchedReference': matchedReference,
      'confidence': confidence.name,
    };
  }
}
