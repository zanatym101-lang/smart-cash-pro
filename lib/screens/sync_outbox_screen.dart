import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../data/app_db.dart';
import '../data/app_session.dart';
import '../data/sqlite/app_database.dart';
import '../widgets/app_title.dart';

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
      // Keep last state on load errors.
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
        return 'إنشاء';
      case 'update':
        return 'تعديل';
      case 'delete':
        return 'حذف';
      default:
        return action;
    }
  }

  String _labelEntity(String entity) {
    switch (entity) {
      case 'txn':
        return 'عملية';
      case 'wallet':
        return 'محفظة';
      case 'claim':
        return 'مستحق';
      case 'daily_close':
        return 'إغلاق يوم';
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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('تم تصدير ملف المزامنة: $path')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('فشل التصدير: $e')));
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
      ).showSnackBar(SnackBar(content: Text('تم حفظ الملف: $path')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('فشل التصدير: $e')));
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
            child: const Text('إلغاء'),
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
      'تعليم الكل كمرسل؟',
      'سيتم اعتبار جميع العناصر مرسلة (بدون حذف).',
      'تأكيد',
    );
    if (!ok) return;
    await AppDb.instance.markAllOutboxSent();
    await _load();
  }

  Future<void> _clearOutbox() async {
    if (!AppSession.isAdmin) return;
    final ok = await _confirm(
      'مسح الـ Outbox؟',
      'سيتم حذف جميع العناصر المعلقة نهائيًا.',
      'مسح',
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
        title: const AppTitle(subtitle: 'المزامنة'),
        actions: [
          IconButton(
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh),
            tooltip: 'تحديث',
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
                      'Outbox (جاهز للمزامنة)',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 6),
                    Text('العناصر المعلقة: $count'),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        ElevatedButton.icon(
                          onPressed: _exportDownloads,
                          icon: const Icon(Icons.cloud_download),
                          label: const Text('تصدير (التحميلات)'),
                        ),
                        OutlinedButton.icon(
                          onPressed: _exportToFolder,
                          icon: const Icon(Icons.folder_open),
                          label: const Text('تصدير (اختيار مجلد)'),
                        ),
                        OutlinedButton.icon(
                          onPressed: _markAllSent,
                          icon: const Icon(Icons.check_circle_outline),
                          label: const Text('تعليم الكل كمرسل'),
                        ),
                        TextButton.icon(
                          onPressed: _clearOutbox,
                          icon: const Icon(Icons.delete_outline),
                          label: const Text('مسح الـ Outbox'),
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
                  ? const Center(child: Text('لا توجد عناصر للمزامنة الآن'))
                  : ListView.separated(
                      itemCount: _items.length,
                      separatorBuilder: (context, index) =>
                          const SizedBox(height: 8),
                      itemBuilder: (context, i) {
                        final e = _items[i];
                        final title =
                            '${_labelEntity(e.entity)} | ${_labelAction(e.action)}';
                        final created = _fmtDate(e.createdAt);
                        final payload = _payloadSummary(e.payload);
                        final parts = <String>[
                          'ID: ${e.id}',
                          'الكيان: ${e.entityId}',
                          'الوقت: $created',
                        ];
                        if (payload.isNotEmpty) {
                          parts.add('البيانات: $payload');
                        }
                        return Card(
                          child: ListTile(
                            title: Text(
                              title,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            subtitle: Text(parts.join(' | ')),
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
