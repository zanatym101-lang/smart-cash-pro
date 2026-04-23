part of 'reports_screen.dart';

extension _ReportsDateRangeHelpers on _ReportsScreenState {
  DateTime _businessShift(DateTime d) {
    if (_dayStartHour <= 0) return d;
    return d.subtract(Duration(hours: _dayStartHour));
  }

  DateRange _todayRange() {
    final now = DateTime.now();
    final shifted = _businessShift(now);
    final start = DateTime(
      shifted.year,
      shifted.month,
      shifted.day,
      _dayStartHour,
    );
    final end = start
        .add(const Duration(days: 1))
        .subtract(const Duration(milliseconds: 1));
    return DateRange(start: start, end: end);
  }

  DateRange _monthRange() {
    final now = DateTime.now();
    final shifted = _businessShift(now);
    final start = DateTime(shifted.year, shifted.month, 1, _dayStartHour);
    final end = DateTime(
      shifted.year,
      shifted.month + 1,
      1,
      _dayStartHour,
    ).subtract(const Duration(milliseconds: 1));
    return DateRange(start: start, end: end);
  }

  DateRange _activeRange() {
    if (_period == 'month') return _monthRange();
    if (_period == 'custom' && _customRange != null) return _customRange!;
    return _todayRange();
  }

  String _fmtDate(DateTime d) {
    final y = d.year.toString().padLeft(4, '0');
    final m = d.month.toString().padLeft(2, '0');
    final day = d.day.toString().padLeft(2, '0');
    return '$y-$m-$day';
  }

  Future<void> _pickCustomRange() async {
    final now = DateTime.now();
    final res = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 5),
      lastDate: DateTime(now.year + 1),
      initialDateRange: _customRange == null
          ? DateTimeRange(start: now, end: now)
          : DateTimeRange(start: _customRange!.start, end: _customRange!.end),
    );
    if (res == null) return;
    final start = DateTime(res.start.year, res.start.month, res.start.day);
    final end = DateTime(
      res.end.year,
      res.end.month,
      res.end.day,
      23,
      59,
      59,
      999,
    );
    _setMountedState(() {
      _customRange = DateRange(start: start, end: end);
    });
    await _load();
  }
}
