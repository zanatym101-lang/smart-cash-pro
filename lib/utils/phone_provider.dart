String providerFromPhone(String phone) {
  final p = normalizePhone(phone);
  if (p.startsWith('010')) return 'vodafone';
  if (p.startsWith('011')) return 'etisalat';
  if (p.startsWith('012')) return 'orange';
  if (p.startsWith('015')) return 'we';
  return 'unknown';
}

String providerDisplayName(String provider) {
  switch (provider.toLowerCase()) {
    case 'vodafone':
      return 'فودافون';
    case 'etisalat':
      return 'اتصالات';
    case 'orange':
      return 'أورنج';
    case 'we':
      return 'وي';
    default:
      return 'غير معروف';
  }
}

String _normalizeDigit(String ch) {
  switch (ch) {
    case '٠':
    case '۰':
      return '0';
    case '١':
    case '۱':
      return '1';
    case '٢':
    case '۲':
      return '2';
    case '٣':
    case '۳':
      return '3';
    case '٤':
    case '۴':
      return '4';
    case '٥':
    case '۵':
      return '5';
    case '٦':
    case '۶':
      return '6';
    case '٧':
    case '۷':
      return '7';
    case '٨':
    case '۸':
      return '8';
    case '٩':
    case '۹':
      return '9';
    default:
      return ch;
  }
}

String normalizePhone(String input) {
  final buf = StringBuffer();
  for (final r in input.runes) {
    final raw = String.fromCharCode(r);
    final ch = _normalizeDigit(raw);
    final code = ch.codeUnitAt(0);
    if (code >= 48 && code <= 57) {
      buf.write(ch);
    }
  }
  return buf.toString();
}

String? defaultTransferCode({
  required String provider,
  required String customerPhone,
  required double amount,
}) {
  final amt = amount % 1 == 0
      ? amount.toStringAsFixed(0)
      : amount.toStringAsFixed(2);

  switch (provider.toLowerCase()) {
    case 'vodafone':
      return '*9*7*$customerPhone*$amt#';
    case 'etisalat':
      // PIN is intentionally left blank by default.
      return '*777*1**$amt*$customerPhone#';
    case 'orange':
      return '#7115#';
    case 'we':
      return null;
    default:
      return null;
  }
}
