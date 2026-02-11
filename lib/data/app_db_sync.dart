part of 'app_db.dart';

extension AppDbSync on AppDb {
  String _outboxFileName(DateTime now) {
    final y = now.year.toString().padLeft(4, '0');
    final m = now.month.toString().padLeft(2, '0');
    final d = now.day.toString().padLeft(2, '0');
    final h = now.hour.toString().padLeft(2, '0');
    final min = now.minute.toString().padLeft(2, '0');
    final s = now.second.toString().padLeft(2, '0');
    return 'smart_cash_outbox_$y$m${d}_$h$min$s.json';
  }

  dynamic _safeJsonDecode(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;
    try {
      return jsonDecode(raw);
    } catch (_) {
      return raw;
    }
  }

  Future<void> appendOutboxEvent({
    required String entity,
    required String entityId,
    required String action,
    Map<String, dynamic>? payload,
  }) async {
    final data = payload == null ? null : jsonEncode(payload);
    await _sqlite.addOutbox(
      entity: entity,
      entityId: entityId,
      action: action,
      payload: data,
    );
  }

  Future<void> enqueueOutbox({
    required String entity,
    required String entityId,
    required String action,
    Map<String, dynamic>? payload,
  }) async {
    try {
      await appendOutboxEvent(
        entity: entity,
        entityId: entityId,
        action: action,
        payload: payload,
      );
    } catch (_) {}
  }

  Future<List<DbOutbox>> listOutbox({int limit = 100}) async {
    return _sqlite.pendingOutbox(limit: limit);
  }

  Future<void> markOutboxSent(int id) async {
    await _sqlite.markOutboxSent(id);
  }

  Future<void> clearOutbox() async {
    await _sqlite.clearOutbox();
  }

  Future<void> markAllOutboxSent() async {
    final items = await listOutbox(limit: 1000);
    for (final e in items) {
      await _sqlite.markOutboxSent(e.id);
    }
  }

  Future<String> exportOutboxToDownloads() async {
    final downloads = await getDownloadsDirectory();
    final dir = downloads ?? await getApplicationSupportDirectory();
    final name = _outboxFileName(DateTime.now());
    final file = File('${dir.path}/$name');
    final items = await listOutbox(limit: 5000);
    final payload = <String, dynamic>{
      'exportedAt': DateTime.now().toIso8601String(),
      'count': items.length,
      'items': items
          .map(
            (e) => {
              'id': e.id,
              'entity': e.entity,
              'entityId': e.entityId,
              'action': e.action,
              'payload': _safeJsonDecode(e.payload),
              'createdAt': e.createdAt.toIso8601String(),
              'sentAt': e.sentAt?.toIso8601String(),
            },
          )
          .toList(),
    };
    await file.writeAsString(jsonEncode(payload));
    return file.path;
  }

  Future<String> exportOutboxToPath(String directoryPath) async {
    final name = _outboxFileName(DateTime.now());
    final path = p.join(directoryPath, name);
    final file = File(path);
    final items = await listOutbox(limit: 5000);
    final payload = <String, dynamic>{
      'exportedAt': DateTime.now().toIso8601String(),
      'count': items.length,
      'items': items
          .map(
            (e) => {
              'id': e.id,
              'entity': e.entity,
              'entityId': e.entityId,
              'action': e.action,
              'payload': _safeJsonDecode(e.payload),
              'createdAt': e.createdAt.toIso8601String(),
              'sentAt': e.sentAt?.toIso8601String(),
            },
          )
          .toList(),
    };
    await file.writeAsString(jsonEncode(payload));
    return file.path;
  }
}
