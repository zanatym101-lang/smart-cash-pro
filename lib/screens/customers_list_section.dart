part of 'customers_screen.dart';

extension _CustomersListSection on _CustomersScreenState {
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

  Widget _listFilterChip(
    String label,
    _CustomerListFilter value, {
    int? count,
  }) {
    final selected = _listFilter == value;
    final text = count != null ? '$label ($count)' : label;
    return ChoiceChip(
      label: Text(text),
      selected: selected,
      onSelected: (_) => _setMountedState(() => _listFilter = value),
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

  Widget _customerCard(_CustomerBucket c, {required bool showArchivedLabel}) {
    final netLabel = c.net >= 0 ? 'صافي عليه' : 'صافي له';
    final netValue = c.net >= 0 ? c.net : -c.net;
    final archivedTag = showArchivedLabel ? ' | مؤرشف' : '';
    final isPinned = _isPinned(c);
    final showWarning =
        _customerAlertThreshold > 0 &&
        (c.receivableTotal >= _customerAlertThreshold ||
            c.payableTotal >= _customerAlertThreshold);
    final last = c.lastActivity;
    final lastText = last == null
        ? 'لا توجد حركة'
        : 'آخر حركة: ${last.year}-${last.month.toString().padLeft(2, '0')}-${last.day.toString().padLeft(2, '0')}';

    return Card(
      child: ListTile(
        onTap: () => _openCustomer(c),
        leading: const CircleAvatar(child: Icon(Icons.person)),
        title: Text(
          c.name,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        subtitle: Text(
          '${c.phone ?? 'بدون هاتف'}$archivedTag\n$lastText\n$netLabel: ${netValue.toStringAsFixed(2)} | عليه: ${c.receivableTotal.toStringAsFixed(2)} | له: ${c.payableTotal.toStringAsFixed(2)}',
        ),
        isThreeLine: true,
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (showWarning)
              const Icon(Icons.warning_amber, color: Colors.orange, size: 18),
            IconButton(
              onPressed: () => _togglePin(c),
              icon: Icon(
                isPinned ? Icons.star : Icons.star_border,
                color: isPinned ? Colors.amber : Colors.grey,
              ),
              tooltip: isPinned ? 'إزالة التثبيت' : 'تثبيت',
              visualDensity: VisualDensity.compact,
            ),
            const Icon(Icons.chevron_right),
          ],
        ),
      ),
    );
  }
}
