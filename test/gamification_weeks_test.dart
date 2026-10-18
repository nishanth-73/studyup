import 'package:flutter_test/flutter_test.dart';
import 'package:studyup/features/home/data/home_models.dart';
import 'package:studyup/features/progress/data/study_gamification.dart';
import 'package:studyup/features/progress/data/study_session.dart';

StudySession ended(String id, DateTime start, DateTime end) => StudySession(
  id: id,
  subjectId: 'general',
  subjectName: 'Daily Study',
  checkInTime: start,
  checkOutTime: end,
  pausedSeconds: end.difference(start).inSeconds,
);

void main() {
  group('monthWeekRows', () {
    test('October 2026 has 5 Monday rows starting Sep 28', () {
      // Oct 1 2026 is a Thursday.
      final rows = monthWeekRows(2026, 10);
      expect(rows.map((r) => r.label), ['W1', 'W2', 'W3', 'W4', 'W5']);
      expect(rows.first.monday, DateTime(2026, 9, 28));
      expect(rows.last.monday, DateTime(2026, 10, 26));
      expect(rows.first.rangeLabel(), '9/28–10/4');
    });

    test('February 2026 has 4 rows (month starts on Sunday)', () {
      // Feb 1 2026 is a Sunday: rows Jan 26, Feb 2, 9, 16, 23.
      final rows = monthWeekRows(2026, 2);
      expect(rows.map((r) => r.label), ['W1', 'W2', 'W3', 'W4', 'W5']);
      expect(rows.first.monday, DateTime(2026, 1, 26));
      expect(rows.last.monday, DateTime(2026, 2, 23));
    });

    test('February 2021 has exactly 4 rows', () {
      // Feb 1 2021 is a Monday and Feb has 28 days.
      final rows = monthWeekRows(2021, 2);
      expect(rows.map((r) => r.label), ['W1', 'W2', 'W3', 'W4']);
      expect(rows.first.monday, DateTime(2021, 2, 1));
      expect(rows.last.sunday, DateTime(2021, 2, 28));
    });

    test('August 2026 needs 6 rows', () {
      // Aug 1 2026 is a Saturday; grid spans Jul 27 – Sep 6.
      final rows = monthWeekRows(2026, 8);
      expect(rows.length, 6);
      expect(rows.last.label, 'W6');
      expect(rows.first.monday, DateTime(2026, 7, 27));
    });

    test('row lookup finds the containing week only', () {
      final rows = monthWeekRows(2026, 10);
      final hit = monthWeekRowForDate(rows, DateTime(2026, 10, 11));
      expect(hit?.label, 'W2');
      expect(monthWeekRowForDate(rows, DateTime(2026, 11, 2)), isNull);
    });
  });

  group('computeStudyStreak', () {
    int mins(Map<String, int> byDay, DateTime day) {
      final key =
          '${day.year}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}';
      return byDay[key] ?? 0;
    }

    test('counts back consecutive studied days', () {
      final data = {'2026-10-09': 30, '2026-10-10': 60, '2026-10-11': 45};
      final streak = computeStudyStreak(
        minutesForDay: (d) => mins(data, d),
        today: DateTime(2026, 10, 11),
        earliestDay: DateTime(2026, 10, 1),
      );
      expect(streak.current, 3);
      expect(streak.best, 3);
    });

    test('quiet today keeps streak alive through yesterday', () {
      final data = {'2026-10-10': 60, '2026-10-09': 30};
      final streak = computeStudyStreak(
        minutesForDay: (d) => mins(data, d),
        today: DateTime(2026, 10, 11),
        earliestDay: DateTime(2026, 10, 1),
      );
      expect(streak.current, 2);
    });

    test('gap days break the current streak but keep the best', () {
      final data = {
        '2026-10-01': 30,
        '2026-10-02': 30,
        '2026-10-03': 30,
        '2026-10-11': 30,
      };
      final streak = computeStudyStreak(
        minutesForDay: (d) => mins(data, d),
        today: DateTime(2026, 10, 11),
        earliestDay: DateTime(2026, 10, 1),
      );
      expect(streak.current, 1);
      expect(streak.best, 3);
    });

    test('no history is 0 / 0', () {
      final streak = computeStudyStreak(
        minutesForDay: (_) => 0,
        today: DateTime(2026, 10, 11),
        earliestDay: DateTime(2026, 10, 11),
      );
      expect(streak.current, 0);
      expect(streak.best, 0);
    });
  });

  group('levels and XP', () {
    test('thresholds accumulate across the five tiers', () {
      expect(xpThresholdForLevel(1), 0);
      expect(xpThresholdForLevel(2), 100);
      expect(xpThresholdForLevel(3), 200);
      expect(xpThresholdForLevel(4), 300);
      expect(xpThresholdForLevel(5), 400);
      expect(xpThresholdForLevel(6), 500);
      expect(xpThresholdForLevel(7), 750);
      expect(xpThresholdForLevel(16), 3000);
      expect(xpThresholdForLevel(31), 10500);
      expect(xpThresholdForLevel(51), 30500);
      expect(xpThresholdForLevel(52), 33000);
    });

    test('levels derive from total XP', () {
      var level = computeStudyLevel(0);
      expect(level.level, 1);
      expect(level.xpIntoLevel, 0);
      expect(level.xpForNextLevel, 100);
      expect(level.xpRemaining, 100);
      expect(level.tier.name, 'Novice');

      // Mid-Novice, mid-level.
      level = computeStudyLevel(450);
      expect(level.level, 5);
      expect(level.xpIntoLevel, 50);
      expect(level.xpForNextLevel, 100);
      expect(level.xpRemaining, 50);

      // Novice -> Apprentice boundary.
      level = computeStudyLevel(500);
      expect(level.level, 6);
      expect(level.tier.name, 'Apprentice');
      expect(level.xpForNextLevel, 250);

      // Multi-tier jump lands on the exact threshold.
      level = computeStudyLevel(3200);
      expect(level.level, 16);
      expect(level.tier.name, 'Achiever');
      expect(level.xpIntoLevel, 200);
      expect(level.xpForNextLevel, 500);
      expect(level.xpRemaining, 300);
    });

    test('zero and negative XP sit at Level 1', () {
      for (final xp in [0, -5]) {
        final level = computeStudyLevel(xp);
        expect(level.level, 1);
        expect(level.totalXp, xp < 0 ? 0 : xp);
      }
    });

    test('tier boundaries map to the right band', () {
      expect(studyTierForLevel(1).name, 'Novice');
      expect(studyTierForLevel(5).name, 'Novice');
      expect(studyTierForLevel(6).name, 'Apprentice');
      expect(studyTierForLevel(15).name, 'Apprentice');
      expect(studyTierForLevel(16).name, 'Achiever');
      expect(studyTierForLevel(30).name, 'Achiever');
      expect(studyTierForLevel(31).name, 'Master');
      expect(studyTierForLevel(50).name, 'Master');
      expect(studyTierForLevel(51).name, 'Grandmaster');
      expect(studyTierForLevel(500).name, 'Grandmaster');
      expect(studyTiers, hasLength(5));
    });

    test('earliest day bounds history', () {
      final sessions = [
        ended('a', DateTime(2026, 10, 10, 9), DateTime(2026, 10, 10, 10)),
      ];
      expect(
        earliestStudyDay(sessions, DateTime(2026, 1, 1)),
        DateTime(2026, 10, 10),
      );
      expect(
        earliestStudyDay(const [], DateTime(2026, 1, 1)),
        DateTime(2026, 1, 1),
      );
    });
  });

  group('taskDayStats', () {
    StudyTask task(String id, bool done) => StudyTask(
      id: id,
      title: id,
      description: '',
      startMinutes: 540,
      endMinutes: 600,
      date: DateTime(2026, 10, 11),
      isDone: done,
    );

    test('counts scheduled, attended, missed and percentage', () {
      final stats = taskDayStats([
        task('a', true),
        task('b', true),
        task('c', false),
        task('d', false),
      ]);
      expect(stats.scheduled, 4);
      expect(stats.attended, 2);
      expect(stats.missed, 2);
      expect(stats.percentage, 50.0);
    });

    test('empty day yields null percentage (dash, no divide by zero)', () {
      final stats = taskDayStats(const []);
      expect(stats.scheduled, 0);
      expect(stats.percentage, isNull);
    });
  });
}
