import 'package:flutter/material.dart';
import '../widgets/app_title.dart';
import '../data/app_db.dart';
import '../data/app_session.dart';
import '../models/transaction.dart';
import '../models/wallet.dart';

class TxDetailsScreen extends StatefulWidget {
  final Txn txn;
  final List<Wallet> wallets;

  const TxDetailsScreen({super.key, required this.txn, required this.wallets});

  @override
  State<TxDetailsScreen> createState() => _TxDetailsScreenState();
}

class _TxDetailsScreenState extends State<TxDetailsScreen> {
  late Txn _txn;
  bool _working = false;

  @override
  void initState() {
    super.initState();
    _txn = widget.txn;
  }

  String _walletName(int? id) {
    if (id == null) return '-';
    final w = widget.wallets.where((x) => x.id == id).toList();
    return w.isEmpty ? '#$id' : w.first.name;
  }

  String _statusLabel(String s) {
    if (s == 'posted') return 'معتمد';
    if (s == 'rolled_back') return 'ملغي (Rollback)';
    if (s == 'pending') return 'معلّق';
    return 'غير معروف';
  }

  String _kindLabel(String k) {
    switch (k) {
      case 'transfer':
        return 'تحويل';
      case 'receive':
        return 'استلام';
      case 'external_funding':
        return 'تمويل خارجي';
      case 'drawer_deposit':
        return 'تمويل درج';
      case 'claim_collect':
        return 'تحصيل مستحقات';
      case 'claim_pay':
        return 'سداد مستحقات';
      case 'fawry_cash':
        return 'فوري نقدي (تحصيل)';
      case 'fawry_credit':
        return 'فوري آجل (خدمة)';
      case 'rollback':
        return 'Rollback';
      default:
        return k;
    }
  }

  String _money(double v) => v.toStringAsFixed(2);

  String _delta(double v) {
    if (v > 0) return '+${_money(v)}';
    if (v < 0) return _money(v);
    return '0.00';
  }

  String _roleLabel(String role) {
    switch (role) {
      case 'admin':
        return 'أدمن';
      case 'user':
        return 'مستخدم';
      case 'system':
        return 'نظام';
      default:
        return role;
    }
  }

  ({
    double walletDelta,
    double drawerDelta,
    double profitDelta,
    String walletLabel,
  })
  _computeImpact() {
    final amt = _txn.amount;
    final cf = _txn.clientFee;
    final nf = _txn.networkFee;

    double walletDelta = 0;
    double drawerDelta = 0;
    double profitDelta = 0;
    String walletLabel = '-';

    if (_txn.kind == 'transfer') {
      walletLabel = _walletName(_txn.walletFromId);
      // Stored amount for transfer is wallet spend.
      walletDelta = -amt;
      if (_txn.mode == 'type1') {
        drawerDelta = (amt - nf) + cf;
      } else if (_txn.mode == 'type2_v2') {
        drawerDelta = amt + cf;
      } else {
        // Legacy type2
        drawerDelta = amt - nf;
      }
      profitDelta = cf;
    } else if (_txn.kind == 'receive') {
      walletLabel = _walletName(_txn.walletToId);
      profitDelta = cf;
      if (_txn.mode == 'cash') {
        walletDelta = amt;
        drawerDelta = -amt;
      } else if (_txn.mode == 'deduct') {
        walletDelta = amt;
        drawerDelta = -(amt - cf);
      } else {
        walletDelta = amt + cf;
      }
    } else if (_txn.kind == 'external_funding') {
      walletLabel = _walletName(_txn.walletToId);
      walletDelta = amt;
    } else if (_txn.kind == 'drawer_deposit') {
      drawerDelta = amt;
    } else if (_txn.kind == 'claim_collect') {
      drawerDelta = amt;
    } else if (_txn.kind == 'claim_pay') {
      drawerDelta = -amt;
    } else if (_txn.kind == 'fawry_cash') {
      drawerDelta = cf;
      profitDelta = cf;
    } else if (_txn.kind == 'fawry_credit') {
      drawerDelta = -amt;
      profitDelta = cf;
    }

    return (
      walletDelta: walletDelta,
      drawerDelta: drawerDelta,
      profitDelta: profitDelta,
      walletLabel: walletLabel,
    );
  }

  Future<void> _refreshTxn() async {
    final txns = await AppDb.instance.listTxns();
    final updated = txns.firstWhere((t) => t.id == _txn.id, orElse: () => _txn);
    setState(() => _txn = updated);
  }

  Future<void> _approve() async {
    setState(() => _working = true);
    try {
      await AppDb.instance.confirmPending(_txn.id);
      await _refreshTxn();
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('تم اعتماد العملية ✅')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('فشل الاعتماد: $e')));
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _cancel() async {
    setState(() => _working = true);
    try {
      await AppDb.instance.cancelPending(_txn.id);
      await _refreshTxn();
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('تم رفض العملية ✅')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('فشل الرفض: $e')));
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _rollback() async {
    setState(() => _working = true);
    try {
      await AppDb.instance.rollbackPosted(_txn.id);
      await _refreshTxn();
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('تم عمل Rollback ✅')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('فشل Rollback: $e')));
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final impact = _computeImpact();
    final date =
        '${_txn.entryDate.year}-${_txn.entryDate.month.toString().padLeft(2, '0')}-${_txn.entryDate.day.toString().padLeft(2, '0')} '
        '${_txn.entryDate.hour.toString().padLeft(2, '0')}:${_txn.entryDate.minute.toString().padLeft(2, '0')}';
    final created =
        '${_txn.createdAt.year}-${_txn.createdAt.month.toString().padLeft(2, '0')}-${_txn.createdAt.day.toString().padLeft(2, '0')} '
        '${_txn.createdAt.hour.toString().padLeft(2, '0')}:${_txn.createdAt.minute.toString().padLeft(2, '0')}';

    final isPending = _txn.status == 'pending';
    final isPosted = _txn.status == 'posted';

    return Scaffold(
      appBar: AppBar(title: const AppTitle(subtitle: 'تفاصيل العملية')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          if (AppSession.isAdmin) ...[
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'إجراءات الأدمن',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        if (isPending)
                          ElevatedButton.icon(
                            onPressed: _working ? null : _approve,
                            icon: const Icon(Icons.check),
                            label: const Text('اعتماد'),
                          ),
                        if (isPending)
                          OutlinedButton.icon(
                            onPressed: _working ? null : _cancel,
                            icon: const Icon(Icons.close),
                            label: const Text('رفض'),
                          ),
                        if (isPosted)
                          ElevatedButton.icon(
                            onPressed: _working ? null : _rollback,
                            icon: const Icon(Icons.undo),
                            label: const Text('Rollback (عكس التأثير)'),
                          ),
                      ],
                    ),
                    if (isPosted)
                      const Padding(
                        padding: EdgeInsets.only(top: 8),
                        child: Text(
                          'تنبيه: Rollback لا يُسمح به إذا كانت المستحقات قد تم تحصيلها.',
                          style: TextStyle(fontSize: 12),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 10),
          ],
          _headerCard(
            '${_kindLabel(_txn.kind)} • ${_statusLabel(_txn.status)}',
          ),
          const SizedBox(height: 12),
          _sectionCard(
            title: 'تفاصيل العملية',
            child: Column(
              children: [
                _infoRow('التاريخ', date),
                _infoRow(
                  'أنشئت بواسطة',
                  '${_txn.createdBy} (${_roleLabel(_txn.createdRole)})',
                ),
                _infoRow('تاريخ الإنشاء', created),
                _infoRow('المبلغ', _money(_txn.amount)),
                if ((_txn.serviceName ?? '').trim().isNotEmpty)
                  _infoRow('الخدمة', _txn.serviceName!),
                if ((_txn.reference ?? '').trim().isNotEmpty)
                  _infoRow('الرقم المرجعي', _txn.reference!),
                if ((_txn.party ?? '').trim().isNotEmpty)
                  _infoRow('الطرف', _txn.party!),
                if (_txn.kind == 'fawry_cash' || _txn.kind == 'fawry_credit')
                  _infoRow(
                    'إجمالي العميل',
                    _money(_txn.amount + _txn.clientFee),
                  ),
                _infoRow('العمولة (CF)', _money(_txn.clientFee)),
                _infoRow('رسوم الشبكة (NF)', _money(_txn.networkFee)),
                if ((_txn.note ?? '').trim().isNotEmpty)
                  _infoRow('ملاحظة', _txn.note!),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _sectionCard(
            title: 'تأثير العملية على الحسابات',
            child: Column(
              children: [
                _impactRow(
                  context,
                  label: 'المحفظة (${impact.walletLabel})',
                  delta: impact.walletDelta,
                ),
                const Divider(),
                _impactRow(
                  context,
                  label: 'الدرج (Drawer)',
                  delta: impact.drawerDelta,
                ),
                const Divider(),
                _impactRow(context, label: 'الربح', delta: impact.profitDelta),
              ],
            ),
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
          const Icon(Icons.receipt, color: Colors.white, size: 32),
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

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: Text(label)),
          const SizedBox(width: 10),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }

  Widget _impactRow(
    BuildContext context, {
    required String label,
    required double delta,
  }) {
    final txt = _delta(delta);
    final isPos = delta > 0;
    final isNeg = delta < 0;
    return Row(
      children: [
        Expanded(child: Text(label)),
        const SizedBox(width: 12),
        Text(
          txt,
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(width: 6),
        Icon(
          isPos
              ? Icons.arrow_upward
              : (isNeg ? Icons.arrow_downward : Icons.remove),
          size: 18,
        ),
      ],
    );
  }
}
