import 'package:flutter/material.dart';
import '../widgets/app_title.dart';
import 'package:flutter/services.dart';
import '../data/app_db.dart';
import '../data/app_session.dart';

class DeveloperToolsScreen extends StatefulWidget {
  const DeveloperToolsScreen({super.key});

  @override
  State<DeveloperToolsScreen> createState() => _DeveloperToolsScreenState();
}

class _DeveloperToolsScreenState extends State<DeveloperToolsScreen> {
  final _deviceCtrl = TextEditingController();
  final _oldPinCtrl = TextEditingController();
  final _newPinCtrl = TextEditingController();
  final _confirmPinCtrl = TextEditingController();

  String _code = '';
  bool _working = false;

  @override
  void dispose() {
    _deviceCtrl.dispose();
    _oldPinCtrl.dispose();
    _newPinCtrl.dispose();
    _confirmPinCtrl.dispose();
    super.dispose();
  }

  void _generate() {
    final code = AppDb.instance.generateActivationCodeForDeviceCode(_deviceCtrl.text);
    setState(() => _code = code);
  }

  Future<void> _copyCode() async {
    final messenger = ScaffoldMessenger.of(context);
    await Clipboard.setData(ClipboardData(text: _code));
    if (!mounted) return;
    messenger.showSnackBar(const SnackBar(content: Text('تم نسخ كود التفعيل')));
  }

  Future<void> _changePin() async {
    if (!AppSession.isAdmin) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('هذه الصفحة للأدمن فقط')),
      );
      return;
    }
    final newPin = _newPinCtrl.text.trim();
    final confirmPin = _confirmPinCtrl.text.trim();
    if (newPin != confirmPin) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('PIN الجديد غير مطابق')),
      );
      return;
    }
    setState(() => _working = true);
    try {
      final ok = await AppDb.instance.verifyDeveloperPin(_oldPinCtrl.text);
      if (!ok) throw Exception('PIN القديم غير صحيح');
      await AppDb.instance.setDeveloperPin(newPin);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم تغيير PIN المطور ✅')),
      );
      _oldPinCtrl.clear();
      _newPinCtrl.clear();
      _confirmPinCtrl.clear();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('خطأ: $e')),
      );
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
                    'مولد أكواد التفعيل\nللاستخدام الداخلي فقط',
                    style: TextStyle(color: Colors.white),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('توليد كود تفعيل', style: TextStyle(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _deviceCtrl,
                    decoration: const InputDecoration(labelText: 'رمز الجهاز'),
                  ),
                  const SizedBox(height: 10),
                  ElevatedButton.icon(
                    onPressed: _generate,
                    icon: const Icon(Icons.auto_fix_high),
                    label: const Text('توليد'),
                  ),
                  if (_code.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(child: Text('الكود: $_code')),
                        IconButton(
                          onPressed: _copyCode,
                          icon: const Icon(Icons.copy),
                          tooltip: 'نسخ',
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('تغيير PIN المطور', style: TextStyle(fontWeight: FontWeight.w700)),
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
                    decoration: const InputDecoration(labelText: 'PIN الجديد (4 أرقام أو أكثر)'),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _confirmPinCtrl,
                    obscureText: true,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'تأكيد PIN الجديد'),
                  ),
                  const SizedBox(height: 10),
                  ElevatedButton.icon(
                    onPressed: _working ? null : _changePin,
                    icon: _working
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
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
