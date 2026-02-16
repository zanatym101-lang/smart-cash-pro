import 'package:barcode_widget/barcode_widget.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/app_db.dart';
import '../data/app_session.dart';
import '../models/wallet.dart';
import '../utils/contact_picker.dart';
import '../utils/phone_provider.dart';
import '../widgets/app_title.dart';
import 'pending_screen.dart';

class ReceiveScreen extends StatefulWidget {
  final String? initialParty;
  final String? initialPhone;
  final bool forcePendingDefault;

  const ReceiveScreen({
    super.key,
    this.initialParty,
    this.initialPhone,
    this.forcePendingDefault = false,
  });

  @override
  State<ReceiveScreen> createState() => _ReceiveScreenState();
}

class _ReceiveScreenState extends State<ReceiveScreen> {
  bool _loading = true;
  bool _saving = false;

  List<Wallet> _wallets = [];
  int? _walletId;

  final _amountCtrl = TextEditingController(text: '1000');
  final _feeCtrl = TextEditingController(text: '10');
  final _noteCtrl = TextEditingController();
  final _partyCtrl = TextEditingController();
  final _partyPhoneCtrl = TextEditingController();
  String? _selectedContactName;

  String _receiveType = 'cash'; // cash | deduct | electronic

  @override
  void initState() {
    super.initState();

    final initialParty = widget.initialParty?.trim();
    if (initialParty != null && initialParty.isNotEmpty) {
      _partyCtrl.text = initialParty;
      _selectedContactName = initialParty;
    }
    final initialPhone = normalizePhone(widget.initialPhone ?? '');
    if (initialPhone.isNotEmpty) {
      _partyPhoneCtrl.text = initialPhone;
    }

    _load();
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    _feeCtrl.dispose();
    _noteCtrl.dispose();
    _partyCtrl.dispose();
    _partyPhoneCtrl.dispose();
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
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  double _toDouble(String s) => double.tryParse(s.trim()) ?? 0;
  String _fmtMoney(double v) => v.toStringAsFixed(2);

  String _encodeDialCode(String code) => code.replaceAll('#', '%23');

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
    if (base != null && base.trim().isNotEmpty) {
      parts.add(base.trim());
    }
    if (phone.isNotEmpty) {
      parts.add('رقم الطرف: $phone');
    }
    return parts.isEmpty ? null : parts.join(' - ');
  }

  Future<void> _copyAndDialCode({
    required String phone,
    required double amount,
  }) async {
    final provider = providerFromPhone(phone);
    final providerName = providerDisplayName(provider);
    final code = defaultTransferCode(
      provider: provider,
      customerPhone: phone,
      amount: amount,
    );
    if (code == null || code.trim().isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('لا يوجد كود افتراضي للمزوّد: $providerName')),
      );
      return;
    }

    await Clipboard.setData(ClipboardData(text: code));
    if (!mounted) return;

    final telUri = Uri.parse('tel:${_encodeDialCode(code)}');
    final launched = await launchUrl(
      telUri,
      mode: LaunchMode.externalApplication,
    );
    if (!launched && mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('تعذر فتح لوحة الاتصال')));
    }
  }

  Future<bool> _showWalletBarcode(String phone, double amount) async {
    final res = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('باركود رقم المحفظة'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            GestureDetector(
              onTap: () => _copyAndDialCode(phone: phone, amount: amount),
              child: BarcodeWidget(
                barcode: Barcode.code128(),
                data: phone,
                width: 260,
                height: 80,
              ),
            ),
            const SizedBox(height: 12),
            GestureDetector(
              onTap: () => _copyAndDialCode(phone: phone, amount: amount),
              child: Text(
                phone,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: () => _copyAndDialCode(phone: phone, amount: amount),
              icon: const Icon(Icons.copy),
              label: const Text('نسخ كود التحويل وفتح الاتصال'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('متابعة'),
          ),
        ],
      ),
    );
    return res == true;
  }

  Future<_ReceiveReviewResult?> _confirmReceiveSubmit({
    required Wallet wallet,
    required double amount,
    required double fee,
    required String receiveType,
    required String partyName,
    required String partyPhone,
    String? note,
  }) async {
    double walletDelta;
    double drawerDelta;
    if (receiveType == 'cash') {
      walletDelta = amount;
      drawerDelta = -amount;
    } else if (receiveType == 'deduct') {
      walletDelta = amount;
      drawerDelta = -(amount - fee);
    } else {
      walletDelta = amount + fee;
      drawerDelta = 0;
    }

    bool markPending = AppSession.isAdmin ? widget.forcePendingDefault : true;

    return showDialog<_ReceiveReviewResult>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: const Text('مراجعة عملية الاستلام'),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('المحفظة: ${wallet.name}'),
                Text('نوع الاستلام: $receiveType'),
                Text('المبلغ: ${_fmtMoney(amount)}'),
                Text('العمولة (CF): ${_fmtMoney(fee)}'),
                Text('تأثير المحفظة: ${_fmtMoney(walletDelta)}'),
                Text('تأثير الدرج: ${_fmtMoney(drawerDelta)}'),
                Text('الربح: ${_fmtMoney(fee)}'),
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
                ).pop(_ReceiveReviewResult(isPending: markPending));
              },
              child: const Text('تنفيذ'),
            ),
          ],
        ),
      ),
    );
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
    final fee = _toDouble(_feeCtrl.text);
    final note = _noteCtrl.text.trim().isEmpty ? null : _noteCtrl.text.trim();
    final partyName = _partyCtrl.text.trim().isEmpty
        ? _selectedContactName
        : _partyCtrl.text.trim();
    final partyPhone = normalizePhone(_partyPhoneCtrl.text);

    if (amt <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('المبلغ يجب أن يكون أكبر من صفر')),
      );
      return;
    }
    if (fee < 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('العمولة لا يمكن أن تكون سالبة')),
      );
      return;
    }

    final wallet = _wallets.where((w) => w.id == wid).toList();
    if (wallet.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('لا توجد محفظة صالحة')));
      return;
    }

    final review = await _confirmReceiveSubmit(
      wallet: wallet.first,
      amount: amt,
      fee: fee,
      receiveType: _receiveType,
      partyName: partyName ?? '',
      partyPhone: partyPhone,
      note: note,
    );
    if (review == null || !mounted) return;

    if (!review.isPending) {
      final phone = wallet.first.phone.trim();
      if (phone.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('رقم المحفظة مطلوب لعرض الباركود')),
        );
        return;
      }
      final ok = await _showWalletBarcode(phone, amt);
      if (!ok) return;
    }

    setState(() => _saving = true);
    try {
      final id = await AppDb.instance.addReceive(
        walletId: wid,
        amount: amt,
        commission: fee,
        receiveType: _receiveType,
        isPending: review.isPending,
        note: _composeNote(note, partyPhone),
        party: partyName,
      );

      if (!mounted) return;
      if (review.isPending) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('تم تسجيل استلام معلّق (ID=$id)')),
        );
        await Navigator.of(
          context,
        ).push(MaterialPageRoute(builder: (_) => const PendingScreen()));
        if (mounted) Navigator.of(context).pop(true);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('تم تنفيذ الاستلام بنجاح (ID=$id)')),
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
    final title = AppSession.isAdmin ? 'استلام' : 'استلام (كمعلقة للمستخدم)';

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
                _headerCard('استلام مع مراجعة قبل التنفيذ'),
                const SizedBox(height: 12),
                _sectionCard(
                  title: 'بيانات الاستلام',
                  child: Column(
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
                          labelText: 'المحفظة (تزيد)',
                        ),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: _partyCtrl,
                        enabled: !_saving,
                        decoration: const InputDecoration(
                          labelText: 'اسم الطرف (اختياري)',
                        ),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: _partyPhoneCtrl,
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
                      const SizedBox(height: 10),
                      TextField(
                        controller: _amountCtrl,
                        keyboardType: TextInputType.number,
                        enabled: !_saving,
                        decoration: const InputDecoration(
                          labelText: 'المبلغ المستلم (EGP)',
                        ),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: _feeCtrl,
                        keyboardType: TextInputType.number,
                        enabled: !_saving,
                        decoration: const InputDecoration(
                          labelText: 'العمولة/الربح (EGP)',
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                _sectionCard(
                  title: 'نوع الاستلام',
                  child: RadioGroup<String>(
                    groupValue: _receiveType,
                    onChanged: (v) {
                      if (_saving || v == null) return;
                      setState(() => _receiveType = v);
                    },
                    child: Column(
                      children: const [
                        RadioListTile<String>(
                          value: 'cash',
                          title: Text('نقدي: العمولة كاش'),
                        ),
                        RadioListTile<String>(
                          value: 'deduct',
                          title: Text('نقدي: خصم العمولة من المبلغ المستلم'),
                        ),
                        RadioListTile<String>(
                          value: 'electronic',
                          title: Text('إلكتروني: المبلغ + العمولة على المحفظة'),
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
          const Icon(Icons.call_received, color: Colors.white, size: 34),
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
}

class _ReceiveReviewResult {
  final bool isPending;

  const _ReceiveReviewResult({required this.isPending});
}
