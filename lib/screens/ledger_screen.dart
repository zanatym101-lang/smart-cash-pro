import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import '../widgets/app_title.dart';
import '../data/app_db.dart';
import '../data/app_session.dart';
import '../models/transaction.dart';
import '../models/wallet.dart';
import 'tx_details_screen.dart';

class LedgerScreen extends StatefulWidget {
  const LedgerScreen({super.key});

  @override
  State<LedgerScreen> createState() => _LedgerScreenState();
}

class _LedgerScreenState extends State<LedgerScreen> {
  bool _loading = true;
  String? _error;

  List<Txn> _all = [];
  List<Txn> _filtered = [];
  List<Wallet> _wallets = [];

  // Filters
  String _period = 'today'; // today | month | all
  String _type =
      'all'; // all | transfer | receive | external_funding | drawer_deposit | rollback
  String _status = 'all'; // all | pending | posted | rolled_back

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
      final txns = await AppDb.instance.listTxns();
      final wallets = await AppDb.instance.listWallets();
      _all = txns;
      _wallets = wallets;
      _applyFilters();
    } catch (e) {
      _error = e.toString();
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _applyFilters() {
    final now = DateTime.now();

    bool inPeriod(Txn t) {
      if (_period == 'all') return true;
      if (_period == 'today') {
        return t.entryDate.year == now.year &&
            t.entryDate.month == now.month &&
            t.entryDate.day == now.day;
      }
      // month
      return t.entryDate.year == now.year && t.entryDate.month == now.month;
    }

    bool inType(Txn t) => _type == 'all' ? true : t.kind == _type;
    bool inStatus(Txn t) => _status == 'all' ? true : t.status == _status;

    _filtered =
        _all.where((t) => inPeriod(t) && inType(t) && inStatus(t)).toList()
          ..sort((a, b) => b.entryDate.compareTo(a.entryDate));

    if (mounted) setState(() {});
  }

  String _kindLabel(String k) {
    switch (k) {
      case 'transfer':
        return 'تحويل';
      case 'receive':
        return 'استلام';
      case 'external_funding':
        return 'تمويل محفظة';
      case 'drawer_deposit':
        return 'تمويل درج';
      case 'expense':
        return 'مصروف';
      case 'claim_collect':
        return 'تحصيل مستحقات';
      case 'claim_pay':
        return 'سداد مستحقات';
      case 'fawry_cash':
        return 'خدمة فوري (نقدي)';
      case 'fawry_credit':
        return 'خدمة فوري (آجل)';
      case 'fawry_fund_drawer':
        return 'شحن رصيد فوري';
      case 'rollback':
        return 'Rollback';
      default:
        return k;
    }
  }

  String _statusLabel(String s) {
    if (s == 'posted') return 'معتمد';
    if (s == 'rolled_back') return 'تم إلغاء اعتمادها';
    return 'معلّق';
  }

  Widget _sectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(top: 18, bottom: 10),
      child: Text(title, style: Theme.of(context).textTheme.titleMedium),
    );
  }

  String _csvCell(Object? value) {
    final raw = (value ?? '').toString();
    final escaped = raw.replaceAll('"', '""');
    return '"$escaped"';
  }

  Future<void> _exportFilteredCsv() async {
    if (_loading) return;
    if (_filtered.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('لا توجد عمليات للتصدير حسب الفلاتر الحالية'),
        ),
      );
      return;
    }

    try {
      final dir =
          await getDownloadsDirectory() ??
          await getApplicationDocumentsDirectory();
      final now = DateTime.now();
      final stamp =
          '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}_${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}';
      final file = File('${dir.path}/ledger_$stamp.csv');

      final lines = <String>[
        [
          'id',
          'date',
          'kind',
          'status',
          'amount',
          'client_fee',
          'network_fee',
          'wallet_from',
          'wallet_to',
          'note',
          'created_by',
        ].map(_csvCell).join(','),
      ];

      for (final t in _filtered) {
        lines.add(
          [
            t.id,
            t.entryDate.toIso8601String(),
            t.kind,
            t.status,
            t.amount,
            t.clientFee,
            t.networkFee,
            t.walletFromId ?? '',
            t.walletToId ?? '',
            t.note ?? '',
            t.createdBy,
          ].map(_csvCell).join(','),
        );
      }

      await file.writeAsString(lines.join('\n'), flush: true);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('تم تصدير السجل: ${file.path}')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('فشل تصدير السجل: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final isAdmin = AppSession.isAdmin;
    final total = _all.length;
    final pendingCount = _all.where((t) => t.status == 'pending').length;
    final postedCount = _all.where((t) => t.status == 'posted').length;

    return Scaffold(
      appBar: AppBar(
        title: const AppTitle(subtitle: 'سجل العمليات'),
        actions: [
          IconButton(
            tooltip: 'تصدير CSV',
            onPressed: _loading ? null : _exportFilteredCsv,
            icon: const Icon(Icons.download),
          ),
          IconButton(
            tooltip: 'تحديث',
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Row(
                  children: [
                    _statChip('الإجمالي', total),
                    const SizedBox(width: 8),
                    _statChip('المعلّق', pendingCount),
                    const SizedBox(width: 8),
                    _statChip('المعتمد', postedCount),
                  ],
                ),
              ),
            ),
            _sectionTitle('الفلاتر'),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    Wrap(
                      spacing: 6,
                      children: [
                        ChoiceChip(
                          label: const Text('اليوم'),
                          selected: _period == 'today',
                          onSelected: (_) {
                            _period = 'today';
                            _applyFilters();
                          },
                        ),
                        ChoiceChip(
                          label: const Text('هذا الشهر'),
                          selected: _period == 'month',
                          onSelected: (_) {
                            _period = 'month';
                            _applyFilters();
                          },
                        ),
                        ChoiceChip(
                          label: const Text('الكل'),
                          selected: _period == 'all',
                          onSelected: (_) {
                            _period = 'all';
                            _applyFilters();
                          },
                        ),
                      ],
                    ),
                    SizedBox(
                      width: 220,
                      child: DropdownButtonFormField<String>(
                        key: ValueKey(_type),
                        initialValue: _type,
                        items: const [
                          DropdownMenuItem(value: 'all', child: Text('الكل')),
                          DropdownMenuItem(
                            value: 'transfer',
                            child: Text('تحويل'),
                          ),
                          DropdownMenuItem(
                            value: 'receive',
                            child: Text('استلام'),
                          ),
                          DropdownMenuItem(
                            value: 'external_funding',
                            child: Text('تمويل محفظة'),
                          ),
                          DropdownMenuItem(
                            value: 'drawer_deposit',
                            child: Text('تمويل درج'),
                          ),
                          DropdownMenuItem(
                            value: 'expense',
                            child: Text('مصروف'),
                          ),
                          DropdownMenuItem(
                            value: 'claim_collect',
                            child: Text('تحصيل مستحقات'),
                          ),
                          DropdownMenuItem(
                            value: 'claim_pay',
                            child: Text('سداد مستحقات'),
                          ),
                          DropdownMenuItem(
                            value: 'fawry_cash',
                            child: Text('فوري نقدي'),
                          ),
                          DropdownMenuItem(
                            value: 'fawry_credit',
                            child: Text('فوري آجل'),
                          ),
                          DropdownMenuItem(
                            value: 'fawry_fund_drawer',
                            child: Text('شحن فوري من الدرج'),
                          ),
                          DropdownMenuItem(
                            value: 'rollback',
                            child: Text('Rollback'),
                          ),
                        ],
                        onChanged: (v) {
                          _type = v ?? 'all';
                          _applyFilters();
                        },
                        decoration: const InputDecoration(
                          labelText: 'النوع',
                          isDense: true,
                        ),
                      ),
                    ),
                    Wrap(
                      spacing: 6,
                      children: [
                        ChoiceChip(
                          label: const Text('الكل'),
                          selected: _status == 'all',
                          onSelected: (_) {
                            _status = 'all';
                            _applyFilters();
                          },
                        ),
                        ChoiceChip(
                          label: const Text('معلّق'),
                          selected: _status == 'pending',
                          onSelected: (_) {
                            _status = 'pending';
                            _applyFilters();
                          },
                        ),
                        ChoiceChip(
                          label: const Text('معتمد'),
                          selected: _status == 'posted',
                          onSelected: (_) {
                            _status = 'posted';
                            _applyFilters();
                          },
                        ),
                        ChoiceChip(
                          label: const Text('ملغي'),
                          selected: _status == 'rolled_back',
                          onSelected: (_) {
                            _status = 'rolled_back';
                            _applyFilters();
                          },
                        ),
                      ],
                    ),
                    if (isAdmin)
                      const Text(
                        'للأدمن: يمكن الاعتماد/الإلغاء/Rollback من تفاصيل العملية.',
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 10),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _error != null
                  ? Center(child: Text('خطأ: $_error'))
                  : _filtered.isEmpty
                  ? const Center(
                      child: Text('لا توجد عمليات حسب الفلاتر الحالية'),
                    )
                  : ListView.separated(
                      itemCount: _filtered.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 8),
                      itemBuilder: (_, i) {
                        final t = _filtered[i];
                        final dt =
                            '${t.entryDate.year}-${t.entryDate.month.toString().padLeft(2, '0')}-${t.entryDate.day.toString().padLeft(2, '0')} '
                            '${t.entryDate.hour.toString().padLeft(2, '0')}:${t.entryDate.minute.toString().padLeft(2, '0')}';

                        return Card(
                          child: ListTile(
                            leading: const Icon(Icons.receipt),
                            title: Text(
                              '${_kindLabel(t.kind)} • ${_statusLabel(t.status)}',
                            ),
                            subtitle: Text(
                              'رقم #${t.id} • $dt • بواسطة ${t.createdBy}',
                            ),
                            trailing: Text(t.amount.toStringAsFixed(2)),
                            onTap: () async {
                              await Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => TxDetailsScreen(
                                    txn: t,
                                    wallets: _wallets,
                                  ),
                                ),
                              );
                              await _load();
                            },
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

  Widget _statChip(String label, int value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Text('$label: $value'),
    );
  }
}
