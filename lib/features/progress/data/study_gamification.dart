import 'study_session.dart';
import '../../home/data/home_models.dart';

/// One Monday-start calendar row covering the viewed month.
/// Rows match the app's Monday convention (same rows the monthly chart
/// consumes): the first row starts on the Monday on/before the 1st, and
/// rows continue while the Monday is still inside the month. Days may
/// spill into adjacent months; [label] is always W1..Wn of THIS month.
class MonthWeekRow {
  final DateTime monday;
  final String label;
  const MonthWeekRow({required this.monday, required this.label});

  DateTime get sunday => monday.add(const Duration(days: 6));

  String rangeLabel() =>
      '${monday.month}/${monday.day}–${sunday.month}/${sunday.day}';

  bool contains(DateTime day) {
    final d = DateTime(day.year, day.month, day.day);
    return !d.isBefore(monday) && !d.isAfter(sunday);
  }
}

/// Monday-start grid rows for [year]/[month]: 4–6 rows depending on the
/// real calendar layout (W6 appears only when the month spans six rows).
List<MonthWeekRow> monthWeekRows(int year, int month) {
  final first = DateTime(year, month, 1);
  final monthEnd = DateTime(year, month + 1, 1);
  var monday = first.subtract(Duration(days: first.weekday - 1));
  final rows = <MonthWeekRow>[];
  while (monday.isBefore(monthEnd)) {
    rows.add(MonthWeekRow(monday: monday, label: 'W${rows.length + 1}'));
    monday = monday.add(const Duration(days: 7));
  }
  return rows;
}

/// Row containing [date], or null when [date]'s week is not part of the
/// viewed month's grid.
MonthWeekRow? monthWeekRowForDate(List<MonthWeekRow> rows, DateTime date) {
  for (final row in rows) {
    if (row.contains(date)) return row;
  }
  return null;
}

/// Earliest calendar date touched by stored sessions (bounds the best-
/// streak walk so it never scans unbounded history).
DateTime earliestStudyDay(List<StudySession> sessions, DateTime fallback) {
  DateTime? first;
  for (final s in sessions) {
    final d = DateTime(
      s.checkInTime.year,
      s.checkInTime.month,
      s.checkInTime.day,
    );
    if (first == null || d.isBefore(first)) first = d;
  }
  return first ?? fallback;
}

/// Day-studied rule: a calendar date counts as studied when actual
/// recorded minutes for it are above zero.
typedef MinutesForDay = int Function(DateTime day);

/// Consecutive studied-day streaks from real history.
/// Current streak counts back from [today]; a quiet today does not break
/// it when yesterday was studied (counts through yesterday).
/// Best streak is the longest run anywhere in stored history.
class StudyStreak {
  final int current;
  final int best;
  const StudyStreak({required this.current, required this.best});
}

StudyStreak computeStudyStreak({
  required MinutesForDay minutesForDay,
  required DateTime today,
  required DateTime earliestDay,
}) {
  bool studied(DateTime d) => minutesForDay(d) > 0;
  final t = DateTime(today.year, today.month, today.day);
  final first = DateTime(earliestDay.year, earliestDay.month, earliestDay.day);

  var cursor = t;
  if (!studied(cursor)) cursor = cursor.subtract(const Duration(days: 1));
  var current = 0;
  while (!cursor.isBefore(first) && studied(cursor)) {
    current++;
    cursor = cursor.subtract(const Duration(days: 1));
  }

  var best = 0;
  var run = 0;
  var day = first;
  while (!day.isAfter(t)) {
    if (studied(day)) {
      run++;
      if (run > best) best = run;
    } else {
      run = 0;
    }
    day = day.add(const Duration(days: 1));
  }
  return StudyStreak(current: current, best: best);
}

/// Total recorded study minutes across all stored sessions (the XP
/// source). Active sessions accrue live through [now]; ended sessions
/// contribute their banked duration.
int totalStudyMinutes(List<StudySession> sessions, DateTime now) {
  var seconds = 0;
  for (final s in sessions) {
    seconds += s.durationAt(s.checkOutTime ?? now).inSeconds;
  }
  return seconds ~/ 60;
}

/// Level rule (explained in the UI): 1 study minute = 1 XP.
/// Level N unlocks at 60*N*(N-1)/2 cumulative XP
/// (L1 0, L2 60, L3 180, L4 360, L5 600, …).
int xpThresholdForLevel(int level) {
  if (level <= 1) return 0;
  return 60 * level * (level - 1) ~/ 2;
}

class StudyLevel {
  final int level;
  final int totalXp;
  final int xpIntoLevel;
  final int xpForNextLevel;
  const StudyLevel({
    required this.level,
    required this.totalXp,
    required this.xpIntoLevel,
    required this.xpForNextLevel,
  });

  double get progress =>
      xpForNextLevel <= 0 ? 1 : (xpIntoLevel / xpForNextLevel).clamp(0.0, 1.0);
}

StudyLevel computeStudyLevel(int totalXp) {
  final xp = totalXp < 0 ? 0 : totalXp;
  var level = 1;
  while (xp >= xpThresholdForLevel(level + 1)) {
    level++;
  }
  final base = xpThresholdForLevel(level);
  final next = xpThresholdForLevel(level + 1);
  return StudyLevel(
    level: level,
    totalXp: xp,
    xpIntoLevel: xp - base,
    xpForNextLevel: next - base,
  );
}

/// Attendance-day stats from the real task list for one calendar date.
/// Mapping (the app has no class-timetable model): scheduled = tasks on
/// the date, attended = done, missed = still open. Percentage is null
/// when nothing is scheduled (UI shows a dash, never divides by zero).
class TaskDayStats {
  final int scheduled;
  final int attended;
  final int missed;
  const TaskDayStats({
    required this.scheduled,
    required this.attended,
    required this.missed,
  });

  double? get percentage => scheduled == 0 ? null : attended / scheduled * 100;
}

TaskDayStats taskDayStats(List<StudyTask> tasks) {
  final attended = tasks.where((t) => t.isDone).length;
  return TaskDayStats(
    scheduled: tasks.length,
    attended: attended,
    missed: tasks.length - attended,
  );
}
