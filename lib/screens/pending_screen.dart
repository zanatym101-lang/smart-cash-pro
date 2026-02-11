// v4: Pending Center (production-ready UI behavior).
// - UI: read-only + commands only (approve/reject)
// - Accounting validation/apply happens inside AppDb -> AccountingEngine
import 'package:flutter/material.dart';
import '../widgets/app_title.dart';
import '../data/app_db.dart';
import '../models/transaction.dart';
import '../models/wallet.dart';

class PendingScreen extends StatefulWidget {
  const PendingScreen({super.key});

  @override
  State<PendingScreen> createState() => _PendingScreenState();
}

class _PendingScreenState extends State<PendingScreen> {
  bool _loading = true;
  final Set<int> _busyTxIds = {};
  List<Txn> _pending = [];
  Map<int, Wallet> _walletsById = {};

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final wallets = await AppDb.instance.listWallets();
      final pending = await AppDb.instance.listTxns(status: 'pending');

      _walletsById = {for (final w in wallets) w.id: w};
      _pending = pending;
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  String _walletName(int? id) {
    if (id == null) return '-';
    return _walletsById[id]?.name ?? 'محفظة#$id';
  }

  String _formatMoney(double v) => v.toStringAsFixed(2);

  String _title(Txn t) {
    // Examples:
    // تحويل (type1) • من: Vodafone
    // تمويل محفظة • إلى: Orange
    switch (t.kind) {
      case 'transfer':
        return 'تحويل (${t.mode}) • من: ${_walletName(t.walletFromId)}';
      case 'external_funding':
      case 'deposit':
      case 'receive':
        return 'استلام • إلى: ${_walletName(t.walletToId)}';
      case 'drawer_deposit':
      case 'drawer_fund':
        return 'تمويل درج';
      case 'fawry_cash':
        return 'فوري نقدي • ${t.serviceName ?? ''}';
      case 'fawry_credit':
        return 'فوري آجل • ${t.serviceName ?? ''} • العميل: ${t.party ?? ''}';
      default:
        return '${t.kind} (${t.mode})';
    }
  }

  String _subtitle(Txn t) {
    if (t.kind == 'fawry_cash' || t.kind == 'fawry_credit') {
      final parts = <String>[];
      if (t.serviceName != null && t.serviceName!.trim().isNotEmpty) {
        parts.add('الخدمة: ${t.serviceName}');
      }
      parts.add('القيمة: ${_formatMoney(t.amount)}');
      parts.add('الربح/العمولة: ${_formatMoney(t.clientFee)}');
      parts.add('إجمالي العميل: ${_formatMoney(t.amount + t.clientFee)}');
      if (t.reference != null && t.reference!.trim().isNotEmpty) {
        parts.add('رقم: ${t.reference}');
      }
      if (t.note != null && t.note!.trim().isNotEmpty) {
        parts.add('ملاحظة: ${t.note}');
      }
      return parts.join(' - ');
    }

    final parts = <String>[];
    parts.add('المبلغ: ${_formatMoney(t.amount)}');
    if (t.clientFee != 0) parts.add('العمولة: ${_formatMoney(t.clientFee)}');
    if (t.networkFee != 0) parts.add('رسوم الشبكة: ${_formatMoney(t.networkFee)}');
    if (t.note != null && t.note!.trim().isNotEmpty) parts.add('ملاحظة: ${t.note}');
    return parts.join(' - ');
  }

  Future<bool> _confirmDialog({
    required String title,
    required String body,
    required String okText,
  }) async {
    final res = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(okText),
          ),
        ],
      ),
    );
    return res == true;
  }

  Future<void> _approve(Txn t) async {
    if (_busyTxIds.contains(t.id)) return;

    final ok = await _confirmDialog(
      title: 'اعتماد عملية معلّقة',
      body: 'سيتم اعتماد العملية رقم #${t.id} وتطبيقها على الحسابات.',
      okText: 'اعتماد',
    );
    if (!ok) return;

    setState(() => _busyTxIds.add(t.id));
    try {
      await AppDb.instance.confirmPending(t.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تم الاعتماد ✅ (#${t.id})')),
      );
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('فشل الاعتماد (#${t.id}): $e')),
      );
    } finally {
      if (mounted) setState(() => _busyTxIds.remove(t.id));
    }
  }

  Future<void> _reject(Txn t) async {
    if (_busyTxIds.contains(t.id)) return;

    final ok = await _confirmDialog(
      title: 'رفض عملية معلّقة',
      body: 'سيتم رفض العملية رقم #${t.id}. لا يمكن التراجع.',
      okText: 'تأكيد الرفض',
    );
    if (!ok) return;

    setState(() => _busyTxIds.add(t.id));
    try {
      await AppDb.instance.cancelPending(t.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تم الرفض ✅ (#${t.id})')),
      );
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('فشل الرفض (#${t.id}): $e')),
      );
    } finally {
      if (mounted) setState(() => _busyTxIds.remove(t.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const AppTitle(subtitle: 'العمليات المعلقة'),
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
          : _pending.isEmpty
              ? _emptyState()
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                    children: [
                      _summaryCard(),
                      const SizedBox(height: 12),
                      ..._pending.map(_pendingCard),
                    ],
                  ),
                ),
    );
  }

  Widget _summaryCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF0F172A), Color(0xFF1E293B)],
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
        ),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'مركز العمليات المعلّقة',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 10),
          Text(
            'عدد العمليات: ${_pending.length}',
            style: const TextStyle(color: Colors.white70),
          ),
          const SizedBox(height: 6),
          const Text(
            'اعتماد/رفض العمليات يطبق الأثر المحاسبي بالكامل.',
            style: TextStyle(color: Colors.white70, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _pendingCard(Txn t) {
    final busy = _busyTxIds.contains(t.id);
    final date = '${t.entryDate.year}-${t.entryDate.month.toString().padLeft(2, '0')}-${t.entryDate.day.toString().padLeft(2, '0')}'
        ' ${t.entryDate.hour.toString().padLeft(2, '0')}:${t.entryDate.minute.toString().padLeft(2, '0')}';

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE2E8F0),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text('#${t.id}'),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(_title(t), style: const TextStyle(fontWeight: FontWeight.w700)),
                ),
                Text(_formatMoney(t.amount)),
              ],
            ),
            const SizedBox(height: 6),
            Text(_subtitle(t)),
            const SizedBox(height: 6),
            Text('التاريخ: $date', style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ElevatedButton.icon(
                  onPressed: busy ? null : () => _approve(t),
                  icon: busy
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.check),
                  label: const Text('اعتماد'),
                ),
                OutlinedButton.icon(
                  onPressed: busy ? null : () => _reject(t),
                  icon: const Icon(Icons.close),
                  label: const Text('رفض'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _emptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: const [
          Icon(Icons.inbox, size: 48, color: Color(0xFF94A3B8)),
          SizedBox(height: 8),
          Text('لا توجد عمليات معلّقة'),
        ],
      ),
    );
  }
}
