import 'models/duplicate_check_result.dart';
import 'models/parsed_transaction_draft.dart';
import 'recent_draft_store.dart';

class DuplicateDetectionService {
  final RecentDraftStore store;
  final Duration heuristicWindow;

  const DuplicateDetectionService({
    required this.store,
    this.heuristicWindow = const Duration(minutes: 5),
  });

  DuplicateCheckResult check(ParsedTransactionDraft draft) {
    final recentDrafts = store.getAll();

    final normalizedReference = _normalizeReference(draft.reference);
    if (normalizedReference != null) {
      for (final existing in recentDrafts) {
        final existingReference = _normalizeReference(existing.reference);
        if (existingReference != null &&
            existingReference == normalizedReference) {
          return DuplicateCheckResult(
            isDuplicate: true,
            reason: 'duplicate_reference',
            matchedReference: existing.reference,
            confidence: ParseConfidence.high,
          );
        }
      }
    }

    ParsedTransactionDraft? bestMatch;
    var bestScore = 0;
    for (final existing in recentDrafts) {
      final score = _heuristicScore(existing, draft);
      if (score > bestScore) {
        bestScore = score;
        bestMatch = existing;
      }
    }

    if (bestScore >= 4 && bestMatch != null) {
      return DuplicateCheckResult(
        isDuplicate: true,
        reason: 'possible_duplicate_heuristic',
        matchedReference: bestMatch.reference,
        confidence: ParseConfidence.medium,
      );
    }

    if (bestScore == 1 && bestMatch != null) {
      return DuplicateCheckResult(
        isDuplicate: false,
        reason: 'weak_match_only',
        matchedReference: bestMatch.reference,
        confidence: ParseConfidence.low,
      );
    }

    return const DuplicateCheckResult(
      isDuplicate: false,
      reason: 'no_duplicate_match',
      matchedReference: null,
      confidence: ParseConfidence.low,
    );
  }

  int _heuristicScore(
    ParsedTransactionDraft existing,
    ParsedTransactionDraft incoming,
  ) {
    var score = 0;

    final amountMatches =
        existing.amount != null &&
        incoming.amount != null &&
        (existing.amount! - incoming.amount!).abs() < 0.0001;
    if (amountMatches) score++;

    if (existing.operationType == incoming.operationType &&
        existing.operationType != ParsedOperationType.unknown) {
      score++;
    }

    final existingProvider = (existing.provider ?? existing.sender).trim().toLowerCase();
    final incomingProvider = (incoming.provider ?? incoming.sender).trim().toLowerCase();
    if (existingProvider.isNotEmpty && existingProvider == incomingProvider) {
      score++;
    }

    final delta = existing.effectiveDate.difference(incoming.effectiveDate).abs();
    if (delta <= heuristicWindow) {
      score++;
    }

    return score;
  }

  String? _normalizeReference(String? value) {
    final normalized = value?.trim().toLowerCase();
    if (normalized == null || normalized.isEmpty) return null;
    return normalized;
  }
}
