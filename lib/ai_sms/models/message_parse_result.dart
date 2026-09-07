import 'ai_parse_result.dart';
import 'parsed_transaction_draft.dart';

class MessageParseResult {
  final ParsedTransactionDraft draft;
  final String? matchedRuleId;
  final List<String> reasons;
  final bool requiresManualReview;
  final AiParseResult? aiParseResult;

  const MessageParseResult({
    required this.draft,
    required this.matchedRuleId,
    required this.reasons,
    required this.requiresManualReview,
    this.aiParseResult,
  });

  Map<String, Object?> toJson() {
    return {
      'draft': draft.toJson(),
      'matchedRuleId': matchedRuleId,
      'reasons': reasons,
      'requiresManualReview': requiresManualReview,
      'aiParseResult': aiParseResult?.toJson(),
    };
  }
}
