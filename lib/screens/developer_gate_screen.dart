import 'package:flutter/material.dart';
import '../widgets/app_title.dart';
import '../data/app_db.dart';
import '../data/app_session.dart';
import 'developer_tools_screen.dart';

class DeveloperGateScreen extends StatefulWidget {
  const DeveloperGateScreen({super.key});

  @override
  State<DeveloperGateScreen> createState() => _DeveloperGateScreenState();
}

class _DeveloperGateScreenState extends State<DeveloperGateScreen> {
  final _pinCtrl = TextEditingController();
  bool _working = false;

  @override
  void dispose() {
    _pinCtrl.dispose();
    super.dispose();
  }

  Future<void> _enter() async {
    if (!AppSession.isAdmin) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('هذه الصفحة للأدمن فقط')),
      );
      return;
    }
    setState(() => _working = true);
    try {
      final ok = await AppDb.instance.verifyDeveloperPin(_pinCtrl.text);
      if (!mounted) return;
      if (!ok) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('PIN غير صحيح')),
        );
        return;
      }
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const DeveloperToolsScreen()),
      );
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const AppTitle(subtitle: 'بوابة المطور')),
      body: Center(
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
                    const Text('أدخل PIN المطور', style: TextStyle(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _pinCtrl,
                      obscureText: true,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'PIN المطور'),
                    ),
                    const SizedBox(height: 12),
                    ElevatedButton.icon(
                      onPressed: _working ? null : _enter,
                      icon: _working
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.lock_open),
                      label: const Text('دخول'),
                    ),
                    const SizedBox(height: 6),
                    const Text('الدخول مخفي ويُستخدم فقط للمالك.',
                        style: TextStyle(fontSize: 12)),
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
