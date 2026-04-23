import 'package:flutter/material.dart';

import '../widgets/app_title.dart';
import '../data/app_db.dart';
import '../data/app_session.dart';
import '../utils/phone_provider.dart';
import '../utils/contact_picker.dart';
import 'pending_screen.dart';

class FawryScreen extends StatefulWidget {
  final String? initialParty;
  final String? initialPhone;
  final bool startCredit;
  final bool forcePendingDefault;

  const FawryScreen({
    super.key,
    this.initialParty,
    this.initialPhone,
    this.startCredit = false,
    this.forcePendingDefault = false,
  });

  @override
  State<FawryScreen> createState() => _FawryScreenState();
}

class _FawryScreenState extends State<FawryScreen> {
  bool _saving = false;
  bool _instantApprove = false;

  final _serviceCtrl = TextEditingController();
  final _referenceCtrl = TextEditingController();
  final _amountCtrl = TextEditingController();
  final _feeCtrl = TextEditingController();
  final _partyCtrl = TextEditingController();
  final _partyPhoneCtrl = TextEditingController();
  final _noteCtrl = TextEditingController();
  String? _selectedContactName;

  String _collection = 'cash'; // cash | credit

  @override
  void initState() {
    super.initState();
    _instantApprove = AppSession.isAdmin && !widget.forcePendingDefault;
    _collection = widget.startCredit ? 'credit' : 'cash';
    final initialParty = widget.initialParty?.trim();
    if (initialParty != null && initialParty.isNotEmpty) {
      _partyCtrl.text = initialParty;
      _selectedContactName = initialParty;
    }
    final initialPhone = normalizePhone(widget.initialPhone ?? '');
    if (initialPhone.isNotEmpty) {
      _partyPhoneCtrl.text = initialPhone;
    }
  }

  @override
  void dispose() {
    _serviceCtrl.dispose();
    _referenceCtrl.dispose();
    _amountCtrl.dispose();
    _feeCtrl.dispose();
    _partyCtrl.dispose();
    _partyPhoneCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  double _toDouble(String s) => double.tryParse(s.trim()) ?? 0;

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

  Future<void> _submit() async {
    final service = _serviceCtrl.text.trim();
    final ref = _referenceCtrl.text.trim();
    final party = _partyCtrl.text.trim().isEmpty
        ? _selectedContactName ?? ''
        : _partyCtrl.text.trim();
    final partyPhone = normalizePhone(_partyPhoneCtrl.text);
    final amountText = _amountCtrl.text.trim();
    final feeText = _feeCtrl.text.trim();
    final note = _noteCtrl.text.trim();

    if (service.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('اسم الخدمة مطلوب')));
      return;
    }
    if (amountText.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('أدخل قيمة الخدمة')));
      return;
    }
    final amt = _toDouble(amountText);
    final fee = _toDouble(feeText);

    if (amt <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('قيمة الخدمة يجب أن تكون أكبر من صفر')),
      );
      return;
    }
    if (fee < 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('الربح لا يمكن أن يكون سالبًا')),
      );
      return;
    }
    if (_collection == 'credit' && party.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('اسم العميل مطلوب في التحصيل الآجل')),
      );
      return;
    }

    setState(() => _saving = true);
    try {
      final id = await AppDb.instance.addFawry(
        serviceName: service,
        reference: ref.isEmpty ? null : ref,
        amount: amt,
        fee: fee,
        collectionMethod: _collection,
        party: party.isEmpty ? null : party,
        note: _composeNote(note.isEmpty ? null : note, partyPhone),
        isPending: !_instantApprove,
      );

      if (!mounted) return;
      if (_instantApprove) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('تم اعتماد خدمة فوري بنجاح (ID=$id)')),
        );
        Navigator.of(context).pop(true);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('تم إنشاء خدمة فوري آجلة بنجاح (ID=$id)')),
        );
        Navigator.of(
          context,
        ).push(MaterialPageRoute(builder: (_) => const PendingScreen()));
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('فشل العملية: $e')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final amt = _toDouble(_amountCtrl.text);
    final fee = _toDouble(_feeCtrl.text);
    final total = amt + fee;
    final title = _instantApprove
        ? 'خدمات فوري (اعتماد فوري)'
        : 'خدمات فوري (طلب آجل)';

    return Scaffold(
      appBar: AppBar(title: AppTitle(subtitle: title)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          _headerCard(title),
          const SizedBox(height: 12),
          if (AppSession.isAdmin)
            _sectionCard(
              title: 'الاعتماد',
              child: SwitchListTile(
                value: _instantApprove,
                onChanged: _saving
                    ? null
                    : (v) => setState(() => _instantApprove = v),
                title: const Text('اعتماد فوري (بدون تعليق)'),
                subtitle: const Text('استخدمها فقط للمشرف/الإدارة.'),
              ),
            ),
          const SizedBox(height: 12),
          _sectionCard(
            title: 'بيانات الخدمة',
            child: Column(
              children: [
                TextField(
                  controller: _serviceCtrl,
                  decoration: const InputDecoration(
                    labelText: 'اسم الخدمة (مثال: كهرباء/موبايل/نت)',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  enabled: !_saving,
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _referenceCtrl,
                  decoration: const InputDecoration(
                    labelText: 'رقم مرجعي/عداد/موبايل (اختياري)',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  enabled: !_saving,
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _partyCtrl,
                  decoration: const InputDecoration(
                    labelText: 'اسم العميل (مطلوب للآجل)',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  enabled: !_saving,
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _partyPhoneCtrl,
                  keyboardType: TextInputType.phone,
                  decoration: InputDecoration(
                    labelText: 'رقم العميل (اختياري)',
                    border: const OutlineInputBorder(),
                    isDense: true,
                    suffixIcon: IconButton(
                      onPressed: _saving ? null : _pickContact,
                      icon: const Icon(Icons.contacts),
                      tooltip: 'اختر من الأسماء',
                    ),
                  ),
                  enabled: !_saving,
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _amountCtrl,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'قيمة الخدمة (Service Amount)',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  enabled: !_saving,
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _feeCtrl,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'الربح/العمولة (Fee)',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  enabled: !_saving,
                  onChanged: (_) => setState(() {}),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _summaryCard(total: total, amt: amt, fee: fee),
          const SizedBox(height: 12),
          _sectionCard(
            title: 'طريقة التحصيل',
            child: RadioGroup<String>(
              groupValue: _collection,
              onChanged: (v) {
                if (_saving || v == null) return;
                setState(() => _collection = v);
              },
              child: Column(
                children: const [
                  RadioListTile<String>(
                    value: 'cash',
                    title: Text('نقدي الآن'),
                  ),
                  RadioListTile<String>(
                    value: 'credit',
                    title: Text('آجل (على العميل)'),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          _sectionCard(
            title: 'ملاحظة',
            child: TextField(
              controller: _noteCtrl,
              decoration: const InputDecoration(
                labelText: 'ملاحظة (اختياري)',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              enabled: !_saving,
            ),
          ),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: _saving ? null : _submit,
            icon: _saving
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.send),
            label: Text(_instantApprove ? 'اعتماد الآن' : 'إرسال كعملية آجلة'),
          ),
        ],
      ),
    );
  }

  Widget _headerCard(String title) {
    return Container(
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
        children: [
          const Icon(Icons.bolt, color: Colors.white, size: 34),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              title,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _summaryCard({
    required double total,
    required double amt,
    required double fee,
  }) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'الإجمالي الذي سيدفعه العميل',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              total.toStringAsFixed(2),
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            Text(
              'الأصل: ${amt.toStringAsFixed(2)} • الربح: ${fee.toStringAsFixed(2)}',
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionCard({required String title, required Widget child}) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 10),
            child,
          ],
        ),
      ),
    );
  }
}
