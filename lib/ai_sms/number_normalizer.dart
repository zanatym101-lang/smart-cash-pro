class NumberNormalizer {
  static const Map<String, String> _arabicDigits = {
    '٠': '0',
    '١': '1',
    '٢': '2',
    '٣': '3',
    '٤': '4',
    '٥': '5',
    '٦': '6',
    '٧': '7',
    '٨': '8',
    '٩': '9',
    '۰': '0',
    '۱': '1',
    '۲': '2',
    '۳': '3',
    '۴': '4',
    '۵': '5',
    '۶': '6',
    '۷': '7',
    '۸': '8',
    '۹': '9',
  };

  static String normalizeText(String input) {
    var result = input;
    _arabicDigits.forEach((key, value) {
      result = result.replaceAll(key, value);
    });
    result = result
        .replaceAll('٫', '.')
        .replaceAll('٬', '')
        .replaceAll('،', ',');
    return result;
  }

  static double? parseLooseNumber(String? input) {
    if (input == null) return null;
    var normalized = normalizeText(input).trim();
    if (normalized.isEmpty) return null;
    normalized = normalized.replaceAll(RegExp(r'(?<=\d),(?=\d{3}\b)'), '');
    normalized = normalized.replaceAll(',', '.');
    return double.tryParse(normalized);
  }
}
