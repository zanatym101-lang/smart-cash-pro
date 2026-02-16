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
  final _partyNameCtrl = TextEditingController();
  final _customerPhoneCtrl = TextEditingController();

  String _transferType = 'type1';
  bool _viaPhone = false;

  @override
  void initState() {
    super.initState();
    final initialParty = widget.initialParty?.trim();
    if (initialParty != null && initialParty.isNotEmpty) {
      _selectedContactName = initialParty;
      _partyNameCtrl.text = initialParty;
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
    _partyNameCtrl.dispose();
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
  String _fmtMoney(double v) => v.toStringAsFixed(2);

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
      _partyNameCtrl.text = picked.name;
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

  Future<bool> _confirmPhoneSuccess() async {
    final res = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('تأكيد نتيجة التنفيذ'),
        content: const Text('هل نجحت عملية التحويل عبر الهاتف؟'),
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

  Future<_TransferReviewResult?> _confirmTransferSubmit({
    required Wallet wallet,
    required String partyName,
    required String partyPhone,
    required double amount,
    required double clientFee,
    required double networkFee,
    required bool viaPhone,
    String? note,
  }) async {
    final sentAmount = _transferType == 'type2'
        ? (amount - clientFee - networkFee)
        : amount;
    final walletDebit = _transferType == 'type2'
        ? (amount - clientFee)
        : (amount + networkFee);
    final drawerIn = _transferType == 'type2' ? amount : (amount + clientFee);

    bool markPending = AppSession.isAdmin ? widget.forcePendingDefault : true;

    return showDialog<_TransferReviewResult>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: const Text('مراجعة عملية التحويل'),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('المحفظة: ${wallet.name}'),
                Text(
                  'نوع التحويل: ${_transferType == 'type1' ? 'Type 1' : 'Type 2'}',
                ),
                Text('المبلغ المدخل: ${_fmtMoney(amount)}'),
                Text('CF (ربحك): ${_fmtMoney(clientFee)}'),
                Text('NF (رسوم شبكة): ${_fmtMoney(networkFee)}'),
                Text('المبلغ المحول للعميل: ${_fmtMoney(sentAmount)}'),
                Text('الخصم من المحفظة: ${_fmtMoney(walletDebit)}'),
                Text('الداخل للدرج: ${_fmtMoney(drawerIn)}'),
                Text('تنفيذ عبر الهاتف: ${viaPhone ? 'نعم' : 'لا'}'),
                if (partyName.trim().isNotEmpty) Text('الطرف: $partyName'),
                if (partyPhone.trim().isNotEmpty)
                  Text('رقم الطرف: $partyPhone'),
                if (note != null && note.trim().isNotEmpty)
                  Text('ملاحظة: ${note.trim()}'),
                const SizedBox(height: 8),
                if (AppSession.isAdmin)
                  CheckboxListTile(
                    value: markPending,
                    onChanged: (v) => setState(() => markPending = v ?? false),
                    contentPadding: EdgeInsets.zero,
                    title: const Text('تسجيل العملية كمعلقة'),
                    subtitle: const Text('إذا لم تحددها سيتم تنفيذها فورًا.'),
                  )
                else
                  const Text(
                    'كمستخدم عادي سيتم تسجيل العملية كمعلقة تلقائيًا.',
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('إلغاء'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.of(
                  ctx,
                ).pop(_TransferReviewResult(isPending: markPending));
              },
              child: const Text('تنفيذ'),
            ),
          ],
        ),
      ),
    );
  }

  String? _composeNote(String? base, String customerPhone) {
    final parts = <String>[];
    if (base != null && base.trim().isNotEmpty) {
      parts.add(base.trim());
    }
    if (customerPhone.isNotEmpty) {
      parts.add('رقم الطرف: $customerPhone');
    }
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
    final partyName = _partyNameCtrl.text.trim().isEmpty
        ? (_selectedContactName ?? '')
        : _partyNameCtrl.text.trim();
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
    if (_transferType == 'type2' && amt <= (cf + nf)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('في Type 2 يجب أن يكون المبلغ أكبر من CF + NF'),
        ),
      );
      return;
    }

    final wallet = _selectedWallet();
    if (wallet == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('اختر محفظة صحيحة')));
      return;
    }

    final review = await _confirmTransferSubmit(
      wallet: wallet,
      partyName: partyName,
      partyPhone: customerPhone,
      amount: amt,
      clientFee: cf,
      networkFee: nf,
      viaPhone: _viaPhone,
      note: note,
    );
    if (review == null || !mounted) return;

    if (_viaPhone && review.isPending) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('التنفيذ عبر الهاتف يتطلب تنفيذًا فوريًا وليس معلقًا'),
        ),
      );
      return;
    }

    if (_viaPhone) {
      if (!AppSession.isAdmin) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('التنفيذ عبر الهاتف متاح للأدمن فقط')),
        );
        return;
      }
      if (customerPhone.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('رقم هاتف الطرف مطلوب للتنفيذ عبر الهاتف'),
          ),
        );
        return;
      }

      if (wallet.phone.trim().isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('رقم المحفظة مطلوب لتحديد كود التحويل')),
        );
        return;
      }

      final provider = providerFromPhone(wallet.phone);
      final providerName = providerDisplayName(provider);
      final defaultCode = defaultTransferCode(
        provider: provider,
        customerPhone: customerPhone,
        amount: amt,
      );
      if (defaultCode == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('لا يوجد كود تحويل افتراضي للمزوّد: $providerName'),
          ),
        );
        return;
      }

      final code = await _editTransferCode(defaultCode, providerName);
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

      if (!await _confirmPhoneSuccess()) {
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
        isPending: review.isPending,
        note: _composeNote(note, customerPhone),
        party: partyName.isEmpty ? null : partyName,
      );

      if (_viaPhone) {
        await NotificationService.show(
          title: 'تحويل عبر الهاتف',
          body: 'تم تنفيذ العملية بنجاح.',
        );
        await AppDb.instance.addRecentNumber(
          phone: customerPhone,
          name: partyName.isEmpty ? null : partyName,
        );
        await _loadRecentNumbers();
      }

      if (!mounted) return;
      if (review.isPending) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('تم تسجيل تحويل معلق (ID=$id)')));
        await Navigator.of(
          context,
        ).push(MaterialPageRoute(builder: (_) => const PendingScreen()));
        if (mounted) Navigator.of(context).pop(true);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('تم تنفيذ التحويل بنجاح (ID=$id)')),
        );
        Navigator.of(context).pop(true);
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
    final title = AppSession.isAdmin ? 'تحويل' : 'تحويل (كمعلقة للمستخدم)';
    final wallet = _selectedWallet();
    final provider = wallet == null || wallet.phone.trim().isEmpty
        ? 'unknown'
        : providerFromPhone(wallet.phone);
    final providerName = provider == 'unknown'
        ? 'غير محدد'
        : providerDisplayName(provider);

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
                _headerCard('تحويل من محفظة مع مراجعة قبل التنفيذ'),
                const SizedBox(height: 12),
                _sectionCard(
                  title: 'طريقة التنفيذ',
                  child: SwitchListTile(
                    value: _viaPhone,
                    onChanged: _saving
                        ? null
                        : (v) => setState(() => _viaPhone = v),
                    title: const Text('تنفيذ العملية عبر الهاتف'),
                    subtitle: const Text(
                      'يفتح لوحة الاتصال بكود التحويل ثم تؤكد نجاح العملية قبل تسجيلها.',
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                _sectionCard(
                  title: 'المحفظة والطرف',
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
                          labelText: 'المحفظة (يُخصم منها)',
                        ),
                      ),
                      const SizedBox(height: 6),
                      _infoPill('مزوّد المحفظة: $providerName'),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _partyNameCtrl,
                        enabled: !_saving,
                        decoration: const InputDecoration(
                          labelText: 'اسم الطرف (اختياري)',
                        ),
                        onChanged: (v) {
                          _selectedContactName = v.trim().isEmpty
                              ? null
                              : v.trim();
                        },
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: _customerPhoneCtrl,
                        keyboardType: TextInputType.phone,
                        enabled: !_saving,
                        decoration: InputDecoration(
                          labelText: 'رقم الطرف (اختياري)',
                          suffixIcon: IconButton(
                            onPressed: _saving ? null : _pickContact,
                            icon: const Icon(Icons.contacts),
                            tooltip: 'اختيار من جهات الاتصال',
                          ),
                        ),
                      ),
                      if (_recentNumbers.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        const Text('آخر الأرقام المستخدمة'),
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: _recentNumbers.map((r) {
                            final label = (r.name == null || r.name!.isEmpty)
                                ? r.phone
                                : '${r.name} | ${r.phone}';
                            return ActionChip(
                              label: Text(label),
                              onPressed: () {
                                setState(() {
                                  _customerPhoneCtrl.text = r.phone;
                                  _selectedContactName = r.name;
                                  _partyNameCtrl.text = r.name ?? '';
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
                          labelText: 'CF (العمولة/الربح) (EGP)',
                        ),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: _networkFeeCtrl,
                        keyboardType: TextInputType.number,
                        enabled: !_saving,
                        decoration: const InputDecoration(
                          labelText: 'NF (رسوم الشبكة) (EGP)',
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
                          title: Text('Type 2: العمولة تُخصم من المبلغ'),
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
                      : const Icon(Icons.play_arrow),
                  label: const Text('تنفيذ'),
                ),
                const SizedBox(height: 8),
                Text(
                  AppSession.isAdmin
                      ? 'يمكنك من نافذة المراجعة تحديد العملية كمعلقة أو تنفيذها فورًا.'
                      : 'كمستخدم عادي، أي عملية جديدة تُسجل كمعلقة وتظهر في شاشة المعلقة.',
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

class _TransferReviewResult {
  final bool isPending;

  const _TransferReviewResult({required this.isPending});
}
