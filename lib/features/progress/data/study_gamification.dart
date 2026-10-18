import 'package:flutter/material.dart';

import 'study_day.dart' show isGoalReached;
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

/// XP rules (replacing the old "1 study minute = 1 XP" rule):
/// - 10 XP for every calendar day whose recorded study minutes meet the
///   daily goal ([isGoalReached]).
/// - 50 XP bonus for every Mon–Sun week whose total minutes meet the full
///   weekly goal — 7 × the daily goal, the app's existing "a full week's
///   goal" definition (see monthlyWeekPercentages in analytics_models).
/// A missed day or week awards nothing, but XP already earned is never
/// removed: [XpLedger] awards are append-only and survive goal changes.
/// Maximum possible XP per week is 120 (7 × 10 daily + 50 weekly bonus).
const int xpPerGoalDay = 10;
const int xpWeeklyBonus = 50;

String _two(int value) => value.toString().padLeft(2, '0');

/// `yyyy-MM-dd` key for one local calendar day.
String xpDayKey(DateTime date) =>
    '${date.year}-${_two(date.month)}-${_two(date.day)}';

/// Monday midnight of [date]'s Mon–Sun week (the app's week convention).
DateTime xpWeekStart(DateTime date) =>
    DateTime(date.year, date.month, date.day).subtract(
      Duration(days: date.weekday - 1),
    );

/// Persistent, append-only record of XP awards. Days and weeks are keyed
/// by local calendar-date strings; set membership makes every evaluation
/// idempotent, so app restarts, screen opens and repeated saves can never
/// award the same day or week twice.
@immutable
class XpLedger {
  final Set<String> awardedDays;
  final Set<String> awardedWeeks;
  const XpLedger({this.awardedDays = const {}, this.awardedWeeks = const {}});

  int get totalXp =>
      awardedDays.length * xpPerGoalDay + awardedWeeks.length * xpWeeklyBonus;

  Map<String, Object?> toJson() => {
    'days': awardedDays.toList()..sort(),
    'weeks': awardedWeeks.toList()..sort(),
  };

  factory XpLedger.fromJson(Map<String, Object?> json) => XpLedger(
    awardedDays: {
      for (final key in json['days'] as List<Object?>? ?? const [])
        key! as String,
    },
    awardedWeeks: {
      for (final key in json['weeks'] as List<Object?>? ?? const [])
        key! as String,
    },
  );
}

/// Minutes for one Monday-start week, used for the weekly bonus check.
typedef MinutesForWeek = int Function(DateTime monday);

/// Evaluates real recorded minutes against the current goal and returns
/// [ledger] extended with every newly qualified day/week award. Returns
/// the same instance when nothing changed (callers can skip persisting).
/// [full] rescans the whole history from [earliestDay] — used on app load
/// and goal changes; a partial check only re-evaluates today and the
/// current week, which is enough because recorded minutes only ever grow
/// while the week is current.
XpLedger syncXpAwards({
  required XpLedger ledger,
  required int dailyGoalMinutes,
  required DateTime now,
  required MinutesForDay minutesForDay,
  required MinutesForWeek minutesForWeek,
  required DateTime earliestDay,
  bool full = false,
}) {
  if (dailyGoalMinutes <= 0) return ledger;
  final weekGoalMinutes = dailyGoalMinutes * 7;
  var days = ledger.awardedDays;
  var weeks = ledger.awardedWeeks;
  var changed = false;

  bool awardDay(DateTime day) {
    final key = xpDayKey(day);
    if (days.contains(key)) return false;
    if (!isGoalReached(minutesForDay(day), dailyGoalMinutes)) return false;
    days = {...days, key};
    return true;
  }

  bool awardWeek(DateTime monday) {
    final key = xpDayKey(monday);
    if (weeks.contains(key)) return false;
    if (!isGoalReached(minutesForWeek(monday), weekGoalMinutes)) return false;
    weeks = {...weeks, key};
    return true;
  }

  final today = DateTime(now.year, now.month, now.day);
  if (full) {
    var day = DateTime(earliestDay.year, earliestDay.month, earliestDay.day);
    while (!day.isAfter(today)) {
      changed = awardDay(day) || changed;
      day = day.add(const Duration(days: 1));
    }
    var monday = xpWeekStart(earliestDay);
    final currentMonday = xpWeekStart(today);
    while (!monday.isAfter(currentMonday)) {
      changed = awardWeek(monday) || changed;
      monday = monday.add(const Duration(days: 7));
    }
  } else {
    changed = awardDay(today) || changed;
    changed = awardWeek(xpWeekStart(today)) || changed;
  }
  if (!changed) return ledger;
  return XpLedger(awardedDays: days, awardedWeeks: weeks);
}

/// Level progression tier: [xpPerLevel] is the cost of clearing each level
/// inside the tier; cumulative thresholds are built from all tiers below.
class StudyTier {
  final String name;
  final String theme;

  /// Belt/diamond theme color for the level icon.
  final Color color;
  final int minLevel;

  /// Highest level in the tier; null = unbounded (Grandmaster).
  final int? maxLevel;
  final int xpPerLevel;
  const StudyTier({
    required this.name,
    required this.theme,
    required this.color,
    required this.minLevel,
    this.maxLevel,
    required this.xpPerLevel,
  });
}

/// The five tiers with their themes and per-level XP cost.
const List<StudyTier> studyTiers = [
  StudyTier(
    name: 'Novice',
    theme: 'Seedling',
    color: Color(0xFFF5F5F7),
    minLevel: 1,
    maxLevel: 5,
    xpPerLevel: 100,
  ),
  StudyTier(
    name: 'Apprentice',
    theme: 'Sprout',
    color: Color(0xFFCD7F32),
    minLevel: 6,
    maxLevel: 15,
    xpPerLevel: 250,
  ),
  StudyTier(
    name: 'Achiever',
    theme: 'Tree',
    color: Color(0xFFC9CBD8),
    minLevel: 16,
    maxLevel: 30,
    xpPerLevel: 500,
  ),
  StudyTier(
    name: 'Master',
    theme: 'Focus Elite',
    color: Color(0xFFFDD679),
    minLevel: 31,
    maxLevel: 50,
    xpPerLevel: 1000,
  ),
  StudyTier(
    name: 'Grandmaster',
    theme: 'Sage',
    color: Color(0xFF8FE3FF),
    minLevel: 51,
    xpPerLevel: 2500,
  ),
];

StudyTier studyTierForLevel(int level) {
  for (final tier in studyTiers.reversed) {
    if (level >= tier.minLevel) return tier;
  }
  return studyTiers.first;
}

/// Cumulative XP threshold to be at [level]: the sum of every cleared
/// level's tier cost (Novice 1–5 at 100 each, Apprentice 6–15 at 250,
/// Achiever 16–30 at 500, Master 31–50 at 1,000, Grandmaster 51+ at
/// 2,500). L1 = 0, L2 = 100, L6 = 500, L16 = 3,000, L31 = 10,500,
/// L51 = 30,500 — earlier tiers are never re-priced by later ones.
int xpThresholdForLevel(int level) {
  if (level <= 1) return 0;
  var remaining = level - 1;
  var total = 0;
  for (final tier in studyTiers) {
    if (remaining <= 0) break;
    final span = tier.maxLevel == null
        ? remaining
        : tier.maxLevel! + 1 - tier.minLevel;
    final cleared = remaining < span ? remaining : span;
    total += cleared * tier.xpPerLevel;
    remaining -= cleared;
  }
  return total;
}

/// Current level plus everything the UI needs for one total XP value.
class StudyLevel {
  final int level;
  final int totalXp;
  final int xpIntoLevel;
  final int xpForNextLevel;

  /// XP still needed to reach the next level.
  final int xpRemaining;
  final StudyTier tier;
  const StudyLevel({
    required this.level,
    required this.totalXp,
    required this.xpIntoLevel,
    required this.xpForNextLevel,
    required this.xpRemaining,
    required this.tier,
  });
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
    xpRemaining: next - xp,
    tier: studyTierForLevel(level),
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
