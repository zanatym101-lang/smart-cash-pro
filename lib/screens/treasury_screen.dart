import 'package:flutter/material.dart';

import '../data/app_db.dart';
import '../widgets/app_title.dart';

class TreasuryScreen extends StatefulWidget {
  const TreasuryScreen({super.key});

  @override
  State<TreasuryScreen> createState() => _TreasuryScreenState();
}

class _TreasuryScreenState extends State<TreasuryScreen> {
  TreasurySnapshot? _snap;
  bool _loading = true;
  bool _adjusting = false;
  String? _error;

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

  Future<void> _drawerAdjustDialog() async {
    if (_adjusting) return;

    final amountCtrl = TextEditingController();
    final noteCtrl = TextEditingController();

    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('تعديل رصيد الدرج (+/-)'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: amountCtrl,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
                signed: true,
              ),
              decoration: const InputDecoration(
                labelText: 'المبلغ (مثال: 500 أو -300)',
              ),
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
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('تنفيذ'),
          ),
        ],
      ),
    );

    if (ok != true) return;

    final amt = double.tryParse(amountCtrl.text.trim()) ?? 0;
    final note = noteCtrl.text.trim().isEmpty ? null : noteCtrl.text.trim();

    if (amt == 0) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('المبلغ لا يمكن أن يساوي صفر')),
      );
      return;
    }

    setState(() => _adjusting = true);
    try {
      await AppDb.instance.drawerDeposit(amount: amt, note: note);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            amt > 0
                ? 'تمت إضافة ${amt.toStringAsFixed(2)} إلى الدرج ✅'
                : 'تم خصم ${(-amt).toStringAsFixed(2)} من الدرج ✅',
          ),
        ),
      );
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('فشل تعديل الدرج: $e')));
    } finally {
      if (mounted) setState(() => _adjusting = false);
    }
  }

  Widget _heroCard(TreasurySnapshot s) {
    final totalAvailable = s.drawerBalance + s.walletsTotal + s.fawryBalance;
    final totalActual =
        s.drawerActualBalance + s.walletsActualTotal + s.fawryActualBalance;

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
            totalAvailable.toStringAsFixed(2),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 28,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 14),
          _darkRow('الدرج (متاح)', s.drawerBalance),
          _darkRow('المحافظ (متاح)', s.walletsTotal),
          const SizedBox(height: 6),
          _darkRow('الدرج (فعلي)', s.drawerActualBalance),
          _darkRow('المحافظ (فعلي)', s.walletsActualTotal),
          const SizedBox(height: 6),
          _darkRow('الإجمالي الفعلي', totalActual),
          _darkRow('ربح اليوم', s.dailyProfit),
        ],
      ),
    );
  }

  Widget _darkRow(String label, double value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
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
      ),
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
              const SizedBox(height: 18),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'تعديل يدوي للدرج',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'يسجل حركة إضافة أو خصم مباشرة على الدرج فقط، ولا يغير الأرباح ولا المحافظ.',
                      ),
                      const SizedBox(height: 12),
                      ElevatedButton.icon(
                        icon: _adjusting
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.edit_note),
                        label: const Text('تعديل رصيد الدرج (+/-)'),
                        onPressed: _adjusting ? null : _drawerAdjustDialog,
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
