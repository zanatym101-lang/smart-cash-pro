import 'package:flutter_test/flutter_test.dart';
import 'package:king_wallet_accounting/ai_sms/sms_parser_service.dart';
import 'package:king_wallet_accounting/ai_sms/models/incoming_message.dart';
import 'package:king_wallet_accounting/ai_sms/models/parsed_transaction_draft.dart';

void main() {
  late SmsParserService parser;

  setUp(() {
    parser = SmsParserService();
  });

  group('SmsParserService 2026 Egyptian Providers & Formats', () {
    test('Vodafone Cash Transfer with Fees and Balance', () {
      final msg = IncomingMessage(
        sender: 'VF-Cash',
        body: 'تم تحويل 500.00 جنيه لرقم 01012345678. مصاريف الخدمة 1.00 جنيه. رصيدك الحالي هو 2450.50 جنيه. رقم العملية: 4589214785.',
        receivedAt: DateTime(2026, 8, 29, 10, 0),
      );

      final result = parser.parse(msg);
      expect(result.draft.provider, 'Vodafone Cash');
      expect(result.draft.operationType, ParsedOperationType.transfer);
      expect(result.draft.amount, 500.0);
      expect(result.draft.reference, '4589214785');
      expect(result.draft.customerName, '01012345678');
      expect(result.draft.confidence, ParseConfidence.high);
    });

    test('Vodafone Cash Receive with comma formatted amount', () {
      final msg = IncomingMessage(
        sender: 'VF-Cash',
        body: 'تم استلام مبلغ 1,250.50 جنيه من 01098765432. رصيدك الحالي 3650.00 جنيه. رقم العملية: 98563214.',
        receivedAt: DateTime(2026, 8, 29, 10, 30),
      );

      final result = parser.parse(msg);
      expect(result.draft.provider, 'Vodafone Cash');
      expect(result.draft.operationType, ParsedOperationType.receive);
      expect(result.draft.amount, 1250.5);
      expect(result.draft.reference, '98563214');
      expect(result.draft.customerName, '01098765432');
      expect(result.draft.confidence, ParseConfidence.high);
    });

    test('InstaPay / IPN Instant Transfer Receive', () {
      final msg = IncomingMessage(
        sender: 'InstaPay',
        body: 'تم استلام تحويل لحظي بمبلغ 2500.00 جم من AHMED ALI لحسابك/محفظتك. مرجع رقم: IPN2026082912345',
        receivedAt: DateTime(2026, 8, 29, 11, 0),
      );

      final result = parser.parse(msg);
      expect(result.draft.provider, 'InstaPay');
      expect(result.draft.operationType, ParsedOperationType.receive);
      expect(result.draft.amount, 2500.0);
      expect(result.draft.reference?.toUpperCase(), contains('IPN'));
      expect(result.draft.confidence, ParseConfidence.medium);
    });

    test('Orange Money / Orange Cash receive message', () {
      final msg = IncomingMessage(
        sender: 'Orange Cash',
        body: 'تم استلام 450 جنيه من 01234567890. رصيدك الآن 1200 جنيه. رقم المعاملة: OR789456',
        receivedAt: DateTime(2026, 8, 29, 11, 15),
      );

      final result = parser.parse(msg);
      expect(result.draft.provider, 'Orange Money');
      expect(result.draft.operationType, ParsedOperationType.receive);
      expect(result.draft.amount, 450.0);
      expect(result.draft.reference, 'OR789456');
      expect(result.draft.customerName, '01234567890');
    });

    test('Etisalat Cash / e& money transfer message', () {
      final msg = IncomingMessage(
        sender: 'e& money',
        body: 'تم تحويل 1000 جنيه بنجاح إلى 01199887766. كود العملية 556677',
        receivedAt: DateTime(2026, 8, 29, 12, 0),
      );

      final result = parser.parse(msg);
      expect(result.draft.provider, 'Etisalat Cash');
      expect(result.draft.operationType, ParsedOperationType.transfer);
      expect(result.draft.amount, 1000.0);
      expect(result.draft.reference, '556677');
      expect(result.draft.customerName, '01199887766');
    });

    test('WE Pay receive message', () {
      final msg = IncomingMessage(
        sender: 'WEPay',
        body: 'تم استلام 700 جنيه من 01551234567 في محفظة WE Pay. كود المعاملة: WE123456',
        receivedAt: DateTime(2026, 8, 29, 12, 30),
      );

      final result = parser.parse(msg);
      expect(result.draft.provider, 'WePay');
      expect(result.draft.operationType, ParsedOperationType.receive);
      expect(result.draft.amount, 700.0);
      expect(result.draft.reference, 'WE123456');
      expect(result.draft.customerName, '01551234567');
    });

    test('Fawry Cash Payment', () {
      final msg = IncomingMessage(
        sender: 'Fawry',
        body: 'تم سداد مبلغ 350 جنيه عبر فوري بنجاح. رقم المرجع: FW987654',
        receivedAt: DateTime(2026, 8, 29, 13, 0),
      );

      final result = parser.parse(msg);
      expect(result.draft.provider, 'Fawry');
      expect(result.draft.operationType, ParsedOperationType.transfer);
      expect(result.draft.amount, 350.0);
      expect(result.draft.reference, 'FW987654');
    });

    test('Bank SMS Deposit (NBE / الأهلي)', () {
      final msg = IncomingMessage(
        sender: 'NBE',
        body: 'تم إضافة مبلغ 5000.00 جم إلى حسابك رقم **1234 من تحويل لحظي مرجع: REF998877',
        receivedAt: DateTime(2026, 8, 29, 13, 30),
      );

      final result = parser.parse(msg);
      expect(result.draft.provider, 'Bank');
      expect(result.draft.operationType, ParsedOperationType.receive);
      expect(result.draft.amount, 5000.0);
      expect(result.draft.reference, contains('998877'));
    });
  });
}
