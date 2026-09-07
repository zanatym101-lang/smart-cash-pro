import 'package:flutter_test/flutter_test.dart';
import 'package:king_wallet_accounting/ai_sms/customer_matching_service.dart';
import 'package:king_wallet_accounting/ai_sms/models/parsed_transaction_draft.dart';

void main() {
  ParsedTransactionDraft draft({
    double amount = 500,
    String rawMessage = 'Wallet transfer 500 EGP to 01012345678',
    String? provider = 'Vodafone Cash',
  }) {
    return ParsedTransactionDraft(
      operationType: ParsedOperationType.transfer,
      amount: amount,
      sender: 'VF-Cash',
      effectiveDate: DateTime(2026, 5, 7, 12),
      reference: 'MATCH500',
      provider: provider,
      confidence: ParseConfidence.medium,
      warnings: const [],
      rawMessage: rawMessage,
    );
  }

  test('suggests customer by same phone with high confidence', () {
    final suggestion = const CustomerMatchingService().suggest(
      draft: draft(),
      existingCustomers: [
        CustomerMatchCandidate(
          customerName: 'Ahmed',
          phone: '01012345678',
          recentAmounts: [200],
          lastActivity: DateTime(2026, 5, 6),
        ),
      ],
    );

    expect(suggestion, isNotNull);
    expect(suggestion!.matchedCustomer, 'Ahmed');
    expect(suggestion.confidence, ParseConfidence.high);
    expect(suggestion.reason, contains('same phone'));
  });

  test('suggests customer by amount and recent activity pattern', () {
    final suggestion = const CustomerMatchingService().suggest(
      draft: draft(rawMessage: 'Wallet transfer 500 EGP'),
      existingCustomers: [
        CustomerMatchCandidate(
          customerName: 'Mona',
          recentAmounts: [500],
          lastActivity: DateTime(2026, 5, 3),
        ),
      ],
    );

    expect(suggestion, isNotNull);
    expect(suggestion!.matchedCustomer, 'Mona');
    expect(suggestion.confidence, ParseConfidence.medium);
    expect(suggestion.reason, contains('same transfer amount pattern'));
  });

  test('does not invent weak customer matches', () {
    final suggestion = const CustomerMatchingService().suggest(
      draft: draft(rawMessage: 'Wallet transfer 500 EGP'),
      existingCustomers: const [
        CustomerMatchCandidate(customerName: 'No Match', recentAmounts: [50]),
      ],
    );

    expect(suggestion, isNull);
  });
}
