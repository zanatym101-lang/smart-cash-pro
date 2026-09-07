import 'models/parsed_transaction_draft.dart';

enum AnomalyLevel { low, medium, high }

class AnomalyResult {
  const AnomalyResult({
    required this.level,
    required this.explanation,
    required this.suggestedAction,
  });

  final AnomalyLevel level;
  final String explanation;
  final String suggestedAction;
}

class TransactionAnomalyService {
  const TransactionAnomalyService({
    this.largeAmountThreshold = 10000,
    this.repeatedWindow = const Duration(minutes: 10),
  });

  final double largeAmountThreshold;
  final Duration repeatedWindow;

  AnomalyResult analyze({
    required ParsedTransactionDraft draft,
    required List<ParsedTransactionDraft> recentDrafts,
  }) {
    final findings = <String>[];
    var level = AnomalyLevel.low;

    final amount = draft.amount;
    if (amount != null && amount >= largeAmountThreshold) {
      findings.add('unusually large amount');
      level = AnomalyLevel.high;
    }

    final duplicateLike = recentDrafts.where((recent) {
      final sameAmount =
          amount != null &&
          recent.amount != null &&
          (recent.amount! - amount).abs() < 0.01;
      final sameProvider =
          (recent.provider ?? recent.sender).trim().toLowerCase() ==
          (draft.provider ?? draft.sender).trim().toLowerCase();
      final closeTime =
          recent.effectiveDate.difference(draft.effectiveDate).abs() <=
          repeatedWindow;
      return sameAmount && sameProvider && closeTime;
    }).length;
    if (duplicateLike >= 1) {
      findings.add('duplicate-like timing');
      if (level != AnomalyLevel.high) level = AnomalyLevel.medium;
    }

    final text = draft.rawMessage.toLowerCase();
    final inconsistentDirection =
        draft.operationType == ParsedOperationType.receive &&
            _containsAny(text, const [
              'debited',
              'sent',
              'transferred',
              'خصم',
            ]) ||
        draft.operationType == ParsedOperationType.transfer &&
            _containsAny(text, const [
              'credited',
              'received',
              'استلام',
              'إضافة',
            ]);
    if (inconsistentDirection) {
      findings.add('inconsistent direction');
      level = AnomalyLevel.high;
    }

    final repeatedSameDirection = recentDrafts.where((recent) {
      return recent.operationType == draft.operationType &&
          recent.operationType != ParsedOperationType.unknown &&
          recent.effectiveDate.difference(draft.effectiveDate).abs() <=
              repeatedWindow;
    }).length;
    if (repeatedSameDirection >= 3) {
      findings.add('suspicious repeated operations');
      if (level == AnomalyLevel.low) level = AnomalyLevel.medium;
    }

    if (findings.isEmpty) {
      return const AnomalyResult(
        level: AnomalyLevel.low,
        explanation: 'No unusual pattern detected.',
        suggestedAction: 'Review normally before confirmation.',
      );
    }

    return AnomalyResult(
      level: level,
      explanation: findings.join(' + '),
      suggestedAction: level == AnomalyLevel.high
          ? 'Verify message, amount, direction, and customer before confirming.'
          : 'Review carefully before confirming.',
    );
  }

  bool _containsAny(String text, List<String> markers) {
    return markers.any(text.contains);
  }
}
