part of 'reports_screen.dart';

extension _ReportsSummaryCards on _ReportsScreenState {
  Widget _kpiCard(String title, double value, {IconData? icon}) {
    return Card(
      child: ListTile(
        leading: icon == null ? null : Icon(icon),
        title: Text(title),
        trailing: Text(value.toStringAsFixed(2)),
      ),
    );
  }

  Widget _countTile(String title, int value, IconData icon) {
    return Card(
      child: ListTile(
        leading: Icon(icon),
        title: Text(title),
        trailing: Text('$value'),
      ),
    );
  }

  Widget _sectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(title, style: Theme.of(context).textTheme.titleMedium),
    );
  }

  Widget _lineRow(String title, double value) {
    return Card(
      child: ListTile(
        title: Text(title),
        trailing: Text(value.toStringAsFixed(2)),
      ),
    );
  }

  Widget _smartKpi(String title, String value, IconData icon) {
    return Card(
      child: ListTile(
        leading: Icon(icon),
        title: Text(title),
        trailing: Text(value),
      ),
    );
  }

  Widget _dayRow(DayInsight d) {
    final parts = <String>[
      'الربح: ${d.profit.toStringAsFixed(2)}',
      'العدد: ${d.count}',
      'الحجم: ${d.volume.toStringAsFixed(2)}',
    ];
    return Card(
      child: ListTile(
        title: Text(d.dateKey),
        subtitle: Text(parts.join(' • ')),
      ),
    );
  }

  Widget _customerRow(CustomerInsight c) {
    final parts = <String>[
      'الربح: ${c.profit.toStringAsFixed(2)}',
      'العدد: ${c.count}',
      'الحجم: ${c.volume.toStringAsFixed(2)}',
    ];
    return Card(
      child: ListTile(title: Text(c.name), subtitle: Text(parts.join(' • '))),
    );
  }
}
