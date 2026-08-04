/// Pure date rule shared by routine projection and planning compatibility.
///
/// Dates are compared as civil UTC days so daylight-saving transitions cannot
/// shift an alternating week. This engine decides dates only: it does not read,
/// write, schedule, or create calendar events.
final class RoutineDateApplicabilityEngine {
  const RoutineDateApplicabilityEngine();

  bool applies({
    required String recurrenceType,
    required List<int> weekdays,
    required DateTime date,
    String? anchorDateIso,
    int? weekOfMonth,
    bool emptyWeekdaysMatchAll = false,
  }) {
    final normalizedType = recurrenceType.trim().toLowerCase();
    final matchesWeekday = weekdays.isEmpty
        ? emptyWeekdaysMatchAll
        : weekdays.contains(date.weekday);

    switch (normalizedType) {
      case 'weekdays':
        return date.weekday >= DateTime.monday &&
            date.weekday <= DateTime.friday;
      case 'biweekly':
        if (!matchesWeekday) return false;
        final anchor = DateTime.tryParse(anchorDateIso?.trim() ?? '');
        if (anchor == null) return false;
        final difference = _civilUtc(date).difference(_civilUtc(anchor)).inDays;
        return difference >= 0 && (difference ~/ 7).isEven;
      case 'monthly_nth_weekday':
      case 'monthlynthweekday':
        if (!matchesWeekday) return false;
        if (weekOfMonth == -1) {
          return date.add(const Duration(days: 7)).month != date.month;
        }
        if (weekOfMonth == null || weekOfMonth < 1 || weekOfMonth > 5) {
          return false;
        }
        return ((date.day - 1) ~/ 7) + 1 == weekOfMonth;
      case 'weekly':
      default:
        return matchesWeekday;
    }
  }

  DateTime _civilUtc(DateTime value) =>
      DateTime.utc(value.year, value.month, value.day);
}
