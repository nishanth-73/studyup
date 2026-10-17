// Midnight study-day boundary (device-local calendar dates).
//
// A new study day begins at exactly 12:00 AM local time. Every second of
// study time belongs to the calendar date containing it: daily totals and
// goal progress are derived per [midnight, next midnight) window, so the
// displayed "today" switches to the new date at midnight and starts from
// zero without touching stored history or running sessions.

/// Calendar date (day-normalized) that [timestamp] belongs to.
DateTime studyDayFor(DateTime timestamp) {
  return DateTime(timestamp.year, timestamp.month, timestamp.day);
}

/// Normalizes a picked compare date to a local calendar day, or returns
/// null when the pick lies after [today]. Future dates are never valid
/// comparison targets — enforced in state logic, not just in the picker.
DateTime? normalizeCompareDay(DateTime picked, DateTime today) {
  final day = DateTime(picked.year, picked.month, picked.day);
  final current = DateTime(today.year, today.month, today.day);
  if (day.isAfter(current)) return null;
  return day;
}

/// Study-day window for [day]: [day 00:00, day+1 00:00).
({DateTime start, DateTime end}) studyDayRange(DateTime day) {
  final d = DateTime(day.year, day.month, day.day);
  return (start: d, end: d.add(const Duration(days: 1)));
}

/// Next midnight after [now] (strictly in the future).
DateTime nextStudyResetAt(DateTime now) {
  final todayMidnight = DateTime(now.year, now.month, now.day);
  if (now.isBefore(todayMidnight.add(const Duration(days: 1)))) {
    return todayMidnight.add(const Duration(days: 1));
  }
  return todayMidnight.add(const Duration(days: 2));
}

/// Unclamped achievement (goal overflow allowed).
/// e.g. 520 / 480 = 1.0833 -> 108.33%.
double achievementRatio(int completedMinutes, int goalMinutes) {
  if (goalMinutes <= 0) return 0;
  final r = completedMinutes / goalMinutes;
  return r < 0 ? 0 : r;
}

/// Normal UI achievement percentage rounded to a whole percent.
String formatAchievement(int completedMinutes, int goalMinutes) {
  final pct = achievementRatio(completedMinutes, goalMinutes) * 100;
  return '${pct.round()}%';
}

/// Detailed percentage shown by the monthly weekly-average graph.
String formatMonthlyPercentage(double percentage) =>
    '${percentage.toStringAsFixed(2)}%';

String _two(int v) => v.toString().padLeft(2, '0');

/// Studied part: `4h 30m`, `45m` (unpadded, per spec examples).
String formatStudied(int minutes) {
  final m = minutes < 0 ? 0 : minutes;
  final h = m ~/ 60;
  final r = m % 60;
  if (h == 0) return '${r}m';
  return '${h}h ${r}m';
}

/// Goal part: `8h 00m` (minutes padded, per spec).
String formatGoal(int goalMinutes) {
  final g = goalMinutes < 0 ? 0 : goalMinutes;
  return '${g ~/ 60}h ${_two(g % 60)}m';
}

/// Goal-reached status: the goal is a reference target, never a cap.
/// True once actual minutes meet/exceed the goal; stays true past it.
bool isGoalReached(int completedMinutes, int goalMinutes) {
  if (goalMinutes <= 0) return false;
  return completedMinutes >= goalMinutes;
}

/// `Total Studied: 4h 30m / 8h 00m Goal` — updates live as sessions accrue.
String formatTotalStudied(int studiedMinutes, int goalMinutes) =>
    'Total Studied: ${formatStudied(studiedMinutes)} / ${formatGoal(goalMinutes)} Goal';

/// `Day A: 6h 15m Studied` comparison readout.
String formatDayStudied(String dayLabel, int studiedMinutes) =>
    '$dayLabel: ${formatStudied(studiedMinutes)} Studied';
