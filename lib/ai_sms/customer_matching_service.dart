import 'models/parsed_transaction_draft.dart';

class CustomerMatchCandidate {
  const CustomerMatchCandidate({
    required this.customerName,
    this.phone,
    this.provider,
    this.recentAmounts = const [],
    this.lastActivity,
  });

  final String customerName;
  final String? phone;
  final String? provider;
  final List<double> recentAmounts;
  final DateTime? lastActivity;
}

class CustomerMatchSuggestion {
  const CustomerMatchSuggestion({
    required this.matchedCustomer,
    this.phone,
    required this.confidence,
    required this.reason,
  });

  final String matchedCustomer;
  final String? phone;
  final ParseConfidence confidence;
  final String reason;
}

class CustomerMatchingService {
  const CustomerMatchingService();

  CustomerMatchSuggestion? suggest({
    required ParsedTransactionDraft draft,
    required List<CustomerMatchCandidate> existingCustomers,
  }) {
    if (existingCustomers.isEmpty) return null;

    CustomerMatchSuggestion? best;
    var bestScore = 0;
    for (final customer in existingCustomers) {
      var score = 0;
      final reasons = <String>[];

      final draftPhone = _extractPhone(
        '${draft.customerName ?? ''} ${draft.note ?? ''} ${draft.rawMessage}',
      );
      final customerPhone = _normalizePhone(customer.phone ?? '');
      if (draftPhone != null &&
          customerPhone.isNotEmpty &&
          draftPhone == customerPhone) {
        score += 6;
        reasons.add('same phone');
      }

      final provider = (draft.provider ?? draft.sender).trim().toLowerCase();
      final customerProvider = (customer.provider ?? '').trim().toLowerCase();
      if (provider.isNotEmpty &&
          customerProvider.isNotEmpty &&
          provider.contains(customerProvider)) {
        score += 2;
        reasons.add('same provider');
      }

      final amount = draft.amount;
      if (amount != null &&
          customer.recentAmounts.any(
            (value) => (value - amount).abs() < 0.01,
          )) {
        score += 3;
        reasons.add('same transfer amount pattern');
      }

      final lastActivity = customer.lastActivity;
      if (lastActivity != null &&
          draft.effectiveDate.difference(lastActivity).abs() <=
              const Duration(days: 14)) {
        score += 1;
        reasons.add('recent activity similarity');
      }

      if (score > bestScore) {
        bestScore = score;
        best = CustomerMatchSuggestion(
          matchedCustomer: customer.customerName,
          phone: customer.phone,
          confidence: _confidenceForScore(score),
          reason: reasons.join(' + '),
        );
      }
    }

    if (bestScore < 3) return null;
    return best;
  }

  ParseConfidence _confidenceForScore(int score) {
    if (score >= 6) return ParseConfidence.high;
    if (score >= 3) return ParseConfidence.medium;
    return ParseConfidence.low;
  }

  String? _extractPhone(String input) {
    for (final match in RegExp(r'\+?\d[\d\s().-]{8,}\d').allMatches(input)) {
      final normalized = _normalizePhone(match.group(0) ?? '');
      if (normalized.length >= 10 && normalized.length <= 15) {
        return normalized;
      }
    }
    return null;
  }

  String _normalizePhone(String input) {
    final buffer = StringBuffer();
    for (final rune in input.runes) {
      final ch = String.fromCharCode(rune);
      final code = ch.codeUnitAt(0);
      if (code >= 48 && code <= 57) {
        buffer.write(ch);
      }
    }
    return buffer.toString();
  }
}
