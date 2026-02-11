import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import '../widgets/app_title.dart';
import '../data/app_db.dart';
import '../data/sqlite/app_database.dart';
import '../data/app_session.dart';

class SyncOutboxScreen extends StatefulWidget {
  const SyncOutboxScreen({super.key});

  @override
  State<SyncOutboxScreen> createState() => _SyncOutboxScreenState();
}

class _SyncOutboxScreenState extends State<SyncOutboxScreen> {
  bool _loading = true;
  List<DbOutbox> _items = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      _items = await AppDb.instance.listOutbox(limit: 500);
    } catch (_) {
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _fmtDate(DateTime d) {
    final y = d.year.toString().padLeft(4, '0');
    final m = d.month.toString().padLeft(2, '0');
    final day = d.day.toString().padLeft(2, '0');
    final h = d.hour.toString().padLeft(2, '0');
    final min = d.minute.toString().padLeft(2, '0');
    return '$y-$m-$day $h:$min';
  }

  String _labelAction(String action) {
    switch (action) {
      case 'create':
        return 'ط¥ظ†ط´ط§ط،';
      case 'update':
        return 'طھط¹ط¯ظٹظ„';
      case 'delete':
        return 'ط­ط°ظپ';
      default:
        return action;
    }
  }

  String _labelEntity(String entity) {
    switch (entity) {
      case 'txn':
        return 'ط¹ظ…ظ„ظٹط©';
      case 'wallet':
        return 'ظ…ط­ظپط¸ط©';
      case 'claim':
        return 'ظ…ط³طھط­ظ‚';
      case 'daily_close':
        return 'ط¥ط؛ظ„ط§ظ‚ ظٹظˆظ…';
      default:
        return entity;
    }
  }

  String _shorten(String text, int max) {
    if (text.length <= max) return text;
    return '${text.substring(0, max)}...';
  }

  String _payloadSummary(String? raw) {
    if (raw == null || raw.trim().isEmpty) return '';
    try {
      final j = jsonDecode(raw);
      final s = jsonEncode(j);
      return _shorten(s, 120);
    } catch (_) {
      return _shorten(raw, 120);
    }
  }

  Future<void> _exportDownloads() async {
    try {
      final path = await AppDb.instance.exportOutboxToDownloads();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('طھظ… طھطµط¯ظٹط± ظ…ظ„ظپ ط§ظ„ظ…ط²ط§ظ…ظ†ط©: $path'),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('ظپط´ظ„ ط§ظ„طھطµط¯ظٹط±: $e')));
    }
  }

  Future<void> _exportToFolder() async {
    final dir = await FilePicker.platform.getDirectoryPath();
    if (dir == null || dir.trim().isEmpty) return;
    try {
      final path = await AppDb.instance.exportOutboxToPath(dir);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('طھظ… ط­ظپط¸ ط§ظ„ظ…ظ„ظپ: $path')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('ظپط´ظ„ ط§ظ„طھطµط¯ظٹط±: $e')));
    }
  }

  Future<bool> _confirm(String title, String body, String okText) async {
    final res = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('ط¥ظ„ط؛ط§ط،'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(okText),
          ),
        ],
      ),
    );
    return res == true;
  }

  Future<void> _markAllSent() async {
    if (!AppSession.isAdmin) return;
    final ok = await _confirm(
      'طھط¹ظ„ظٹظ… ط§ظ„ظƒظ„ ظƒظ…ظڈط±ط³ظ„طں',
      'ط³ظٹطھظ… ط§ط¹طھط¨ط§ط± ط¬ظ…ظٹط¹ ط§ظ„ط¹ظ†ط§طµط± ظ…ظڈط±ط³ظ„ط© (ط¨ط¯ظˆظ† ط­ط°ظپ).',
      'طھط£ظƒظٹط¯',
    );
    if (!ok) return;
    await AppDb.instance.markAllOutboxSent();
    await _load();
  }

  Future<void> _clearOutbox() async {
    if (!AppSession.isAdmin) return;
    final ok = await _confirm(
      'ظ…ط³ط­ ط§ظ„ظ€ Outboxطں',
      'ط³ظٹطھظ… ط­ط°ظپ ط¬ظ…ظٹط¹ ط§ظ„ط¹ظ†ط§طµط± ط§ظ„ظ…ط¹ظ„ظ‘ظ‚ط© ظ†ظ‡ط§ط¦ظٹظ‹ط§.',
      'ظ…ط³ط­',
    );
    if (!ok) return;
    await AppDb.instance.clearOutbox();
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final count = _items.length;
    return Scaffold(
      appBar: AppBar(
        title: const AppTitle(subtitle: 'ظ…ط²ط§ظ…ظ†ط©'),
        actions: [
          IconButton(
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh),
            tooltip: 'طھط­ط¯ظٹط«',
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Outbox (ط¬ط§ظ‡ط² ظ„ظ„ظ…ط²ط§ظ…ظ†ط©)',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 6),
                    Text('ط§ظ„ط¹ظ†ط§طµط± ط§ظ„ظ…ط¹ظ„ظ‘ظ‚ط©: $count'),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        ElevatedButton.icon(
                          onPressed: _exportDownloads,
                          icon: const Icon(Icons.cloud_download),
                          label: const Text('طھطµط¯ظٹط± (ط§ظ„طھط­ظ…ظٹظ„ط§طھ)'),
                        ),
                        OutlinedButton.icon(
                          onPressed: _exportToFolder,
                          icon: const Icon(Icons.folder_open),
                          label: const Text(
                            'طھطµط¯ظٹط± (ط§ط®طھظٹط§ط± ظ…ط¬ظ„ط¯)',
                          ),
                        ),
                        OutlinedButton.icon(
                          onPressed: _markAllSent,
                          icon: const Icon(Icons.check_circle_outline),
                          label: const Text('طھط¹ظ„ظٹظ… ط§ظ„ظƒظ„ ظƒظ…ظڈط±ط³ظ„'),
                        ),
                        TextButton.icon(
                          onPressed: _clearOutbox,
                          icon: const Icon(Icons.delete_outline),
                          label: const Text('ظ…ط³ط­ ط§ظ„ظ€ Outbox'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : count == 0
                  ? const Center(
                      child: Text(
                        'ظ„ط§ طھظˆط¬ط¯ ط¹ظ†ط§طµط± ظ„ظ„ظ…ط²ط§ظ…ظ†ط© ط§ظ„ط¢ظ†',
                      ),
                    )
                  : ListView.separated(
                      itemCount: _items.length,
                      separatorBuilder: (context, index) =>
                          const SizedBox(height: 8),
                      itemBuilder: (context, i) {
                        final e = _items[i];
                        final title =
                            '${_labelEntity(e.entity)} â€¢ ${_labelAction(e.action)}';
                        final created = _fmtDate(e.createdAt);
                        final payload = _payloadSummary(e.payload);
                        final parts = <String>[
                          'ID: ${e.id}',
                          'ط§ظ„ظƒظٹط§ظ†: ${e.entityId}',
                          'ط§ظ„ظˆظ‚طھ: $created',
                        ];
                        if (payload.isNotEmpty) {
                          parts.add('ط§ظ„ط¨ظٹط§ظ†ط§طھ: $payload');
                        }
                        return Card(
                          child: ListTile(
                            title: Text(
                              title,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            subtitle: Text(parts.join(' â€¢ ')),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
