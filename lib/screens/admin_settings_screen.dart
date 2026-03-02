import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:local_auth/local_auth.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import '../widgets/app_title.dart';
import '../data/app_db.dart';
import '../data/app_session.dart';
import '../models/license_info.dart';
import 'developer_gate_screen.dart';
import 'audit_log_screen.dart';
import 'sync_outbox_screen.dart';
import 'drive_backup_screen.dart';

class AdminSettingsScreen extends StatefulWidget {
  const AdminSettingsScreen({super.key});

  @override
  State<AdminSettingsScreen> createState() => _AdminSettingsScreenState();
}

class _AdminSettingsScreenState extends State<AdminSettingsScreen> {
  final _oldCtrl = TextEditingController();
  final _newCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();
  final _bizCtrl = TextEditingController();
  final _currencyCtrl = TextEditingController();
  final _activationCtrl = TextEditingController();

  bool _saving = false;
  bool _settingsSaving = false;
  bool _backupWorking = false;
  bool _healthWorking = false;
  bool _activating = false;
  bool _biometricSupported = false;
  bool _biometricEnabled = false;
  int _dayStartHour = 0;
  List<String> _quickActionsOrder = [];
  LicenseInfo? _license;
  SystemHealthSummary? _health;
  int _devTapCount = 0;
  DateTime? _lastDevTap;

  final _auth = LocalAuthentication();

  @override
  void initState() {
    super.initState();
    _loadBiometric();
    _loadSettings();
    _loadLicense();
    _loadHealth();
  }

  Future<void> _loadBiometric() async {
    try {
      final enabled = await AppDb.instance.getBiometricEnabled();
      final supported = await _auth.isDeviceSupported();
      final canCheck = await _auth.canCheckBiometrics;
      if (!mounted) return;
      setState(() {
        _biometricEnabled = enabled;
        _biometricSupported = supported || canCheck;
      });
    } catch (_) {}
  }

  Future<void> _loadSettings() async {
    try {
      final settings = await AppDb.instance.getAppSettings();
      if (!mounted) return;
      setState(() {
        _bizCtrl.text = settings.businessName;
        _currencyCtrl.text = settings.currency;
        _dayStartHour = settings.dayStartHour;
        _quickActionsOrder = settings.quickActionsOrder;
      });
    } catch (_) {}
  }

  Future<void> _loadLicense() async {
    try {
      final info = await AppDb.instance.getLicenseInfo();
      if (!mounted) return;
      setState(() => _license = info);
    } catch (_) {}
  }

  Future<void> _loadHealth() async {
    try {
      final health = await AppDb.instance.getSystemHealthSummary();
      if (!mounted) return;
      setState(() => _health = health);
    } catch (_) {}
  }

  String _fmtDateTime(DateTime? d) {
    if (d == null) return 'غير متوفر';
    final local = d.toLocal();
    final y = local.year.toString().padLeft(4, '0');
    final m = local.month.toString().padLeft(2, '0');
    final day = local.day.toString().padLeft(2, '0');
    final h = local.hour.toString().padLeft(2, '0');
    final min = local.minute.toString().padLeft(2, '0');
    return '$y-$m-$day $h:$min';
  }

  String _fmtSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    final kb = bytes / 1024;
    if (kb < 1024) return '${kb.toStringAsFixed(1)} KB';
    final mb = kb / 1024;
    return '${mb.toStringAsFixed(1)} MB';
  }

  Future<void> _runIntegrityNow() async {
    if (!AppSession.isAdmin) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('هذه الصفحة للأدمن فقط')));
      return;
    }
    setState(() => _healthWorking = true);
    try {
      final result = await AppDb.instance.runIntegrityCheck(force: true);
      await _loadHealth();
      if (!mounted) return;
      if (result.ok) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('فحص السلامة: سليم ✅')));
      } else {
        final first = result.issues.isEmpty
            ? 'تم اكتشاف مشاكل'
            : result.issues.first.message;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('فحص السلامة: $first')));
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('فشل فحص السلامة: $e')));
    } finally {
      if (mounted) setState(() => _healthWorking = false);
    }
  }

  Future<void> _repairIntegrityNow() async {
    if (!AppSession.isAdmin) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('هذه الصفحة للأدمن فقط')));
      return;
    }
    final ok = await _confirmDialog(
      title: 'إصلاح تلقائي',
      body:
          'سيتم إنشاء نسخة JSON احتياطية أولًا، ثم محاولة إصلاح مشاكل التكرار في المعرفات.',
      okText: 'ابدأ الإصلاح',
    );
    if (!ok) return;

    setState(() => _healthWorking = true);
    try {
      final result = await AppDb.instance.repairDuplicateIntegrityIssues(
        createJsonBackup: true,
      );
      await _loadHealth();
      if (!mounted) return;
      if (!result.changed) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('لا توجد مشاكل تكرار تحتاج إصلاحًا')),
        );
        return;
      }
      final totalFixed =
          result.walletsFixed +
          result.txnsFixed +
          result.claimsFixed +
          result.dailyClosesFixed;
      final status = result.after.ok
          ? 'والفحص بعد الإصلاح سليم ✅'
          : 'ولا تزال هناك مشاكل أخرى';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تم الإصلاح ($totalFixed) $status')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('فشل الإصلاح: $e')));
    } finally {
      if (mounted) setState(() => _healthWorking = false);
    }
  }

  Future<bool> _confirmDialog({
    required String title,
    required String body,
    required String okText,
  }) async {
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

  Future<void> _resetDatabase() async {
    if (!AppSession.isAdmin) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('هذه الصفحة للأدمن فقط')));
      return;
    }

    final ok = await _confirmDialog(
      title: 'تصفير البيانات (مع بيانات البداية)؟',
      body: 'سيتم حذف قاعدة البيانات ثم إنشاء بيانات بداية افتراضية.',
      okText: 'تصفير',
    );
    if (!ok) return;

    setState(() => _saving = true);
    try {
      await AppDb.instance.resetDatabase();
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('تم تصفير البيانات ✅')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('خطأ: $e')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _resetDatabaseEmpty() async {
    if (!AppSession.isAdmin) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('هذه الصفحة للأدمن فقط')));
      return;
    }

    final ok = await _confirmDialog(
      title: 'تصفير كامل بدون بيانات؟',
      body: 'سيتم حذف قاعدة البيانات بدون إنشاء أي بيانات بداية.',
      okText: 'تصفير كامل',
    );
    if (!ok) return;

    setState(() => _saving = true);
    try {
      await AppDb.instance.resetDatabaseEmpty();
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('تم التصفير الكامل ✅')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('خطأ: $e')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  void dispose() {
    _oldCtrl.dispose();
    _newCtrl.dispose();
    _confirmCtrl.dispose();
    _bizCtrl.dispose();
    _currencyCtrl.dispose();
    _activationCtrl.dispose();
    super.dispose();
  }

  void _handleDevTap() {
    final now = DateTime.now();
    if (_lastDevTap == null || now.difference(_lastDevTap!).inSeconds > 4) {
      _devTapCount = 0;
    }
    _lastDevTap = now;
    _devTapCount += 1;
    if (_devTapCount >= 7) {
      _devTapCount = 0;
      Navigator.of(
        context,
      ).push(MaterialPageRoute(builder: (_) => const DeveloperGateScreen()));
    }
  }

  Future<void> _activateLicense() async {
    if (!AppSession.isAdmin) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('هذه الصفحة للأدمن فقط')));
      return;
    }
    setState(() => _activating = true);
    try {
      final ok = await AppDb.instance.activateWithCode(_activationCtrl.text);
      if (!mounted) return;
      if (!ok) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('كود التفعيل غير صحيح')));
      } else {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('تم تفعيل البرنامج ✅')));
        _activationCtrl.clear();
        await _loadLicense();
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('خطأ: $e')));
    } finally {
      if (mounted) setState(() => _activating = false);
    }
  }

  Future<void> _savePin() async {
    if (!AppSession.isAdmin) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('هذه الصفحة للأدمن فقط')));
      return;
    }

    final newPin = _newCtrl.text.trim();
    final confirmPin = _confirmCtrl.text.trim();
    if (newPin != confirmPin) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('PIN الجديد غير مطابق')));
      return;
    }

    setState(() => _saving = true);
    try {
      final ok = await AppDb.instance.verifyAdminPin(_oldCtrl.text);
      if (!ok) throw Exception('PIN القديم غير صحيح');
      await AppDb.instance.setAdminPin(newPin);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('تم تغيير PIN ✅')));
      _oldCtrl.clear();
      _newCtrl.clear();
      _confirmCtrl.clear();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('خطأ: $e')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _saveSettings() async {
    if (!AppSession.isAdmin) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('هذه الصفحة للأدمن فقط')));
      return;
    }

    setState(() => _settingsSaving = true);
    try {
      final existing = await AppDb.instance.getAppSettings();
      final settings = existing.copyWith(
        businessName: _bizCtrl.text.trim(),
        currency: _currencyCtrl.text.trim(),
        dayStartHour: _dayStartHour,
        quickActionsOrder: _quickActionsOrder,
      );
      await AppDb.instance.setAppSettings(settings);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('تم حفظ الإعدادات ✅')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('خطأ: $e')));
    } finally {
      if (mounted) setState(() => _settingsSaving = false);
    }
  }

  Future<void> _backupToFile() async {
    if (!AppSession.isAdmin) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('هذه الصفحة للأدمن فقط')));
      return;
    }
    setState(() => _backupWorking = true);
    try {
      final path = await AppDb.instance.exportBackupToDownloads();
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('تم إنشاء نسخة احتياطية: $path')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('فشل النسخ الاحتياطي: $e')));
    } finally {
      if (mounted) setState(() => _backupWorking = false);
    }
  }

  Future<void> _backupToFolder() async {
    if (!AppSession.isAdmin) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('هذه الصفحة للأدمن فقط')));
      return;
    }
    final dir = await FilePicker.platform.getDirectoryPath();
    if (dir == null || dir.trim().isEmpty) return;
    setState(() => _backupWorking = true);
    try {
      final path = await AppDb.instance.exportBackupToPath(dir);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('تم حفظ النسخة: $path')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('فشل النسخ الاحتياطي: $e')));
    } finally {
      if (mounted) setState(() => _backupWorking = false);
    }
  }

  Future<void> _backupJsonToFile() async {
    if (!AppSession.isAdmin) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('هذه الصفحة للأدمن فقط')));
      return;
    }
    setState(() => _backupWorking = true);
    try {
      final path = await AppDb.instance.exportJsonBackupToDownloads();
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('تم إنشاء نسخة JSON: $path')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('فشل النسخ الاحتياطي: $e')));
    } finally {
      if (mounted) setState(() => _backupWorking = false);
    }
  }

  Future<void> _backupJsonToFolder() async {
    if (!AppSession.isAdmin) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('هذه الصفحة للأدمن فقط')));
      return;
    }
    final dir = await FilePicker.platform.getDirectoryPath();
    if (dir == null || dir.trim().isEmpty) return;
    setState(() => _backupWorking = true);
    try {
      final path = await AppDb.instance.exportJsonBackupToPath(dir);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('تم حفظ نسخة JSON: $path')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('فشل النسخ الاحتياطي: $e')));
    } finally {
      if (mounted) setState(() => _backupWorking = false);
    }
  }

  Future<String?> _resolvePickedFilePath(
    PlatformFile file, {
    required String extensionHint,
  }) async {
    final rawPath = file.path?.trim();
    if (rawPath != null &&
        rawPath.isNotEmpty &&
        !rawPath.toLowerCase().startsWith('content://')) {
      return rawPath;
    }

    Uint8List? bytes = file.bytes;
    if ((bytes == null || bytes.isEmpty) && file.readStream != null) {
      final builder = BytesBuilder(copy: false);
      await for (final chunk in file.readStream!) {
        builder.add(chunk);
      }
      bytes = builder.takeBytes();
    }
    if (bytes == null || bytes.isEmpty) return null;

    final tmpDir = await getTemporaryDirectory();
    final cleanName = (file.name.trim().isEmpty ? 'restore' : file.name.trim())
        .replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
    final hasExt = cleanName.contains('.');
    final name = hasExt ? cleanName : '$cleanName.$extensionHint';
    final out = File(
      '${tmpDir.path}/restore_${DateTime.now().millisecondsSinceEpoch}_$name',
    );
    await out.writeAsBytes(bytes, flush: true);
    return out.path;
  }

  bool _hasAllowedBackupExtension(
    PlatformFile file,
    List<String> allowedExtensions,
  ) {
    final name = file.name.toLowerCase();
    final path = (file.path ?? '').toLowerCase();
    for (final ext in allowedExtensions) {
      final dotExt = '.${ext.toLowerCase()}';
      if (name.endsWith(dotExt) || path.endsWith(dotExt)) {
        return true;
      }
    }
    return false;
  }

  Future<void> _restoreFromFile() async {
    if (!AppSession.isAdmin) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Admin only')));
      return;
    }

    final pick = await FilePicker.platform.pickFiles(
      type: FileType.any,
      withData: true,
      withReadStream: true,
    );
    if (pick == null || pick.files.isEmpty) return;
    final picked = pick.files.single;
    if (!_hasAllowedBackupExtension(picked, const [
      'db',
      'sqlite',
      'sqlite3',
    ])) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Selected file is not a database backup (.db/.sqlite/.sqlite3).',
          ),
        ),
      );
      return;
    }
    final sourcePath = picked.path?.trim();
    final path = await _resolvePickedFilePath(picked, extensionHint: 'db');
    final isTempRestoreFile =
        sourcePath == null ||
        sourcePath.isEmpty ||
        sourcePath.toLowerCase().startsWith('content://');
    if (path == null || path.trim().isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Cannot read backup file. Choose a local file and try again.',
          ),
        ),
      );
      return;
    }

    final ok = await _confirmDialog(
      title: 'Restore database backup?',
      body: 'Current data will be replaced by the selected backup file.',
      okText: 'Restore',
    );
    if (!ok) return;

    setState(() => _backupWorking = true);
    try {
      await AppDb.instance.restoreBackupFromPath(path);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Restore completed')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Restore failed: $e')));
    } finally {
      if (isTempRestoreFile) {
        try {
          await File(path).delete();
        } catch (_) {}
      }
      if (mounted) setState(() => _backupWorking = false);
    }
  }

  Future<void> _restoreFromJsonFile() async {
    if (!AppSession.isAdmin) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Admin only')));
      return;
    }

    final pick = await FilePicker.platform.pickFiles(
      type: FileType.any,
      withData: true,
      withReadStream: true,
    );
    if (pick == null || pick.files.isEmpty) return;
    final picked = pick.files.single;
    if (!_hasAllowedBackupExtension(picked, const ['json'])) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Selected file is not a JSON backup (.json).'),
        ),
      );
      return;
    }
    final sourcePath = picked.path?.trim();
    final path = await _resolvePickedFilePath(picked, extensionHint: 'json');
    final isTempRestoreFile =
        sourcePath == null ||
        sourcePath.isEmpty ||
        sourcePath.toLowerCase().startsWith('content://');
    if (path == null || path.trim().isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Cannot read JSON file. Choose a local JSON file and try again.',
          ),
        ),
      );
      return;
    }

    final ok = await _confirmDialog(
      title: 'Restore JSON backup?',
      body: 'Current data will be replaced by the selected JSON file.',
      okText: 'Restore',
    );
    if (!ok) return;

    setState(() => _backupWorking = true);
    try {
      await AppDb.instance.restoreJsonBackupFromPath(path);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Restore completed')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Restore failed: $e')));
    } finally {
      if (isTempRestoreFile) {
        try {
          await File(path).delete();
        } catch (_) {}
      }
      if (mounted) setState(() => _backupWorking = false);
    }
  }

  String _hourLabel(int h) => '${h.toString().padLeft(2, '0')}:00';
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: GestureDetector(
          onTap: _handleDevTap,
          child: const AppTitle(subtitle: 'إعدادات الأدمن'),
        ),
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 500),
            child: Column(
              children: [
                if (_license != null)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'ترخيص البرنامج',
                            style: TextStyle(fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            _license!.isActivated
                                ? 'الحالة: مفعّل ✅'
                                : 'الحالة: تجريبي (متبقي ${_license!.daysLeft} يوم)',
                          ),
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  'رمز الجهاز: ${_license!.deviceCode}',
                                ),
                              ),
                              IconButton(
                                tooltip: 'نسخ',
                                onPressed: () async {
                                  final messenger = ScaffoldMessenger.of(
                                    context,
                                  );
                                  await Clipboard.setData(
                                    ClipboardData(text: _license!.deviceCode),
                                  );
                                  if (!mounted) return;
                                  messenger.showSnackBar(
                                    const SnackBar(
                                      content: Text('تم نسخ رمز الجهاز'),
                                    ),
                                  );
                                },
                                icon: const Icon(Icons.copy),
                              ),
                            ],
                          ),
                          if (!_license!.isActivated) ...[
                            const SizedBox(height: 6),
                            Text(
                              'الحدود: محافظ ${_license!.maxWallets} • عمليات ${_license!.maxOperations} • تقارير ${_license!.maxReports}',
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'المتبقي: عمليات ${_license!.operationsLeft} • تقارير ${_license!.reportsLeft}',
                            ),
                            const SizedBox(height: 10),
                            TextField(
                              controller: _activationCtrl,
                              decoration: const InputDecoration(
                                labelText: 'كود التفعيل',
                              ),
                            ),
                            const SizedBox(height: 10),
                            ElevatedButton.icon(
                              onPressed: _activating ? null : _activateLicense,
                              icon: _activating
                                  ? const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Icon(Icons.verified),
                              label: const Text('تفعيل'),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                if (_health != null) ...[
                  const SizedBox(height: 12),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'صحة النظام',
                            style: TextStyle(fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'آخر نسخة: ${_fmtDateTime(_health!.lastBackupAt)}'
                            '${_health!.lastBackupType == null ? '' : ' • ${_health!.lastBackupType}'}',
                          ),
                          Text(
                            'حجم قاعدة البيانات: ${_fmtSize(_health!.databaseSizeBytes)}',
                          ),
                          Text('عمليات معلقة: ${_health!.pendingCount}'),
                          Text(
                            'آخر فحص: ${_fmtDateTime(_health!.lastIntegrityAt)}'
                            '${_health!.lastIntegrityOk == null ? '' : (_health!.lastIntegrityOk! ? ' • سليم ✅' : ' • يوجد مشاكل ⚠️')}',
                          ),
                          if ((_health!.lastIntegrityError ?? '')
                              .trim()
                              .isNotEmpty)
                            Text('تفاصيل: ${_health!.lastIntegrityError}'),
                          const SizedBox(height: 10),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              ElevatedButton.icon(
                                onPressed: _healthWorking
                                    ? null
                                    : _runIntegrityNow,
                                icon: _healthWorking
                                    ? const SizedBox(
                                        width: 16,
                                        height: 16,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : const Icon(Icons.verified_user),
                                label: const Text('تشغيل فحص السلامة الآن'),
                              ),
                              OutlinedButton.icon(
                                onPressed: _healthWorking
                                    ? null
                                    : _repairIntegrityNow,
                                icon: const Icon(Icons.build_circle_outlined),
                                label: const Text('إصلاح التكرارات تلقائيًا'),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'إعدادات عامة',
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: _bizCtrl,
                          decoration: const InputDecoration(
                            labelText: 'اسم النشاط',
                          ),
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: _currencyCtrl,
                          decoration: const InputDecoration(
                            labelText: 'العملة',
                          ),
                        ),
                        const SizedBox(height: 8),
                        DropdownButtonFormField<int>(
                          initialValue: _dayStartHour,
                          items: List.generate(
                            24,
                            (i) => DropdownMenuItem(
                              value: i,
                              child: Text(_hourLabel(i)),
                            ),
                          ),
                          onChanged: (v) {
                            if (v == null) return;
                            setState(() => _dayStartHour = v);
                          },
                          decoration: const InputDecoration(
                            labelText: 'بداية اليوم',
                          ),
                        ),
                        const SizedBox(height: 12),
                        ElevatedButton.icon(
                          onPressed: _settingsSaving ? null : _saveSettings,
                          icon: _settingsSaving
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.save),
                          label: const Text('حفظ الإعدادات'),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _oldCtrl,
                  obscureText: true,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'PIN القديم'),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _newCtrl,
                  obscureText: true,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'PIN الجديد (4 أرقام أو أكثر)',
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _confirmCtrl,
                  obscureText: true,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'تأكيد PIN الجديد',
                  ),
                ),
                const SizedBox(height: 16),
                ElevatedButton.icon(
                  onPressed: _saving ? null : _savePin,
                  icon: _saving
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.save),
                  label: const Text('حفظ PIN'),
                ),
                const SizedBox(height: 20),
                SwitchListTile(
                  value: _biometricEnabled,
                  onChanged: (!_biometricSupported || _saving)
                      ? null
                      : (v) async {
                          setState(() => _biometricEnabled = v);
                          await AppDb.instance.setBiometricEnabled(v);
                        },
                  title: const Text('تفعيل البصمة للأدمن'),
                  subtitle: Text(
                    _biometricSupported
                        ? 'يسمح بالدخول باستخدام البصمة/FaceID.'
                        : 'البصمة غير مدعومة على هذا الجهاز.',
                  ),
                ),
                const SizedBox(height: 12),
                const Divider(),
                const SizedBox(height: 12),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'تصفير البيانات',
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          'يحذف قاعدة البيانات المحلية ويعيد التطبيق للبداية.',
                        ),
                        const SizedBox(height: 10),
                        ElevatedButton.icon(
                          onPressed: _saving ? null : _resetDatabase,
                          icon: const Icon(Icons.delete_forever),
                          label: const Text('تصفير مع بيانات البداية'),
                        ),
                        const SizedBox(height: 8),
                        OutlinedButton.icon(
                          onPressed: _saving ? null : _resetDatabaseEmpty,
                          icon: const Icon(Icons.delete_sweep),
                          label: const Text('تصفير كامل بدون بيانات'),
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
                          'نسخ احتياطي/استعادة',
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          'يمكن حفظ نسخة قاعدة البيانات في التحميلات أو اختيار مجلد.',
                        ),
                        const SizedBox(height: 10),
                        ElevatedButton.icon(
                          onPressed: _backupWorking ? null : _backupToFile,
                          icon: const Icon(Icons.backup),
                          label: const Text('نسخة قاعدة البيانات (التحميلات)'),
                        ),
                        const SizedBox(height: 8),
                        OutlinedButton.icon(
                          onPressed: _backupWorking ? null : _backupToFolder,
                          icon: const Icon(Icons.folder_open),
                          label: const Text(
                            'نسخة قاعدة البيانات (اختيار مجلد)',
                          ),
                        ),
                        const SizedBox(height: 8),
                        OutlinedButton.icon(
                          onPressed: _backupWorking ? null : _restoreFromFile,
                          icon: const Icon(Icons.restore),
                          label: const Text('استعادة من ملف'),
                        ),
                        const SizedBox(height: 12),
                        const Divider(),
                        const Text('نسخة JSON'),
                        const SizedBox(height: 8),
                        ElevatedButton.icon(
                          onPressed: _backupWorking ? null : _backupJsonToFile,
                          icon: const Icon(Icons.backup),
                          label: const Text('نسخة JSON (التحميلات)'),
                        ),
                        const SizedBox(height: 8),
                        OutlinedButton.icon(
                          onPressed: _backupWorking
                              ? null
                              : _backupJsonToFolder,
                          icon: const Icon(Icons.folder_open),
                          label: const Text('نسخة JSON (اختيار مجلد)'),
                        ),
                        const SizedBox(height: 8),
                        OutlinedButton.icon(
                          onPressed: _backupWorking
                              ? null
                              : _restoreFromJsonFile,
                          icon: const Icon(Icons.restore),
                          label: const Text('استعادة من JSON'),
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
                          'Google Drive',
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 6),
                        const Text('نسخ احتياطي سحابي (يتطلب إعداد OAuth).'),
                        const SizedBox(height: 10),
                        ElevatedButton.icon(
                          onPressed: () {
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => const DriveBackupScreen(),
                              ),
                            );
                          },
                          icon: const Icon(Icons.cloud),
                          label: const Text('فتح إعدادات Drive'),
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
                          'سجل التدقيق',
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 6),
                        const Text('يعرض جميع التغييرات والعمليات الهامة.'),
                        const SizedBox(height: 10),
                        ElevatedButton.icon(
                          onPressed: () {
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => const AuditLogScreen(),
                              ),
                            );
                          },
                          icon: const Icon(Icons.receipt_long),
                          label: const Text('فتح سجل التدقيق'),
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
                          'المزامنة (جاهزية)',
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          'إدارة قائمة الإرسال عند توفر المزامنة لاحقًا.',
                        ),
                        const SizedBox(height: 10),
                        ElevatedButton.icon(
                          onPressed: () {
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => const SyncOutboxScreen(),
                              ),
                            );
                          },
                          icon: const Icon(Icons.sync_alt),
                          label: const Text('فتح شاشة المزامنة'),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
