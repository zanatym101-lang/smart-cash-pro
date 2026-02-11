import 'package:flutter/material.dart';
import '../widgets/app_title.dart';

class PrivacyPolicyScreen extends StatelessWidget {
  const PrivacyPolicyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const AppTitle(subtitle: 'سياسة الخصوصية')),
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
                Icon(Icons.privacy_tip, color: Colors.white, size: 32),
                SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'نحن نحترم خصوصيتك\nملخص السياسة داخل التطبيق',
                    style: TextStyle(color: Colors.white),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _section('البيانات التي نجمعها',
              'لا نجمع بيانات شخصية خارج الجهاز. كل البيانات المحاسبية تُحفظ محليًا في قاعدة بيانات على الجهاز.'),
          _section('الاتصال بالإنترنت',
              'التطبيق يعمل Offline. لا يتم إرسال أي بيانات تلقائيًا لأي خادم.'),
          _section('الأذونات',
              'قد يطلب التطبيق أذونات مثل جهات الاتصال أو الاتصال الهاتفي لتنفيذ ميزات اختيارية (مثل اختيار رقم أو تنفيذ تحويل عبر الهاتف). هذه الأذونات تُستخدم فقط عند طلب المستخدم.'),
          _section('النسخ الاحتياطي',
              'يمكنك إنشاء نسخة احتياطية يدويًا كملف وحفظها في مكان تختاره. الاستعادة تتم فقط بإذن المستخدم.'),
          _section('التواصل عبر واتساب',
              'زر التواصل يفتح واتساب خارجيًا. لا يتم إرسال أي بيانات بدون موافقتك.'),
          _section('التحديثات',
              'قد يتم تحديث هذه السياسة مستقبلًا مع إضافة ميزات جديدة.'),
        ],
      ),
    );
  }

  Widget _section(String title, String body) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            Text(body),
          ],
        ),
      ),
    );
  }
}
