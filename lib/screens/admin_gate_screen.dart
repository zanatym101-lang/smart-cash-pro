import 'package:flutter/material.dart';
import '../widgets/app_title.dart';
import 'package:flutter/foundation.dart';
import 'package:local_auth/local_auth.dart';
import '../core/branding.dart';
import '../data/app_db.dart';
import '../data/app_session.dart';
import '../widgets/brand_logo.dart';
import 'dashboard_screen.dart';

class AdminGateScreen extends StatefulWidget {
  const AdminGateScreen({super.key});

  @override
  State<AdminGateScreen> createState() => _AdminGateScreenState();
}

class _AdminGateScreenState extends State<AdminGateScreen> {
  bool _loading = true;
  final _pinCtrl = TextEditingController();
  final _auth = LocalAuthentication();
  bool _biometricAvailable = false;
  bool _biometricEnabled = false;
  SecureRestoreStatus _pinStatus = const SecureRestoreStatus(
    failedAttempts: 0,
    maxAttempts: 5,
    remainingAttempts: 5,
    lockedUntil: null,
    locked: false,
  );

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      // Ensures settings file exists (default PIN = 1234)
      await AppDb.instance.getAdminPin();
      _pinStatus = await AppDb.instance.getAdminPinStatus();
      _biometricEnabled = await AppDb.instance.getBiometricEnabled();
      final supported = await _auth.isDeviceSupported();
      final canCheck = await _auth.canCheckBiometrics;
      _biometricAvailable = _biometricEnabled && (supported || canCheck);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('خطأ في تهيئة الدخول: $e')));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _minutesLabel(Duration d) {
    final mins = d.inMinutes + ((d.inSeconds % 60) > 0 ? 1 : 0);
    return mins <= 0 ? '1' : mins.toString();
  }

  Future<void> _refreshPinStatus() async {
    final status = await AppDb.instance.getAdminPinStatus();
    if (!mounted) return;
    setState(() => _pinStatus = status);
  }

  @override
  void dispose() {
    _pinCtrl.dispose();
    super.dispose();
  }

  void _enterUser() {
    AppSession.enterUser();
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const DashboardScreen()),
    );
  }

  Future<void> _enterAdmin() async {
    try {
      await _refreshPinStatus();
      if (_pinStatus.locked && _pinStatus.lockedUntil != null) {
        final left = _pinStatus.lockedUntil!.difference(DateTime.now());
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'تم قفل الإدخال مؤقتًا. حاول بعد ${_minutesLabel(left)} دقيقة.',
            ),
          ),
        );
        return;
      }

      final ok = await AppDb.instance.verifyAdminPin(_pinCtrl.text);
      await _refreshPinStatus();
      if (!mounted) return;

      if (!ok) {
        if (_pinStatus.locked && _pinStatus.lockedUntil != null) {
          final left = _pinStatus.lockedUntil!.difference(DateTime.now());
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'تم قفل الإدخال مؤقتًا. حاول بعد ${_minutesLabel(left)} دقيقة.',
              ),
            ),
          );
        } else {
          final remaining = _pinStatus.remainingAttempts;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('PIN غير صحيح. المتبقي: $remaining')),
          );
        }
        return;
      }

      AppSession.enterAdmin();
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const DashboardScreen()),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('خطأ أثناء التحقق من PIN: $e')));
    }
  }

  Future<void> _enterAdminBiometric() async {
    if (!_biometricAvailable) return;
    try {
      final ok = await _auth.authenticate(
        localizedReason: 'الدخول إلى وضع الأدمن',
        options: const AuthenticationOptions(
          biometricOnly: true,
          stickyAuth: true,
        ),
      );
      if (!mounted) return;
      if (!ok) return;
      AppSession.enterAdmin();
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const DashboardScreen()),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('تعذر استخدام البصمة: $e')));
    }
  }

  Future<void> _resetPinToDefault() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('إعادة تعيين PIN'),
        content: const Text(
          'سيتم ضبط PIN الأدمن إلى 1234.\n\n'
          'ملاحظة: زر تجريبي أثناء التطوير.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('تأكيد'),
          ),
        ],
      ),
    );

    if (ok != true) return;

    try {
      await AppDb.instance.setAdminPin('1234');
      await _refreshPinStatus();
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('تم ضبط PIN إلى 1234 ✅')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('فشل إعادة التعيين: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const AppTitle(subtitle: 'بوابة الأدمن')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Image.asset(
                            AppBranding.logoFullAsset,
                            width: 220,
                            fit: BoxFit.contain,
                            errorBuilder: (context, error, stackTrace) =>
                                const BrandLogo(size: 90),
                          ),
                          const SizedBox(height: 10),
                          Text(
                            AppBranding.nameAr,
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          Text(
                            AppBranding.nameEn,
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.black.withValues(alpha: 0.6),
                              fontWeight: FontWeight.w600,
                              letterSpacing: 0.8,
                            ),
                          ),
                          const SizedBox(height: 12),
                          const Text(
                            'اختر وضع الدخول',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 12),
                          ElevatedButton.icon(
                            icon: const Icon(Icons.person),
                            label: const Text('دخول كمستخدم'),
                            onPressed: _enterUser,
                          ),
                          const SizedBox(height: 14),
                          const Divider(),
                          const SizedBox(height: 10),
                          TextField(
                            controller: _pinCtrl,
                            obscureText: true,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: 'PIN الأدمن',
                              prefixIcon: Icon(Icons.lock),
                              hintText: 'افتراضي: 1234',
                            ),
                          ),
                          const SizedBox(height: 10),
                          ElevatedButton.icon(
                            icon: const Icon(Icons.verified_user),
                            label: const Text('دخول كأدمن'),
                            onPressed: _enterAdmin,
                          ),
                          if (_biometricAvailable) ...[
                            const SizedBox(height: 8),
                            OutlinedButton.icon(
                              icon: const Icon(Icons.fingerprint),
                              label: const Text('دخول بالبصمة'),
                              onPressed: _enterAdminBiometric,
                            ),
                          ],
                          if (kDebugMode) ...[
                            const SizedBox(height: 6),
                            TextButton.icon(
                              onPressed: _resetPinToDefault,
                              icon: const Icon(Icons.restart_alt),
                              label: const Text(
                                'إعادة تعيين PIN إلى 1234 (تجريبي)',
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
    );
  }
}
