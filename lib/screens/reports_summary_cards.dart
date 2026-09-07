part of 'reports_screen.dart';

const Color kReportEmeraldGreen = Color(0xFF10B981);
const Color kReportOutflowRed = Color(0xFFEF4444);
const Color kReportExpenseOrange = Color(0xFFF97316);

extension _ReportsSummaryCards on _ReportsScreenState {
  Widget _kpiCard(
    String title,
    double value, {
    IconData? icon,
    Color? color,
    Color? valueColor,
    Color? iconColor,
    String? subtitle,
  }) {
    final effectiveValueColor = valueColor ?? color;
    final effectiveIconColor = iconColor ?? color;
    return Card(
      child: ListTile(
        leading: icon == null
            ? null
            : Icon(icon, color: effectiveIconColor),
        title: Text(title),
        subtitle: subtitle == null ? null : Text(subtitle),
        trailing: Text(
          value.toStringAsFixed(2),
          style: TextStyle(
            fontWeight: FontWeight.w700,
            color: effectiveValueColor,
          ),
        ),
      ),
    );
  }

  Widget _countTile(String title, int value, IconData icon, {Color? color}) {
    return Card(
      child: ListTile(
        leading: Icon(icon, color: color),
        title: Text(title),
        trailing: Text(
          '$value',
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
    );
  }

  Widget _sectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 6),
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleMedium?.copyWith(
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _lineRow(String title, double value, {Color? color, IconData? icon}) {
    return Card(
      child: ListTile(
        leading: icon == null ? null : Icon(icon, color: color, size: 20),
        title: Text(title),
        trailing: Text(
          value.toStringAsFixed(2),
          style: TextStyle(
            fontWeight: FontWeight.w600,
            color: color,
          ),
        ),
      ),
    );
  }

  Widget _smartKpi(
    String title,
    String value,
    IconData icon, {
    Color? color,
    Color? valueColor,
    Color? iconColor,
    String? subtitle,
  }) {
    final effectiveValueColor = valueColor ?? color;
    final effectiveIconColor = iconColor ?? color;
    return Card(
      child: ListTile(
        leading: Icon(icon, color: effectiveIconColor),
        title: Text(title),
        subtitle: subtitle == null ? null : Text(subtitle),
        trailing: Text(
          value,
          style: TextStyle(
            fontWeight: FontWeight.w700,
            color: effectiveValueColor,
          ),
        ),
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

