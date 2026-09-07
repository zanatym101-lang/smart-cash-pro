import 'package:flutter/material.dart';
import '../data/app_db.dart';
import '../models/transaction.dart';
import '../models/wallet.dart';

class TxReversalSheet extends StatefulWidget {
  final Txn txn;
  final List<Wallet> wallets;
  final VoidCallback? onReversed;

  const TxReversalSheet({
    super.key,
    required this.txn,
    required this.wallets,
    this.onReversed,
  });

  static Future<bool?> show(
    BuildContext context, {
    required Txn txn,
    required List<Wallet> wallets,
    VoidCallback? onReversed,
  }) {
    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => TxReversalSheet(
        txn: txn,
        wallets: wallets,
        onReversed: onReversed,
      ),
    );
  }

  @override
  State<TxReversalSheet> createState() => _TxReversalSheetState();
}

class _TxReversalSheetState extends State<TxReversalSheet> {
  final _reasonController = TextEditingController();
  bool _working = false;

  @override
  void dispose() {
    _reasonController.dispose();
    super.dispose();
  }

  String _walletName(int? id) {
    if (id == null) return 'غير محددة';
    final w = widget.wallets.where((x) => x.id == id).toList();
    return w.isEmpty ? '#$id' : w.first.name;
  }

  String _kindLabel(String k) {
    switch (k) {
      case 'transfer':
        return 'تحويل (إرسال نقد)';
      case 'receive':
        return 'استلام (استلام نقد)';
      case 'external_funding':
        return 'تمويل محفظة';
      case 'drawer_deposit':
        return 'إيداع بالدرج';
      case 'claim_collect':
        return 'تحصيل مستحق';
      case 'claim_pay':
        return 'سداد مستحق';
      case 'fawry_cash':
        return 'فوري نقدي';
      case 'fawry_credit':
        return 'فوري آجل';
      default:
        return k;
    }
  }

  ({
    String walletTitle,
    double walletAmount,
    bool walletIsCredit,
    String drawerTitle,
    double drawerAmount,
    bool drawerIsCredit,
    double profitReversed,
    bool hasClaimNotice,
  }) _computeImpacts() {
    final t = widget.txn;
    final amt = t.amount;
    final cf = t.clientFee;
    final nf = t.networkFee;

    if (t.kind == 'transfer') {
      final wName = _walletName(t.walletFromId);
      final walletRefund = amt;
      final drawerDeduction = t.mode == 'type1' ? (amt + cf) : (amt + cf + nf);
      final profit = cf - nf;
      return (
        walletTitle: 'المبلغ المرتجع للمحفظة ($wName)',
        walletAmount: walletRefund,
        walletIsCredit: true,
        drawerTitle: 'المبلغ المخصوم من الخزينة / الدرج',
        drawerAmount: drawerDeduction,
        drawerIsCredit: false,
        profitReversed: profit,
        hasClaimNotice: t.party != null && t.party!.trim().isNotEmpty,
      );
    } else if (t.kind == 'receive') {
      final wName = _walletName(t.walletToId);
      final drawerRefund = (amt - cf).clamp(0, 1e18).toDouble();
      return (
        walletTitle: 'المبلغ المخصوم من المحفظة ($wName)',
        walletAmount: amt,
        walletIsCredit: false,
        drawerTitle: 'المبلغ المرتجع للخزينة / الدرج',
        drawerAmount: drawerRefund,
        drawerIsCredit: true,
        profitReversed: cf,
        hasClaimNotice: t.party != null && t.party!.trim().isNotEmpty,
      );
    } else if (t.kind == 'fawry_cash') {
      return (
        walletTitle: 'رصيد فوري',
        walletAmount: amt,
        walletIsCredit: true,
        drawerTitle: 'المبلغ المخصوم من الدرج',
        drawerAmount: amt + cf,
        drawerIsCredit: false,
        profitReversed: cf,
        hasClaimNotice: false,
      );
    } else if (t.kind == 'fawry_credit') {
      return (
        walletTitle: 'رصيد فوري',
        walletAmount: amt,
        walletIsCredit: true,
        drawerTitle: 'الدرج (غير متأثر)',
        drawerAmount: 0,
        drawerIsCredit: true,
        profitReversed: cf,
        hasClaimNotice: true,
      );
    } else if (t.kind == 'external_funding') {
      final wName = _walletName(t.walletToId);
      return (
        walletTitle: 'المبلغ المخصوم من المحفظة ($wName)',
        walletAmount: amt,
        walletIsCredit: false,
        drawerTitle: 'الدرج',
        drawerAmount: 0,
        drawerIsCredit: true,
        profitReversed: 0,
        hasClaimNotice: false,
      );
    } else {
      return (
        walletTitle: 'المحفظة',
        walletAmount: 0,
        walletIsCredit: true,
        drawerTitle: 'المبلغ المخصوم من الدرج',
        drawerAmount: amt,
        drawerIsCredit: false,
        profitReversed: 0,
        hasClaimNotice: false,
      );
    }
  }

  Future<void> _executeReversal() async {
    setState(() => _working = true);
    try {
      final reason = _reasonController.text.trim();
      await AppDb.instance.reverseTransaction(
        widget.txn.id.toString(),
        reason: reason.isEmpty ? null : reason,
      );

      if (!mounted) return;
      Navigator.of(context).pop(true);

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('تم تنفيذ القيد العكسي وإلغاء العملية بنجاح ✅'),
          backgroundColor: Color(0xFF10B981),
          behavior: SnackBarBehavior.floating,
        ),
      );

      widget.onReversed?.call();
    } catch (e) {
      if (!mounted) return;
      final msg = e.toString().replaceFirst('Exception: ', '');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(msg),
          backgroundColor: Colors.red.shade700,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final impact = _computeImpacts();
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Container(
      padding: EdgeInsets.fromLTRB(20, 16, 20, 20 + bottomInset),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.orange.shade50,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.undo_rounded,
                    color: Colors.orange,
                    size: 28,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'إلغاء وقيد عكسي',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        'معاملة #${widget.txn.id} • ${_kindLabel(widget.txn.kind)}',
                        style: TextStyle(
                          color: Colors.grey.shade600,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'الأثر المالي المتوقع للقيد العكسي:',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                  const Divider(height: 16),
                  if (impact.walletAmount > 0)
                    _impactRow(
                      impact.walletTitle,
                      '${impact.walletIsCredit ? '+' : '-'}${impact.walletAmount.toStringAsFixed(2)} ج.م',
                      impact.walletIsCredit ? Colors.green : Colors.red.shade700,
                      impact.walletIsCredit ? Icons.add_circle_outline : Icons.remove_circle_outline,
                    ),
                  if (impact.drawerAmount > 0) ...[
                    const SizedBox(height: 8),
                    _impactRow(
                      impact.drawerTitle,
                      '${impact.drawerIsCredit ? '+' : '-'}${impact.drawerAmount.toStringAsFixed(2)} ج.م',
                      impact.drawerIsCredit ? Colors.green : Colors.red.shade700,
                      impact.drawerIsCredit ? Icons.add_circle_outline : Icons.remove_circle_outline,
                    ),
                  ],
                  if (impact.profitReversed > 0) ...[
                    const SizedBox(height: 8),
                    _impactRow(
                      'عكس الأرباح المحققة',
                      '-${impact.profitReversed.toStringAsFixed(2)} ج.م',
                      Colors.orange.shade800,
                      Icons.trending_down_rounded,
                    ),
                  ],
                ],
              ),
            ),
            if (impact.hasClaimNotice) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.blue.shade200),
                ),
                child: Row(
                  children: [
                    Icon(Icons.info_outline, color: Colors.blue.shade700, size: 20),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        'سيتم إلغاء أي مطالبة مفتوحة مرتبطة بهذه العملية تلقائياً وتحديث كشف حساب العميل.',
                        style: TextStyle(fontSize: 12, color: Color(0xFF1E3A8A)),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.amber.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.amber.shade300),
              ),
              child: Row(
                children: [
                  Icon(Icons.shield_outlined, color: Colors.amber.shade900, size: 20),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'ضمان عدم السلبية: لن يكتمل القيد إذا كان رصيد المحفظة أو الخزينة غير كافٍ.',
                      style: TextStyle(fontSize: 12, color: Color(0xFF78350F)),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _reasonController,
              decoration: InputDecoration(
                labelText: 'سبب الإلغاء (اختياري)',
                hintText: 'مثال: خطأ في إدخال الرقم أو المبلغ',
                prefixIcon: const Icon(Icons.edit_note, size: 20),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                isDense: true,
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _working ? null : () => Navigator.of(context).pop(),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text('تراجع'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: ElevatedButton(
                    onPressed: _working ? null : _executeReversal,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red.shade700,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: _working
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Text(
                            'تأكيد القيد العكسي ↩️',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _impactRow(String title, String val, Color color, IconData icon) {
    return Row(
      children: [
        Icon(icon, color: color, size: 18),
        const SizedBox(width: 8),
        Expanded(
          child: Text(title, style: const TextStyle(fontSize: 13)),
        ),
        Text(
          val,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
      ],
    );
  }
}