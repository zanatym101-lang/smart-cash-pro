import 'package:flutter/material.dart';

import '../widgets/app_title.dart';
import '../data/app_db.dart';
import '../data/app_session.dart';
import '../utils/phone_provider.dart';
import '../utils/contact_picker.dart';

class ExpensesScreen extends StatefulWidget {
  const ExpensesScreen({super.key});

  @override
  State<ExpensesScreen> createState() => _ExpensesScreenState();
}

class _ExpensesScreenState extends State<ExpensesScreen> {
  final _amountCtrl = TextEditingController();
  final _noteCtrl = TextEditingController();
  final _partyCtrl = TextEditingController();
  final _partyPhoneCtrl = TextEditingController();
  String? _selectedContactName;
  String _category = 'إيجار';
  bool _saving = false;

  final _categories = const [
    'إيجار',
    'كهرباء',
    'إنترنت',
    'مرتبات',
    'مواصلات',
    'صيانة',
    'أخرى',
  ];

  @override
  void dispose() {
    _amountCtrl.dispose();
    _noteCtrl.dispose();
    _partyCtrl.dispose();
    _partyPhoneCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickContact() async {
    final picked = await pickContact(context);
    if (picked == null) return;

    setState(() {
      _partyCtrl.text = picked.name;
      _partyPhoneCtrl.text = picked.phone;
      _selectedContactName = picked.name;
    });
  }

  String? _composeNote(String? base, String phone) {
    final parts = <String>[];
    if (base != null && base.trim().isNotEmpty) parts.add(base.trim());
    if (phone.isNotEmpty) parts.add('رقم الطرف: $phone');
    return parts.isEmpty ? null : parts.join(' - ');
  }

  Future<void> _save() async {
    if (!AppSession.isAdmin) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('المصروفات للأدمن فقط')));
      return;
    }

    final amt = double.tryParse(_amountCtrl.text.trim());
    if (amt == null || amt <= 0) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('أدخل مبلغ صحيح')));
      return;
    }

    final partyName = _partyCtrl.text.trim().isEmpty
        ? _selectedContactName
        : _partyCtrl.text.trim();
    final partyPhone = normalizePhone(_partyPhoneCtrl.text);

    setState(() => _saving = true);
    try {
      await AppDb.instance.addExpense(
        amount: amt,
        category: _category,
        note: _composeNote(
          _noteCtrl.text.trim().isEmpty ? null : _noteCtrl.text.trim(),
          partyPhone,
        ),
        party: partyName,
        isPending: false,
      );

      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('تم تسجيل المصروف بنجاح')));
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('خطأ: $e')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const AppTitle(subtitle: 'المصروفات')),
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
                Icon(Icons.payments, color: Colors.white, size: 32),
                SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'تسجيل مصروف جديد\nيخصم من الدرج فقط دون التأثير على المحافظ أو الأرباح.',
                    style: TextStyle(color: Colors.white),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'بيانات المصروف',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _partyCtrl,
                    decoration: const InputDecoration(
                      labelText: 'اسم الطرف (اختياري)',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _partyPhoneCtrl,
                    keyboardType: TextInputType.phone,
                    decoration: InputDecoration(
                      labelText: 'رقم الطرف (اختياري)',
                      border: const OutlineInputBorder(),
                      isDense: true,
                      suffixIcon: IconButton(
                        onPressed: _saving ? null : _pickContact,
                        icon: const Icon(Icons.contacts),
                        tooltip: 'اختر من الأسماء',
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    key: ValueKey(_category),
                    initialValue: _category,
                    items: _categories
                        .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                        .toList(),
                    onChanged: (v) =>
                        setState(() => _category = v ?? _category),
                    decoration: const InputDecoration(
                      labelText: 'التصنيف',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _amountCtrl,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(
                      labelText: 'المبلغ (جنيه)',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.payments),
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _noteCtrl,
                    decoration: const InputDecoration(
                      labelText: 'ملاحظة (اختياري)',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.notes),
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    onPressed: _saving ? null : _save,
                    icon: _saving
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.save),
                    label: Text(_saving ? 'جارٍ الحفظ...' : 'حفظ'),
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
