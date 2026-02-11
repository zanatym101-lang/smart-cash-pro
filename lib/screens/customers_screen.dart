import 'package:flutter/material.dart';

import '../data/app_db.dart';
import '../models/transaction.dart';
import '../widgets/app_title.dart';
import 'fawry_screen.dart';
import 'receive_screen.dart';
import 'transfer_screen.dart';

class CustomersScreen extends StatefulWidget {
  const CustomersScreen({super.key});

  @override
  State<CustomersScreen> createState() => _CustomersScreenState();
}

class _CustomersScreenState extends State<CustomersScreen> {
  bool _loading = true;
  String? _error;
  String _query = '';
  List<_CustomerBucket> _customers = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  String _normalizePhone(String raw) {
    final b = StringBuffer();
    for (final r in raw.runes) {
      final ch = String.fromCharCode(r);
      final cu = ch.codeUnitAt(0);
      if (cu >= 48 && cu <= 57) b.write(ch);
    }
    return b.toString();
  }

  String? _extractPhone(String? text) {
    if (text == null || text.trim().isEmpty) return null;
    final matches = RegExp(r'\d{10,15}').allMatches(text);
    if (matches.isEmpty) return null;
    final phone = _normalizePhone(matches.first.group(0) ?? '');
    return phone.isEmpty ? null : phone;
  }

  String _bucketKey({required String name, String? phone}) {
    final p = _normalizePhone(phone ?? '');
    if (p.isNotEmpty) return 'p:$p';
    return 'n:${name.trim().toLowerCase()}';
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final txns = await AppDb.instance.listTxns();
      final claims = await AppDb.instance.listClaims();
      final map = <String, _CustomerBucket>{};

      _CustomerBucket bucketFor({required String name, String? phone}) {
        final normalizedName = name.trim().isEmpty
            ? 'عميل بدون اسم'
            : name.trim();
        final normalizedPhone = _normalizePhone(phone ?? '');
        final key = _bucketKey(name: normalizedName, phone: normalizedPhone);
        return map.putIfAbsent(
          key,
          () => _CustomerBucket(
            name: normalizedName,
            phone: normalizedPhone.isEmpty ? null : normalizedPhone,
          ),
        );
      }

      for (final c in claims) {
        if (c.status != 'open') continue;
        final name = c.party.trim();
        if (name.isEmpty) continue;
        final phone = _extractPhone(c.note);
        final b = bucketFor(name: name, phone: phone);
        if (c.type == 'receivable') {
          b.receivableClaims += c.amount;
          b.lines.add(
            _CustomerLine(
              date: c.entryDate,
              side: _LineSide.receivable,
              amount: c.amount,
              title: 'مستحق مفتوح (لنا)',
              details: c.note,
              ref: 'Claim#${c.id}',
            ),
          );
        } else if (c.type == 'payable') {
          b.payableClaims += c.amount;
          b.lines.add(
            _CustomerLine(
              date: c.entryDate,
              side: _LineSide.payable,
              amount: c.amount,
              title: 'مستحق مفتوح (علينا)',
              details: c.note,
              ref: 'Claim#${c.id}',
            ),
          );
        }
      }

      for (final t in txns) {
        if (t.status != 'pending') continue;
        final name = (t.party ?? '').trim();
        if (name.isEmpty) continue;
        final phone = _extractPhone(t.note);
        final b = bucketFor(name: name, phone: phone);

        if (t.kind == 'transfer') {
          final baseAmount = t.amount - t.networkFee;
          final due = t.mode == 'type1'
              ? (baseAmount + t.clientFee)
              : baseAmount;
          if (due > 0) {
            b.receivablePending += due;
            b.lines.add(
              _CustomerLine(
                date: t.entryDate,
                side: _LineSide.receivable,
                amount: due,
                title: 'تحويل معلّق',
                details: _detailsForTransfer(t),
                ref: 'Txn#${t.id}',
              ),
            );
          }
          continue;
        }

        if (t.kind == 'receive') {
          final due = _pendingReceiveDue(t);
          if (due > 0) {
            b.payablePending += due;
            b.lines.add(
              _CustomerLine(
                date: t.entryDate,
                side: _LineSide.payable,
                amount: due,
                title: 'استلام معلّق',
                details: _detailsForReceive(t),
                ref: 'Txn#${t.id}',
              ),
            );
          }
          continue;
        }

        if (t.kind == 'fawry_credit') {
          final due = t.amount + t.clientFee;
          if (due > 0) {
            b.receivablePending += due;
            b.lines.add(
              _CustomerLine(
                date: t.entryDate,
                side: _LineSide.receivable,
                amount: due,
                title: 'فوري آجل معلّق',
                details: _detailsForFawry(t),
                ref: 'Txn#${t.id}',
              ),
            );
          }
        }
      }

      final customers =
          map.values
              .where((c) => c.receivableTotal > 0 || c.payableTotal > 0)
              .toList()
            ..sort((a, b) => b.net.abs().compareTo(a.net.abs()));
      for (final c in customers) {
        c.lines.sort((a, b) => b.date.compareTo(a.date));
      }

      if (!mounted) return;
      setState(() => _customers = customers);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _detailsForTransfer(Txn t) {
    final base = (t.amount - t.networkFee).toStringAsFixed(2);
    final fee = t.clientFee.toStringAsFixed(2);
    final phone = _extractPhone(t.note);
    final parts = <String>['الأساس: $base', 'CF: $fee', 'النوع: ${t.mode}'];
    if (phone != null) parts.add('الهاتف: $phone');
    return parts.join(' • ');
  }

  String _detailsForReceive(Txn t) {
    final amt = t.amount.toStringAsFixed(2);
    final fee = t.clientFee.toStringAsFixed(2);
    final phone = _extractPhone(t.note);
    final parts = <String>['المبلغ: $amt', 'CF: $fee', 'النوع: ${t.mode}'];
    if (phone != null) parts.add('الهاتف: $phone');
    return parts.join(' • ');
  }

  String _detailsForFawry(Txn t) {
    final svc = (t.serviceName ?? '').trim();
    final ref = (t.reference ?? '').trim();
    final base = t.amount.toStringAsFixed(2);
    final fee = t.clientFee.toStringAsFixed(2);
    final phone = _extractPhone(t.note);
    final p = <String>['الخدمة: $svc', 'الأساس: $base', 'الربح: $fee'];
    if (ref.isNotEmpty) p.add('المرجع: $ref');
    if (phone != null) p.add('الهاتف: $phone');
    return p.join(' • ');
  }

  double _pendingReceiveDue(Txn t) {
    if (t.mode == 'cash') return t.amount;
    if (t.mode == 'deduct') {
      return (t.amount - t.clientFee).clamp(0, 1e18).toDouble();
    }
    return 0;
  }

  List<_CustomerBucket> get _filtered {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return _customers;
    return _customers.where((c) {
      final name = c.name.toLowerCase();
      final phone = (c.phone ?? '').toLowerCase();
      return name.contains(q) || phone.contains(q);
    }).toList();
  }

  Future<void> _openCustomer(_CustomerBucket c) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (ctx) => _CustomerSheet(
        customer: c,
        onTransferPending: () async {
          Navigator.of(ctx).pop();
          await Navigator.of(context).push<bool>(
            MaterialPageRoute(
              builder: (_) => TransferScreen(
                initialParty: c.name,
                initialPhone: c.phone,
                forcePendingDefault: true,
              ),
            ),
          );
          _load();
        },
        onReceivePending: () async {
          Navigator.of(ctx).pop();
          await Navigator.of(context).push<bool>(
            MaterialPageRoute(
              builder: (_) => ReceiveScreen(
                initialParty: c.name,
                initialPhone: c.phone,
                forcePendingDefault: true,
              ),
            ),
          );
          _load();
        },
        onFawryCredit: () async {
          Navigator.of(ctx).pop();
          await Navigator.of(context).push<bool>(
            MaterialPageRoute(
              builder: (_) => FawryScreen(
                initialParty: c.name,
                initialPhone: c.phone,
                startCredit: true,
              ),
            ),
          );
          _load();
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final items = _filtered;
    final totalReceivable = items.fold<double>(
      0,
      (s, c) => s + c.receivableTotal,
    );
    final totalPayable = items.fold<double>(0, (s, c) => s + c.payableTotal);
    final net = totalReceivable - totalPayable;

    return Scaffold(
      appBar: AppBar(
        title: const AppTitle(subtitle: 'العملاء'),
        actions: [
          IconButton(
            tooltip: 'تحديث',
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          children: [
            _summaryCard(
              receivable: totalReceivable,
              payable: totalPayable,
              net: net,
              customers: items.length,
            ),
            const SizedBox(height: 12),
            TextField(
              onChanged: (v) => setState(() => _query = v),
              decoration: const InputDecoration(
                labelText: 'بحث باسم أو هاتف العميل',
                prefixIcon: Icon(Icons.search),
              ),
            ),
            const SizedBox(height: 12),
            if (_loading)
              const Center(
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: CircularProgressIndicator(),
                ),
              )
            else if (_error != null)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text('خطأ: $_error'),
                ),
              )
            else if (items.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(child: Text('لا توجد بيانات عملاء حالياً')),
              )
            else
              ...items.map((c) => _customerCard(c)),
          ],
        ),
      ),
    );
  }

  Widget _summaryCard({
    required double receivable,
    required double payable,
    required double net,
    required int customers,
  }) {
    final netLabel = net >= 0 ? 'الصافي لنا' : 'الصافي علينا';
    final netValue = net >= 0 ? net : -net;
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'إجمالي العملاء: $customers',
            style: const TextStyle(color: Colors.white70),
          ),
          const SizedBox(height: 8),
          _row('إجمالي لنا', receivable),
          _row('إجمالي علينا', payable),
          _row(netLabel, netValue),
        ],
      ),
    );
  }

  Widget _row(String label, double value) {
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(label, style: const TextStyle(color: Colors.white70)),
          ),
          Text(
            value.toStringAsFixed(2),
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _customerCard(_CustomerBucket c) {
    final netLabel = c.net >= 0 ? 'صافي لنا' : 'صافي علينا';
    final netValue = c.net >= 0 ? c.net : -c.net;

    return Card(
      child: ListTile(
        onTap: () => _openCustomer(c),
        leading: const CircleAvatar(child: Icon(Icons.person)),
        title: Text(
          c.name,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        subtitle: Text(
          '${c.phone ?? 'بدون هاتف'}\nلنا: ${c.receivableTotal.toStringAsFixed(2)} • علينا: ${c.payableTotal.toStringAsFixed(2)} • $netLabel: ${netValue.toStringAsFixed(2)}',
        ),
        isThreeLine: true,
        trailing: const Icon(Icons.chevron_right),
      ),
    );
  }
}

class _CustomerSheet extends StatelessWidget {
  final _CustomerBucket customer;
  final VoidCallback onTransferPending;
  final VoidCallback onReceivePending;
  final VoidCallback onFawryCredit;

  const _CustomerSheet({
    required this.customer,
    required this.onTransferPending,
    required this.onReceivePending,
    required this.onFawryCredit,
  });

  @override
  Widget build(BuildContext context) {
    final netLabel = customer.net >= 0 ? 'صافي لنا' : 'صافي علينا';
    final netValue = customer.net >= 0 ? customer.net : -customer.net;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  customer.name,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              IconButton(
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close),
              ),
            ],
          ),
          Text('الهاتف: ${customer.phone ?? 'غير مسجل'}'),
          Text('لنا: ${customer.receivableTotal.toStringAsFixed(2)}'),
          Text('علينا: ${customer.payableTotal.toStringAsFixed(2)}'),
          Text('$netLabel: ${netValue.toStringAsFixed(2)}'),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ElevatedButton.icon(
                onPressed: onTransferPending,
                icon: const Icon(Icons.swap_horiz),
                label: const Text('تحويل معلّق'),
              ),
              ElevatedButton.icon(
                onPressed: onReceivePending,
                icon: const Icon(Icons.call_received),
                label: const Text('استلام معلّق'),
              ),
              ElevatedButton.icon(
                onPressed: onFawryCredit,
                icon: const Icon(Icons.flash_on),
                label: const Text('فوري آجل'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Expanded(
            child: customer.lines.isEmpty
                ? const Center(child: Text('لا توجد قيود على هذا العميل'))
                : ListView.separated(
                    itemCount: customer.lines.length,
                    separatorBuilder: (_, i) => const Divider(height: 1),
                    itemBuilder: (_, i) {
                      final line = customer.lines[i];
                      final sign = line.side == _LineSide.receivable
                          ? '+'
                          : '-';
                      final color = line.side == _LineSide.receivable
                          ? const Color(0xFF047857)
                          : const Color(0xFFB91C1C);
                      final d = line.date;
                      final date =
                          '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
                      final subtitleParts = <String>[line.ref, date];
                      if ((line.details ?? '').trim().isNotEmpty) {
                        subtitleParts.add(line.details!.trim());
                      }
                      return ListTile(
                        dense: true,
                        title: Text(line.title),
                        subtitle: Text(subtitleParts.join(' • ')),
                        trailing: Text(
                          '$sign${line.amount.toStringAsFixed(2)}',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: color,
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

enum _LineSide { receivable, payable }

class _CustomerLine {
  final DateTime date;
  final _LineSide side;
  final double amount;
  final String title;
  final String? details;
  final String ref;

  const _CustomerLine({
    required this.date,
    required this.side,
    required this.amount,
    required this.title,
    required this.details,
    required this.ref,
  });
}

class _CustomerBucket {
  final String name;
  final String? phone;
  double receivableClaims = 0;
  double payableClaims = 0;
  double receivablePending = 0;
  double payablePending = 0;
  final List<_CustomerLine> lines = [];

  _CustomerBucket({required this.name, this.phone});

  double get receivableTotal => receivableClaims + receivablePending;
  double get payableTotal => payableClaims + payablePending;
  double get net => receivableTotal - payableTotal;
}
