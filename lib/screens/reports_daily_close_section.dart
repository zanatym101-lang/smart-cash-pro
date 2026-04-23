part of 'reports_screen.dart';

extension _ReportsDailyCloseSection on _ReportsScreenState {
  Future<void> _closeDay() async {
    if (!AppSession.isAdmin) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('هذه الصفحة للأدمن فقط')));
      return;
    }
    try {
      await AppDb.instance.closeDaily(_closeDate);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('تم إغلاق اليوم ✅')));
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('خطأ: $e')));
    }
  }

  Future<void> _reopenDay() async {
    if (!AppSession.isAdmin) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('هذه الصفحة للأدمن فقط')));
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('إلغاء إغلاق اليوم'),
        content: const Text(
          'سيتم فتح اليوم مرة أخرى للسماح بإضافة أو تعديل العمليات.\n'
          'لن يُسمح بالإلغاء إذا كانت هناك عمليات بعد وقت الإغلاق.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('تأكيد الإلغاء'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    try {
      await AppDb.instance.reopenDaily(_closeDate);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('تم إلغاء إغلاق اليوم ✅')));
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('خطأ: $e')));
    }
  }

  Widget _dailyCloseTab() {
    final dateLabel = _fmtDate(_closeDate);
    final existing = _closes.where((c) => c.dateKey == dateLabel).toList();

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'إغلاق اليوم',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Text('التاريخ: $dateLabel'),
                    const SizedBox(width: 12),
                    TextButton.icon(
                      onPressed: () async {
                        final now = DateTime.now();
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: _closeDate,
                          firstDate: DateTime(now.year - 5),
                          lastDate: DateTime(now.year + 1),
                        );
                        if (picked == null) return;
                        _setMountedState(() => _closeDate = picked);
                      },
                      icon: const Icon(Icons.date_range),
                      label: const Text('تغيير'),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                if (existing.isNotEmpty) ...[
                  Text('تم الإغلاق بالفعل: ${existing.first.closedAt}'),
                  const SizedBox(height: 8),
                  if (AppSession.isAdmin)
                    OutlinedButton.icon(
                      onPressed: _reopenDay,
                      icon: const Icon(Icons.undo),
                      label: const Text('إلغاء الإغلاق'),
                    ),
                ] else
                  ElevatedButton.icon(
                    onPressed: _closeDay,
                    icon: const Icon(Icons.lock),
                    label: const Text('إغلاق اليوم'),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        const Text('سجل الإغلاقات'),
        const SizedBox(height: 8),
        ..._closes
            .take(10)
            .map(
              (c) => Card(
                child: ListTile(
                  title: Text('تاريخ: ${c.dateKey}'),
                  subtitle: Text('وقت الإغلاق: ${c.closedAt}'),
                  trailing: Text(c.profitTotal.toStringAsFixed(2)),
                ),
              ),
            ),
      ],
    );
  }
}
