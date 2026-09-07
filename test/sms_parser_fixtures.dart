class SmsParserFixture {
  final String sender;
  final String body;
  final String provider;
  final double? amount;
  final String operation;
  final String? reference;
  final String confidence;

  const SmsParserFixture({
    required this.sender,
    required this.body,
    required this.provider,
    required this.amount,
    required this.operation,
    required this.reference,
    required this.confidence,
  });
}

const smsParserFixtures = <SmsParserFixture>[
  SmsParserFixture(
    sender: 'Vodafone Cash',
    body: 'تم استلام مبلغ 500 جنيه من محفظة رقم 01012345678. رقم العملية 123456.',
    provider: 'Vodafone Cash',
    amount: 500,
    operation: 'receive',
    reference: '123456',
    confidence: 'high',
  ),
  SmsParserFixture(
    sender: 'Vodafone Cash',
    body: 'تم خصم 200 جنيه. Txn ID: 98765',
    provider: 'Vodafone Cash',
    amount: 200,
    operation: 'transfer',
    reference: '98765',
    confidence: 'high',
  ),
  SmsParserFixture(
    sender: 'VF-Cash',
    body: 'تم تحويل مبلغ 500 جنيه. Txn ID: VF500',
    provider: 'Vodafone Cash',
    amount: 500,
    operation: 'transfer',
    reference: 'VF500',
    confidence: 'high',
  ),
  SmsParserFixture(
    sender: 'Vodafone365',
    body: 'تم ارسال 350 جنيه. Ref# VF-350',
    provider: 'Vodafone Cash',
    amount: 350,
    operation: 'transfer',
    reference: 'VF-350',
    confidence: 'high',
  ),
  SmsParserFixture(
    sender: 'Etisalat Cash',
    body: 'تم تحويل مبلغ 275.50 جنيه. رقم المرجع 998877.',
    provider: 'Etisalat Cash',
    amount: 275.50,
    operation: 'transfer',
    reference: '998877',
    confidence: 'high',
  ),
  SmsParserFixture(
    sender: 'Etisalat Cash',
    body: 'تم إضافة 100 جنيه إلى حسابك. Ref# ABC123',
    provider: 'Etisalat Cash',
    amount: 100,
    operation: 'receive',
    reference: 'ABC123',
    confidence: 'high',
  ),
  SmsParserFixture(
    sender: 'Orange Money',
    body: 'تم استلام ٣٠٠ جنيه. رقم العملية OR-55',
    provider: 'Orange Money',
    amount: 300,
    operation: 'receive',
    reference: 'OR-55',
    confidence: 'medium',
  ),
  SmsParserFixture(
    sender: 'Orange Money',
    body: 'تم تحويل 1,200 جنيه إلى عميل آخر.',
    provider: 'Orange Money',
    amount: 1200,
    operation: 'transfer',
    reference: null,
    confidence: 'medium',
  ),
  SmsParserFixture(
    sender: 'WePay',
    body: 'Received 450 EGP. Ref# WP-2026-77',
    provider: 'WePay',
    amount: 450,
    operation: 'receive',
    reference: 'WP-2026-77',
    confidence: 'medium',
  ),
  SmsParserFixture(
    sender: 'InstaPay',
    body: 'تم خصم 150 جنيه. Txn ID: IN555',
    provider: 'InstaPay',
    amount: 150,
    operation: 'transfer',
    reference: 'IN555',
    confidence: 'medium',
  ),
];
