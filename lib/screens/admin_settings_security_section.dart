part of 'admin_settings_screen.dart';

extension _AdminSettingsSecuritySection on _AdminSettingsScreenState {
  Future<void> _loadBiometric() async {
    try {
      final enabled = await _adminSecurity.getBiometricEnabled();
      final supported = await _auth.isDeviceSupported();
      final canCheck = await _auth.canCheckBiometrics;
      if (!mounted) return;
      _setMountedState(() {
        _biometricEnabled = enabled;
        _biometricSupported = supported || canCheck;
      });
    } catch (_) {}
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

    _setMountedState(() => _saving = true);
    try {
      final ok = await _adminSecurity.verifyAdminPin(_oldCtrl.text);
      if (!ok) throw Exception('PIN القديم غير صحيح');
      await _adminSecurity.setAdminPin(newPin);
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
      if (mounted) _setMountedState(() => _saving = false);
    }
  }
}
