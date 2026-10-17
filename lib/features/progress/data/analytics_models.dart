import 'package:flutter/foundation.dart';

import 'study_session.dart';

/// Daily goal baseline. 8 hours = 480 minutes = 100%.
const int defaultDailyGoalMinutes = defaultDailyStudyGoalMinutes;

/// Persistable user goal.
@immutable
class UserGoal {
  final int dailyGoalMinutes;
  final DateTime updatedAt;

  const UserGoal({
    this.dailyGoalMinutes = defaultDailyGoalMinutes,
    required this.updatedAt,
  });

  double progressPercentage(int completedMinutes) {
    if (dailyGoalMinutes <= 0) return 0;
    return (completedMinutes / dailyGoalMinutes).clamp(0.0, 1.0) * 100;
  }

  double progressRatio(int completedMinutes) {
    if (dailyGoalMinutes <= 0) return 0;
    return (completedMinutes / dailyGoalMinutes).clamp(0.0, 1.0);
  }

  Map<String, Object?> toJson() => {
    'dailyGoalMinutes': dailyGoalMinutes,
    'updatedAt': updatedAt.toIso8601String(),
  };

  factory UserGoal.fromJson(Map<String, Object?> json) => UserGoal(
    dailyGoalMinutes:
        json['dailyGoalMinutes'] as int? ?? defaultDailyGoalMinutes,
    updatedAt: json['updatedAt'] == null
        ? DateTime.now()
        : DateTime.parse(json['updatedAt']! as String),
  );
}

/// Four fixed local-time buckets, exact and mutually exclusive:
/// Night [00:00, 06:00), Morning [06:00, 12:00),
/// Afternoon [12:00, 18:00), Evening [18:00, 24:00).
/// Every second of study time belongs to exactly one period.
enum TimePeriod { morning, afternoon, evening, night }

int timePeriodIndexForHour(int hour) {
  if (hour >= 6 && hour < 12) return 0;
  if (hour >= 12 && hour < 18) return 1;
  if (hour >= 18) return 2;
  return 3;
}

TimePeriod timePeriodForHour(int hour) =>
    TimePeriod.values[timePeriodIndexForHour(hour)];

/// Per-session attribution split across the four periods (minutes).
@immutable
class TimePeriodSession {
  final String sessionId;
  final String subjectId;
  final DateTime date;
  final int morningMinutes;
  final int afternoonMinutes;
  final int eveningMinutes;
  final int nightMinutes;

  const TimePeriodSession({
    required this.sessionId,
    required this.subjectId,
    required this.date,
    this.morningMinutes = 0,
    this.afternoonMinutes = 0,
    this.eveningMinutes = 0,
    this.nightMinutes = 0,
  });

  int get totalMinutes =>
      morningMinutes + afternoonMinutes + eveningMinutes + nightMinutes;

  List<int> get asList => [
    morningMinutes,
    afternoonMinutes,
    eveningMinutes,
    nightMinutes,
  ];

  /// Goal-relative fractions (0.0-1.0) for pie slices.
  List<double> goalFractions(int goalMinutes) {
    if (goalMinutes <= 0) return const [0, 0, 0, 0];
    return [for (final m in asList) (m / goalMinutes).clamp(0.0, 1.0)];
  }
}

/// Split [start,end) into the four buckets by local time, second-accurate.
/// The cursor walks hour boundaries (all four period edges are
/// hour-aligned), seconds accumulate per period, and the minute conversion
/// happens once at the end so no seconds are lost to per-slice truncation.
List<int> splitMinutesByPeriod(DateTime start, DateTime end) {
  final seconds = List<int>.filled(4, 0);
  var cursor = start;
  while (cursor.isBefore(end)) {
    final nextHour = DateTime(
      cursor.year,
      cursor.month,
      cursor.day,
      cursor.hour + 1,
    );
    final segEnd = nextHour.isBefore(end) ? nextHour : end;
    seconds[timePeriodIndexForHour(cursor.hour)] += segEnd
        .difference(cursor)
        .inSeconds;
    cursor = segEnd;
  }
  return [for (final s in seconds) s ~/ 60];
}

/// Goal-relative pie percentages (0-100) for the four periods.
List<double> periodGoalPercentages(List<int> minutesByPart, int goalMinutes) {
  if (goalMinutes <= 0) return List<double>.filled(4, 0);
  return [for (final m in minutesByPart) m / goalMinutes * 100];
}

/// Remaining-track percentage to fill the pie up to 100%.
double remainingGoalPercentage(List<int> minutesByPart, int goalMinutes) {
  final done = minutesByPart.fold(0, (a, b) => a + b);
  if (goalMinutes <= 0) return 100;
  return ((goalMinutes - done) / goalMinutes * 100).clamp(0.0, 100.0);
}

/// Chart 2 — Daily Goal Completion bar (single day).
/// Bar Fill % = min(100%, completed / goal * 100). 4h of 8h = 50%.
double barFillRatio(int completedMinutes, int goalMinutes) {
  if (goalMinutes <= 0) return 0;
  return (completedMinutes / goalMinutes).clamp(0.0, 1.0);
}

double barFillPercentage(int completedMinutes, int goalMinutes) =>
    barFillRatio(completedMinutes, goalMinutes) * 100;

/// Chart 3 — Weekly Goal Analytics (Mon..Sun).
/// Day d Value % = min(100%, completed(d) / goal(d) * 100).
/// Future / unstudied days naturally yield 0 minutes -> 0%.
List<double> weeklyDayPercentages(List<int> minutesByDay, int goalMinutes) {
  final g = goalMinutes <= 0 ? defaultDailyGoalMinutes : goalMinutes;
  return [for (final m in minutesByDay) (m / g * 100).clamp(0.0, 100.0)];
}

/// Monthly view: each point is one calendar week's total.
/// Goal-relative against a full week's goal (dailyGoal * 7).
List<double> monthlyWeekPercentages(List<int> minutesByWeek, int goalMinutes) {
  final weekGoal =
      (goalMinutes <= 0 ? defaultDailyGoalMinutes : goalMinutes) * 7;
  return [
    for (final m in minutesByWeek) (m / weekGoal * 100).clamp(0.0, 100.0),
  ];
}
