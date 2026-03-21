import 'package:flutter/material.dart';

import '../data/app_db.dart';
import '../data/app_session.dart';
import '../widgets/app_title.dart';

class DeveloperToolsScreen extends StatefulWidget {
  const DeveloperToolsScreen({super.key});

  @override
  State<DeveloperToolsScreen> createState() => _DeveloperToolsScreenState();
}

class _DeveloperToolsScreenState extends State<DeveloperToolsScreen> {
  static const bool _showLegacyCodeGenerator = bool.fromEnvironment(
    'SHOW_LEGACY_CODE_GENERATOR',
    defaultValue: false,
  );

  final _oldPinCtrl = TextEditingController();
  final _newPinCtrl = TextEditingController();
  final _confirmPinCtrl = TextEditingController();

  bool _working = false;

  @override
  void dispose() {
    _oldPinCtrl.dispose();
    _newPinCtrl.dispose();
    _confirmPinCtrl.dispose();
    super.dispose();
  }

  Future<void> _changePin() async {
    if (!AppSession.isAdmin) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('هذه الصفحة للأدمن فقط')));
      return;
    }

    final newPin = _newPinCtrl.text.trim();
    final confirmPin = _confirmPinCtrl.text.trim();
    if (newPin != confirmPin) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('PIN الجديد غير مطابق')));
      return;
    }

    setState(() => _working = true);
    try {
      final ok = await AppDb.instance.verifyDeveloperPin(_oldPinCtrl.text);
      if (!ok) throw Exception('PIN القديم غير صحيح');

      await AppDb.instance.setDeveloperPin(newPin);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('تم تغيير PIN المطور ✅')));
      _oldPinCtrl.clear();
      _newPinCtrl.clear();
      _confirmPinCtrl.clear();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('خطأ: $e')));
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const AppTitle(subtitle: 'أدوات المطور')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          if (_showLegacyCodeGenerator) ...[
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF0F172A), Color(0xFF1E293B)],
                  begin: Alignment.topRight,
                  end: Alignment.bottomLeft,
                ),
                borderRadius: BorderRadius.circular(22),
              ),
              child: Row(
                children: const [
                  Icon(Icons.key, color: Colors.white, size: 32),
                  SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'مولد أكواد التفعيل المحلي مفعّل لهذه النسخة الداخلية فقط',
                      style: TextStyle(color: Colors.white),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
          ],
          if (!_showLegacyCodeGenerator) ...[
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFFE7F5FF),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFFB6E0FE)),
              ),
              child: const Text(
                'التفعيل الآن سحابي من السيرفر.\nمولد الأكواد المحلي مخفي في هذه النسخة.',
              ),
            ),
            const SizedBox(height: 12),
          ],
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'تغيير PIN المطور',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _oldPinCtrl,
                    obscureText: true,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'PIN الحالي'),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _newPinCtrl,
                    obscureText: true,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'PIN الجديد (4 أرقام أو أكثر)',
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _confirmPinCtrl,
                    obscureText: true,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'تأكيد PIN الجديد',
                    ),
                  ),
                  const SizedBox(height: 10),
                  ElevatedButton.icon(
                    onPressed: _working ? null : _changePin,
                    icon: _working
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.save),
                    label: const Text('حفظ PIN المطور'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
