String providerFromPhone(String phone) {
  final p = phone.trim();
  if (p.startsWith('010')) return 'فودافون';
  if (p.startsWith('011')) return 'اتصالات';
  if (p.startsWith('012')) return 'موبينل';
  if (p.startsWith('015')) return 'وي';
  return 'غير معروف';
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

  switch (provider) {
    case 'فودافون':
      return '*9*7*$customerPhone*$amt#';
    case 'اتصالات':
      // PIN left blank intentionally: *777*1*PIN*amount*recipient#
      return '*777*1**$amt*$customerPhone#';
    case 'موبينل':
      return '#7115#';
    case 'وي':
      return null;
    default:
      return null;
  }
}
