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
}
