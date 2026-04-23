part of 'admin_settings_screen.dart';

extension _AdminSettingsScreenSections on _AdminSettingsScreenState {
  Future<void> _loadSettings() async {
    try {
      final settings = await AppDb.instance.getAppSettings();
      if (!mounted) return;
      _setMountedState(() {
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
      _setMountedState(() => _license = info);
    } catch (_) {}
  }

  Future<void> _loadHealth() async {
    try {
      final health = await AppDb.instance.getSystemHealthSummary();
      if (!mounted) return;
      _setMountedState(() => _health = health);
    } catch (_) {}
  }

  Future<void> _activateLicense() async {
    if (!AppSession.isAdmin) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('هذه الصفحة للأدمن فقط')));
      return;
    }
    _setMountedState(() => _activating = true);
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
      if (mounted) _setMountedState(() => _activating = false);
    }
  }

  Future<void> _saveSettings() async {
    if (!AppSession.isAdmin) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('هذه الصفحة للأدمن فقط')));
      return;
    }

    _setMountedState(() => _settingsSaving = true);
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
      if (mounted) _setMountedState(() => _settingsSaving = false);
    }
  }

  String _hourLabel(int h) => '${h.toString().padLeft(2, '0')}:00';
}
