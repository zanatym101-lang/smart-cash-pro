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

  String _arabicWeekday(int weekday) {
    switch (weekday) {
      case DateTime.monday:
        return 'الإثنين';
      case DateTime.tuesday:
        return 'الثلاثاء';
      case DateTime.wednesday:
        return 'الأربعاء';
      case DateTime.thursday:
        return 'الخميس';
      case DateTime.friday:
        return 'الجمعة';
      case DateTime.saturday:
        return 'السبت';
      case DateTime.sunday:
        return 'الأحد';
      default:
        return '';
    }
  }

  String _arabicMonth(int month) {
    switch (month) {
      case 1:
        return 'يناير';
      case 2:
        return 'فبراير';
      case 3:
        return 'مارس';
      case 4:
        return 'أبريل';
      case 5:
        return 'مايو';
      case 6:
        return 'يونيو';
      case 7:
        return 'يوليو';
      case 8:
        return 'أغسطس';
      case 9:
        return 'سبتمبر';
      case 10:
        return 'أكتوبر';
      case 11:
        return 'نوفمبر';
      case 12:
        return 'ديسمبر';
      default:
        return '';
    }
  }

  String _formatPeriodSubtitle(DateRange range) {
    if (_period == 'today') {
      final d = range.start;
      final dayName = _arabicWeekday(d.weekday);
      final monthName = _arabicMonth(d.month);
      return 'اليوم: $dayName ${d.day} $monthName ${d.year}';
    } else if (_period == 'month') {
      final d = range.start;
      final monthName = _arabicMonth(d.month);
      return 'الفترة: شهر $monthName ${d.year} (من ${_fmtDate(range.start)} إلى ${_fmtDate(range.end)})';
    }
    return 'الفترة: من ${_fmtDate(range.start)} إلى ${_fmtDate(range.end)}';
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

