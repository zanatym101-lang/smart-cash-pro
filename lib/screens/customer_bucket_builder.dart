part of 'customers_screen.dart';

extension _CustomerBucketKeyHelpers on _CustomersScreenState {
  String _normalizePhone(String raw) {
    final b = StringBuffer();
    for (final r in raw.runes) {
      final ch = String.fromCharCode(r);
      final cu = ch.codeUnitAt(0);
      if (cu >= 48 && cu <= 57) b.write(ch);
    }
    return b.toString();
  }

  String? _extractPhone(String? text) {
    if (text == null || text.trim().isEmpty) return null;
    final matches = RegExp(r'\d{10,15}').allMatches(text);
    if (matches.isEmpty) return null;
    final phone = _normalizePhone(matches.first.group(0) ?? '');
    return phone.isEmpty ? null : phone;
  }

  int? _extractPendingSettlementRef(String? note) {
    if (note == null || note.trim().isEmpty) return null;
    final m = RegExp(r'pending_txn:(\d+)').firstMatch(note);
    if (m == null) return null;
    return int.tryParse(m.group(1) ?? '');
  }

  int? _extractClaimIdFromNote(String? note) {
    if (note == null || note.trim().isEmpty) return null;
    final m = RegExp(r'claim_id:(\d+)').firstMatch(note);
    if (m == null) return null;
    return int.tryParse(m.group(1) ?? '');
  }

  String _bucketKey({required String name, String? phone}) {
    final p = _normalizePhone(phone ?? '');
    if (p.isNotEmpty) return 'p:$p';
    return 'n:${name.trim().toLowerCase()}';
  }

  String _customerKeyFor(_CustomerBucket c) {
    return c.key;
  }

  bool _isPinned(_CustomerBucket c) {
    return _pinnedCustomers.contains(_customerKeyFor(c));
  }
}
