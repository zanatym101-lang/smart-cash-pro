import 'financial_sender_rules.dart';
import 'number_normalizer.dart';
import 'models/incoming_message.dart';
import 'models/message_parse_result.dart';
import 'models/parsed_transaction_draft.dart';

class SmsParserService {
  static const String _numberPattern =
      r'((?:\d{1,3}(?:[.,]\d{3})+|\d+)(?:[.,]\d{1,2})?)';

  static final List<_SenderRule> _senderRules = [
    _SenderRule(
      id: 'vodafone_cash',
      provider: 'Vodafone Cash',
      patterns: [
        ...?financialSenderAliasesByProvider['Vodafone Cash'],
        'vodafonecash',
        'فودافون كاش',
      ],
      strongMatch: true,
    ),
    _SenderRule(
      id: 'etisalat_cash',
      provider: 'Etisalat Cash',
      patterns: [
        ...?financialSenderAliasesByProvider['Etisalat Cash'],
        'اتصالات كاش',
        'e& money',
        'e&',
      ],
      strongMatch: true,
    ),
    _SenderRule(
      id: 'orange_money',
      provider: 'Orange Money',
      patterns: [
        ...?financialSenderAliasesByProvider['Orange Money'],
        'اورنج موني',
        'أورنج موني',
        'اورنج كاش',
        'أورنج كاش',
      ],
      strongMatch: false,
    ),
    _SenderRule(
      id: 'wepay',
      provider: 'WePay',
      patterns: [
        ...?financialSenderAliasesByProvider['WePay'],
        'وي باي',
        'وى باي',
      ],
      strongMatch: false,
    ),
    _SenderRule(
      id: 'instapay',
      provider: 'InstaPay',
      patterns: [
        ...?financialSenderAliasesByProvider['InstaPay'],
        'انستا باي',
        'انستاباي',
        'ipn',
      ],
      strongMatch: false,
    ),
    _SenderRule(
      id: 'fawry',
      provider: 'Fawry',
      patterns: [
        ...?financialSenderAliasesByProvider['Fawry'],
        'فوري',
        'فوري كاش',
      ],
      strongMatch: true,
    ),
    _SenderRule(
      id: 'bank',
      provider: 'Bank',
      patterns: [
        ...?financialSenderAliasesByProvider['Bank'],
        'الأهلي',
        'بنك مصر',
        'cib',
        'qnb',
      ],
      strongMatch: true,
    ),
  ];

  static final List<RegExp> _receivePatterns = [
    RegExp(r'تم\s+استلام', caseSensitive: false),
    RegExp(r'تم\s+إضافة', caseSensitive: false),
    RegExp(r'تم\s+اضافة', caseSensitive: false),
    RegExp(r'تم\s+استقبال', caseSensitive: false),
    RegExp(r'تم\s+إيداع', caseSensitive: false),
    RegExp(r'تم\s+ايداع', caseSensitive: false),
    RegExp(r'تم\s+تنفيذ\s+طلب\s+تحويل\s+إليك', caseSensitive: false),
    RegExp(r'وصلك', caseSensitive: false),
    RegExp(r'إليك', caseSensitive: false),
    RegExp(r'اليك', caseSensitive: false),
    RegExp(r'received', caseSensitive: false),
    RegExp(r'credited', caseSensitive: false),
    RegExp(r'deposited', caseSensitive: false),
    RegExp(r'you\s+received', caseSensitive: false),
  ];

  static final List<RegExp> _transferPatterns = [
    RegExp(r'تم\s+تحويل', caseSensitive: false),
    RegExp(r'تم\s+خصم', caseSensitive: false),
    RegExp(r'تم\s+سحب', caseSensitive: false),
    RegExp(r'تم\s+ارسال', caseSensitive: false),
    RegExp(r'تم\s+إرسال', caseSensitive: false),
    RegExp(r'تم\s+سداد', caseSensitive: false),
    RegExp(r'تم\s+دفع', caseSensitive: false),
    RegExp(r'تم\s+تنفيذ\s+تحويل', caseSensitive: false),
    RegExp(r'ارسلت', caseSensitive: false),
    RegExp(r'أرسلت', caseSensitive: false),
    RegExp(r'transferred', caseSensitive: false),
    RegExp(r'debited', caseSensitive: false),
    RegExp(r'sent', caseSensitive: false),
    RegExp(r'paid', caseSensitive: false),
    RegExp(r'withdrawn', caseSensitive: false),
  ];

  static final List<RegExp> _amountPatterns = [
    RegExp(
      '$_numberPattern\\s*(?:جنيه|ج\\.?م|جم|egp|le)\\b',
      caseSensitive: false,
    ),
    RegExp('تم\\s+تحويل\\s*(?:مبلغ\\s*)?$_numberPattern', caseSensitive: false),
    RegExp('تم\\s+استلام\\s*(?:مبلغ\\s*)?$_numberPattern', caseSensitive: false),
    RegExp('تم\\s+خصم\\s*(?:مبلغ\\s*)?$_numberPattern', caseSensitive: false),
    RegExp('تم\\s+إضافة\\s*(?:مبلغ\\s*)?$_numberPattern', caseSensitive: false),
    RegExp('تم\\s+اضافة\\s*(?:مبلغ\\s*)?$_numberPattern', caseSensitive: false),
    RegExp('تم\\s+إرسال\\s*(?:مبلغ\\s*)?$_numberPattern', caseSensitive: false),
    RegExp('تم\\s+ارسال\\s*(?:مبلغ\\s*)?$_numberPattern', caseSensitive: false),
    RegExp('تم\\s+إيداع\\s*(?:مبلغ\\s*)?$_numberPattern', caseSensitive: false),
    RegExp('تم\\s+ايداع\\s*(?:مبلغ\\s*)?$_numberPattern', caseSensitive: false),
    RegExp('تم\\s+سحب\\s*(?:مبلغ\\s*)?$_numberPattern', caseSensitive: false),
    RegExp('بمبلغ\\s*$_numberPattern', caseSensitive: false),
    RegExp('بقيمة\\s*$_numberPattern', caseSensitive: false),
    RegExp('رصيدك\\s+أصبح\\s*$_numberPattern', caseSensitive: false),
    RegExp('رصيدك\\s+اصبح\\s*$_numberPattern', caseSensitive: false),
    RegExp('مبلغ(?:\\s+قدره)?\\s*$_numberPattern', caseSensitive: false),
    RegExp('amount\\s*:?\\s*$_numberPattern', caseSensitive: false),
    RegExp('egp\\s*$_numberPattern', caseSensitive: false),
    RegExp('le\\s*$_numberPattern', caseSensitive: false),
    RegExp('balance\\s*(?:is|becomes|became)?\\s*$_numberPattern', caseSensitive: false),
  ];

  static final List<RegExp> _referencePatterns = [
    RegExp(r'رقم\s+العملية\s*[:#-]?\s*([A-Za-z0-9\-_/]+)', caseSensitive: false),
    RegExp(r'رقم\s+المرجع\s*[:#-]?\s*([A-Za-z0-9\-_/]+)', caseSensitive: false),
    RegExp(r'المرجع\s*[:#-]?\s*([A-Za-z0-9\-_/]+)', caseSensitive: false),
    RegExp(r'كود\s+العملية\s*[:#-]?\s*([A-Za-z0-9\-_/]+)', caseSensitive: false),
    RegExp(r'كود\s+المعاملة\s*[:#-]?\s*([A-Za-z0-9\-_/]+)', caseSensitive: false),
    RegExp(r'رقم\s+المعاملة\s*[:#-]?\s*([A-Za-z0-9\-_/]+)', caseSensitive: false),
    RegExp(r'txn(?:\s+id)?\s*[:#-]?\s*([A-Za-z0-9\-_/]+)', caseSensitive: false),
    RegExp(r'ref#\s*([A-Za-z0-9\-_/]+)', caseSensitive: false),
    RegExp(r'reference\s*[:#-]?\s*([A-Za-z0-9\-_/]+)', caseSensitive: false),
    RegExp(r'ref\s*[:#-]?\s*([A-Za-z0-9\-_/]+)', caseSensitive: false),
    RegExp(r'ipn[0-9a-zA-Z]+', caseSensitive: false),
  ];

  static final List<RegExp> _phonePatterns = [
    RegExp(r'(?:من|إلى|الى|لرقم|لـ|ل|from|to)\s*(01[0125][0-9]{8})', caseSensitive: false),
    RegExp(r'\b(01[0125][0-9]{8})\b'),
    RegExp(r'\+20(1[0125][0-9]{8})'),
  ];

  MessageParseResult parse(IncomingMessage message) {
    final normalizedBody = NumberNormalizer.normalizeText(message.body);
    final senderRule = _matchSenderRule(message.normalizedSender) ??
        _matchSenderFromContent(normalizedBody);
    final operationType = _detectOperationType(normalizedBody);
    final amount = _extractAmount(normalizedBody);
    final reference = _extractReference(normalizedBody);
    final counterpartyPhone = _extractPhone(normalizedBody);
    final effectiveDate = message.receivedAt ?? DateTime.now();

    final reasons = <String>[];
    if (senderRule != null) {
      reasons.add('matched_sender:${senderRule.id}');
    } else {
      reasons.add('sender_unknown');
    }

    if (operationType != ParsedOperationType.unknown) {
      reasons.add('operation_detected:${operationType.name}');
    } else {
      reasons.add('operation_unclear');
    }

    if (amount != null) {
      reasons.add('amount_extracted');
    } else {
      reasons.add('amount_missing');
    }

    if (reference != null) {
      reasons.add('reference_extracted');
    }

    if (counterpartyPhone != null) {
      reasons.add('phone_extracted');
    }

    final confidence = _score(
      senderRule: senderRule,
      hasOperation: operationType != ParsedOperationType.unknown,
      hasAmount: amount != null,
      hasReference: reference != null,
    );

    final warnings = <String>[];
    if (senderRule == null) {
      warnings.add('لم يتم التعرف على جهة الإرسال.');
    }
    if (operationType == ParsedOperationType.unknown) {
      warnings.add('نوع العملية غير واضح.');
    }
    if (amount == null) {
      warnings.add('تعذر استخراج المبلغ.');
    }

    final draft = ParsedTransactionDraft(
      operationType: operationType,
      amount: amount,
      sender: message.sender.trim(),
      effectiveDate: effectiveDate,
      reference: reference,
      provider: senderRule?.provider,
      customerName: counterpartyPhone,
      note: counterpartyPhone != null ? 'رقم الطرف الآخر: $counterpartyPhone' : null,
      confidence: confidence,
      warnings: warnings,
      rawMessage: message.body,
    );

    return MessageParseResult(
      draft: draft,
      matchedRuleId: senderRule?.id,
      reasons: reasons,
      requiresManualReview:
          confidence != ParseConfidence.high ||
          amount == null ||
          operationType == ParsedOperationType.unknown,
    );
  }

  _SenderRule? _matchSenderRule(String normalizedSender) {
    for (final rule in _senderRules) {
      for (final pattern in rule.patterns) {
        if (normalizedSender.contains(pattern)) {
          return rule;
        }
      }
    }
    return null;
  }

  _SenderRule? _matchSenderFromContent(String body) {
    final lower = body.toLowerCase();
    for (final rule in _senderRules) {
      for (final pattern in rule.patterns) {
        if (lower.contains(pattern.toLowerCase())) {
          return rule;
        }
      }
    }
    return null;
  }

  ParsedOperationType _detectOperationType(String body) {
    final normalized = body.trim().toLowerCase();
    for (final pattern in _receivePatterns) {
      if (pattern.hasMatch(normalized)) return ParsedOperationType.receive;
    }
    for (final pattern in _transferPatterns) {
      if (pattern.hasMatch(normalized)) return ParsedOperationType.transfer;
    }
    return ParsedOperationType.unknown;
  }

  double? _extractAmount(String body) {
    for (final pattern in _amountPatterns) {
      final match = pattern.firstMatch(body);
      if (match == null) continue;
      final value = NumberNormalizer.parseLooseNumber(match.group(1));
      if (value != null) return value;
    }
    return null;
  }

  String? _extractReference(String body) {
    for (final pattern in _referencePatterns) {
      final match = pattern.firstMatch(body);
      if (match == null) continue;
      final raw = match.group(match.groupCount >= 1 ? 1 : 0)?.trim();
      if (raw != null && raw.isNotEmpty) return raw;
    }
    return null;
  }

  String? _extractPhone(String body) {
    for (final pattern in _phonePatterns) {
      final match = pattern.firstMatch(body);
      if (match == null) continue;
      final raw = match.group(1)?.trim();
      if (raw != null && raw.isNotEmpty) {
        if (raw.startsWith('20') && raw.length == 12) {
          return '0${raw.substring(2)}';
        }
        return raw;
      }
    }
    return null;
  }

  ParseConfidence _score({
    required _SenderRule? senderRule,
    required bool hasOperation,
    required bool hasAmount,
    required bool hasReference,
  }) {
    if (senderRule != null &&
        senderRule.strongMatch &&
        hasOperation &&
        hasAmount &&
        hasReference) {
      return ParseConfidence.high;
    }
    if ((senderRule != null && hasAmount) || (hasOperation && hasAmount)) {
      return ParseConfidence.medium;
    }
    return ParseConfidence.low;
  }
}

class _SenderRule {
  final String id;
  final String provider;
  final List<String> patterns;
  final bool strongMatch;

  const _SenderRule({
    required this.id,
    required this.provider,
    required this.patterns,
    required this.strongMatch,
  });
}
