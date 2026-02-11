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
  String _typeFilter = 'all';
  List<Map<String, dynamic>> _items = [];

  static const Map<String, String> _typeLabels = {
    'all': 'ط·آ·ط¢آ§ط·آ¸أ¢â‚¬â€چط·آ¸ط¦â€™ط·آ¸أ¢â‚¬â€چ',
    'transfer_add':
        'ط·آ·ط¢آ¥ط·آ·ط¢آ¶ط·آ·ط¢آ§ط·آ¸ط¸آ¾ط·آ·ط¢آ© ط·آ·ط¹آ¾ط·آ·ط¢آ­ط·آ¸ط«â€ ط·آ¸ط¸آ¹ط·آ¸أ¢â‚¬â€چ',
    'receive_add':
        'ط·آ·ط¢آ¥ط·آ·ط¢آ¶ط·آ·ط¢آ§ط·آ¸ط¸آ¾ط·آ·ط¢آ© ط·آ·ط¢آ§ط·آ·ط¢آ³ط·آ·ط¹آ¾ط·آ¸أ¢â‚¬â€چط·آ·ط¢آ§ط·آ¸أ¢â‚¬آ¦',
    'expense_add':
        'ط·آ·ط¢آ¥ط·آ·ط¢آ¶ط·آ·ط¢آ§ط·آ¸ط¸آ¾ط·آ·ط¢آ© ط·آ¸أ¢â‚¬آ¦ط·آ·ط¢آµط·آ·ط¢آ±ط·آ¸ط«â€ ط·آ¸ط¸آ¾',
    'fawry_add':
        'ط·آ·ط¢آ¥ط·آ·ط¢آ¶ط·آ·ط¢آ§ط·آ¸ط¸آ¾ط·آ·ط¢آ© ط·آ¸ط¸آ¾ط·آ¸ط«â€ ط·آ·ط¢آ±ط·آ¸ط¸آ¹',
    'drawer_deposit':
        'ط·آ·ط¹آ¾ط·آ¸أ¢â‚¬آ¦ط·آ¸ط«â€ ط·آ¸ط¸آ¹ط·آ¸أ¢â‚¬â€چ ط·آ·ط¢آ¯ط·آ·ط¢آ±ط·آ·ط¢آ¬',
    'external_funding':
        'ط·آ·ط¹آ¾ط·آ¸أ¢â‚¬آ¦ط·آ¸ط«â€ ط·آ¸ط¸آ¹ط·آ¸أ¢â‚¬â€چ ط·آ¸أ¢â‚¬آ¦ط·آ·ط¢آ­ط·آ¸ط¸آ¾ط·آ·ط¢آ¸ط·آ·ط¢آ©',
    'claim_add':
        'ط·آ·ط¢آ¥ط·آ·ط¢آ¶ط·آ·ط¢آ§ط·آ¸ط¸آ¾ط·آ·ط¢آ© ط·آ¸أ¢â‚¬آ¦ط·آ·ط¢آ³ط·آ·ط¹آ¾ط·آ·ط¢آ­ط·آ¸أ¢â‚¬ع‘',
    'claim_settle':
        'ط·آ·ط¹آ¾ط·آ·ط¢آ­ط·آ·ط¢آµط·آ¸ط¸آ¹ط·آ¸أ¢â‚¬â€چ/ط·آ·ط¢آ³ط·آ·ط¢آ¯ط·آ·ط¢آ§ط·آ·ط¢آ¯ ط·آ¸أ¢â‚¬آ¦ط·آ·ط¢آ³ط·آ·ط¹آ¾ط·آ·ط¢آ­ط·آ¸أ¢â‚¬ع‘',
    'pending_confirm':
        'ط·آ·ط¢آ§ط·آ·ط¢آ¹ط·آ·ط¹آ¾ط·آ¸أ¢â‚¬آ¦ط·آ·ط¢آ§ط·آ·ط¢آ¯ ط·آ·ط¢آ¹ط·آ¸أ¢â‚¬آ¦ط·آ¸أ¢â‚¬â€چط·آ¸ط¸آ¹ط·آ·ط¢آ©',
    'pending_cancel':
        'ط·آ·ط¢آ¥ط·آ¸أ¢â‚¬â€چط·آ·ط·â€؛ط·آ·ط¢آ§ط·آ·ط·إ’ ط·آ·ط¢آ¹ط·آ¸أ¢â‚¬آ¦ط·آ¸أ¢â‚¬â€چط·آ¸ط¸آ¹ط·آ·ط¢آ© ط·آ¸أ¢â‚¬آ¦ط·آ·ط¢آ¹ط·آ¸أ¢â‚¬â€چط·آ¸أ¢â‚¬ع©ط·آ¸أ¢â‚¬ع‘ط·آ·ط¢آ©',
    'txn_rollback': 'Rollback ط·آ·ط¢آ¹ط·آ¸أ¢â‚¬آ¦ط·آ¸أ¢â‚¬â€چط·آ¸ط¸آ¹ط·آ·ط¢آ©',
    'wallet_add':
        'ط·آ·ط¢آ¥ط·آ·ط¢آ¶ط·آ·ط¢آ§ط·آ¸ط¸آ¾ط·آ·ط¢آ© ط·آ¸أ¢â‚¬آ¦ط·آ·ط¢آ­ط·آ¸ط¸آ¾ط·آ·ط¢آ¸ط·آ·ط¢آ©',
    'wallet_update':
        'ط·آ·ط¹آ¾ط·آ·ط¢آ¹ط·آ·ط¢آ¯ط·آ¸ط¸آ¹ط·آ¸أ¢â‚¬â€چ ط·آ¸أ¢â‚¬آ¦ط·آ·ط¢آ­ط·آ¸ط¸آ¾ط·آ·ط¢آ¸ط·آ·ط¢آ©',
    'daily_close':
        'ط·آ·ط¢آ¥ط·آ·ط·â€؛ط·آ¸أ¢â‚¬â€چط·آ·ط¢آ§ط·آ¸أ¢â‚¬ع‘ ط·آ¸ط¸آ¹ط·آ¸ط«â€ ط·آ¸أ¢â‚¬آ¦',
    'daily_close_reopen':
        'ط·آ·ط¢آ¥ط·آ¸أ¢â‚¬â€چط·آ·ط·â€؛ط·آ·ط¢آ§ط·آ·ط·إ’ ط·آ·ط¢آ¥ط·آ·ط·â€؛ط·آ¸أ¢â‚¬â€چط·آ·ط¢آ§ط·آ¸أ¢â‚¬ع‘ ط·آ¸ط¸آ¹ط·آ¸ط«â€ ط·آ¸أ¢â‚¬آ¦',
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
      if (!mounted) return;
      setState(() => _items = items);
    } catch (_) {
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _clearLog() async {
    if (!AppSession.isAdmin) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text(
          'ط·آ¸أ¢â‚¬آ¦ط·آ·ط¢آ³ط·آ·ط¢آ­ ط·آ·ط¢آ³ط·آ·ط¢آ¬ط·آ¸أ¢â‚¬â€چ ط·آ·ط¢آ§ط·آ¸أ¢â‚¬â€چط·آ·ط¹آ¾ط·آ·ط¢آ¯ط·آ¸أ¢â‚¬ع‘ط·آ¸ط¸آ¹ط·آ¸أ¢â‚¬ع‘ط·آ·ط¹ط›',
        ),
        content: const Text(
          'ط·آ·ط¢آ³ط·آ¸ط¸آ¹ط·آ·ط¹آ¾ط·آ¸أ¢â‚¬آ¦ ط·آ·ط¢آ­ط·آ·ط¢آ°ط·آ¸ط¸آ¾ ط·آ·ط¢آ§ط·آ¸أ¢â‚¬â€چط·آ·ط¢آ³ط·آ·ط¢آ¬ط·آ¸أ¢â‚¬â€چ ط·آ·ط¢آ¨ط·آ·ط¢آ§ط·آ¸أ¢â‚¬â€چط·آ¸ط¦â€™ط·آ·ط¢آ§ط·آ¸أ¢â‚¬آ¦ط·آ¸أ¢â‚¬â€چ.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('ط·آ·ط¢آ¥ط·آ¸أ¢â‚¬â€چط·آ·ط·â€؛ط·آ·ط¢آ§ط·آ·ط·إ’'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('ط·آ¸أ¢â‚¬آ¦ط·آ·ط¢آ³ط·آ·ط¢آ­'),
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
        title: const AppTitle(
          subtitle:
              'ط·آ·ط¢آ³ط·آ·ط¢آ¬ط·آ¸أ¢â‚¬â€چ ط·آ·ط¢آ§ط·آ¸أ¢â‚¬â€چط·آ·ط¹آ¾ط·آ·ط¢آ¯ط·آ¸أ¢â‚¬ع‘ط·آ¸ط¸آ¹ط·آ¸أ¢â‚¬ع‘',
        ),
        actions: [
          IconButton(
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh),
            tooltip: 'ط·آ·ط¹آ¾ط·آ·ط¢آ­ط·آ·ط¢آ¯ط·آ¸ط¸آ¹ط·آ·ط¢آ«',
          ),
          IconButton(
            onPressed: _loading ? null : _clearLog,
            icon: const Icon(Icons.delete_outline),
            tooltip:
                'ط·آ¸أ¢â‚¬آ¦ط·آ·ط¢آ³ط·آ·ط¢آ­ ط·آ·ط¢آ§ط·آ¸أ¢â‚¬â€چط·آ·ط¢آ³ط·آ·ط¢آ¬ط·آ¸أ¢â‚¬â€چ',
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            TextField(
              controller: _searchCtrl,
              decoration: const InputDecoration(
                labelText: 'ط·آ·ط¢آ¨ط·آ·ط¢آ­ط·آ·ط¢آ«',
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
              decoration: const InputDecoration(
                labelText:
                    'ط·آ¸أ¢â‚¬آ ط·آ¸ط«â€ ط·آ·ط¢آ¹ ط·آ·ط¢آ§ط·آ¸أ¢â‚¬â€چط·آ·ط¢آ­ط·آ·ط¢آ¯ط·آ·ط¢آ«',
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _filtered.isEmpty
                  ? const Center(
                      child: Text(
                        'ط·آ¸أ¢â‚¬â€چط·آ·ط¢آ§ ط·آ·ط¹آ¾ط·آ¸ط«â€ ط·آ·ط¢آ¬ط·آ·ط¢آ¯ ط·آ·ط¢آ³ط·آ·ط¢آ¬ط·آ¸أ¢â‚¬â€چط·آ·ط¢آ§ط·آ·ط¹آ¾',
                      ),
                    )
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
                          parts.add(
                            'ط·آ·ط¢آ§ط·آ¸أ¢â‚¬â€چط·آ¸ط«â€ ط·آ¸أ¢â‚¬ع‘ط·آ·ط¹آ¾: $at',
                          );
                        }
                        if (by.isNotEmpty) {
                          parts.add(
                            'ط·آ·ط¢آ¨ط·آ¸ط«â€ ط·آ·ط¢آ§ط·آ·ط¢آ³ط·آ·ط¢آ·ط·آ·ط¢آ©: $by',
                          );
                        }
                        if (role.isNotEmpty) {
                          parts.add(
                            'ط·آ·ط¢آ§ط·آ¸أ¢â‚¬â€چط·آ·ط¢آ¯ط·آ¸ط«â€ ط·آ·ط¢آ±: $role',
                          );
                        }
                        if (e['dateKey'] != null) {
                          parts.add(
                            'ط·آ·ط¢آ§ط·آ¸أ¢â‚¬â€چط·آ¸ط¸آ¹ط·آ¸ط«â€ ط·آ¸أ¢â‚¬آ¦: ${e['dateKey']}',
                          );
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
                          parts.add(
                            'ط·آ·ط¢آ§ط·آ¸أ¢â‚¬â€چط·آ¸أ¢â‚¬آ¦ط·آ·ط¢آ¨ط·آ¸أ¢â‚¬â€چط·آ·ط·â€؛: ${amount.toString()}',
                          );
                        }
                        if (note != null && note.trim().isNotEmpty) {
                          parts.add(
                            'ط·آ¸أ¢â‚¬آ¦ط·آ¸أ¢â‚¬â€چط·آ·ط¢آ§ط·آ·ط¢آ­ط·آ·ط¢آ¸ط·آ·ط¢آ©: ${note.trim()}',
                          );
                        }
                        return Card(
                          child: ListTile(
                            title: Text(
                              label,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            subtitle: Text(parts.join(' ط£آ¢أ¢â€ڑآ¬ط¢آ¢ ')),
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
