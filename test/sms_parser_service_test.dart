import 'package:flutter_test/flutter_test.dart';
import 'package:king_wallet_accounting/ai_sms/models/incoming_message.dart';
import 'package:king_wallet_accounting/ai_sms/models/parsed_transaction_draft.dart';
import 'package:king_wallet_accounting/ai_sms/number_normalizer.dart';
import 'package:king_wallet_accounting/ai_sms/sms_parser_service.dart';

import 'sms_parser_fixtures.dart';

void main() {
  group('NumberNormalizer', () {
    test('converts Arabic digits and separators', () {
      expect(NumberNormalizer.normalizeText('١٬٢٠٠٫٥٠ جنيه'), '1200.50 جنيه');
      expect(
        NumberNormalizer.parseLooseNumber('١٬٢٠٠٫٥٠'),
        closeTo(1200.50, 0.0001),
      );
    });
  });

  group('SmsParserService', () {
    final parser = SmsParserService();

    for (final fixture in smsParserFixtures) {
      test('parses fixture for ${fixture.sender}: ${fixture.body}', () {
        final result = parser.parse(
          IncomingMessage(sender: fixture.sender, body: fixture.body),
        );

        expect(result.draft.provider, fixture.provider);
        expect(
          result.draft.amount,
          fixture.amount == null ? isNull : closeTo(fixture.amount!, 0.0001),
        );
        expect(
          result.draft.operationType,
          fixture.operation == 'receive'
              ? ParsedOperationType.receive
              : ParsedOperationType.transfer,
        );
        expect(result.draft.reference, fixture.reference);
        expect(result.draft.confidence.name, fixture.confidence);
      });
    }

    test('balance-only message extracts amount but keeps operation unclear', () {
      final result = parser.parse(
        const IncomingMessage(
          sender: 'Vodafone Cash',
          body: 'رصيدك أصبح 1200 جنيه بعد آخر عملية.',
        ),
      );

      expect(result.draft.amount, closeTo(1200, 0.0001));
      expect(result.draft.operationType, ParsedOperationType.unknown);
      expect(result.draft.confidence, ParseConfidence.medium);
      expect(result.requiresManualReview, isTrue);
    });

    test('VF-Cash outgoing transfer is parsed as transfer', () {
      final result = parser.parse(
        const IncomingMessage(
          sender: 'VF-Cash',
          body: 'تم خصم 500 جنيه من محفظتك. Txn ID: OUT500',
        ),
      );

      expect(result.draft.provider, 'Vodafone Cash');
      expect(result.draft.amount, closeTo(500, 0.0001));
      expect(result.draft.operationType, ParsedOperationType.transfer);
      expect(result.draft.reference, 'OUT500');
    });

    test('parses Arabic outgoing phrase تم ارسال', () {
      final result = parser.parse(
        const IncomingMessage(
          sender: 'Vodafone365',
          body: 'تم ارسال 500 جنيه. Ref# SEND500',
        ),
      );

      expect(result.draft.provider, 'Vodafone Cash');
      expect(result.draft.amount, closeTo(500, 0.0001));
      expect(result.draft.operationType, ParsedOperationType.transfer);
      expect(result.draft.reference, 'SEND500');
    });

    test('returns low confidence for unclear message', () {
      final result = parser.parse(
        const IncomingMessage(
          sender: 'Unknown Sender',
          body: 'رسالة عامة بدون تفاصيل مالية واضحة.',
        ),
      );

      expect(result.draft.operationType, ParsedOperationType.unknown);
      expect(result.draft.amount, isNull);
      expect(result.draft.confidence, ParseConfidence.low);
      expect(result.requiresManualReview, isTrue);
    });
  });
}
