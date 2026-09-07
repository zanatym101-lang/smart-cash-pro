part of 'app_db.dart';

extension AppDbContacts on AppDb {
  Future<List<RecentNumber>> listRecentNumbers({int limit = 10}) async {
    await _ensureLoaded();
    final sorted = _recentNumbers.toList()
      ..sort((a, b) => b.lastUsed.compareTo(a.lastUsed));
    if (limit <= 0 || sorted.length <= limit) return sorted;
    return sorted.take(limit).toList();
  }

  Future<void> addRecentNumber({required String phone, String? name}) async {
    await _ensureLoaded();
    final p = phone.trim();
    if (p.isEmpty) return;

    final now = DateTime.now();
    final idx = _recentNumbers.indexWhere((r) => r.phone == p);
    if (idx >= 0) {
      final existing = _recentNumbers[idx];
      _recentNumbers[idx] = existing.copyWith(
        name: (name != null && name.trim().isNotEmpty) ? name.trim() : existing.name,
        lastUsed: now,
      );
    } else {
      _recentNumbers.add(
        RecentNumber(phone: p, name: name?.trim().isEmpty ?? true ? null : name!.trim(), lastUsed: now),
      );
    }

    _recentNumbers.sort((a, b) => b.lastUsed.compareTo(a.lastUsed));
    if (_recentNumbers.length > 50) {
      _recentNumbers.removeRange(50, _recentNumbers.length);
    }

    await _save();
  }

  Future<List<CustomerMatchCandidate>> listCustomerCandidates() async {
    final txns = await listTxns();
    final claims = await listClaims();
    final byKey = <String, CustomerMatchCandidate>{};

    String normalizePhone(String input) {
      final buffer = StringBuffer();
      for (final rune in input.runes) {
        final ch = String.fromCharCode(rune);
        final code = ch.codeUnitAt(0);
        if (code >= 48 && code <= 57) {
          buffer.write(ch);
        }
      }
      return buffer.toString();
    }

    String? extractPhone(String? input) {
      if (input == null) return null;
      for (final match in RegExp(r'\+?\d[\d\s().-]{8,}\d').allMatches(input)) {
        final normalized = normalizePhone(match.group(0) ?? '');
        if (normalized.length >= 10 && normalized.length <= 15) {
          return normalized;
        }
      }
      return null;
    }

    void add({
      required String name,
      String? phone,
    }) {
      final trimmedName = name.trim();
      if (trimmedName.isEmpty) return;
      final normalizedPhone = normalizePhone(phone ?? '');
      final key = normalizedPhone.isNotEmpty
          ? 'p:$normalizedPhone'
          : 'n:${trimmedName.toLowerCase()}';
      
      if (!byKey.containsKey(key)) {
        byKey[key] = CustomerMatchCandidate(
          customerName: trimmedName,
          phone: normalizedPhone.isEmpty ? null : normalizedPhone,
        );
      }
    }

    for (final txn in txns) {
      add(
        name: txn.party ?? '',
        phone: extractPhone(txn.note) ?? extractPhone(txn.reference),
      );
    }
    for (final claim in claims) {
      add(
        name: claim.party,
        phone: extractPhone(claim.note),
      );
    }

    return byKey.values.toList(growable: false);
  }
}
