import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:studyup/features/focus/data/focus_models.dart';
import 'package:studyup/features/progress/data/analytics_models.dart';
import 'package:studyup/features/progress/data/study_day.dart';
import 'package:studyup/features/progress/data/app_metadata.dart';
import 'package:studyup/features/progress/data/study_session.dart';
import 'package:studyup/features/progress/presentation/study_progress_controller.dart';
import 'package:studyup/features/subjects/data/subjects_models.dart';

void main() {
  group('Goal-relative progress (100% bug fix)', () {
    test('1 minute of 480 is ~0.21%, not 100%', () {
      final goal = UserGoal(
        dailyGoalMinutes: 480,
        updatedAt: DateTime(2026, 1, 1),
      );
      expect(goal.progressPercentage(1), closeTo(0.208, 0.01));
      expect(goal.progressPercentage(0), 0);
      expect(goal.progressPercentage(480), 100);
      expect(goal.progressPercentage(600), 100);
      expect(goal.progressRatio(1), closeTo(0.00208, 0.0001));
    });

    test('pie slices are goal-relative with remaining track', () {
      const mins = [30, 60, 0, 30];
      final pcts = periodGoalPercentages(mins, 480);
      expect(pcts[0], closeTo(6.25, 0.01));
      expect(pcts[1], closeTo(12.5, 0.01));
      expect(remainingGoalPercentage(mins, 480), closeTo(75.0, 0.01));
      expect(remainingGoalPercentage(const [0, 0, 0, 0], 480), 100);
    });

    test('time buckets follow 6/12/18 midnight-aligned boundaries', () {
      expect(timePeriodIndexForHour(0), 3);
      expect(timePeriodIndexForHour(5), 3);
      expect(timePeriodIndexForHour(6), 0);
      expect(timePeriodIndexForHour(11), 0);
      expect(timePeriodIndexForHour(12), 1);
      expect(timePeriodIndexForHour(17), 1);
      expect(timePeriodIndexForHour(18), 2);
      expect(timePeriodIndexForHour(23), 2);
    });

    test('cross-boundary session splits across periods', () {
      final parts = splitMinutesByPeriod(
        DateTime(2026, 1, 1, 11, 30),
        DateTime(2026, 1, 1, 12, 30),
      );
      expect(parts[0], 30);
      expect(parts[1], 30);
      expect(parts[2], 0);
      expect(parts[3], 0);
    });

    test('daily attendance follows calendar dates, uncapped', () {
      // Overnight Oct 5 11 PM -> Oct 6 2 AM belongs to both dates.
      final sessions = [
        FocusSessionModel(
          id: 'overnight',
          subjectId: 'math',
          startTime: DateTime(2026, 10, 5, 23),
          endTime: DateTime(2026, 10, 6, 2),
        ),
      ];
      final oct5 = DailyAttendanceModel(
        date: DateTime(2026, 10, 5),
        sessions: sessions,
      );
      final oct6 = DailyAttendanceModel(
        date: DateTime(2026, 10, 6),
        sessions: sessions,
      );
      expect(oct5.totalStudiedMinutes, 60);
      expect(oct6.totalStudiedMinutes, 120);
      expect(oct5.sessionCount, 1);
      // Recorded progress is exact; bars may cap visually.
      final long = DailyAttendanceModel(
        date: DateTime(2026, 3, 3),
        targetGoalMinutes: 480,
        sessions: [
          FocusSessionModel(
            id: 'long',
            subjectId: 'math',
            startTime: DateTime(2026, 3, 3, 8),
            endTime: DateTime(2026, 3, 3, 18),
          ),
        ],
      );
      expect(long.totalStudiedMinutes, 600);
      expect(long.achievementRatio, closeTo(1.25, 0.001));
    });

    test('bar fill is goal-relative and capped', () {
      expect(barFillRatio(240, 480), closeTo(0.5, 0.001));
      expect(barFillPercentage(240, 480), closeTo(50.0, 0.01));
      expect(barFillRatio(0, 480), 0);
      expect(barFillRatio(600, 480), 1.0);
      expect(barFillRatio(1, 480), closeTo(0.00208, 0.0001));
    });

    test('weekly days are goal-relative, future/unstudied are 0', () {
      final pcts = weeklyDayPercentages([384, 480, 240, 0, 0, 0, 0], 480);
      expect(pcts[0], closeTo(80.0, 0.01));
      expect(pcts[1], closeTo(100.0, 0.01));
      expect(pcts[2], closeTo(50.0, 0.01));
      expect(pcts[3], 0);
      expect(pcts[6], 0);
    });

    test('monthly weeks are goal-relative against goal x 7', () {
      final pcts = monthlyWeekPercentages([1680, 3360], 480);
      expect(pcts[0], closeTo(50.0, 0.01));
      expect(pcts[1], closeTo(100.0, 0.01));
      expect(monthlyWeekPercentages([0], 480)[0], 0);
    });
  });

  group('Attendance first-launch rules', () {
    final first = DateTime(2026, 2, 10);
    final today = DateTime(2026, 2, 12);

    test('dates before first launch are disabled', () {
      expect(
        attendanceStatusFor(
          day: DateTime(2026, 2, 9),
          firstLaunchDay: first,
          today: today,
          hasSession: true,
        ),
        AttendanceStatus.disabled,
      );
    });

    test('present needs >=1 session, absent only for ended days', () {
      expect(
        attendanceStatusFor(
          day: DateTime(2026, 2, 11),
          firstLaunchDay: first,
          today: today,
          hasSession: true,
        ),
        AttendanceStatus.present,
      );
      expect(
        attendanceStatusFor(
          day: DateTime(2026, 2, 11),
          firstLaunchDay: first,
          today: today,
          hasSession: false,
        ),
        AttendanceStatus.absent,
      );
      expect(
        attendanceStatusFor(
          day: today,
          firstLaunchDay: first,
          today: today,
          hasSession: false,
        ),
        AttendanceStatus.pending,
      );
    });
  });

  group('Chapter-based subject progress', () {
    Subject makeSubject() => Subject(
      id: 's1',
      name: 'Math',
      meta: 'm',
      weekHours: '',
      color: Colors.blue,
      icon: Icons.book,
      totalHours: '',
      chapters: const [
        Chapter(
          id: 'c1',
          title: 'Ch1',
          topics: [
            Topic(id: 't1', name: 'a', done: true),
            Topic(id: 't2', name: 'b', done: true),
          ],
        ),
        Chapter(
          id: 'c2',
          title: 'Ch2',
          topics: [
            Topic(id: 't3', name: 'c', done: true),
            Topic(id: 't4', name: 'd', done: false),
          ],
        ),
        Chapter(id: 'c3', title: 'Empty', topics: []),
      ],
    );

    test('empty chapters never count as complete', () {
      final s = makeSubject();
      expect(s.chapters[0].isChapterCompleted, isTrue);
      expect(s.chapters[1].isChapterCompleted, isFalse);
      expect(s.chapters[2].isChapterCompleted, isFalse);
      expect(s.totalChapters, 3);
      expect(s.completedChapters, 1);
      expect(s.progressPercentage, closeTo(33.33, 0.01));
      expect(s.progressRatio, closeTo(1 / 3, 0.001));
    });

    test('zero chapters is 0%, not NaN', () {
      const s = Subject(
        id: 's',
        name: 'n',
        meta: 'm',
        weekHours: '',
        color: Colors.blue,
        icon: Icons.book,
        totalHours: '',
        chapters: [],
      );
      expect(s.totalChapters, 0);
      expect(s.completedChapters, 0);
      expect(s.progressPercentage, 0);
    });
  });

  group('Midnight study-day window', () {
    test('every timestamp belongs to its own calendar date', () {
      expect(studyDayFor(DateTime(2026, 3, 10, 0, 0)), DateTime(2026, 3, 10));
      expect(studyDayFor(DateTime(2026, 3, 10, 4, 59)), DateTime(2026, 3, 10));
      expect(studyDayFor(DateTime(2026, 3, 10, 5, 0)), DateTime(2026, 3, 10));
      expect(studyDayFor(DateTime(2026, 3, 10, 23, 30)), DateTime(2026, 3, 10));
    });

    test('window spans midnight to next midnight', () {
      final w = studyDayRange(DateTime(2026, 3, 10));
      expect(w.start, DateTime(2026, 3, 10));
      expect(w.end, DateTime(2026, 3, 11));
    });

    test('next reset is the coming midnight', () {
      expect(
        nextStudyResetAt(DateTime(2026, 3, 10, 0, 0)),
        DateTime(2026, 3, 11),
      );
      expect(
        nextStudyResetAt(DateTime(2026, 3, 10, 4, 0)),
        DateTime(2026, 3, 11),
      );
      expect(
        nextStudyResetAt(DateTime(2026, 3, 10, 6, 0)),
        DateTime(2026, 3, 11),
      );
      expect(
        nextStudyResetAt(DateTime(2026, 3, 10, 23, 59)),
        DateTime(2026, 3, 11),
      );
    });

    test('overflow preserved: 520/480 = 108.33%', () {
      expect(achievementRatio(520, 480), closeTo(1.0833, 0.001));
      expect(formatAchievement(520, 480), '108%');
      expect(formatAchievement(240, 480), '50%');
      expect(formatAchievement(0, 480), '0%');
      expect(formatMonthlyPercentage(32.142857), '32.14%');
    });

    test('readout formats match spec', () {
      expect(
        formatTotalStudied(270, 480),
        'Total Studied: 4h 30m / 8h 00m Goal',
      );
      expect(formatDayStudied('Day A', 375), 'Day A: 6h 15m Studied');
      expect(formatDayStudied('Day B', 285), 'Day B: 4h 45m Studied');
    });
  });

  group('Subject analytics isolation + accumulation', () {
    StudyProgressState stateWithSessions() => StudyProgressState(
      isLoaded: true,
      sessions: [
        StudySession(
          id: 'g1',
          subjectId: 'general',
          subjectName: 'General Study',
          checkInTime: DateTime(2026, 3, 10, 9),
          checkOutTime: DateTime(2026, 3, 10, 9, 30),
        ),
        StudySession(
          id: 'p1',
          subjectId: 'physics',
          subjectName: 'Physics',
          checkInTime: DateTime(2026, 3, 10, 10),
          checkOutTime: DateTime(2026, 3, 10, 10, 45),
        ),
        StudySession(
          id: 'p2',
          subjectId: 'physics',
          subjectName: 'Physics',
          checkInTime: DateTime(2026, 3, 10, 14),
          checkOutTime: DateTime(2026, 3, 10, 15),
        ),
        StudySession(
          id: 'late',
          subjectId: 'physics',
          subjectName: 'Physics',
          checkInTime: DateTime(2026, 3, 11, 2),
          checkOutTime: DateTime(2026, 3, 11, 2, 30),
        ),
      ],
    );

    test('general sessions never leak into subject totals', () {
      final s = stateWithSessions();
      final start = DateTime(2026, 3, 10, 5);
      final end = DateTime(2026, 3, 11, 5);
      // p1 (45) + p2 (60) + late-night 02:00 session (30) share the window.
      expect(s.minutesForSubjectInRange('physics', start, end), 135);
      expect(s.sessionCountForSubjectInRange('physics', start, end), 3);
      expect(s.minutesForSubjectInRange('general', start, end), 30);
      expect(s.minutesForSubjectInRange('chemistry', start, end), 0);
    });

    test('early-morning sessions belong to their calendar date', () {
      final s = stateWithSessions();
      expect(s.minutesForSubjectOnDate('physics', DateTime(2026, 3, 10)), 105);
      expect(s.minutesForSubjectOnDate('physics', DateTime(2026, 3, 11)), 30);
      expect(
        s.sessionCountForSubjectOnDate('physics', DateTime(2026, 3, 10)),
        2,
      );
      expect(
        s.sessionCountForSubjectOnDate('physics', DateTime(2026, 3, 11)),
        1,
      );
    });
  });

  group('Pause/resume session math', () {
    test('running accrues live from the resume anchor', () {
      final t0 = DateTime(2026, 4, 1, 9, 0, 0);
      final running = StudySession(
        id: 'r',
        subjectId: 'math',
        subjectName: 'Math',
        checkInTime: t0,
        resumedAt: t0,
      );
      expect(running.isRunning, isTrue);
      expect(
        running.durationAt(t0.add(const Duration(seconds: 3))).inSeconds,
        3,
      );
    });

    test('paused freezes at banked seconds, ended returns banked total', () {
      final t0 = DateTime(2026, 4, 1, 9, 0, 0);
      final paused = StudySession(
        id: 'p',
        subjectId: 'math',
        subjectName: 'Math',
        checkInTime: t0,
        pausedSeconds: 3,
        resumedAt: null,
      );
      expect(paused.isPaused, isTrue);
      expect(paused.durationAt(t0.add(const Duration(hours: 5))).inSeconds, 3);

      final ended = StudySession(
        id: 'e',
        subjectId: 'math',
        subjectName: 'Math',
        checkInTime: t0,
        checkOutTime: t0.add(const Duration(seconds: 5)),
        pausedSeconds: 5,
        resumedAt: null,
      );
      expect(ended.durationAt(t0.add(const Duration(days: 9))).inSeconds, 5);
    });

    test('legacy rows migrate wall-clock into banked seconds', () {
      final ended = StudySession.fromJson({
        'id': 'legacy-ended',
        'subjectId': 'math',
        'subjectName': 'Math',
        'checkInTime': '2026-04-01T09:00:00.000',
        'checkOutTime': '2026-04-01T10:00:00.000',
      });
      expect(ended.pausedSeconds, 3600);
      expect(ended.durationAt(DateTime(2026, 4, 2)).inHours, 1);

      final active = StudySession.fromJson({
        'id': 'legacy-active',
        'subjectId': 'math',
        'subjectName': 'Math',
        'checkInTime': '2026-04-01T09:00:00.000',
        'checkOutTime': null,
      });
      expect(active.isRunning, isTrue);
      expect(active.durationAt(DateTime(2026, 4, 1, 9, 0, 3)).inSeconds, 3);
    });
  });
}
