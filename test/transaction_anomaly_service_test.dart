import 'package:flutter_test/flutter_test.dart';
import 'package:king_wallet_accounting/ai_sms/models/parsed_transaction_draft.dart';
import 'package:king_wallet_accounting/ai_sms/transaction_anomaly_service.dart';

void main() {
  ParsedTransactionDraft draft({
    ParsedOperationType operationType = ParsedOperationType.transfer,
    double amount = 500,
    String rawMessage = 'Transferred 500 EGP',
    DateTime? effectiveDate,
  }) {
    return ParsedTransactionDraft(
      operationType: operationType,
      amount: amount,
      sender: 'VF-Cash',
      effectiveDate: effectiveDate ?? DateTime(2026, 5, 7, 12),
      reference: 'ANOMALY',
      provider: 'Vodafone Cash',
      confidence: ParseConfidence.medium,
      warnings: const [],
      rawMessage: rawMessage,
    );
  }

  test('flags unusually large amount as high anomaly', () {
    final result = const TransactionAnomalyService().analyze(
      draft: draft(amount: 20000),
      recentDrafts: const [],
    );

    expect(result.level, AnomalyLevel.high);
    expect(result.explanation, contains('unusually large amount'));
  });

  test('flags duplicate-like timing as medium anomaly', () {
    final current = draft();
    final result = const TransactionAnomalyService().analyze(
      draft: current,
      recentDrafts: [
        draft(
          effectiveDate: current.effectiveDate.subtract(
            const Duration(minutes: 3),
          ),
        ),
      ],
    );

    expect(result.level, AnomalyLevel.medium);
    expect(result.explanation, contains('duplicate-like timing'));
  });

  test('flags inconsistent direction as high anomaly', () {
    final result = const TransactionAnomalyService().analyze(
      draft: draft(
        operationType: ParsedOperationType.receive,
        rawMessage: 'Your wallet was debited by 500 EGP',
      ),
      recentDrafts: const [],
    );

    expect(result.level, AnomalyLevel.high);
    expect(result.explanation, contains('inconsistent direction'));
  });

  test('normal transaction remains low anomaly', () {
    final result = const TransactionAnomalyService().analyze(
      draft: draft(rawMessage: 'Transferred 500 EGP'),
      recentDrafts: const [],
    );

    expect(result.level, AnomalyLevel.low);
  });
}
