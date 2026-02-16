import 'package:flutter/material.dart';
import '../widgets/app_title.dart';
import '../data/app_db.dart';
import '../data/app_session.dart';

class AuditLogScreen extends StatefulWidget {
  const AuditLogScreen({super.key});

  @override
  State<AuditLogScreen> createState() => _AuditLogScreenState();
}

class _AuditLogScreenState extends State<AuditLogScreen> {
  final _searchCtrl = TextEditingController();
  bool _loading = true;
  bool _verifying = false;
  String _typeFilter = 'all';
  List<Map<String, dynamic>> _items = [];
  AuditChainStatus? _chain;

  static const Map<String, String> _typeLabels = {
    'all': 'الكل',
    'transfer_add': 'إضافة تحويل',
    'receive_add': 'إضافة استلام',
    'expense_add': 'إضافة مصروف',
    'fawry_add': 'إضافة فوري',
    'drawer_deposit': 'تمويل درج',
    'external_funding': 'تمويل محفظة',
    'claim_add': 'إضافة مستحق',
    'claim_settle': 'تحصيل/سداد مستحق',
    'pending_confirm': 'اعتماد عملية معلقة',
    'pending_cancel': 'إلغاء عملية معلقة',
    'txn_rollback': 'Rollback عملية',
    'wallet_add': 'إضافة محفظة',
    'wallet_update': 'تعديل محفظة',
    'daily_close': 'إغلاق يوم',
    'daily_close_reopen': 'إلغاء إغلاق يوم',
  };

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final items = await AppDb.instance.listAudit();
      final chain = await AppDb.instance.verifyAuditChain();
      if (!mounted) return;
      setState(() {
        _items = items;
        _chain = chain;
      });
    } catch (_) {
      // Keep last known state if loading fails.
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _verifyChain() async {
    setState(() => _verifying = true);
    try {
      final chain = await AppDb.instance.verifyAuditChain();
      if (!mounted) return;
      setState(() => _chain = chain);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            chain.ok
                ? 'سلسلة التدقيق سليمة ✅'
                : 'تحذير: سلسلة التدقيق غير سليمة',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('فشل التحقق: $e')));
    } finally {
      if (mounted) setState(() => _verifying = false);
    }
  }

  Future<void> _clearLog() async {
    if (!AppSession.isAdmin) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('مسح سجل العمليات؟'),
        content: const Text('سيتم حذف كل السجل نهائيًا.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('مسح'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await AppDb.instance.clearAudit();
    await _load();
  }

  String _formatDate(String? iso) {
    if (iso == null || iso.trim().isEmpty) return '';
    final dt = DateTime.tryParse(iso);
    if (dt == null) return iso;
    final d = dt.toLocal();
    final y = d.year.toString().padLeft(4, '0');
    final m = d.month.toString().padLeft(2, '0');
    final day = d.day.toString().padLeft(2, '0');
    final h = d.hour.toString().padLeft(2, '0');
    final min = d.minute.toString().padLeft(2, '0');
    return '$y-$m-$day $h:$min';
  }

  List<Map<String, dynamic>> get _filtered {
    final q = _searchCtrl.text.trim().toLowerCase();
    final type = _typeFilter;
    return _items.where((e) {
      if (type != 'all' && e['type']?.toString() != type) return false;
      if (q.isEmpty) return true;
      final hay = [
        e['type'],
        e['note'],
        e['by'],
        e['role'],
        e['dateKey'],
        e['txnId'],
        e['claimId'],
        e['walletId'],
        e['amount'],
      ].map((v) => v?.toString().toLowerCase() ?? '').join(' ');
      return hay.contains(q);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final types = _typeLabels.entries.toList();
    return Scaffold(
      appBar: AppBar(
        title: const AppTitle(subtitle: 'سجل عمليات النظام'),
        actions: [
          IconButton(
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh),
            tooltip: 'تحديث',
          ),
          IconButton(
            onPressed: (_loading || _verifying) ? null : _verifyChain,
            icon: _verifying
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.shield),
            tooltip: 'التحقق من سلامة السلسلة',
          ),
          IconButton(
            onPressed: _loading ? null : _clearLog,
            icon: const Icon(Icons.delete_outline),
            tooltip: 'مسح السجل',
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            if (_chain != null)
              Card(
                child: ListTile(
                  leading: Icon(
                    _chain!.ok ? Icons.verified : Icons.warning_amber_rounded,
                    color: _chain!.ok ? Colors.green : Colors.orange,
                  ),
                  title: Text(
                    _chain!.ok
                        ? 'سلسلة التدقيق سليمة'
                        : 'تحذير: سلسلة التدقيق غير سليمة',
                  ),
                  subtitle: Text(
                    'عدد السجلات: ${_chain!.count}'
                    '${_chain!.tailHash == null ? '' : ' • Tail: ${_chain!.tailHash!.substring(0, 12)}...'}'
                    '${_chain!.error == null ? '' : ' • ${_chain!.error}'}',
                  ),
                ),
              ),
            if (_chain != null) const SizedBox(height: 8),
            TextField(
              controller: _searchCtrl,
              decoration: const InputDecoration(
                labelText: 'بحث',
                prefixIcon: Icon(Icons.search),
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              initialValue: _typeFilter,
              items: types
                  .map(
                    (e) => DropdownMenuItem(value: e.key, child: Text(e.value)),
                  )
                  .toList(),
              onChanged: (v) {
                if (v == null) return;
                setState(() => _typeFilter = v);
              },
              decoration: const InputDecoration(labelText: 'نوع العملية'),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _filtered.isEmpty
                  ? const Center(child: Text('لا توجد عناصر مطابقة'))
                  : ListView.separated(
                      itemCount: _filtered.length,
                      separatorBuilder: (context, index) =>
                          const SizedBox(height: 8),
                      itemBuilder: (context, i) {
                        final e = _filtered[i];
                        final type = e['type']?.toString() ?? '';
                        final label = _typeLabels[type] ?? type;
                        final at = _formatDate(e['at']?.toString());
                        final by = e['by']?.toString() ?? '';
                        final role = e['role']?.toString() ?? '';
                        final note = e['note']?.toString();
                        final amount = e['amount'];
                        final parts = <String>[];
                        if (at.isNotEmpty) {
                          parts.add('الوقت: $at');
                        }
                        if (by.isNotEmpty) {
                          parts.add('بواسطة: $by');
                        }
                        if (role.isNotEmpty) {
                          parts.add('الدور: $role');
                        }
                        if (e['dateKey'] != null) {
                          parts.add('اليوم: ${e['dateKey']}');
                        }
                        if (e['txnId'] != null) {
                          parts.add('Txn: #${e['txnId']}');
                        }
                        if (e['claimId'] != null) {
                          parts.add('Claim: #${e['claimId']}');
                        }
                        if (e['walletId'] != null) {
                          parts.add('Wallet: #${e['walletId']}');
                        }
                        if (amount != null) {
                          parts.add('المبلغ: ${amount.toString()}');
                        }
                        if (note != null && note.trim().isNotEmpty) {
                          parts.add('ملاحظة: ${note.trim()}');
                        }
                        return Card(
                          child: ListTile(
                            title: Text(
                              label,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            subtitle: Text(parts.join(' | ')),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
