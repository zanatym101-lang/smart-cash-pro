// v9: Treasury Screen (read-only + drawer funding command).
// - No accounting math in UI.
// - Drawer can be negative (rule).
// - Funding command goes through AppDb (backed by AccountingEngine).
import 'package:flutter/material.dart';
import '../widgets/app_title.dart';
import '../data/app_db.dart';

class TreasuryScreen extends StatefulWidget {
  const TreasuryScreen({super.key});

  @override
  State<TreasuryScreen> createState() => _TreasuryScreenState();
}

class _TreasuryScreenState extends State<TreasuryScreen> {
  TreasurySnapshot? _snap;
  bool _loading = true;
  bool _depositing = false;
  String? _error;

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final s = await AppDb.instance.getTreasurySnapshot();
      if (!mounted) return;
      setState(() => _snap = s);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _drawerDepositDialog() async {
    if (_depositing) return;

    final amountCtrl = TextEditingController();
    final noteCtrl = TextEditingController();

    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('تمويل الخزنة من مصدر خارجي'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: amountCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'المبلغ (EGP)'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: noteCtrl,
              decoration: const InputDecoration(labelText: 'ملاحظة (اختياري)'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('حفظ'),
          ),
        ],
      ),
    );

    if (ok != true) return;

    final amt = double.tryParse(amountCtrl.text.trim()) ?? 0;
    final note = noteCtrl.text.trim().isEmpty ? null : noteCtrl.text.trim();

    if (amt <= 0) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('المبلغ يجب أن يكون أكبر من صفر')),
      );
      return;
    }

    setState(() => _depositing = true);
    try {
      await AppDb.instance.drawerDeposit(amount: amt, note: note);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('تم تمويل الخزنة ✅')));
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('فشل تمويل الخزنة: $e')));
    } finally {
      if (mounted) setState(() => _depositing = false);
    }
  }

  Widget _heroCard(TreasurySnapshot s) {
    final total = s.drawerBalance + s.walletsTotal;
    final actualTotal = s.drawerActualBalance + s.walletsActualTotal;
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        gradient: const LinearGradient(
          colors: [Color(0xFF0F172A), Color(0xFF111827)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.15),
            blurRadius: 24,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'إجمالي السيولة المتاحة',
            style: TextStyle(color: Colors.white70),
          ),
          const SizedBox(height: 6),
          Text(
            total.toStringAsFixed(2),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 28,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 14),
          _darkRow('الخزنة (كاش) - متاح', s.drawerBalance),
          const SizedBox(height: 6),
          _darkRow('المحافظ - متاح', s.walletsTotal),
          const SizedBox(height: 6),
          _darkRow('الخزنة (كاش) - فعلي', s.drawerActualBalance),
          const SizedBox(height: 6),
          _darkRow('المحافظ - فعلي', s.walletsActualTotal),
          const SizedBox(height: 6),
          _darkRow('الإجمالي الفعلي', actualTotal),
          const SizedBox(height: 6),
          _darkRow('ربح اليوم', s.dailyProfit),
        ],
      ),
    );
  }

  Widget _darkRow(String label, double value) {
    return Row(
      children: [
        Expanded(
          child: Text(label, style: const TextStyle(color: Colors.white70)),
        ),
        Text(
          value.toStringAsFixed(2),
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  Widget _sectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(top: 18, bottom: 10),
      child: Text(title, style: Theme.of(context).textTheme.titleMedium),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = _snap;

    return Scaffold(
      appBar: AppBar(
        title: const AppTitle(subtitle: 'الخزنة'),
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
          padding: const EdgeInsets.all(16),
          children: [
            if (_loading)
              const Center(
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: CircularProgressIndicator(),
                ),
              )
            else if (_error != null)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('حدث خطأ أثناء التحميل'),
                      const SizedBox(height: 8),
                      Text(_error!),
                      const SizedBox(height: 12),
                      ElevatedButton.icon(
                        onPressed: _load,
                        icon: const Icon(Icons.refresh),
                        label: const Text('إعادة المحاولة'),
                      ),
                    ],
                  ),
                ),
              )
            else if (s != null) ...[
              _heroCard(s),
              _sectionTitle('إجراءات'),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'تمويل الخزنة',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 8),
                      const Text('تمويل الخزنة لا يؤثر على أرصدة المحافظ.'),
                      const SizedBox(height: 12),
                      ElevatedButton.icon(
                        icon: _depositing
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.add),
                        label: const Text('تمويل الخزنة من مصدر خارجي'),
                        onPressed: _depositing ? null : _drawerDepositDialog,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
