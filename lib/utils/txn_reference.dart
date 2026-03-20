String formatTxnReference(int id) => 'ZA${id.toString().padLeft(6, '0')}';

int? txnIdFromReference(String reference) {
  final normalized = reference.trim();
  final match = RegExp(r'^ZA(\d{6,})$').firstMatch(normalized);
  if (match == null) return null;
  return int.tryParse(match.group(1)!);
}
