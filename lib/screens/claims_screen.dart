import 'package:flutter/material.dart';

import '../data/app_db.dart';
import '../models/claim.dart';
import '../utils/contact_picker.dart';
import '../utils/phone_provider.dart';
import '../widgets/app_title.dart';

class ClaimsScreen extends StatefulWidget {
  const ClaimsScreen({super.key});

  @override
  State<ClaimsScreen> createState() => _ClaimsScreenState();
}

class _ClaimsScreenState extends State<ClaimsScreen> {
  bool _loading = true;
  String? _error;
  List<Claim> _claims = [];
  final Set<int> _busyClaimIds = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      _claims = await AppDb.instance.listClaims();
    } catch (e) {
      _error = e.toString();
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _fmtDate(DateTime d) {
    final y = d.year.toString().padLeft(4, '0');
    final m = d.month.toString().padLeft(2, '0');
    final day = d.day.toString().padLeft(2, '0');
    final h = d.hour.toString().padLeft(2, '0');
    final min = d.minute.toString().padLeft(2, '0');
    return '$y-$m-$day $h:$min';
  }

  String _fmtMoney(double v) => v.toStringAsFixed(2);

  Future<void> _addClaimDialog(String type) async {
    final partyCtrl = TextEditingController();
    final phoneCtrl = TextEditingController();
    final amountCtrl = TextEditingController();
    final noteCtrl = TextEditingController();

    try {
      final ok = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          title: Text(
            type == 'receivable' ? 'إضافة مبلغ لنا' : 'إضافة مبلغ علينا',
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: partyCtrl,
                  decoration: const InputDecoration(
                    labelText: 'اسم الطرف',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: phoneCtrl,
                  keyboardType: TextInputType.phone,
                  decoration: InputDecoration(
                    labelText: 'رقم الطرف (اختياري)',
                    border: const OutlineInputBorder(),
                    isDense: true,
                    suffixIcon: IconButton(
                      onPressed: () async {
                        final picked = await pickContact(context);
                        if (picked == null) return;
                        partyCtrl.text = picked.name;
                        phoneCtrl.text = picked.phone;
                      },
                      icon: const Icon(Icons.contacts),
                      tooltip: 'اختيار من جهات الاتصال',
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: amountCtrl,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'المبلغ',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: noteCtrl,
                  decoration: const InputDecoration(
                    labelText: 'ملاحظة (اختياري)',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('إلغاء'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('إضافة'),
            ),
          ],
        ),
      );
      if (!mounted || ok != true) return;

      final amt = double.tryParse(amountCtrl.text.trim());
      if (amt == null || amt <= 0) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('أدخل مبلغًا صحيحًا')));
        return;
      }

      await AppDb.instance.addClaim(
        type: type,
        party: partyCtrl.text.trim(),
        amount: amt,
        phone: normalizePhone(phoneCtrl.text),
        note: noteCtrl.text.trim().isEmpty ? null : noteCtrl.text.trim(),
      );

      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('تمت إضافة المستحق ✅')));
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('خطأ: $e')));
    } finally {
      partyCtrl.dispose();
      phoneCtrl.dispose();
      amountCtrl.dispose();
      noteCtrl.dispose();
    }
  }

  Future<double?> _promptSettlementAmount({
    required Claim claim,
    required String actionLabel,
  }) async {
    final ctrl = TextEditingController();
    String? error;

    try {
      return await showDialog<double>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => StatefulBuilder(
          builder: (ctx, setState) => AlertDialog(
            title: Text('$actionLabel المستحق'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('الطرف: ${claim.party}'),
                const SizedBox(height: 6),
                Text('المتبقي: ${_fmtMoney(claim.amount)}'),
                const SizedBox(height: 12),
                TextField(
                  controller: ctrl,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'المبلغ',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
                if (error != null) ...[
                  const SizedBox(height: 8),
                  Text(error!, style: const TextStyle(color: Colors.red)),
                ],
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('إلغاء'),
              ),
              ElevatedButton(
                onPressed: () {
                  final value = double.tryParse(ctrl.text.trim());
                  if (value == null || value <= 0) {
                    setState(() => error = 'أدخل مبلغًا صحيحًا');
                    return;
                  }
                  if (value > claim.amount) {
                    setState(() => error = 'المبلغ أكبر من المتبقي');
                    return;
                  }
                  Navigator.of(ctx).pop(value);
                },
                child: Text(actionLabel),
              ),
            ],
          ),
        ),
      );
    } finally {
      ctrl.dispose();
    }
  }

  Future<bool> _confirmAction({
    required String title,
    required String body,
    required String okText,
  }) async {
    final res = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(okText),
          ),
        ],
      ),
    );
    return res == true;
  }

  Future<void> _settleClaim(Claim claim) async {
    if (_busyClaimIds.contains(claim.id)) return;

    final actionLabel = claim.type == 'receivable' ? 'تحصيل' : 'سداد';
    final settleAmount = await _promptSettlementAmount(
      claim: claim,
      actionLabel: actionLabel,
    );
    if (!mounted || settleAmount == null) return;

    final ok = await _confirmAction(
      title: '$actionLabel المستحق',
      body:
          'سيتم $actionLabel مبلغ ${_fmtMoney(settleAmount)} للطرف ${claim.party}.',
      okText: actionLabel,
    );
    if (!mounted || !ok) return;

    setState(() => _busyClaimIds.add(claim.id));
    try {
      await AppDb.instance.settleClaim(claimId: claim.id, amount: settleAmount);
      if (!mounted) return;

      final partial = settleAmount < claim.amount;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            partial ? 'تم $actionLabel جزئيًا ✅' : 'تم $actionLabel بالكامل ✅',
          ),
        ),
      );
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('خطأ: $e')));
    } finally {
      if (mounted) setState(() => _busyClaimIds.remove(claim.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    final openReceivableTotal = _claims
        .where((c) => c.type == 'receivable' && c.status == 'open')
        .fold<double>(0, (s, c) => s + c.amount);
    final openPayableTotal = _claims
        .where((c) => c.type == 'payable' && c.status == 'open')
        .fold<double>(0, (s, c) => s + c.amount);
    final net = openReceivableTotal - openPayableTotal;

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const AppTitle(subtitle: 'المستحقات'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'مبالغ لنا'),
              Tab(text: 'مبالغ علينا'),
            ],
          ),
          actions: [
            IconButton(
              tooltip: 'تحديث',
              onPressed: _loading ? null : _load,
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        body: Column(
          children: [
            _heroSummary(
              openReceivableTotal: openReceivableTotal,
              openPayableTotal: openPayableTotal,
              net: net,
            ),
            Expanded(
              child: TabBarView(
                children: [
                  _buildTab(type: 'receivable'),
                  _buildTab(type: 'payable'),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _heroSummary({
    required double openReceivableTotal,
    required double openPayableTotal,
    required double net,
  }) {
    String netLabel;
    double netValue;
    if (net > 0) {
      netLabel = 'صافي لنا';
      netValue = net;
    } else if (net < 0) {
      netLabel = 'صافي علينا';
      netValue = -net;
    } else {
      netLabel = 'الصافي';
      netValue = 0;
    }

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF0F172A), Color(0xFF1E293B)],
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
        ),
        borderRadius: BorderRadius.circular(22),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'ملخص المستحقات المفتوحة',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(child: _heroStat('مبالغ لنا', openReceivableTotal)),
              const SizedBox(width: 12),
              Expanded(child: _heroStat('مبالغ علينا', openPayableTotal)),
            ],
          ),
          const SizedBox(height: 12),
          _heroStat(netLabel, netValue, wide: true),
        ],
      ),
    );
  }

  Widget _heroStat(String label, double value, {bool wide = false}) {
    return Container(
      width: wide ? double.infinity : null,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0x1FFFFFFF),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(color: Colors.white70)),
          const SizedBox(height: 6),
          Text(
            _fmtMoney(value),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTab({required String type}) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(child: Text('خطأ: $_error'));
    }

    final open = _claims
        .where((c) => c.type == type && c.status == 'open')
        .toList();
    final closed = _claims
        .where((c) => c.type == type && c.status == 'closed')
        .toList();

    final addLabel = type == 'receivable'
        ? 'إضافة (مبلغ لنا)'
        : 'إضافة (مبلغ علينا)';
    final actionLabel = type == 'receivable' ? 'تحصيل' : 'سداد';

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          _actionCard(
            addLabel: addLabel,
            openCount: open.length,
            closedCount: closed.length,
            onAdd: () => _addClaimDialog(type),
          ),
          const SizedBox(height: 12),
          _sectionHeader('مفتوحة', open.length),
          const SizedBox(height: 8),
          if (open.isEmpty)
            const Text('لا توجد مستحقات مفتوحة.')
          else
            ...open.map((c) => _claimCard(c, actionLabel)),
          const SizedBox(height: 16),
          _sectionHeader('مقفولة', closed.length),
          const SizedBox(height: 8),
          if (closed.isEmpty)
            const Text('لا توجد مستحقات مقفولة.')
          else
            ...closed.map(_closedClaimCard),
        ],
      ),
    );
  }

  Widget _actionCard({
    required String addLabel,
    required int openCount,
    required int closedCount,
    required VoidCallback onAdd,
  }) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Wrap(
          spacing: 10,
          runSpacing: 10,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            _countPill('مفتوحة', openCount),
            _countPill('مقفولة', closedCount),
            ElevatedButton.icon(
              onPressed: onAdd,
              icon: const Icon(Icons.add),
              label: Text(addLabel),
            ),
          ],
        ),
      ),
    );
  }

  Widget _countPill(String label, int count) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFFE2E8F0),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text('$label: $count'),
    );
  }

  Widget _sectionHeader(String title, int count) {
    return Row(
      children: [
        Text(title, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: const Color(0xFFEEF2FF),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text('$count'),
        ),
      ],
    );
  }

  Widget _claimCard(Claim c, String actionLabel) {
    final busy = _busyClaimIds.contains(c.id);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: const Color(0xFFE2E8F0),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.request_quote),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${c.party} • ${_fmtMoney(c.amount)}',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'المتبقي: ${_fmtMoney(c.amount)}\nتاريخ: ${_fmtDate(c.entryDate)}${_noteLine(c.note)}',
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            ElevatedButton.icon(
              onPressed: busy ? null : () => _settleClaim(c),
              icon: busy
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.check),
              label: Text(actionLabel),
            ),
          ],
        ),
      ),
    );
  }

  Widget _closedClaimCard(Claim c) {
    final extra = c.settledTxnId != null ? ' • عملية #${c.settledTxnId}' : '';
    final settled = c.settledDate != null ? _fmtDate(c.settledDate!) : '-';
    return Card(
      child: ListTile(
        leading: const Icon(Icons.lock),
        title: Text('${c.party} • ${_fmtMoney(c.amount)}'),
        subtitle: Text('أُغلقت: $settled$extra${_noteLine(c.note)}'),
      ),
    );
  }

  String _noteLine(String? note) {
    final n = note?.trim() ?? '';
    if (n.isEmpty) return '';
    return '\nملاحظة: $n';
  }
}
