import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:local_auth/local_auth.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import '../widgets/app_title.dart';
import '../data/app_db.dart';
import '../data/app_session.dart';
import '../models/license_info.dart';
import '../services/admin_security_service.dart';
import 'developer_gate_screen.dart';
import 'audit_log_screen.dart';
import 'sync_outbox_screen.dart';
import 'drive_backup_screen.dart';

part 'admin_settings_backup_section.dart';
part 'admin_settings_maintenance_section.dart';
part 'admin_settings_screen_sections.dart';
part 'admin_settings_security_section.dart';

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
  final _adminSecurity = AdminSecurityService.instance;

  @override
  void initState() {
    super.initState();
    _loadBiometric();
    _loadSettings();
    _loadLicense();
    _loadHealth();
  }

  void _setMountedState(VoidCallback fn) {
    if (mounted) setState(fn);
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
                          Text('عمليات آجلة: ${_health!.pendingCount}'),
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
                          await _adminSecurity.setBiometricEnabled(v);
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
                        const SizedBox(height: 10),
                        const Divider(),
                        const SizedBox(height: 6),
                        const Text(
                          'استرجاع ذكي (آخر نسختين محليًا)',
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),
                        _smartLocalRestoreSection(),
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
