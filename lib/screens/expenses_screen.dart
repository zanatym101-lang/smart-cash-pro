import 'package:flutter/material.dart';

import '../widgets/app_title.dart';
import '../data/app_db.dart';
import '../data/app_session.dart';
import '../models/transaction.dart';
import '../utils/phone_provider.dart';
import '../utils/contact_picker.dart';

class ExpensesScreen extends StatefulWidget {
  const ExpensesScreen({super.key});

  @override
  State<ExpensesScreen> createState() => _ExpensesScreenState();
}

class _ExpensesScreenState extends State<ExpensesScreen> {
  final _db = AppDb.instance;
  final _amountCtrl = TextEditingController();
  final _noteCtrl = TextEditingController();
  final _partyCtrl = TextEditingController();
  final _partyPhoneCtrl = TextEditingController();
  String? _selectedContactName;
  String _category = 'إيجار';
  bool _saving = false;
  bool _loadingList = true;
  String? _listError;
  List<Txn> _expenses = [];
  String _period = 'today'; // today | month | archive
  int _dayStartHour = 0;

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
  void initState() {
    super.initState();
    _loadExpenses();
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    _noteCtrl.dispose();
    _partyCtrl.dispose();
    _partyPhoneCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadExpenses() async {
    setState(() {
      _loadingList = true;
      _listError = null;
    });
    try {
      final settings = await _db.getAppSettings();
      _dayStartHour = settings.dayStartHour;
      final rows = await _db.listTxns(kind: 'expense');
      rows.sort((a, b) {
        final c = b.entryDate.compareTo(a.entryDate);
        if (c != 0) return c;
        return b.id.compareTo(a.id);
      });
      if (!mounted) return;
      setState(() => _expenses = rows);
    } catch (e) {
      if (!mounted) return;
      setState(() => _listError = e.toString());
    } finally {
      if (mounted) setState(() => _loadingList = false);
    }
  }

  String _fmtDate(DateTime d) {
    final y = d.year.toString().padLeft(4, '0');
    final m = d.month.toString().padLeft(2, '0');
    final day = d.day.toString().padLeft(2, '0');
    return '$y-$m-$day';
  }

  DateTime _businessShift(DateTime d) {
    if (_dayStartHour <= 0) return d;
    return d.subtract(Duration(hours: _dayStartHour));
  }

  DateTime _todayStart() {
    final now = DateTime.now();
    final shifted = _businessShift(now);
    return DateTime(shifted.year, shifted.month, shifted.day, _dayStartHour);
  }

  DateTime _monthStart() {
    final now = DateTime.now();
    final shifted = _businessShift(now);
    return DateTime(shifted.year, shifted.month, 1, _dayStartHour);
  }

  bool _inRange(DateTime d, DateTime start, DateTime end) {
    return !d.isBefore(start) && !d.isAfter(end);
  }

  List<Txn> _filterExpenses(String period) {
    final monthStart = _monthStart();
    if (period == 'archive') {
      return _expenses
          .where((e) => e.entryDate.isBefore(monthStart))
          .toList();
    }
    final start = period == 'month' ? monthStart : _todayStart();
    final end = (period == 'month')
        ? DateTime(monthStart.year, monthStart.month + 1, 1, _dayStartHour)
            .subtract(const Duration(milliseconds: 1))
        : start.add(const Duration(days: 1)).subtract(const Duration(milliseconds: 1));
    return _expenses.where((e) => _inRange(e.entryDate, start, end)).toList();
  }

  double _sumExpenses(List<Txn> items) {
    return items.fold<double>(0, (s, e) => s + e.amount);
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
      await _loadExpenses();
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
    final filtered = _filterExpenses(_period);
    final totalToday = _sumExpenses(_filterExpenses('today'));
    final totalMonth = _sumExpenses(_filterExpenses('month'));
    final totalArchive = _sumExpenses(_filterExpenses('archive'));
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
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'سجل المصروفات',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      ChoiceChip(
                        label: const Text('\u0627\u0644\u064a\u0648\u0645'),
                        selected: _period == 'today',
                        onSelected: (_) => setState(() => _period = 'today'),
                      ),
                      ChoiceChip(
                        label: const Text('\u0647\u0630\u0627 \u0627\u0644\u0634\u0647\u0631'),
                        selected: _period == 'month',
                        onSelected: (_) => setState(() => _period = 'month'),
                      ),
                      ChoiceChip(
                        label: const Text('\u0627\u0644\u0623\u0631\u0634\u064a\u0641'),
                        selected: _period == 'archive',
                        onSelected: (_) => setState(() => _period = 'archive'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: _statChip('\u0627\u0644\u064a\u0648\u0645', totalToday),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _statChip('\u0647\u0630\u0627 \u0627\u0644\u0634\u0647\u0631', totalMonth),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _statChip('\u0627\u0644\u0623\u0631\u0634\u064a\u0641', totalArchive),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (_loadingList)
                    const Center(child: CircularProgressIndicator())
                  else if (_listError != null)
                    Text('خطأ: $_listError')
                  else if (filtered.isEmpty)
                    const Text('لا توجد مصروفات مسجلة بعد.')
                  else
                    Column(
                      children: filtered.map((e) {
                        final title = e.mode.isEmpty ? 'مصروف' : e.mode;
                        final date = _fmtDate(e.entryDate);
                        final note = (e.note ?? '').trim();
                        final party = (e.party ?? '').trim();
                        final subtitleParts = <String>[
                          date,
                          if (party.isNotEmpty) 'الطرف: $party',
                          if (note.isNotEmpty) note,
                        ];
                        return ListTile(
                          dense: true,
                          leading: const Icon(Icons.payments_outlined),
                          title: Text(title),
                          subtitle: Text(subtitleParts.join(' | ')),
                          trailing: Text('-${e.amount.toStringAsFixed(2)}'),
                        );
                      }).toList(),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _statChip(String label, double value) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontSize: 11, color: Colors.black54)),
          const SizedBox(height: 2),
          Text(value.toStringAsFixed(2),
              style: const TextStyle(fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }

}
