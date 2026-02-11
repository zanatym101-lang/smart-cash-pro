import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/app_db.dart';
import '../data/app_session.dart';
import '../models/recent_number.dart';
import '../models/wallet.dart';
import '../services/notification_service.dart';
import '../utils/contact_picker.dart';
import '../utils/phone_provider.dart';
import '../widgets/app_title.dart';
import 'pending_screen.dart';

class TransferScreen extends StatefulWidget {
  final String? initialParty;
  final String? initialPhone;
  final bool forcePendingDefault;

  const TransferScreen({
    super.key,
    this.initialParty,
    this.initialPhone,
    this.forcePendingDefault = false,
  });

  @override
  State<TransferScreen> createState() => _TransferScreenState();
}

class _TransferScreenState extends State<TransferScreen> {
  bool _loading = true;
  bool _saving = false;

  List<Wallet> _wallets = [];
  int? _walletId;
  List<RecentNumber> _recentNumbers = [];
  String? _selectedContactName;

  final _amountCtrl = TextEditingController(text: '100');
  final _clientFeeCtrl = TextEditingController(text: '4');
  final _networkFeeCtrl = TextEditingController(text: '1');
  final _noteCtrl = TextEditingController();
  final _customerPhoneCtrl = TextEditingController();

  String _transferType = 'type1'; // type1 | type2
  bool _instantApprove = false;
  bool _viaPhone = false;

  @override
  void initState() {
    super.initState();
    _instantApprove = AppSession.isAdmin && !widget.forcePendingDefault;
    final initialParty = widget.initialParty?.trim();
    if (initialParty != null && initialParty.isNotEmpty) {
      _selectedContactName = initialParty;
    }
    final initialPhone = normalizePhone(widget.initialPhone ?? '');
    if (initialPhone.isNotEmpty) {
      _customerPhoneCtrl.text = initialPhone;
    }
    _load();
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    _clientFeeCtrl.dispose();
    _networkFeeCtrl.dispose();
    _noteCtrl.dispose();
    _customerPhoneCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final wallets = await AppDb.instance.listWallets();
      if (!mounted) return;
      setState(() {
        _wallets = wallets;
        _walletId = wallets.isNotEmpty ? wallets.first.id : null;
      });
      await _loadRecentNumbers();
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadRecentNumbers() async {
    final items = await AppDb.instance.listRecentNumbers(limit: 10);
    if (!mounted) return;
    setState(() => _recentNumbers = items);
  }

  Wallet? _selectedWallet() {
    final id = _walletId;
    if (id == null) return null;
    for (final w in _wallets) {
      if (w.id == id) return w;
    }
    return null;
  }

  double _toDouble(String s) => double.tryParse(s.trim()) ?? 0;

  String _fmtDate(DateTime d) {
    final y = d.year.toString().padLeft(4, '0');
    final m = d.month.toString().padLeft(2, '0');
    final day = d.day.toString().padLeft(2, '0');
    return '$y-$m-$day';
  }

  String _encodeDialCode(String code) => code.replaceAll('#', '%23');

  Future<void> _pickContact() async {
    final picked = await pickContact(context);
    if (picked == null) return;

    setState(() {
      _customerPhoneCtrl.text = picked.phone;
      _selectedContactName = picked.name;
    });
  }

  Future<String?> _editTransferCode(String defaultCode, String provider) async {
    final ctrl = TextEditingController(text: defaultCode);
    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: Text('كود التحويل عبر الهاتف ($provider)'),
        content: TextField(
          controller: ctrl,
          decoration: const InputDecoration(labelText: 'كود التحويل الكامل'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(null),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(ctrl.text.trim()),
            child: const Text('اتصال'),
          ),
        ],
      ),
    );
  }

  Future<bool> _confirmSuccess() async {
    final res = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('تأكيد نتيجة العملية'),
        content: const Text('هل تمت عملية التحويل بنجاح؟'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('فشلت'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('نجحت'),
          ),
        ],
      ),
    );
    return res == true;
  }

  String? _composeNote(String? base, String customerPhone) {
    final parts = <String>[];
    if (base != null && base.trim().isNotEmpty) parts.add(base.trim());
    if (customerPhone.isNotEmpty) parts.add('رقم العميل: $customerPhone');
    return parts.isEmpty ? null : parts.join(' - ');
  }

  Future<void> _submit() async {
    final wid = _walletId;
    if (wid == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('لا توجد محافظ. أضف محفظة أولًا.')),
      );
      return;
    }

    final amt = _toDouble(_amountCtrl.text);
    final cf = _toDouble(_clientFeeCtrl.text);
    final nf = _toDouble(_networkFeeCtrl.text);
    final note = _noteCtrl.text.trim();
    final customerPhone = normalizePhone(_customerPhoneCtrl.text);

    if (amt <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('المبلغ يجب أن يكون أكبر من صفر')),
      );
      return;
    }
    if (cf < 0 || nf < 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('الرسوم لا يمكن أن تكون سالبة')),
      );
      return;
    }

    if (_viaPhone) {
      if (!AppSession.isAdmin || !_instantApprove) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('التنفيذ عبر الهاتف يتطلب اعتماد فوري من الأدمن.'),
          ),
        );
        return;
      }
      if (customerPhone.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('رقم هاتف العميل مطلوب للتنفيذ عبر الهاتف'),
          ),
        );
        return;
      }

      final wallet = _selectedWallet();
      if (wallet == null || wallet.phone.trim().isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('رقم المحفظة مطلوب لتحديد كود التحويل')),
        );
        return;
      }

      final provider = providerFromPhone(wallet.phone);
      final defaultCode = defaultTransferCode(
        provider: provider,
        customerPhone: customerPhone,
        amount: amt,
      );
      if (defaultCode == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('لا يوجد كود افتراضي للمزوّد: $provider')),
        );
        return;
      }

      final code = await _editTransferCode(defaultCode, provider);
      if (code == null || code.isEmpty) return;

      final telUri = Uri.parse('tel:${_encodeDialCode(code)}');
      final launched = await launchUrl(
        telUri,
        mode: LaunchMode.externalApplication,
      );
      if (!launched) {
        if (!mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('تعذر فتح لوحة الاتصال')));
        return;
      }

      if (!await _confirmSuccess()) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تم إلغاء العملية بعد الاتصال')),
        );
        await NotificationService.show(
          title: 'تحويل عبر الهاتف',
          body: 'تم إلغاء العملية بعد الاتصال.',
        );
        return;
      }
    }

    setState(() => _saving = true);
    try {
      final id = await AppDb.instance.addTransfer(
        walletId: wid,
        amount: amt,
        clientFee: cf,
        networkFee: nf,
        transferType: _transferType,
        isPending: !_instantApprove,
        note: _composeNote(note, _viaPhone ? customerPhone : ''),
        party: _selectedContactName,
      );

      if (!mounted) return;

      if (_viaPhone) {
        await NotificationService.show(
          title: 'تحويل عبر الهاتف',
          body: 'تم تنفيذ العملية بنجاح.',
        );
        await AppDb.instance.addRecentNumber(
          phone: customerPhone,
          name: _selectedContactName,
        );
        await _loadRecentNumbers();
      }

      if (!mounted) return;
      if (_instantApprove) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('تم اعتماد التحويل فورًا (ID=$id)')),
        );
        Navigator.of(context).pop(true);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('تم إنشاء تحويل معلّق (ID=$id)')),
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
    final title = _instantApprove ? 'تحويل (اعتماد فوري)' : 'تحويل (طلب معلّق)';
    final wallet = _selectedWallet();
    final provider = wallet == null || wallet.phone.trim().isEmpty
        ? 'غير محدد'
        : providerFromPhone(wallet.phone);

    return Scaffold(
      appBar: AppBar(
        title: AppTitle(subtitle: title),
        actions: [
          IconButton(
            tooltip: 'تحديث',
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              children: [
                _headerCard(title),
                const SizedBox(height: 12),
                if (AppSession.isAdmin)
                  _sectionCard(
                    title: 'الاعتماد والتنفيذ',
                    child: Column(
                      children: [
                        SwitchListTile(
                          value: _instantApprove,
                          onChanged: _saving
                              ? null
                              : (v) => setState(() => _instantApprove = v),
                          title: const Text('اعتماد فوري (بدون تعليق)'),
                          subtitle: const Text('استخدمها فقط للمشرف/الإدارة.'),
                        ),
                        SwitchListTile(
                          value: _viaPhone,
                          onChanged: _saving
                              ? null
                              : (v) => setState(() => _viaPhone = v),
                          title: const Text('تنفيذ العملية عبر الهاتف'),
                          subtitle: const Text(
                            'فتح لوحة الاتصال بكود التحويل ثم تأكيد النتيجة.',
                          ),
                        ),
                      ],
                    ),
                  )
                else
                  _sectionCard(
                    title: 'طريقة التنفيذ',
                    child: SwitchListTile(
                      value: _viaPhone,
                      onChanged: _saving
                          ? null
                          : (v) => setState(() => _viaPhone = v),
                      title: const Text('تنفيذ العملية عبر الهاتف'),
                      subtitle: const Text(
                        'يتطلب اعتماد فوري من الأدمن عند التنفيذ.',
                      ),
                    ),
                  ),
                const SizedBox(height: 12),
                _sectionCard(
                  title: 'المحفظة والعميل',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      DropdownButtonFormField<int>(
                        key: ValueKey(_walletId),
                        initialValue: _walletId,
                        items: _wallets
                            .map(
                              (w) => DropdownMenuItem(
                                value: w.id,
                                child: Text(w.name),
                              ),
                            )
                            .toList(),
                        onChanged: _saving
                            ? null
                            : (v) => setState(() => _walletId = v),
                        decoration: const InputDecoration(
                          labelText: 'المحفظة (خصم منها)',
                        ),
                      ),
                      const SizedBox(height: 6),
                      _infoPill('مزوّد المحفظة: $provider'),
                      if (_viaPhone) ...[
                        const SizedBox(height: 12),
                        TextField(
                          controller: _customerPhoneCtrl,
                          keyboardType: TextInputType.phone,
                          enabled: !_saving,
                          decoration: InputDecoration(
                            labelText: 'رقم هاتف العميل',
                            suffixIcon: IconButton(
                              onPressed: _saving ? null : _pickContact,
                              icon: const Icon(Icons.contacts),
                              tooltip: 'اختر من جهات الاتصال',
                            ),
                          ),
                        ),
                        if (_selectedContactName != null &&
                            _selectedContactName!.trim().isNotEmpty) ...[
                          const SizedBox(height: 6),
                          Text(
                            'الاسم المختار: $_selectedContactName',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                        if (_recentNumbers.isNotEmpty) ...[
                          const SizedBox(height: 12),
                          const Text('أحدث الأرقام'),
                          const SizedBox(height: 6),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: _recentNumbers.map((r) {
                              final label = (r.name == null || r.name!.isEmpty)
                                  ? r.phone
                                  : '${r.name} • ${r.phone}';
                              return ActionChip(
                                label: Text(label),
                                onPressed: () {
                                  setState(() {
                                    _customerPhoneCtrl.text = r.phone;
                                    _selectedContactName = r.name;
                                  });
                                },
                              );
                            }).toList(),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'آخر استخدام: ${_fmtDate(_recentNumbers.first.lastUsed)}',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                _sectionCard(
                  title: 'قيم التحويل',
                  child: Column(
                    children: [
                      TextField(
                        controller: _amountCtrl,
                        keyboardType: TextInputType.number,
                        enabled: !_saving,
                        decoration: const InputDecoration(
                          labelText: 'المبلغ (EGP)',
                        ),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: _clientFeeCtrl,
                        keyboardType: TextInputType.number,
                        enabled: !_saving,
                        decoration: const InputDecoration(
                          labelText: 'CF العمولة/الربح (EGP)',
                        ),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: _networkFeeCtrl,
                        keyboardType: TextInputType.number,
                        enabled: !_saving,
                        decoration: const InputDecoration(
                          labelText: 'NF رسوم الشبكة (EGP)',
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                _sectionCard(
                  title: 'نوع التحويل',
                  child: RadioGroup<String>(
                    groupValue: _transferType,
                    onChanged: (v) {
                      if (_saving || v == null) return;
                      setState(() => _transferType = v);
                    },
                    child: Column(
                      children: const [
                        RadioListTile<String>(
                          value: 'type1',
                          title: Text('Type 1: العميل يدفع العمولة كاش'),
                        ),
                        RadioListTile<String>(
                          value: 'type2',
                          title: Text('Type 2: العمولة تخصم من مبلغ التحويل'),
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
                    enabled: !_saving,
                    decoration: const InputDecoration(
                      labelText: 'ملاحظة (اختياري)',
                    ),
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
                  label: Text(
                    _instantApprove ? 'اعتماد الآن' : 'إرسال كعملية معلّقة',
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  _instantApprove
                      ? 'ملاحظة: الاعتماد الفوري يغيّر الأرصدة مباشرة.'
                      : 'ملاحظة: العملية المعلّقة تُعرض في الرصيد المتاح وتنتظر الاعتماد النهائي.',
                  style: Theme.of(context).textTheme.bodySmall,
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
          const Icon(Icons.compare_arrows, color: Colors.white, size: 34),
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

  Widget _infoPill(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFFE2E8F0),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(text, style: Theme.of(context).textTheme.bodySmall),
    );
  }
}
