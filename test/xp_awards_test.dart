import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:studyup/features/progress/data/study_gamification.dart';
import 'package:studyup/features/progress/data/study_session.dart';
import 'package:studyup/features/progress/presentation/study_progress_controller.dart';

void main() {
  group('XP awards (pure syncXpAwards)', () {
    int minutesFor(Map<String, int> byDay, DateTime day) =>
        byDay[xpDayKey(day)] ?? 0;

    int weekTotal(Map<String, int> byDay, DateTime monday) {
      var total = 0;
      for (var i = 0; i < 7; i++) {
        total += minutesFor(byDay, monday.add(Duration(days: i)));
      }
      return total;
    }

    XpLedger sync(
      Map<String, int> byDay, {
      required XpLedger ledger,
      required DateTime now,
      DateTime? earliest,
      int goal = 480,
      bool full = false,
    }) => syncXpAwards(
      ledger: ledger,
      dailyGoalMinutes: goal,
      now: now,
      minutesForDay: (day) => minutesFor(byDay, day),
      minutesForWeek: (monday) => weekTotal(byDay, monday),
      earliestDay: earliest ?? DateTime(2026, 10, 12),
      full: full,
    );

    test('a goal-met day earns 10 XP exactly once', () {
      final now = DateTime(2026, 10, 17, 14);
      final byDay = {'2026-10-17': 480};
      final first = sync(
        byDay,
        ledger: const XpLedger(),
        now: now,
        full: true,
      );
      expect(first.totalXp, 10);
      expect(first.awardedDays, {'2026-10-17'});
      expect(first.awardedWeeks, isEmpty);

      // Re-evaluating the same history never duplicates the award.
      final again = sync(byDay, ledger: first, now: now, full: true);
      expect(identical(again, first), isTrue);
    });

    test('a missed day awards nothing and keeps earned XP', () {
      const ledger = XpLedger(awardedDays: {'2026-10-16'});
      final now = DateTime(2026, 10, 17, 14);
      final result = sync(
        {'2026-10-17': 479},
        ledger: ledger,
        now: now,
        full: true,
      );
      expect(identical(result, ledger), isTrue);
      expect(result.totalXp, 10);
    });

    test('minutes growing later still award the day (no award removed)', () {
      final now = DateTime(2026, 10, 17, 14);
      final ledger = const XpLedger();
      final morning = sync(
        {'2026-10-17': 100},
        ledger: ledger,
        now: now,
        full: false,
      );
      expect(identical(morning, ledger), isTrue);

      final evening = sync(
        {'2026-10-17': 480},
        ledger: morning,
        now: now,
        full: false,
      );
      expect(evening.totalXp, 10);
      expect(evening.awardedDays, {'2026-10-17'});
    });

    test('partial sync only evaluates today and the current week', () {
      // A full previous week (Oct 5–11) plus a full current week.
      final byDay = <String, int>{
        for (var i = 0; i < 7; i++)
          xpDayKey(DateTime(2026, 10, 5).add(Duration(days: i))): 480,
        for (var i = 0; i < 7; i++)
          xpDayKey(DateTime(2026, 10, 12).add(Duration(days: i))): 480,
      };
      final now = DateTime(2026, 10, 17, 14);

      final partial = sync(byDay, ledger: const XpLedger(), now: now);
      expect(partial.totalXp, 60); // today 10 + current-week bonus 50
      expect(partial.awardedDays, {'2026-10-17'});

      // Full rescan backfills the whole history exactly once.
      final full = sync(
        byDay,
        ledger: partial,
        now: now,
        earliest: DateTime(2026, 10, 5),
        full: true,
      );
      expect(full.awardedDays, hasLength(13)); // Oct 5 .. Oct 17
      expect(full.awardedWeeks, {'2026-10-05', '2026-10-12'});
      expect(full.totalXp, 13 * 10 + 2 * 50);
    });

    test('weekly bonus needs the full 7x goal and lands once per week', () {
      // 6 x 479 + 486 = 3,360 = exactly 7 x 480; only Sunday meets the day.
      final byDay = <String, int>{
        for (var i = 0; i < 6; i++)
          xpDayKey(DateTime(2026, 10, 12).add(Duration(days: i))): 479,
        '2026-10-18': 486,
      };
      final sunday = DateTime(2026, 10, 18, 20);
      final result = sync(byDay, ledger: const XpLedger(), now: sunday);
      expect(result.awardedWeeks, {'2026-10-12'});
      expect(result.awardedDays, {'2026-10-18'});
      expect(result.totalXp, 60);

      // One minute short of the weekly goal: no bonus and no day award
      // (every day stays below the 480-minute daily goal too).
      final short = sync({
        ...byDay,
        '2026-10-18': 479,
      }, ledger: const XpLedger(), now: sunday);
      expect(short.awardedWeeks, isEmpty);
      expect(short.awardedDays, isEmpty);
      expect(short.totalXp, 0);
    });

    test('a new week starts fresh; awards from last week are kept', () {
      final byDay = <String, int>{
        for (var i = 0; i < 7; i++)
          xpDayKey(DateTime(2026, 10, 12).add(Duration(days: i))): 480,
      };
      final sunday = DateTime(2026, 10, 18, 22);
      final weekOne = sync(byDay, ledger: const XpLedger(), now: sunday);
      expect(weekOne.awardedWeeks, {'2026-10-12'});

      // Monday: the new week has no minutes yet, awards stay untouched.
      final monday = sync(
        byDay,
        ledger: weekOne,
        now: DateTime(2026, 10, 19, 8),
      );
      expect(identical(monday, weekOne), isTrue);
      expect(monday.awardedWeeks, {'2026-10-12'});
    });

    test('zero or negative goal is inert', () {
      final byDay = {'2026-10-17': 5000};
      final result = sync(
        byDay,
        ledger: const XpLedger(),
        now: DateTime(2026, 10, 17),
        goal: 0,
        full: true,
      );
      expect(result.totalXp, 0);
    });

    test('week keys follow the Monday convention', () {
      expect(xpWeekStart(DateTime(2026, 10, 19)), DateTime(2026, 10, 19));
      expect(xpWeekStart(DateTime(2026, 10, 25)), DateTime(2026, 10, 19));
      expect(xpWeekStart(DateTime(2026, 10, 26)), DateTime(2026, 10, 26));
    });

    test('ledger JSON round-trips and tolerates missing keys', () {
      expect(XpLedger.fromJson(const {}).totalXp, 0);
      const ledger = XpLedger(
        awardedDays: {'2026-10-17'},
        awardedWeeks: {'2026-10-12'},
      );
      final restored = XpLedger.fromJson(ledger.toJson());
      expect(restored.awardedDays, ledger.awardedDays);
      expect(restored.awardedWeeks, ledger.awardedWeeks);
      expect(restored.totalXp, 60);
    });
  });

  group('StudyProgressController XP persistence', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    final seedStart = DateTime(2026, 9, 14, 10);

    /// Fully ended session stored exactly as the app persists it, so the
    /// controller recomputes XP from real history (no live timer race).
    Map<String, Object?> storedSession(DateTime start, int minutes) =>
        StudySession(
          id: 'seed',
          subjectId: dailyStudySubjectId,
          subjectName: dailyStudySubjectName,
          checkInTime: start,
          checkOutTime: start.add(Duration(minutes: minutes)),
          pausedSeconds: minutes * 60,
          studySegments: [
            StudyTimeSegment(
              startTime: start,
              endTime: start.add(Duration(minutes: minutes)),
            ),
          ],
        ).toJson();

    void seedSessions(int minutes) {
      SharedPreferences.setMockInitialValues({
        'studyup.studySessions.v1': jsonEncode([storedSession(seedStart, minutes)]),
      });
    }

    Future<void> waitFor(bool Function() condition) async {
      for (var attempt = 0; attempt < 400 && !condition(); attempt++) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      expect(condition(), isTrue);
    }

    Future<void> waitForLoad(StudyProgressController controller) async {
      await waitFor(() => controller.state.isLoaded);
      expect(controller.state.error, isNull);
    }

    test('goal-met day persists 10 XP and is never double-awarded', () async {
      seedSessions(480);

      final first = StudyProgressController();
      await waitForLoad(first);
      await waitFor(() => first.state.xp.totalXp == 10);
      expect(first.state.xp.awardedDays, {'2026-09-14'});
      expect(first.state.xp.awardedWeeks, isEmpty);
      first.dispose();

      final second = StudyProgressController();
      await waitForLoad(second);
      await waitFor(() => second.state.xp.totalXp == 10);
      await Future<void>.delayed(const Duration(milliseconds: 80));
      expect(second.state.xp.totalXp, 10);
      expect(second.state.xp.awardedDays, hasLength(1));
      second.dispose();
    });

    test('lowering the goal backfills past days once', () async {
      seedSessions(300);

      final controller = StudyProgressController();
      await waitForLoad(controller);
      await Future<void>.delayed(const Duration(milliseconds: 80));
      expect(controller.state.xp.totalXp, 0);

      await controller.setDailyStudyGoalMinutes(240);
      await waitFor(() => controller.state.xp.totalXp == 10);

      // Raising it back never removes an award.
      await controller.setDailyStudyGoalMinutes(480);
      await Future<void>.delayed(const Duration(milliseconds: 80));
      expect(controller.state.xp.totalXp, 10);
      controller.dispose();

      final restarted = StudyProgressController();
      await waitForLoad(restarted);
      await waitFor(() => restarted.state.xp.totalXp == 10);
      restarted.dispose();
    });

    test('a corrupt ledger rebuilds from real history', () async {
      SharedPreferences.setMockInitialValues({
        'studyup.studySessions.v1': jsonEncode([storedSession(seedStart, 480)]),
        'studyup.xpLedger.v1': 'not-json',
      });

      final controller = StudyProgressController();
      await waitForLoad(controller);
      await waitFor(() => controller.state.xp.totalXp == 10);
      expect(controller.state.xp.awardedDays, {'2026-09-14'});
      controller.dispose();
    });
  });
}
