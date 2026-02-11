import 'package:flutter/material.dart';
import 'package:local_auth/local_auth.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import '../widgets/app_title.dart';
import '../data/app_db.dart';
import '../data/app_session.dart';
import '../models/app_settings.dart';
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
  bool _activating = false;
  bool _biometricSupported = false;
  bool _biometricEnabled = false;
  int _dayStartHour = 0;
  List<String> _quickActionsOrder = [];
  LicenseInfo? _license;
  int _devTapCount = 0;
  DateTime? _lastDevTap;

  final _auth = LocalAuthentication();

  @override
  void initState() {
    super.initState();
    _loadBiometric();
    _loadSettings();
    _loadLicense();
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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('هذه الصفحة للأدمن فقط')),
      );
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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم تصفير البيانات ✅')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('خطأ: $e')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _resetDatabaseEmpty() async {
    if (!AppSession.isAdmin) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('هذه الصفحة للأدمن فقط')),
      );
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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم التصفير الكامل ✅')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('خطأ: $e')),
      );
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
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const DeveloperGateScreen()),
      );
    }
  }

  Future<void> _activateLicense() async {
    if (!AppSession.isAdmin) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('هذه الصفحة للأدمن فقط')),
      );
      return;
    }
    setState(() => _activating = true);
    try {
      final ok = await AppDb.instance.activateWithCode(_activationCtrl.text);
      if (!mounted) return;
      if (!ok) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('كود التفعيل غير صحيح')),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تم تفعيل البرنامج ✅')),
        );
        _activationCtrl.clear();
        await _loadLicense();
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('خطأ: $e')),
      );
    } finally {
      if (mounted) setState(() => _activating = false);
    }
  }

  Future<void> _savePin() async {
    if (!AppSession.isAdmin) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('هذه الصفحة للأدمن فقط')),
      );
      return;
    }

    final newPin = _newCtrl.text.trim();
    final confirmPin = _confirmCtrl.text.trim();
    if (newPin != confirmPin) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('PIN الجديد غير مطابق')),
      );
      return;
    }

    setState(() => _saving = true);
    try {
      final ok = await AppDb.instance.verifyAdminPin(_oldCtrl.text);
      if (!ok) throw Exception('PIN القديم غير صحيح');
      await AppDb.instance.setAdminPin(newPin);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم تغيير PIN ✅')),
      );
      _oldCtrl.clear();
      _newCtrl.clear();
      _confirmCtrl.clear();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('خطأ: $e')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _saveSettings() async {
    if (!AppSession.isAdmin) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('هذه الصفحة للأدمن فقط')),
      );
      return;
    }

    setState(() => _settingsSaving = true);
    try {
      final settings = AppSettings(
        businessName: _bizCtrl.text.trim(),
        currency: _currencyCtrl.text.trim(),
        dayStartHour: _dayStartHour,
        quickActionsOrder: _quickActionsOrder,
      );
      await AppDb.instance.setAppSettings(settings);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم حفظ الإعدادات ✅')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('خطأ: $e')),
      );
    } finally {
      if (mounted) setState(() => _settingsSaving = false);
    }
  }

  Future<void> _backupToFile() async {
    if (!AppSession.isAdmin) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('هذه الصفحة للأدمن فقط')),
      );
      return;
    }
    setState(() => _backupWorking = true);
    try {
      final path = await AppDb.instance.exportBackupToDownloads();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تم إنشاء نسخة احتياطية: $path')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('فشل النسخ الاحتياطي: $e')),
      );
    } finally {
      if (mounted) setState(() => _backupWorking = false);
    }
  }

  Future<void> _backupToFolder() async {
    if (!AppSession.isAdmin) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('هذه الصفحة للأدمن فقط')),
      );
      return;
    }
    final dir = await FilePicker.platform.getDirectoryPath();
    if (dir == null || dir.trim().isEmpty) return;
    setState(() => _backupWorking = true);
    try {
      final path = await AppDb.instance.exportBackupToPath(dir);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تم حفظ النسخة: $path')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('فشل النسخ الاحتياطي: $e')),
      );
    } finally {
      if (mounted) setState(() => _backupWorking = false);
    }
  }

  Future<void> _backupJsonToFile() async {
    if (!AppSession.isAdmin) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('هذه الصفحة للأدمن فقط')),
      );
      return;
    }
    setState(() => _backupWorking = true);
    try {
      final path = await AppDb.instance.exportJsonBackupToDownloads();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تم إنشاء نسخة JSON: $path')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('فشل النسخ الاحتياطي: $e')),
      );
    } finally {
      if (mounted) setState(() => _backupWorking = false);
    }
  }

  Future<void> _backupJsonToFolder() async {
    if (!AppSession.isAdmin) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('هذه الصفحة للأدمن فقط')),
      );
      return;
    }
    final dir = await FilePicker.platform.getDirectoryPath();
    if (dir == null || dir.trim().isEmpty) return;
    setState(() => _backupWorking = true);
    try {
      final path = await AppDb.instance.exportJsonBackupToPath(dir);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تم حفظ نسخة JSON: $path')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('فشل النسخ الاحتياطي: $e')),
      );
    } finally {
      if (mounted) setState(() => _backupWorking = false);
    }
  }

  Future<void> _restoreFromFile() async {
    if (!AppSession.isAdmin) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('هذه الصفحة للأدمن فقط')),
      );
      return;
    }

    final pick = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['db', 'sqlite'],
    );
    if (pick == null || pick.files.isEmpty) return;
    final path = pick.files.single.path;
    if (path == null || path.trim().isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تعذر قراءة مسار الملف')),
      );
      return;
    }

    final ok = await _confirmDialog(
      title: 'استعادة النسخة الاحتياطية؟',
      body: 'سيتم استبدال البيانات الحالية بالملف المختار.',
      okText: 'استعادة',
    );
    if (!ok) return;

    setState(() => _backupWorking = true);
    try {
      await AppDb.instance.restoreBackupFromPath(path);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تمت الاستعادة ✅')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('فشل الاستعادة: $e')),
      );
    } finally {
      if (mounted) setState(() => _backupWorking = false);
    }
  }

  Future<void> _restoreFromJsonFile() async {
    if (!AppSession.isAdmin) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('هذه الصفحة للأدمن فقط')),
      );
      return;
    }

    final pick = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['json'],
    );
    if (pick == null || pick.files.isEmpty) return;
    final path = pick.files.single.path;
    if (path == null || path.trim().isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تعذر قراءة مسار الملف')),
      );
      return;
    }

    final ok = await _confirmDialog(
      title: 'استعادة نسخة JSON؟',
      body: 'سيتم استبدال البيانات الحالية بالملف المختار.',
      okText: 'استعادة',
    );
    if (!ok) return;

    setState(() => _backupWorking = true);
    try {
      await AppDb.instance.restoreJsonBackupFromPath(path);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تمت الاستعادة ✅')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('فشل الاستعادة: $e')),
      );
    } finally {
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
                        const Text('ترخيص البرنامج', style: TextStyle(fontWeight: FontWeight.w700)),
                        const SizedBox(height: 6),
                        Text(
                          _license!.isActivated
                              ? 'الحالة: مفعّل ✅'
                              : 'الحالة: تجريبي (متبقي ${_license!.daysLeft} يوم)',
                        ),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            Expanded(child: Text('رمز الجهاز: ${_license!.deviceCode}')),
                            IconButton(
                              tooltip: 'نسخ',
                              onPressed: () async {
                                final messenger = ScaffoldMessenger.of(context);
                                await Clipboard.setData(ClipboardData(text: _license!.deviceCode));
                                if (!mounted) return;
                                messenger.showSnackBar(
                                  const SnackBar(content: Text('تم نسخ رمز الجهاز')),
                                );
                              },
                              icon: const Icon(Icons.copy),
                            ),
                          ],
                        ),
                        if (!_license!.isActivated) ...[
                          const SizedBox(height: 6),
                          Text('الحدود: محافظ ${_license!.maxWallets} • عمليات ${_license!.maxOperations} • تقارير ${_license!.maxReports}'),
                          const SizedBox(height: 6),
                          Text('المتبقي: عمليات ${_license!.operationsLeft} • تقارير ${_license!.reportsLeft}'),
                          const SizedBox(height: 10),
                          TextField(
                            controller: _activationCtrl,
                            decoration: const InputDecoration(labelText: 'كود التفعيل'),
                          ),
                          const SizedBox(height: 10),
                          ElevatedButton.icon(
                            onPressed: _activating ? null : _activateLicense,
                            icon: _activating
                                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                                : const Icon(Icons.verified),
                            label: const Text('تفعيل'),
                          ),
                        ],
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
                      const Text('إعدادات عامة', style: TextStyle(fontWeight: FontWeight.w700)),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _bizCtrl,
                        decoration: const InputDecoration(labelText: 'اسم النشاط'),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _currencyCtrl,
                        decoration: const InputDecoration(labelText: 'العملة'),
                      ),
                      const SizedBox(height: 8),
                      DropdownButtonFormField<int>(
                        initialValue: _dayStartHour,
                        items: List.generate(
                          24,
                          (i) => DropdownMenuItem(value: i, child: Text(_hourLabel(i))),
                        ),
                        onChanged: (v) {
                          if (v == null) return;
                          setState(() => _dayStartHour = v);
                        },
                        decoration: const InputDecoration(labelText: 'بداية اليوم'),
                      ),
                      const SizedBox(height: 12),
                      ElevatedButton.icon(
                        onPressed: _settingsSaving ? null : _saveSettings,
                        icon: _settingsSaving
                            ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
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
                decoration: const InputDecoration(labelText: 'PIN الجديد (4 أرقام أو أكثر)'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _confirmCtrl,
                obscureText: true,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'تأكيد PIN الجديد'),
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: _saving ? null : _savePin,
                icon: _saving
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
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
                      const Text('تصفير البيانات', style: TextStyle(fontWeight: FontWeight.w700)),
                      const SizedBox(height: 6),
                      const Text('يحذف قاعدة البيانات المحلية ويعيد التطبيق للبداية.'),
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
                      const Text('نسخ احتياطي/استعادة', style: TextStyle(fontWeight: FontWeight.w700)),
                      const SizedBox(height: 6),
                      const Text('يمكن حفظ نسخة قاعدة البيانات في التحميلات أو اختيار مجلد.'),
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
                        label: const Text('نسخة قاعدة البيانات (اختيار مجلد)'),
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
                        onPressed: _backupWorking ? null : _backupJsonToFolder,
                        icon: const Icon(Icons.folder_open),
                        label: const Text('نسخة JSON (اختيار مجلد)'),
                      ),
                      const SizedBox(height: 8),
                      OutlinedButton.icon(
                        onPressed: _backupWorking ? null : _restoreFromJsonFile,
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
                      const Text('Google Drive', style: TextStyle(fontWeight: FontWeight.w700)),
                      const SizedBox(height: 6),
                      const Text('نسخ احتياطي سحابي (يتطلب إعداد OAuth).'),
                      const SizedBox(height: 10),
                      ElevatedButton.icon(
                        onPressed: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(builder: (_) => const DriveBackupScreen()),
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
                      const Text('سجل التدقيق', style: TextStyle(fontWeight: FontWeight.w700)),
                      const SizedBox(height: 6),
                      const Text('يعرض جميع التغييرات والعمليات الهامة.'),
                      const SizedBox(height: 10),
                      ElevatedButton.icon(
                        onPressed: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(builder: (_) => const AuditLogScreen()),
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
                      const Text('المزامنة (جاهزية)', style: TextStyle(fontWeight: FontWeight.w700)),
                      const SizedBox(height: 6),
                      const Text('إدارة قائمة الإرسال عند توفر المزامنة لاحقًا.'),
                      const SizedBox(height: 10),
                      ElevatedButton.icon(
                        onPressed: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(builder: (_) => const SyncOutboxScreen()),
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
