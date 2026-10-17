import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/focus_models.dart';
import '../../progress/data/app_metadata.dart';
import '../../progress/presentation/study_progress_controller.dart';
import '../../subjects/data/subjects_models.dart';

/// All focus/attendance state is DERIVED from the single source of truth:
/// [studyProgressProvider]. This guarantees there is only ONE timer running.
/// Starting a focus session ticks both the subject daily progress and the
/// overall daily attendance because both read the same session list.

// All focus sessions as unified models.
final focusSessionsProvider = Provider<List<FocusSessionModel>>((ref) {
  final progress = ref.watch(studyProgressProvider);
  return [
    for (final s in progress.sessions) FocusSessionModel.fromStudySession(s),
  ];
});

// Currently running session, if any.
final activeFocusSessionProvider = Provider<FocusSessionModel?>((ref) {
  final sessions = ref.watch(focusSessionsProvider);
  for (final s in sessions) {
    if (s.isActive) return s;
  }
  return null;
});

// Daily attendance uses the same goal managed from Profile/Settings.
final dailyAttendanceGoalProvider = Provider<int>((ref) {
  return ref.watch(
    studyProgressProvider.select((p) => p.dailyStudyGoalMinutes),
  );
});

/// Daily attendance aggregate for a calendar day.
/// Usage: `ref.watch(dailyAttendanceProvider(someDate))`.
final dailyAttendanceProvider = Provider.family<DailyAttendanceModel, DateTime>(
  (ref, date) {
    final day = DateTime(date.year, date.month, date.day);
    final sessions = ref.watch(focusSessionsProvider);
    final goal = ref.watch(dailyAttendanceGoalProvider);
    return DailyAttendanceModel(
      date: day,
      sessions: sessions,
      targetGoalMinutes: goal,
    );
  },
);

/// Param for per-subject-per-day minutes.
class SubjectDayQuery {
  final String subjectId;
  final DateTime date;
  const SubjectDayQuery(this.subjectId, this.date);

  @override
  bool operator ==(Object other) =>
      other is SubjectDayQuery &&
      other.subjectId == subjectId &&
      other.date.year == date.year &&
      other.date.month == date.month &&
      other.date.day == date.day;

  @override
  int get hashCode => Object.hash(subjectId, date.year, date.month, date.day);
}

/// Minutes studied for one subject on one day (live while active).
final subjectDailyMinutesProvider = Provider.family<int, SubjectDayQuery>((
  ref,
  query,
) {
  final progress = ref.watch(studyProgressProvider);
  return progress.minutesForSubjectOnDate(query.subjectId, query.date);
});

/// Resolve a display name for a session's subject. Prefers the stored
/// session name (new daily sessions store "Daily Study"); falls back to
/// "General Study" for legacy general rows and unknown subjects.
String resolveFocusSubjectName({
  required String subjectId,
  required List<Subject> subjects,
  required String storedNameFallback,
}) {
  if (storedNameFallback.isNotEmpty) {
    for (final s in subjects) {
      if (s.id == subjectId) return s.name;
    }
    return storedNameFallback;
  }
  if (subjectId == generalStudySubjectId) return generalStudySubjectName;
  for (final s in subjects) {
    if (s.id == subjectId) return s.name;
  }
  return generalStudySubjectName;
}

/// Start the single daily focus session. Single-timer invariant is enforced
/// by [StudyProgressController] (throws if another session is active).
Future<void> startFocusSession(WidgetRef ref) {
  return ref.read(studyProgressProvider.notifier).startSession();
}

Future<void> endFocusSession(WidgetRef ref) {
  return ref.read(studyProgressProvider.notifier).endSession();
}

/// Time-period minutes for a calendar date: [morning, afternoon,
// evening, night] on the fixed [00-06/06-12/12-18/18-24] boundaries.
// Progress Percentage = min(100%, completed / goal * 100).
final timePeriodMinutesProvider = Provider.family<List<int>, DateTime>((
  ref,
  date,
) {
  final progress = ref.watch(studyProgressProvider);
  final day = DateTime(date.year, date.month, date.day);
  return progress.dayPartMinutes(day);
});

/// Goal-relative pie fractions + remaining track.
final timePeriodGoalFractionsProvider = Provider.family<List<double>, DateTime>(
  (ref, date) {
    final mins = ref.watch(timePeriodMinutesProvider(date));
    final goal = ref.watch(dailyAttendanceGoalProvider);
    final g = goal <= 0 ? 480 : goal;
    final fractions = [for (final m in mins) (m / g).clamp(0.0, 1.0)];
    final done = fractions.fold(0.0, (a, b) => a + b).clamp(0.0, 1.0);
    return [...fractions, (1 - done).clamp(0.0, 1.0)];
  },
);

/// Active session progress ratio 0.0-1.0 (never 100% on start).
/// Uses the calendar date (midnight to midnight).
final activeProgressRatioProvider = Provider<double>((ref) {
  final progress = ref.watch(studyProgressProvider);
  final active = progress.activeSession;
  if (active == null) {
    final today = DateTime.now();
    return progress
            .minutesForDate(today)
            .clamp(0, progress.dailyStudyGoalMinutes) /
        (progress.dailyStudyGoalMinutes <= 0
            ? 480
            : progress.dailyStudyGoalMinutes);
  }
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final completed = progress.minutesForDate(today, now: now);
  final goal = progress.dailyStudyGoalMinutes <= 0
      ? 480
      : progress.dailyStudyGoalMinutes;
  return (completed / goal).clamp(0.0, 1.0);
});

/// Attendance status for a calendar day (disabled before first launch).
/// Presence = actual recorded study time on that calendar date.
final attendanceStatusProvider = Provider.family<AttendanceStatus, DateTime>((
  ref,
  date,
) {
  final meta = ref.watch(appMetadataProvider).valueOrNull;
  final first = meta?.firstLaunchDay;
  final progress = ref.watch(studyProgressProvider);
  final day = DateTime(date.year, date.month, date.day);
  return attendanceStatusFor(
    day: day,
    firstLaunchDay: first,
    today: DateTime.now(),
    hasSession: progress.minutesForDate(day) > 0,
  );
});
