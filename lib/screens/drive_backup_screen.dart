import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../data/app_db.dart';
import '../services/drive_backup_service.dart';
import '../widgets/app_title.dart';

class DriveBackupScreen extends StatefulWidget {
  const DriveBackupScreen({super.key, this.service});

  final DriveBackupService? service;

  @override
  State<DriveBackupScreen> createState() => _DriveBackupScreenState();
}

class _BackupInput {
  final String passphrase;
  final String? note;

  const _BackupInput({required this.passphrase, required this.note});
}

class _DriveBackupScreenState extends State<DriveBackupScreen> {
  bool _loading = true;
  String? _email;
  bool _working = false;
  List<BackupMetadata> _backups = const [];
  AutoBackupSettings _autoBackupSettings = AutoBackupSettings.defaults;
  bool _autoBackupDue = false;

  DriveBackupService get _service =>
      widget.service ?? DriveBackupService.instance;

  @override
  void initState() {
    super.initState();
    _load();
  }

  bool get _isMobile => !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      _email = await _service.currentEmail();
      _autoBackupSettings = await _service.getAutoBackupSettings();
      _autoBackupDue = await _service.isAutoBackupDue();
      if (_autoBackupDue) {
        await _service.showAutoBackupReminderIfDue();
      }
      if (_email != null && _email!.trim().isNotEmpty) {
        _backups = await _service.listDriveBackups();
      }
    } catch (_) {
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _signIn() async {
    if (!_isMobile) return;
    setState(() => _working = true);
    try {
      final acc = await _service.signIn();
      if (!mounted) return;
      setState(() => _email = acc?.email);
      await _refreshBackups();
      if (!mounted) return;
      if (acc == null) {
        await _showDriveAuthDebugDialog(_service.lastAuthDiagnostic);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تعذر تسجيل الدخول إلى Google Drive')),
        );
      }
    } on DriveAuthException catch (e) {
      await _showDriveAuthDebugDialog(
        e.diagnostic ?? _service.lastAuthDiagnostic,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تعذر تسجيل الدخول إلى Google Drive')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تعذر تسجيل الدخول إلى Google Drive')),
      );
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _signOut() async {
    setState(() => _working = true);
    try {
      await _service.signOut();
      if (!mounted) return;
      setState(() => _email = null);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('فشل تسجيل الخروج: $e')));
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _uploadNow() async {
    if (!_isMobile) return;
    setState(() => _working = true);
    try {
      final id = await _service.uploadLatestBackup();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تم رفع النسخة إلى Drive (ID: $id)')),
      );
    } on DriveAuthException catch (e) {
      await _showDriveAuthDebugDialog(
        e.diagnostic ?? _service.lastAuthDiagnostic,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('فشل الرفع: $e')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('فشل الرفع: $e')));
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _createEncryptedBackup() async {
    if (!_isMobile) return;
    final input = await _encryptedBackupDialog();
    if (input == null) return;
    setState(() => _working = true);
    try {
      await _service.createEncryptedDriveBackup(
        input.passphrase,
        note: input.note,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم إنشاء النسخة الاحتياطية بنجاح')),
      );
      await _refreshBackups();
    } on DriveAuthException catch (e) {
      await _showDriveAuthDebugDialog(
        e.diagnostic ?? _service.lastAuthDiagnostic,
      );
      try {
        final path = await _service.createEncryptedLocalBackup(
          input.passphrase,
          note: input.note,
        );
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'تعذر تسجيل الدخول إلى Google Drive. تم إنشاء نسخة محلية: $path',
            ),
          ),
        );
      } catch (_) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تعذر تسجيل الدخول إلى Google Drive')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('فشل إنشاء النسخة الاحتياطية: $e')),
      );
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _refreshBackups() async {
    if (_email == null || _email!.trim().isEmpty) return;
    final backups = await _service.listDriveBackups();
    if (mounted) setState(() => _backups = backups);
  }

  Future<DriveBackupFileRef?> _pickBackupDialog(
    List<DriveBackupFileRef> files,
  ) async {
    return showDialog<DriveBackupFileRef>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('اختر نسخة للاسترجاع'),
        content: SizedBox(
          width: 420,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: files.length,
            itemBuilder: (context, index) {
              final file = files[index];
              final modified = file.modifiedTime;
              final modifiedText = modified == null
                  ? ''
                  : '${modified.year.toString().padLeft(4, '0')}-'
                        '${modified.month.toString().padLeft(2, '0')}-'
                        '${modified.day.toString().padLeft(2, '0')} '
                        '${modified.hour.toString().padLeft(2, '0')}:'
                        '${modified.minute.toString().padLeft(2, '0')}';
              return ListTile(
                dense: true,
                title: Text(file.name),
                subtitle: Text(
                  modifiedText.isEmpty
                      ? 'اضغط للاختيار'
                      : 'آخر تعديل: $modifiedText',
                ),
                onTap: () => Navigator.of(ctx).pop(file),
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('إلغاء'),
          ),
        ],
      ),
    );
  }

  Future<void> _restoreFromDrive() async {
    if (!_isMobile) return;
    setState(() => _working = true);
    String? tempPath;
    try {
      final files = await _service.listBackups();
      if (!mounted) return;
      if (files.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('لا توجد نسخ احتياطية على Google Drive.'),
          ),
        );
        return;
      }

      final selected = await _pickBackupDialog(files);
      if (!mounted || selected == null) return;

      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('تأكيد الاسترجاع من Drive'),
          content: Text(
            'سيتم استبدال كل البيانات الحالية بالنسخة:\n${selected.name}\n\nهل تريد المتابعة؟',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('إلغاء'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('استرجاع'),
            ),
          ],
        ),
      );
      if (ok != true) return;

      tempPath = await _service.downloadBackupToTemporary(
        fileId: selected.id,
        fileName: selected.name,
      );
      await AppDb.instance.restoreBackupFromPath(tempPath);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم الاسترجاع من Google Drive بنجاح')),
      );
    } on DriveAuthException catch (e) {
      await _showDriveAuthDebugDialog(
        e.diagnostic ?? _service.lastAuthDiagnostic,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('فشل الاسترجاع من Drive: $e')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('فشل الاسترجاع من Drive: $e')));
    } finally {
      if (tempPath != null && tempPath.trim().isNotEmpty) {
        try {
          final file = File(tempPath);
          if (await file.exists()) {
            await file.delete();
          }
        } catch (_) {}
      }
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _restoreEncryptedBackup(BackupMetadata backup) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('تأكيد الاستعادة من Google Drive'),
        content: Text(
          'سيتم استبدال البيانات الحالية. سيتم إنشاء نسخة أمان محلية أولًا.\n\n${backup.fileName ?? backup.backupId}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('متابعة'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final passphrase = await _passphraseDialog(title: 'كلمة مرور النسخة');
    if (passphrase == null) return;
    setState(() => _working = true);
    try {
      await _service.restoreEncryptedDriveBackup(
        backupId: backup.backupId,
        passphrase: passphrase,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تمت استعادة النسخة الاحتياطية بنجاح')),
      );
    } on BackupIntegrityException {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('كلمة المرور غير صحيحة أو النسخة تالفة')),
      );
    } on DriveAuthException catch (e) {
      await _showDriveAuthDebugDialog(
        e.diagnostic ?? _service.lastAuthDiagnostic,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('فشل الاستعادة من Drive: $e')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('فشل الاستعادة من Drive: $e')));
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<_BackupInput?> _encryptedBackupDialog() async {
    final passCtrl = TextEditingController();
    final confirmCtrl = TextEditingController();
    final noteCtrl = TextEditingController();
    String? error;
    try {
      return showDialog<_BackupInput>(
        context: context,
        builder: (ctx) => StatefulBuilder(
          builder: (ctx, setState) => AlertDialog(
            title: const Text('إنشاء نسخة احتياطية مشفرة'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: passCtrl,
                    obscureText: true,
                    decoration: const InputDecoration(
                      labelText: 'كلمة المرور',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: confirmCtrl,
                    obscureText: true,
                    decoration: InputDecoration(
                      labelText: 'تأكيد كلمة المرور',
                      border: const OutlineInputBorder(),
                      errorText: error,
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: noteCtrl,
                    decoration: const InputDecoration(
                      labelText: 'ملاحظة اختيارية',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('إلغاء'),
              ),
              ElevatedButton(
                onPressed: () {
                  final pass = passCtrl.text;
                  if (pass.length < 8) {
                    setState(
                      () => error = 'كلمة المرور يجب أن تكون 8 أحرف على الأقل',
                    );
                    return;
                  }
                  if (pass != confirmCtrl.text) {
                    setState(() => error = 'كلمتا المرور غير متطابقتين');
                    return;
                  }
                  final note = noteCtrl.text.trim();
                  Navigator.of(ctx).pop(
                    _BackupInput(
                      passphrase: pass,
                      note: note.isEmpty ? null : note,
                    ),
                  );
                },
                child: const Text('إنشاء'),
              ),
            ],
          ),
        ),
      );
    } finally {
      passCtrl.dispose();
      confirmCtrl.dispose();
      noteCtrl.dispose();
    }
  }

  Future<String?> _passphraseDialog({required String title}) async {
    final ctrl = TextEditingController();
    try {
      return showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(title),
          content: TextField(
            controller: ctrl,
            obscureText: true,
            decoration: const InputDecoration(
              labelText: 'كلمة المرور',
              border: OutlineInputBorder(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('إلغاء'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(ctx).pop(ctrl.text),
              child: const Text('متابعة'),
            ),
          ],
        ),
      );
    } finally {
      ctrl.dispose();
    }
  }

  Future<void> _saveAutoBackupSettings({
    bool? enabled,
    AutoBackupFrequency? frequency,
  }) async {
    final next = _autoBackupSettings.copyWith(
      enabled: enabled,
      frequency: frequency,
    );
    await _service.setAutoBackupSettings(next);
    if (!mounted) return;
    setState(() {
      _autoBackupSettings = next;
      _autoBackupDue = next.isDue(DateTime.now());
    });
  }

  String _fmtDate(DateTime date) {
    return '${date.year.toString().padLeft(4, '0')}-'
        '${date.month.toString().padLeft(2, '0')}-'
        '${date.day.toString().padLeft(2, '0')} '
        '${date.hour.toString().padLeft(2, '0')}:'
        '${date.minute.toString().padLeft(2, '0')}';
  }

  String _fmtSize(int bytes) {
    if (bytes >= 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    if (bytes >= 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '$bytes B';
  }

  Future<void> _showDriveAuthDebugDialog(
    DriveAuthDiagnostic? diagnostic,
  ) async {
    if (kDebugMode && diagnostic != null) {
      debugPrint('drive_auth_likely_cause=${diagnostic.likelyCause}');
    }
  }

  @override
  Widget build(BuildContext context) {
    final signedIn = _email != null && _email!.trim().isNotEmpty;
    return Scaffold(
      appBar: AppBar(title: const AppTitle(subtitle: 'Google Drive')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                children: [
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'النسخ الاحتياطي على Google Drive',
                            style: TextStyle(fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 8),
                          if (!_isMobile)
                            const Text('متاح على Android/iOS فقط.')
                          else ...[
                            Text(
                              signedIn
                                  ? 'تم تسجيل الدخول: $_email'
                                  : 'غير مسجل الدخول',
                            ),
                            const SizedBox(height: 10),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                ElevatedButton.icon(
                                  onPressed: (_working || signedIn)
                                      ? null
                                      : _signIn,
                                  icon: const Icon(Icons.login),
                                  label: const Text('تسجيل الدخول'),
                                ),
                                OutlinedButton.icon(
                                  onPressed: (_working || !signedIn)
                                      ? null
                                      : _signOut,
                                  icon: const Icon(Icons.logout),
                                  label: const Text('تسجيل الخروج'),
                                ),
                                ElevatedButton.icon(
                                  onPressed: (_working || !signedIn)
                                      ? null
                                      : _uploadNow,
                                  icon: const Icon(Icons.cloud_upload),
                                  label: const Text('رفع نسخة الآن'),
                                ),
                                OutlinedButton.icon(
                                  onPressed: (_working || !signedIn)
                                      ? null
                                      : _restoreFromDrive,
                                  icon: const Icon(Icons.cloud_download),
                                  label: const Text('استرجاع من Drive'),
                                ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (_autoBackupDue)
                    Card(
                      color: Colors.amber.shade50,
                      child: const ListTile(
                        leading: Icon(Icons.notifications_active),
                        title: Text('حان وقت النسخ الاحتياطي'),
                        subtitle: Text('أدخل كلمة المرور لإنشاء نسخة مشفرة.'),
                      ),
                    ),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'النسخ المشفر',
                            style: TextStyle(fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 10),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              ElevatedButton.icon(
                                onPressed: (_working || !_isMobile)
                                    ? null
                                    : _createEncryptedBackup,
                                icon: const Icon(Icons.enhanced_encryption),
                                label: const Text('إنشاء نسخة احتياطية مشفرة'),
                              ),
                              OutlinedButton.icon(
                                onPressed: (_working || !signedIn)
                                    ? null
                                    : _refreshBackups,
                                icon: const Icon(Icons.refresh),
                                label: const Text('تحديث القائمة'),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          if (_backups.isEmpty)
                            const Text('لا توجد نسخ مشفرة معروضة.')
                          else
                            ..._backups.map(
                              (backup) => ListTile(
                                contentPadding: EdgeInsets.zero,
                                leading: const Icon(Icons.lock),
                                title: Text(_fmtDate(backup.createdAt)),
                                subtitle: Text(
                                  '${_fmtSize(backup.sizeBytes)} • مشفرة • '
                                  '${backup.appVersion}+${backup.buildNumber} • '
                                  '${backup.deviceName}'
                                  '${backup.note == null ? '' : '\n${backup.note}'}',
                                ),
                                trailing: OutlinedButton(
                                  onPressed: _working
                                      ? null
                                      : () => _restoreEncryptedBackup(backup),
                                  child: const Text('استعادة'),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'تذكير النسخ التلقائي',
                            style: TextStyle(fontWeight: FontWeight.w700),
                          ),
                          SwitchListTile(
                            contentPadding: EdgeInsets.zero,
                            value: _autoBackupSettings.enabled,
                            onChanged: _working
                                ? null
                                : (value) =>
                                      _saveAutoBackupSettings(enabled: value),
                            title: const Text('تفعيل تذكير النسخ الاحتياطي'),
                            subtitle: const Text(
                              'لن يتم تخزين كلمة المرور ولن يتم رفع نسخة في الخلفية.',
                            ),
                          ),
                          DropdownButtonFormField<AutoBackupFrequency>(
                            initialValue: _autoBackupSettings.frequency,
                            decoration: const InputDecoration(
                              labelText: 'التكرار',
                              border: OutlineInputBorder(),
                            ),
                            items: const [
                              DropdownMenuItem(
                                value: AutoBackupFrequency.daily,
                                child: Text('يومي'),
                              ),
                              DropdownMenuItem(
                                value: AutoBackupFrequency.weekly,
                                child: Text('أسبوعي'),
                              ),
                              DropdownMenuItem(
                                value: AutoBackupFrequency.monthly,
                                child: Text('شهري'),
                              ),
                            ],
                            onChanged: _working
                                ? null
                                : (value) {
                                    if (value != null) {
                                      _saveAutoBackupSettings(frequency: value);
                                    }
                                  },
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'الاستحقاق القادم: ${_fmtDate(_autoBackupSettings.nextDueAt(DateTime.now()))}',
                          ),
                          const SizedBox(height: 8),
                          OutlinedButton.icon(
                            onPressed: _working ? null : _createEncryptedBackup,
                            icon: const Icon(Icons.backup),
                            label: const Text('نسخ احتياطي الآن'),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Card(
                    child: Padding(
                      padding: EdgeInsets.all(12),
                      child: Text(
                        'ملاحظة: لتفعيل Google Drive بالكامل، يلزم إعداد OAuth '
                        'للأندرويد والآيفون (Client ID).',
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}
