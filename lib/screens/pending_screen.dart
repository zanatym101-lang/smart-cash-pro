// v4: Pending Center (production-ready UI behavior).
// - UI: read-only + commands only (approve/reject)
// - Accounting validation/apply happens inside AppDb -> AccountingEngine
import 'package:flutter/material.dart';
import '../widgets/app_title.dart';
import '../data/app_db.dart';
import '../models/transaction.dart';
import '../models/wallet.dart';

enum _PendingFilter { all, dueToday, overdue }

const String _pendingFilterPreferenceKey = 'pendingScreenFilter';

class PendingScreen extends StatefulWidget {
  const PendingScreen({super.key});

  @override
  State<PendingScreen> createState() => _PendingScreenState();
}

class _PendingScreenState extends State<PendingScreen> {
  bool _loading = true;
  bool _bulkApproving = false;
  final Set<int> _busyTxIds = {};
  final Set<int> _selectedTxnIds = {};
  List<Txn> _pending = [];
  Map<int, Wallet> _walletsById = {};
  int _dayStartHour = 0;
  _PendingFilter _filter = _PendingFilter.all;

  DateTime _businessShift(DateTime d) {
    if (_dayStartHour <= 0) return d;
    return d.subtract(Duration(hours: _dayStartHour));
  }

  DateTimeRange _todayBusinessRange() {
    final now = DateTime.now();
    final shifted = _businessShift(now);
    final start = DateTime(
      shifted.year,
      shifted.month,
      shifted.day,
      _dayStartHour,
    );
    final end = start.add(const Duration(days: 1));
    return DateTimeRange(start: start, end: end);
  }

  bool _isDueToday(Txn t) {
    final range = _todayBusinessRange();
    return !t.entryDate.isBefore(range.start) && t.entryDate.isBefore(range.end);
  }

  bool _isOverdue(Txn t) {
    final range = _todayBusinessRange();
    return t.entryDate.isBefore(range.start);
  }

  int _pendingGroupRank(Txn t) {
    if (_isOverdue(t)) return 0;
    if (_isDueToday(t)) return 1;
    return 2;
  }

  int _comparePending(Txn a, Txn b, {required bool groupFirst}) {
    if (groupFirst) {
      final groupCompare = _pendingGroupRank(a).compareTo(
        _pendingGroupRank(b),
      );
      if (groupCompare != 0) return groupCompare;
    }
    final dateCompare = a.entryDate.compareTo(b.entryDate);
    if (dateCompare != 0) return dateCompare;
    return a.id.compareTo(b.id);
  }

  List<Txn> get _filteredPending {
    final items = switch (_filter) {
      _PendingFilter.dueToday => _pending.where(_isDueToday).toList(),
      _PendingFilter.overdue => _pending.where(_isOverdue).toList(),
      _PendingFilter.all => List<Txn>.from(_pending),
    };

    switch (_filter) {
      case _PendingFilter.all:
        items.sort((a, b) => _comparePending(a, b, groupFirst: true));
        return items;
      case _PendingFilter.dueToday:
      case _PendingFilter.overdue:
        items.sort((a, b) => _comparePending(a, b, groupFirst: false));
        return items;
    }
  }

  String? _dateStatusLabel(Txn t) {
    if (_isOverdue(t)) return 'متأخر';
    if (_isDueToday(t)) return 'اليوم';
    return null;
  }

  Color _dateStatusColor(String label) {
    return label == 'متأخر' ? Colors.red.shade700 : Colors.blue.shade700;
  }

  _PendingFilter _filterFromPreference(String? value) {
    for (final filter in _PendingFilter.values) {
      if (filter.name == value) return filter;
    }
    return _PendingFilter.all;
  }

  Future<void> _saveFilterPreference(_PendingFilter filter) async {
    final settings = await AppDb.instance.readRawSettingsMap();
    settings[_pendingFilterPreferenceKey] = filter.name;
    await AppDb.instance.writeRawSettingsMap(settings);
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final wallets = await AppDb.instance.listWallets();
      final pending = await AppDb.instance.listTxns(status: 'pending');
      final settings = await AppDb.instance.getAppSettings();
      final rawSettings = await AppDb.instance.readRawSettingsMap();

      _walletsById = {for (final w in wallets) w.id: w};
      _pending = pending;
      _selectedTxnIds.removeWhere(
        (id) => !_pending.any((t) => t.id == id && t.status == 'pending'),
      );
      _dayStartHour = settings.dayStartHour;
      _filter = _filterFromPreference(
        rawSettings[_pendingFilterPreferenceKey]?.toString(),
      );
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
    if (t.networkFee != 0) {
      parts.add('رسوم الشبكة: ${_formatMoney(t.networkFee)}');
    }
    if (t.note != null && t.note!.trim().isNotEmpty) {
      parts.add('ملاحظة: ${t.note}');
    }
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
      title: 'اعتماد عملية آجلة',
      body:
          'سيتم اعتماد العملية رقم #${t.id}. أثر التحويل/الاستلام الآجل محسوب فعليًا بالفعل.',
      okText: 'اعتماد',
    );
    if (!ok) return;

    setState(() => _busyTxIds.add(t.id));
    try {
      await AppDb.instance.confirmPending(t.id);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('تم الاعتماد ✅ (#${t.id})')));
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('فشل الاعتماد (#${t.id}): $e')));
    } finally {
      if (mounted) setState(() => _busyTxIds.remove(t.id));
    }
  }

  void _toggleSelected(Txn t, bool selected) {
    if (t.status != 'pending' || _busyTxIds.contains(t.id) || _bulkApproving) {
      return;
    }
    setState(() {
      if (selected) {
        _selectedTxnIds.add(t.id);
      } else {
        _selectedTxnIds.remove(t.id);
      }
    });
  }

  Iterable<int> _actionableVisibleIds() {
    return _filteredPending
        .where((t) => t.status == 'pending' && !_busyTxIds.contains(t.id))
        .map((t) => t.id);
  }

  void _selectVisible() {
    if (_bulkApproving) return;
    setState(() => _selectedTxnIds.addAll(_actionableVisibleIds()));
  }

  void _clearVisibleSelection() {
    if (_bulkApproving) return;
    setState(() => _selectedTxnIds.removeAll(_actionableVisibleIds()));
  }

  Future<void> _approveSelected() async {
    if (_bulkApproving || _selectedTxnIds.isEmpty) return;

    final ok = await _confirmDialog(
      title: 'اعتماد العمليات المحددة',
      body: 'سيتم اعتماد ${_selectedTxnIds.length} عملية آجلة محددة.',
      okText: 'اعتماد المحدد',
    );
    if (!ok) return;

    final currentPending = await AppDb.instance.listTxns(status: 'pending');
    final currentPendingIds = currentPending.map((t) => t.id).toSet();
    final ids = _selectedTxnIds
        .where((id) => currentPendingIds.contains(id))
        .toList();

    if (ids.isEmpty) {
      _selectedTxnIds.clear();
      await _load();
      return;
    }

    setState(() {
      _bulkApproving = true;
      _busyTxIds.addAll(ids);
    });

    var approved = 0;
    var failed = 0;
    try {
      for (final id in ids) {
        try {
          await AppDb.instance.confirmPending(id);
          approved++;
        } catch (_) {
          failed++;
        }
      }
      if (!mounted) return;
      final msg = failed == 0
          ? 'تم اعتماد $approved عملية'
          : 'تم اعتماد $approved عملية، وفشل $failed';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
      _selectedTxnIds.clear();
      await _load();
    } finally {
      if (mounted) {
        setState(() {
          _bulkApproving = false;
          _busyTxIds.removeAll(ids);
        });
      }
    }
  }

  Future<void> _cancelSelected() async {
    if (_bulkApproving || _selectedTxnIds.isEmpty) return;

    final ok = await _confirmDialog(
      title: 'إلغاء العمليات المحددة',
      body: 'سيتم إلغاء ${_selectedTxnIds.length} عملية آجلة محددة.',
      okText: 'إلغاء المحدد',
    );
    if (!ok) return;

    final currentPending = await AppDb.instance.listTxns(status: 'pending');
    final currentPendingIds = currentPending.map((t) => t.id).toSet();
    final ids = _selectedTxnIds
        .where((id) => currentPendingIds.contains(id))
        .toList();

    if (ids.isEmpty) {
      _selectedTxnIds.clear();
      await _load();
      return;
    }

    setState(() {
      _bulkApproving = true;
      _busyTxIds.addAll(ids);
    });

    var canceled = 0;
    var failed = 0;
    try {
      for (final id in ids) {
        try {
          await AppDb.instance.cancelPending(id);
          canceled++;
        } catch (_) {
          failed++;
        }
      }
      if (!mounted) return;
      final msg = failed == 0
          ? 'تم إلغاء $canceled عملية'
          : 'تم إلغاء $canceled عملية، وفشل $failed';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
      _selectedTxnIds.clear();
      await _load();
    } finally {
      if (mounted) {
        setState(() {
          _bulkApproving = false;
          _busyTxIds.removeAll(ids);
        });
      }
    }
  }

  Future<void> _reject(Txn t) async {
    if (_busyTxIds.contains(t.id)) return;

    final ok = await _confirmDialog(
      title: 'إلغاء عملية آجلة',
      body:
          'سيتم إلغاء العملية رقم #${t.id} وعكس أثرها إن كانت أثرت على الرصيد.',
      okText: 'تأكيد الإلغاء',
    );
    if (!ok) return;

    setState(() => _busyTxIds.add(t.id));
    try {
      await AppDb.instance.cancelPending(t.id);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('تم الإلغاء ✅ (#${t.id})')));
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('فشل الإلغاء (#${t.id}): $e')));
    } finally {
      if (mounted) setState(() => _busyTxIds.remove(t.id));
    }
  }

  ({int count, double total, int overdue}) _selectedSummary() {
    final selected = _pending
        .where((t) => _selectedTxnIds.contains(t.id) && t.status == 'pending')
        .toList();
    final total = selected.fold<double>(0, (sum, t) => sum + t.amount);
    final overdue = selected.where(_isOverdue).length;
    return (count: selected.length, total: total, overdue: overdue);
  }

  @override
  Widget build(BuildContext context) {
    final visiblePending = _filteredPending;
    return Scaffold(
      appBar: AppBar(
        title: const AppTitle(subtitle: 'العمليات الآجلة'),
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
                  _filterBar(),
                  const SizedBox(height: 8),
                  _selectionToolsBar(visiblePending),
                  const SizedBox(height: 12),
                  if (_selectedTxnIds.isNotEmpty) ...[
                    _bulkApproveBar(),
                    const SizedBox(height: 12),
                  ],
                  if (visiblePending.isEmpty)
                    _emptyFilteredState()
                  else
                    ...visiblePending.map(_pendingCard),
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
            'مركز العمليات الآجلة',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 10),
          Text(
            'عدد العمليات: ${_pending.length}',
            style: const TextStyle(color: Colors.white70),
          ),
          const SizedBox(height: 6),
          const Text(
            'التحويل والاستلام الآجلان يؤثران فعليًا، والاعتماد لا يكرر الأثر.',
            style: TextStyle(color: Colors.white70, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _selectionToolsBar(List<Txn> visiblePending) {
    final actionableCount = visiblePending
        .where((t) => t.status == 'pending' && !_busyTxIds.contains(t.id))
        .length;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        OutlinedButton.icon(
          onPressed: _bulkApproving || actionableCount == 0
              ? null
              : _selectVisible,
          icon: const Icon(Icons.select_all),
          label: const Text('تحديد المعروض'),
        ),
        TextButton.icon(
          onPressed: _bulkApproving || actionableCount == 0
              ? null
              : _clearVisibleSelection,
          icon: const Icon(Icons.clear_all),
          label: const Text('إلغاء تحديد المعروض'),
        ),
      ],
    );
  }

  Widget _bulkApproveBar() {
    final summary = _selectedSummary();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('المحدد: ${summary.count} عملية'),
                  const SizedBox(height: 2),
                  Text(
                    'الإجمالي: ${_formatMoney(summary.total)}'
                    '${summary.overdue > 0 ? ' • متأخر: ${summary.overdue}' : ''}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            TextButton(
              onPressed: _bulkApproving
                  ? null
                  : () => setState(_selectedTxnIds.clear),
              child: const Text('إلغاء التحديد'),
            ),
            const SizedBox(width: 8),
            OutlinedButton.icon(
              onPressed: _bulkApproving ? null : _cancelSelected,
              icon: const Icon(Icons.close),
              label: const Text('إلغاء المحدد'),
            ),
            const SizedBox(width: 8),
            ElevatedButton.icon(
              onPressed: _bulkApproving ? null : _approveSelected,
              icon: _bulkApproving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.done_all),
              label: const Text('اعتماد المحدد'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _filterBar() {
    return SegmentedButton<_PendingFilter>(
      showSelectedIcon: false,
      segments: const [
        ButtonSegment(value: _PendingFilter.all, label: Text('الكل')),
        ButtonSegment(
          value: _PendingFilter.dueToday,
          label: Text('مستحق اليوم'),
        ),
        ButtonSegment(value: _PendingFilter.overdue, label: Text('متأخر')),
      ],
      selected: {_filter},
      onSelectionChanged: (value) {
        final next = value.first;
        setState(() => _filter = next);
        _saveFilterPreference(next);
      },
    );
  }

  Widget _pendingCard(Txn t) {
    final busy = _busyTxIds.contains(t.id);
    final selected = _selectedTxnIds.contains(t.id);
    final dateStatus = _dateStatusLabel(t);
    final date =
        '${t.entryDate.year}-${t.entryDate.month.toString().padLeft(2, '0')}-${t.entryDate.day.toString().padLeft(2, '0')}'
        ' ${t.entryDate.hour.toString().padLeft(2, '0')}:${t.entryDate.minute.toString().padLeft(2, '0')}';

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Checkbox(
                  value: selected,
                  onChanged: busy || _bulkApproving
                      ? null
                      : (value) => _toggleSelected(t, value == true),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE2E8F0),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text('#${t.id}'),
                ),
                const SizedBox(width: 10),
                if (dateStatus != null) ...[
                  _dateStatusChip(dateStatus),
                  const SizedBox(width: 8),
                ],
                Expanded(
                  child: Text(
                    _title(t),
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                Text(_formatMoney(t.amount)),
              ],
            ),
            const SizedBox(height: 6),
            Text(_subtitle(t)),
            const SizedBox(height: 6),
            Text(
              'التاريخ: $date',
              style: Theme.of(context).textTheme.bodySmall,
            ),
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

  Widget _dateStatusChip(String label) {
    final color = _dateStatusColor(label);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w700,
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
          Text('لا توجد عمليات آجلة'),
        ],
      ),
    );
  }

  Widget _emptyFilteredState() {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 24),
      child: Center(child: Text('لا توجد عمليات آجلة في هذا الفلتر')),
    );
  }
}
