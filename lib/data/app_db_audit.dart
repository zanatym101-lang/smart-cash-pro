part of 'app_db.dart';

extension AppDbAudit on AppDb {
  Future<void> appendAudit({
    required String type,
    String? dateKey,
    String? note,
    int? txnId,
    int? claimId,
    int? walletId,
    double? amount,
  }) async {
    final m = await _readSettingsMap();
    final raw = m['audit'];
    final list = <Map<String, dynamic>>[];
    if (raw is List) {
      for (final e in raw) {
        if (e is Map) {
          list.add(Map<String, dynamic>.from(e.map((k, v) => MapEntry(k.toString(), v))));
        }
      }
    }
    final entry = <String, dynamic>{
      'type': type,
      'at': DateTime.now().toIso8601String(),
      'by': _actorName(),
      'role': _actorRole(),
    };
    if (dateKey != null) entry['dateKey'] = dateKey;
    if (note != null && note.trim().isNotEmpty) entry['note'] = note.trim();
    if (txnId != null) entry['txnId'] = txnId;
    if (claimId != null) entry['claimId'] = claimId;
    if (walletId != null) entry['walletId'] = walletId;
    if (amount != null) entry['amount'] = amount;
    list.add(entry);
    if (list.length > 200) {
      list.removeRange(0, list.length - 200);
    }
    m['audit'] = list;
    await _writeSettingsMap(m);
  }

  Future<List<Map<String, dynamic>>> listAudit({int limit = 200}) async {
    final m = await _readSettingsMap();
    final raw = m['audit'];
    final list = <Map<String, dynamic>>[];
    if (raw is List) {
      for (final e in raw) {
        if (e is Map) {
          list.add(Map<String, dynamic>.from(e.map((k, v) => MapEntry(k.toString(), v))));
        }
      }
    }
    list.sort((a, b) {
      final aAt = DateTime.tryParse(a['at']?.toString() ?? '') ?? DateTime.fromMillisecondsSinceEpoch(0);
      final bAt = DateTime.tryParse(b['at']?.toString() ?? '') ?? DateTime.fromMillisecondsSinceEpoch(0);
      return bAt.compareTo(aAt);
    });
    if (list.length > limit) {
      return list.sublist(0, limit);
    }
    return list;
  }

  Future<void> clearAudit() async {
    final m = await _readSettingsMap();
    m['audit'] = <Map<String, dynamic>>[];
    await _writeSettingsMap(m);
  }
}
