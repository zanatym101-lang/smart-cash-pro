import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:share_plus/share_plus.dart';

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

  // Cloud Code Generator Controllers
  final _customCodeCtrl = TextEditingController();
  final _customDaysCtrl = TextEditingController(text: '30');
  final _customDevicesCtrl = TextEditingController(text: '1');
  int _selectedDays = 30;
  int _selectedMaxDevices = 1;
  bool _generatingCode = false;
  String? _lastGeneratedCode;

  bool _working = false;

  @override
  void dispose() {
    _oldPinCtrl.dispose();
    _newPinCtrl.dispose();
    _confirmPinCtrl.dispose();
    _customCodeCtrl.dispose();
    _customDaysCtrl.dispose();
    _customDevicesCtrl.dispose();
    super.dispose();
  }

  String _generateRandomCode([int length = 8]) {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final rnd = Random.secure();
    return List.generate(length, (_) => chars[rnd.nextInt(chars.length)]).join();
  }

  Future<void> _createCloudActivationCode() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تنبيه: يُفضل تسجيل الدخول السحابي أولاً بالأدمن zanatym101@gmail.com')),
      );
    }

    final code = _customCodeCtrl.text.trim().isNotEmpty
        ? _customCodeCtrl.text.trim().toUpperCase()
        : 'KW-${_generateRandomCode(4)}-${_generateRandomCode(4)}';

    final days = int.tryParse(_customDaysCtrl.text.trim()) ?? _selectedDays;
    final maxDevices = int.tryParse(_customDevicesCtrl.text.trim()) ?? _selectedMaxDevices;

    setState(() => _generatingCode = true);
    try {
      final codeRef = FirebaseFirestore.instance.collection('activation_codes').doc(code);
      final snap = await codeRef.get();
      if (snap.exists) {
        throw Exception('هذا الكود موجود بالفعل في السيرفر');
      }

      await codeRef.set({
        'days': days,
        'maxDevices': maxDevices,
        'usedDevices': [],
        'usedCount': 0,
        'isUsed': false,
        'createdAt': FieldValue.serverTimestamp(),
        'createdBy': user?.email ?? 'admin',
      });

      if (!mounted) return;
      setState(() {
        _lastGeneratedCode = code;
        _customCodeCtrl.clear();
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: const Color(0xFF047857),
          content: Text('✅ تم توليد الكود السحابي: $code ($maxDevices أجهزة - $days يوم)'),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: const Color(0xFFB91C1C),
          content: Text('خطأ أثناء إنشاء الكود: $e'),
        ),
      );
    } finally {
      if (mounted) setState(() => _generatingCode = false);
    }
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
      appBar: AppBar(title: const AppTitle(subtitle: 'أدوات المطور وتوليد الأكواد')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          // Developer VIP Status Badge
          if (_showLegacyCodeGenerator) ...[
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF0F172A), Color(0xFF1E293B)],
                  begin: Alignment.topRight,
                  end: Alignment.bottomLeft,
                ),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                children: const [
                  Icon(Icons.workspace_premium, color: Color(0xFFFBBF24), size: 28),
                  SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'نسخة الأدمن والمطور: مفعلة دائماً بصلاحيات غير محدودة 👑',
                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
          ],

          // Cloud Code Generator Card
          Card(
            color: const Color(0xFFF8FAFC),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: const BorderSide(color: Color(0xFFCBD5E1)),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: const [
                      Icon(Icons.cloud_done, color: Color(0xFF0284C7), size: 24),
                      SizedBox(width: 8),
                      Text(
                        'مولد أكواد التفعيل السحابية',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  const Text('مدة التفعيل:', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [30, 90, 180, 365].map((d) {
                      final sel = _selectedDays == d;
                      return ChoiceChip(
                        label: Text('$d يوم'),
                        selected: sel,
                        onSelected: (val) {
                          if (val) {
                            setState(() {
                              _selectedDays = d;
                              _customDaysCtrl.text = d.toString();
                            });
                          }
                        },
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 12),
                  const Text('عدد الأجهزة المسموحة للكود (Max Devices):', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [1, 2, 3, 5].map((dev) {
                      final sel = _selectedMaxDevices == dev;
                      return ChoiceChip(
                        label: Text(dev == 1 ? 'جهاز واحد' : '$dev أجهزة'),
                        selected: sel,
                        onSelected: (val) {
                          if (val) {
                            setState(() {
                              _selectedMaxDevices = dev;
                              _customDevicesCtrl.text = dev.toString();
                            });
                          }
                        },
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _customDaysCtrl,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'الأيام',
                            isDense: true,
                            border: OutlineInputBorder(),
                          ),
                          onChanged: (v) {
                            final parsed = int.tryParse(v);
                            if (parsed != null) setState(() => _selectedDays = parsed);
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: _customDevicesCtrl,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'الأجهزة',
                            isDense: true,
                            border: OutlineInputBorder(),
                          ),
                          onChanged: (v) {
                            final parsed = int.tryParse(v);
                            if (parsed != null) setState(() => _selectedMaxDevices = parsed);
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        flex: 2,
                        child: TextField(
                          controller: _customCodeCtrl,
                          decoration: const InputDecoration(
                            labelText: 'كود مخصص (اختياري)',
                            hintText: 'توليد تلقائي',
                            isDense: true,
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _generatingCode ? null : _createCloudActivationCode,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF0284C7),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      icon: _generatingCode
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          : const Icon(Icons.add_task),
                      label: const Text('توليد وحفظ الكود في السيرفر', style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                  ),
                  if (_lastGeneratedCode != null) ...[
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFECFDF5),
                        border: Border.all(color: const Color(0xFF10B981)),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        children: [
                          const Text('الكود الأخير الذي تم توليده في السيرفر:', style: TextStyle(fontSize: 12, color: Color(0xFF065F46))),
                          const SizedBox(height: 4),
                          SelectableText(
                            _lastGeneratedCode!,
                            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Color(0xFF047857), letterSpacing: 2),
                          ),
                          const SizedBox(height: 8),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              OutlinedButton.icon(
                                onPressed: () {
                                  Clipboard.setData(ClipboardData(text: _lastGeneratedCode!));
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(content: Text('تم نسخ الكود للحافظة')),
                                  );
                                },
                                icon: const Icon(Icons.copy, size: 16),
                                label: const Text('نسخ الكود'),
                              ),
                              const SizedBox(width: 8),
                              ElevatedButton.icon(
                                onPressed: () {
                                  // ignore: deprecated_member_use
                                  Share.share(
                                    'كود تفعيل Smart Cash Pro:\n$_lastGeneratedCode\nلمدة $_selectedDays يوم على $_selectedMaxDevices أجهزة.',
                                  );
                                },
                                icon: const Icon(Icons.share, size: 16),
                                label: const Text('إرسال للعميل'),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Live Cloud Codes List Card
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: const [
                      Icon(Icons.devices, color: Color(0xFF475569)),
                      SizedBox(width: 8),
                      Text(
                        'الأكواد المحفوظة وحالة الأجهزة (Live)',
                        style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  StreamBuilder<QuerySnapshot>(
                    stream: FirebaseFirestore.instance
                        .collection('activation_codes')
                        .orderBy('createdAt', descending: true)
                        .limit(20)
                        .snapshots(),
                    builder: (context, snapshot) {
                      if (snapshot.hasError) {
                        return Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFEF2F2),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text('حالة السحابة: سجل دخول بحسابك الأدمن لرؤية الأكواد (${snapshot.error})', style: const TextStyle(fontSize: 12, color: Colors.red)),
                        );
                      }
                      if (!snapshot.hasData) {
                        return const Center(
                          child: Padding(
                            padding: EdgeInsets.all(16),
                            child: CircularProgressIndicator(),
                          ),
                        );
                      }
                      final docs = snapshot.data!.docs;
                      if (docs.isEmpty) {
                        return const Padding(
                          padding: EdgeInsets.all(12),
                          child: Text('لا توجد أكواد منشأة في السيرفر حتى الآن', style: TextStyle(color: Colors.grey)),
                        );
                      }
                      return ListView.separated(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: docs.length,
                        separatorBuilder: (context, index) => const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final doc = docs[index];
                          final data = doc.data() as Map<String, dynamic>? ?? {};
                          final isUsed = data['isUsed'] == true;
                          final days = data['days'] ?? 30;
                          final maxDev = data['maxDevices'] ?? 1;
                          final rawDevList = data['usedDevices'] as List<dynamic>? ?? [];
                          final usedCount = rawDevList.length;
                          final code = doc.id;

                          final isFull = usedCount >= maxDev || isUsed;
                          final isPartial = usedCount > 0 && usedCount < maxDev;

                          return ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: Icon(
                              isFull
                                  ? Icons.lock
                                  : isPartial
                                      ? Icons.phone_android
                                      : Icons.check_circle,
                              color: isFull
                                  ? const Color(0xFFDC2626)
                                  : isPartial
                                      ? const Color(0xFFD97706)
                                      : const Color(0xFF16A34A),
                            ),
                            title: SelectableText(
                              code,
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                decoration: isFull ? TextDecoration.lineThrough : null,
                              ),
                            ),
                            subtitle: Text(
                              isFull
                                  ? '🔴 ممتلئ ($usedCount/$maxDev أجهزة) | $days يوم'
                                  : isPartial
                                      ? '🟡 مفعل جزئياً ($usedCount/$maxDev أجهزة) | $days يوم'
                                      : '🟢 متاح بالكامل (0/$maxDev أجهزة) | $days يوم',
                              style: TextStyle(
                                fontSize: 12,
                                color: isFull
                                    ? const Color(0xFFDC2626)
                                    : isPartial
                                        ? const Color(0xFFD97706)
                                        : const Color(0xFF16A34A),
                              ),
                            ),
                            trailing: IconButton(
                              icon: const Icon(Icons.copy, size: 18),
                              tooltip: 'نسخ الكود',
                              onPressed: () {
                                Clipboard.setData(ClipboardData(text: code));
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text('تم نسخ الكود: $code')),
                                );
                              },
                            ),
                          );
                        },
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Developer PIN Management Card
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
