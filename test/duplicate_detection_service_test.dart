import 'package:flutter_test/flutter_test.dart';
import 'package:king_wallet_accounting/ai_sms/duplicate_detection_service.dart';
import 'package:king_wallet_accounting/ai_sms/models/parsed_transaction_draft.dart';
import 'package:king_wallet_accounting/ai_sms/recent_draft_store.dart';

void main() {
  ParsedTransactionDraft buildDraft({
    required double amount,
    required ParsedOperationType type,
    required String provider,
    required DateTime at,
    String? reference,
  }) {
    return ParsedTransactionDraft(
      operationType: type,
      amount: amount,
      sender: provider,
      effectiveDate: at,
      reference: reference,
      provider: provider,
      confidence: ParseConfidence.high,
      warnings: const [],
      rawMessage: 'raw',
    );
  }

  group('DuplicateDetectionService', () {
    late RecentDraftStore store;
    late DuplicateDetectionService service;

    setUp(() {
      store = RecentDraftStore();
      service = DuplicateDetectionService(store: store);
    });

    test('same reference is duplicate with high confidence', () {
      store.add(
        buildDraft(
          amount: 500,
          type: ParsedOperationType.receive,
          provider: 'Vodafone Cash',
          at: DateTime(2026, 5, 2, 10, 0),
          reference: 'ABC123',
        ),
      );

      final result = service.check(
        buildDraft(
          amount: 500,
          type: ParsedOperationType.receive,
          provider: 'Vodafone Cash',
          at: DateTime(2026, 5, 2, 10, 2),
          reference: 'abc123',
        ),
      );

      expect(result.isDuplicate, isTrue);
      expect(result.reason, 'duplicate_reference');
      expect(result.confidence, ParseConfidence.high);
      expect(result.matchedReference, 'ABC123');
    });

    test('same amount + type + provider within window is possible duplicate', () {
      store.add(
        buildDraft(
          amount: 300,
          type: ParsedOperationType.transfer,
          provider: 'Etisalat Cash',
          at: DateTime(2026, 5, 2, 10, 0),
        ),
      );

      final result = service.check(
        buildDraft(
          amount: 300,
          type: ParsedOperationType.transfer,
          provider: 'Etisalat Cash',
          at: DateTime(2026, 5, 2, 10, 3),
        ),
      );

      expect(result.isDuplicate, isTrue);
      expect(result.reason, 'possible_duplicate_heuristic');
      expect(result.confidence, ParseConfidence.medium);
    });

    test('different amount is not duplicate', () {
      store.add(
        buildDraft(
          amount: 300,
          type: ParsedOperationType.transfer,
          provider: 'Etisalat Cash',
          at: DateTime(2026, 5, 2, 10, 0),
        ),
      );

      final result = service.check(
        buildDraft(
          amount: 350,
          type: ParsedOperationType.transfer,
          provider: 'Etisalat Cash',
          at: DateTime(2026, 5, 2, 10, 3),
        ),
      );

      expect(result.isDuplicate, isFalse);
      expect(result.reason, isNot('duplicate_reference'));
    });

    test('single weak match returns low confidence non-duplicate', () {
      store.add(
        buildDraft(
          amount: 450,
          type: ParsedOperationType.receive,
          provider: 'WePay',
          at: DateTime(2026, 5, 2, 10, 0),
        ),
      );

      final result = service.check(
        buildDraft(
          amount: 999,
          type: ParsedOperationType.transfer,
          provider: 'WePay',
          at: DateTime(2026, 5, 2, 12, 0),
        ),
      );

      expect(result.isDuplicate, isFalse);
      expect(result.reason, 'weak_match_only');
      expect(result.confidence, ParseConfidence.low);
    });

    test('outside time window is not heuristic duplicate', () {
      store.add(
        buildDraft(
          amount: 300,
          type: ParsedOperationType.transfer,
          provider: 'Orange Money',
          at: DateTime(2026, 5, 2, 10, 0),
        ),
      );

      final result = service.check(
        buildDraft(
          amount: 300,
          type: ParsedOperationType.transfer,
          provider: 'Orange Money',
          at: DateTime(2026, 5, 2, 10, 20),
        ),
      );

      expect(result.isDuplicate, isFalse);
    });
  });
}
