import 'package:flutter/material.dart';
import '../widgets/app_title.dart';
import 'package:url_launcher/url_launcher.dart';
import 'privacy_policy_screen.dart';

class HelpScreen extends StatelessWidget {
  const HelpScreen({super.key});

  Future<void> _openWhatsApp(BuildContext context) async {
    final uri = Uri.parse(
      'https://wa.me/201223361572?text=مرحبا%20،%20أرغب%20في%20التواصل%20بخصوص%20التطبيق',
    );
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('تعذر فتح واتساب')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const AppTitle(subtitle: 'المساعدة')),
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
                Icon(Icons.help_outline, color: Colors.white, size: 32),
                SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'دليل سريع لاستخدام التطبيق\nعمليات واضحة + حسابات دقيقة',
                    style: TextStyle(color: Colors.white),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _sectionCard(
            context,
            title: 'الوظائف الأساسية',
            child: Column(
              children: const [
                ListTile(
                  leading: Icon(Icons.swap_horiz),
                  title: Text('تحويل'),
                  subtitle: Text('خصم من المحفظة + تأثير على الدرج حسب النوع.'),
                ),
                ListTile(
                  leading: Icon(Icons.call_received),
                  title: Text('استلام'),
                  subtitle: Text('يزيد المحفظة ويؤثر على الدرج حسب النوع.'),
                ),
                /* ListTile(
                  leading: Icon(Icons.bolt),
                  title: Text('خدمات فوري'),
                  subtitle: Text(
                    'نقدي أو آجل مع ربح واضح، والآجل يفتح مستحقات.',
                  ),
                ), */
                ListTile(
                  leading: Icon(Icons.request_quote),
                  title: Text('المستحقات'),
                  subtitle: Text(
                    'مبالغ لنا/علينا تظل مفتوحة حتى التحصيل/السداد.',
                  ),
                ),
                ListTile(
                  leading: Icon(Icons.account_balance_wallet),
                  title: Text('المحافظ'),
                  subtitle: Text('إدارة المحافظ وأرصدة التحويل.'),
                ),
                ListTile(
                  leading: Icon(Icons.account_balance),
                  title: Text('الخزنة'),
                  subtitle: Text('يعرض الدرج والمحافظ وإجمالي السيولة.'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _sectionCard(
            context,
            title: 'صلاحيات وأمان',
            child: Column(
              children: const [
                ListTile(
                  leading: Icon(Icons.verified_user),
                  title: Text('أدمن / مستخدم'),
                  subtitle: Text(
                    'المستخدم العادي ينشئ عمليات آجلة، والأدمن يعتمدها.',
                  ),
                ),
                ListTile(
                  leading: Icon(Icons.lock),
                  title: Text('PIN / بصمة (للأدمن)'),
                  subtitle: Text('حماية للدخول وتنفيذ الاعتماد.'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _sectionCard(
            context,
            title: 'التقارير والنسخ الاحتياطي',
            child: Column(
              children: const [
                ListTile(
                  leading: Icon(Icons.analytics),
                  title: Text('تقارير الأرباح/الخزنة/المستحقات'),
                  subtitle: Text('متاحة للأدمن داخل الفترة المختارة.'),
                ),
                ListTile(
                  leading: Icon(Icons.backup),
                  title: Text('نسخ احتياطي واستعادة'),
                  subtitle: Text('نسخة قاعدة البيانات أو JSON إلى ملف.'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _sectionCard(
            context,
            title: 'التفعيل والترخيص',
            child: Column(
              children: const [
                ListTile(
                  leading: Icon(Icons.key),
                  title: Text('رمز الجهاز'),
                  subtitle: Text(
                    'يظهر في إعدادات الأدمن. أرسله لتلقي كود التفعيل.',
                  ),
                ),
                ListTile(
                  leading: Icon(Icons.offline_bolt),
                  title: Text('التطبيق يعمل Offline'),
                  subtitle: Text('كل البيانات محفوظة محليًا على الجهاز.'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _sectionCard(
            context,
            title: 'روابط مهمة',
            child: Column(
              children: [
                ElevatedButton.icon(
                  onPressed: () => _openWhatsApp(context),
                  icon: const Icon(Icons.chat),
                  label: const Text('تواصل معنا عبر واتساب'),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const PrivacyPolicyScreen(),
                      ),
                    );
                  },
                  icon: const Icon(Icons.privacy_tip),
                  label: const Text('سياسة الخصوصية'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                children: const [
                  Text(
                    'Munzer Company Soft',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  SizedBox(height: 4),
                  Text('كوبي رايت © 2026 جميع الحقوق محفوظة'),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionCard(
    BuildContext context, {
    required String title,
    required Widget child,
  }) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            child,
          ],
        ),
      ),
    );
  }
}
