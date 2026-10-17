import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:studyup/features/progress/data/study_day.dart';
import 'package:studyup/features/progress/data/study_session.dart';
import 'package:studyup/features/progress/presentation/study_progress_controller.dart';

void main() {
  group('StudyProgressState', () {
    test('starts with no progress and the default daily goal', () {
      const state = StudyProgressState(isLoaded: true);

      expect(state.sessions, isEmpty);
      expect(state.dailyStudyGoalMinutes, 480);
      expect(state.minutesForDate(DateTime(2026, 1, 2)), 0);
      expect(state.minutesForWeek(DateTime(2026, 1, 2)), 0);
      expect(state.minutesForMonth(DateTime(2026, 1)), 0);
    });

    test(
      'splits cross-midnight study time into the correct dates and weeks',
      () {
        final mondayNight = DateTime(2026, 1, 5, 23, 30);
        final tuesdayMorning = DateTime(2026, 1, 6, 1);
        final state = StudyProgressState(
          sessions: [
            StudySession(
              id: 'overnight',
              subjectId: 'math',
              subjectName: 'Math',
              checkInTime: mondayNight,
              checkOutTime: tuesdayMorning,
            ),
          ],
          isLoaded: true,
        );

        expect(state.minutesForDate(DateTime(2026, 1, 5)), 30);
        expect(state.minutesForDate(DateTime(2026, 1, 6)), 60);
        expect(state.minutesForWeek(DateTime(2026, 1, 5)), 90);
        expect(state.minutesForMonth(DateTime(2026, 1)), 90);
        expect(state.minutesForSubject('math'), 90);
        expect(state.minutesForSubjectInWeek('math', DateTime(2026, 1, 6)), 90);
        expect(state.dayPartMinutes(DateTime(2026, 1, 5)), [0, 0, 30, 0]);
        expect(state.dayPartMinutes(DateTime(2026, 1, 6)), [0, 0, 0, 60]);
      },
    );

    test('aggregates weekday and month-week chart data', () {
      final state = StudyProgressState(
        sessions: [
          StudySession(
            id: 'first',
            subjectId: 'math',
            subjectName: 'Math',
            checkInTime: DateTime(2026, 2, 2, 9),
            checkOutTime: DateTime(2026, 2, 2, 10),
          ),
          StudySession(
            id: 'last',
            subjectId: 'science',
            subjectName: 'Science',
            checkInTime: DateTime(2026, 2, 28, 13),
            checkOutTime: DateTime(2026, 2, 28, 14, 30),
          ),
        ],
        isLoaded: true,
      );

      expect(state.minutesByWeekday(DateTime(2026, 2, 2)), [
        60,
        0,
        0,
        0,
        0,
        0,
        0,
      ]);
      expect(state.minutesByMonthWeek(DateTime(2026, 2)), [60, 0, 0, 90]);
      expect(state.dayPartMinutes(DateTime(2026, 2, 2)), [60, 0, 0, 0]);
      expect(state.dayPartMinutes(DateTime(2026, 2, 28)), [0, 90, 0, 0]);
    });

    test('overnight session splits across midnight dates and periods', () {
      // Oct 5, 11:00 PM -> Oct 6, 2:00 AM = 3h total.
      final state = StudyProgressState(
        sessions: [
          StudySession(
            id: 'overnight',
            subjectId: 'math',
            subjectName: 'Math',
            checkInTime: DateTime(2026, 10, 5, 23),
            checkOutTime: DateTime(2026, 10, 6, 2),
          ),
        ],
        isLoaded: true,
      );

      expect(state.minutesForDate(DateTime(2026, 10, 5)), 60);
      expect(state.minutesForDate(DateTime(2026, 10, 6)), 120);
      expect(state.sessionCountForDate(DateTime(2026, 10, 5)), 1);
      expect(state.sessionCountForDate(DateTime(2026, 10, 6)), 1);
      // 11 PM belongs to Oct 5 evening; 12-2 AM belong to Oct 6 night.
      expect(state.dayPartMinutes(DateTime(2026, 10, 5)), [0, 0, 60, 0]);
      expect(state.dayPartMinutes(DateTime(2026, 10, 6)), [0, 0, 0, 120]);
    });

    test('month weeks average the capped Mon-Sun daily percentages', () {
      // Single 240-min session on Monday Feb 2 with a 480 goal.
      // Feb 2026 Mon-Sun weeks: Jan 26, Feb 2, 9, 16, 23.
      // Week Feb 2-8 = (50 + 0*6) / 7; all others 0.
      final state = StudyProgressState(
        sessions: [
          StudySession(
            id: 'only',
            subjectId: 'math',
            subjectName: 'Math',
            checkInTime: DateTime(2026, 2, 2, 9),
            checkOutTime: DateTime(2026, 2, 2, 13),
          ),
        ],
        isLoaded: true,
      );

      final averages = state.monthWeekAveragePercentages(DateTime(2026, 2, 15));
      expect(averages.length, 5);
      expect(averages[0], 0);
      expect(averages[1], closeTo(50 / 7, 0.001));
      expect(averages[2], 0);
      expect(averages[3], 0);
      expect(averages[4], 0);
    });

    test('weekly example averages to 32.14% for the Mon-Sun week', () {
      // Mon 4h = 50%, Tue 6h = 75%, Wed 8h = 100%, Thu-Sun 0%:
      // (50 + 75 + 100 + 0 + 0 + 0 + 0) / 7 = 32.142857... -> '32.14%'.
      final state = StudyProgressState(
        sessions: [
          StudySession(
            id: 'mon',
            subjectId: 'general',
            subjectName: 'Daily Study',
            checkInTime: DateTime(2026, 2, 2, 9),
            checkOutTime: DateTime(2026, 2, 2, 13),
          ),
          StudySession(
            id: 'tue',
            subjectId: 'general',
            subjectName: 'Daily Study',
            checkInTime: DateTime(2026, 2, 3, 9),
            checkOutTime: DateTime(2026, 2, 3, 15),
          ),
          StudySession(
            id: 'wed',
            subjectId: 'general',
            subjectName: 'Daily Study',
            checkInTime: DateTime(2026, 2, 4, 9),
            checkOutTime: DateTime(2026, 2, 4, 17),
          ),
        ],
        isLoaded: true,
      );

      expect(state.cappedDailyPercentage(DateTime(2026, 2, 2)), 50.0);
      expect(state.cappedDailyPercentage(DateTime(2026, 2, 3)), 75.0);
      expect(state.cappedDailyPercentage(DateTime(2026, 2, 4)), 100.0);
      final averages = state.monthWeekAveragePercentages(DateTime(2026, 2, 15));
      expect(averages[1], closeTo(225 / 7, 0.0001));
      expect(formatMonthlyPercentage(averages[1]), '32.14%');
    });

    test('overflow past the goal is preserved, not capped', () {
      // 600 of 480 = 125% recorded exactly in the stored minutes, while
      // the monthly average consumes the capped visual day (100 / 7).
      final state = StudyProgressState(
        sessions: [
          StudySession(
            id: 'long',
            subjectId: 'math',
            subjectName: 'Math',
            checkInTime: DateTime(2026, 3, 3, 8),
            checkOutTime: DateTime(2026, 3, 3, 18),
          ),
        ],
        dailyStudyGoalMinutes: 480,
        isLoaded: true,
      );

      expect(state.minutesForDate(DateTime(2026, 3, 3)), 600);
      final averages = state.monthWeekAveragePercentages(DateTime(2026, 3, 3));
      // March 2026 Mon-Sun weeks: Feb 23, Mar 2, 9, 16, 23, 30.
      // March 3 sits in week Mar 2-8: capped 100 / 7.
      expect(averages.length, 6);
      expect(averages[1], closeTo(100 / 7, 0.001));
    });

    test('goal reached only at/above the goal, never a cap', () {
      expect(isGoalReached(420, 480), isFalse); // 7h: not reached.
      expect(isGoalReached(480, 480), isTrue); // exactly 8h: reached.
      expect(isGoalReached(600, 480), isTrue); // 10h: still reached.
      expect(isGoalReached(0, 0), isFalse);
    });

    test('stopped 10h session keeps 10h as its actual duration', () {
      final ended = StudySession(
        id: 'ten',
        subjectId: 'math',
        subjectName: 'Math',
        checkInTime: DateTime(2026, 4, 1, 9),
        checkOutTime: DateTime(2026, 4, 1, 19),
        pausedSeconds: 36000,
        resumedAt: null,
      );
      expect(ended.durationAt(DateTime(2026, 4, 2)).inHours, 10);
    });

    test('afternoon-evening boundary splits 5:30 PM - 6:30 PM', () {
      final state = StudyProgressState(
        sessions: [
          StudySession(
            id: 'boundary',
            subjectId: 'math',
            subjectName: 'Math',
            checkInTime: DateTime(2026, 4, 2, 17, 30),
            checkOutTime: DateTime(2026, 4, 2, 18, 30),
          ),
        ],
        isLoaded: true,
      );

      expect(state.dayPartMinutes(DateTime(2026, 4, 2)), [0, 30, 30, 0]);
    });

    test('night-morning boundary splits 5:30 AM - 6:30 AM', () {
      final state = StudyProgressState(
        sessions: [
          StudySession(
            id: 'boundary',
            subjectId: 'math',
            subjectName: 'Math',
            checkInTime: DateTime(2026, 4, 2, 5, 30),
            checkOutTime: DateTime(2026, 4, 2, 6, 30),
          ),
        ],
        isLoaded: true,
      );

      // [morning, afternoon, evening, night]: 30 + 30.
      expect(state.dayPartMinutes(DateTime(2026, 4, 2)), [30, 0, 0, 30]);
    });
  });

  group('StudyProgressController persistence', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test(
      'restores an active session and daily goal across controllers',
      () async {
        final firstController = StudyProgressController();
        await _waitForLoad(firstController);
        await firstController.startSession(
          checkInTime: DateTime(2026, 2, 1, 10),
        );
        await firstController.setDailyStudyGoalMinutes(75);
        firstController.dispose();

        final restoredController = StudyProgressController();
        await _waitForLoad(restoredController);

        expect(restoredController.state.activeSession, isNotNull);
        expect(
          restoredController.state.activeSession!.subjectId,
          dailyStudySubjectId,
        );
        expect(restoredController.state.dailyStudyGoalMinutes, 75);
        expect(
          restoredController.state.activeSession!
              .durationAt(DateTime(2026, 2, 1, 10, 0, 3))
              .inSeconds,
          3,
        );
        await expectLater(restoredController.startSession(), throwsStateError);

        await restoredController.endSession(
          checkOutTime: DateTime(2026, 2, 1, 11),
        );
        expect(restoredController.state.activeSession, isNull);
        expect(
          restoredController.state.minutesForDate(DateTime(2026, 2, 1)),
          60,
        );
        restoredController.dispose();
      },
    );

    test('pause freezes elapsed and resume continues exactly', () async {
      final controller = StudyProgressController();
      await _waitForLoad(controller);
      final t0 = DateTime(2026, 3, 1, 10, 0, 0);
      await controller.startSession(checkInTime: t0);
      // 3 seconds in, pause: elapsed banks at exactly 3.
      await controller.pauseSession(at: t0.add(const Duration(seconds: 3)));
      var active = controller.state.activeSession!;
      expect(active.isPaused, isTrue);
      expect(active.pausedSeconds, 3);
      expect(
        active.durationAt(t0.add(const Duration(seconds: 100))).inSeconds,
        3,
      );
      await expectLater(
        controller.pauseSession(at: t0.add(const Duration(seconds: 4))),
        throwsStateError,
      );

      // Resume 10 wall-seconds later: timer continues 3 -> 4 -> 5.
      await controller.resumeSession(at: t0.add(const Duration(seconds: 13)));
      active = controller.state.activeSession!;
      expect(active.isRunning, isTrue);
      expect(active.pausedSeconds, 3);
      expect(
        active.durationAt(t0.add(const Duration(seconds: 14))).inSeconds,
        4,
      );
      await expectLater(controller.resumeSession(), throwsStateError);

      // Pause survives reload with banked seconds intact.
      controller.dispose();
      final restored = StudyProgressController();
      await _waitForLoad(restored);
      final resumed = restored.state.activeSession!;
      expect(resumed.isRunning, isTrue);
      expect(resumed.pausedSeconds, 3);
      expect(
        restored.state.minutesForDate(
          t0,
          now: t0.add(const Duration(seconds: 14)),
        ),
        0,
      );
      expect(
        resumed.durationAt(t0.add(const Duration(seconds: 14))).inSeconds,
        4,
      );

      // End banks the final total without resetting history.
      await restored.endSession(
        checkOutTime: t0.add(const Duration(seconds: 15)),
      );
      expect(restored.state.activeSession, isNull);
      expect(restored.state.sessions.single.pausedSeconds, 5);
      restored.dispose();
    });

    test('a restarted daily timer begins at zero', () async {
      final controller = StudyProgressController();
      await _waitForLoad(controller);
      final t0 = DateTime(2026, 4, 1, 10, 0, 0);
      await controller.startSession(checkInTime: t0);
      await controller.endSession(
        checkOutTime: t0.add(const Duration(seconds: 11)),
      );
      final t1 = t0.add(const Duration(seconds: 12));
      await controller.startSession(checkInTime: t1);
      var active = controller.state.activeSession!;
      expect(active.carriedSeconds, 0);
      expect(active.durationAt(t1).inSeconds, 0);
      expect(
        active.durationAt(t1.add(const Duration(seconds: 1))).inSeconds,
        1,
      );
      await controller.endSession(
        checkOutTime: t1.add(const Duration(seconds: 2)),
      );
      final totalSeconds = controller.state.sessions.fold(
        0,
        (sum, s) =>
            sum + s.durationAt(t1.add(const Duration(seconds: 2))).inSeconds,
      );
      expect(totalSeconds, 11 + 2);
      await controller.startSession(
        checkInTime: t1.add(const Duration(seconds: 3)),
      );
      active = controller.state.activeSession!;
      expect(active.carriedSeconds, 0);
      expect(
        active.durationAt(t1.add(const Duration(seconds: 3))).inSeconds,
        0,
      );
      controller.dispose();
    });

    test(
      'daily sessions add into the one daily goal without double counting',
      () async {
        final controller = StudyProgressController();
        await _waitForLoad(controller);
        final start = DateTime(2026, 4, 2, 8);

        await controller.startSession(checkInTime: start);
        await controller.endSession(
          checkOutTime: start.add(const Duration(minutes: 30)),
        );
        expect(
          controller.state.minutesForDate(
            start,
            now: start.add(const Duration(minutes: 30)),
          ),
          30,
        );
        expect(
          formatAchievement(30, controller.state.dailyStudyGoalMinutes),
          '6%',
        );

        final secondStart = start.add(const Duration(minutes: 30));
        await controller.startSession(checkInTime: secondStart);
        expect(controller.state.activeSession!.subjectId, dailyStudySubjectId);
        expect(
          controller.state.activeSession!.durationAt(secondStart).inMinutes,
          0,
        );
        await controller.endSession(
          checkOutTime: secondStart.add(const Duration(minutes: 20)),
        );
        final afterSecond = secondStart.add(const Duration(minutes: 20));
        expect(controller.state.minutesForDate(start, now: afterSecond), 50);
        expect(
          formatAchievement(50, controller.state.dailyStudyGoalMinutes),
          '10%',
        );

        final thirdStart = secondStart.add(const Duration(minutes: 20));
        await controller.startSession(checkInTime: thirdStart);
        expect(
          controller.state.activeSession!.durationAt(thirdStart),
          Duration.zero,
        );
        await controller.endSession(
          checkOutTime: thirdStart.add(const Duration(minutes: 15)),
        );

        final finalTime = thirdStart.add(const Duration(minutes: 15));
        final finalState = controller.state;
        expect(finalState.sessions, hasLength(3));
        expect(finalState.dailyStudyGoalMinutes, 480);
        expect(finalState.minutesForDate(start, now: finalTime), 65);
        expect(
          formatAchievement(
            finalState.minutesForDate(start, now: finalTime),
            finalState.dailyStudyGoalMinutes,
          ),
          '14%',
        );
        controller.dispose();
      },
    );

    test('daily sessions keep accruing past 100% without stopping', () async {
      final controller = StudyProgressController();
      await _waitForLoad(controller);
      final start = DateTime(2026, 4, 3, 8);
      await controller.startSession(checkInTime: start);
      await controller.endSession(
        checkOutTime: start.add(const Duration(hours: 1)),
      );

      final secondStart = start.add(const Duration(hours: 1));
      await controller.startSession(checkInTime: secondStart);
      expect(controller.state.activeSession!.subjectId, dailyStudySubjectId);
      final goalReachedAt = start.add(const Duration(hours: 8));
      expect(controller.state.activeSession!.isActive, isTrue);
      expect(controller.state.minutesForDate(start, now: goalReachedAt), 480);
      expect(
        formatAchievement(480, controller.state.dailyStudyGoalMinutes),
        '100%',
      );
      await controller.endSession(
        checkOutTime: start.add(const Duration(hours: 9)),
      );
      final state = controller.state;
      expect(state.dailyStudyGoalMinutes, 480);
      expect(
        state.minutesForDate(start, now: start.add(const Duration(hours: 9))),
        540,
      );
      expect(
        state.minutesForSubject(
          dailyStudySubjectId,
          now: start.add(const Duration(hours: 9)),
        ),
        540,
      );
      expect(
        formatAchievement(
          state.minutesForDate(start, now: start.add(const Duration(hours: 9))),
          state.dailyStudyGoalMinutes,
        ),
        '113%',
      );
      controller.dispose();
    });

    test(
      'stale paused session is finalized at midnight, history kept',
      () async {
        final controller = StudyProgressController();
        await _waitForLoad(controller);
        // Monday 1:00 AM start, paused at 2:00 AM with 1h banked.
        final checkIn = DateTime(2026, 3, 2, 1);
        await controller.startSession(checkInTime: checkIn);
        await controller.pauseSession(at: DateTime(2026, 3, 2, 2));
        expect(controller.state.activeSession!.isPaused, isTrue);
        // Starting Tuesday 6 AM finalizes the stale row at its 2:00 AM
        // pause moment (midnight passed; 1h stays saved), then starts fresh.
        await controller.startSession(checkInTime: DateTime(2026, 3, 3, 6));
        expect(controller.state.sessions.length, 2);
        final ended = controller.state.sessions.first;
        expect(ended.checkOutTime, DateTime(2026, 3, 2, 2));
        expect(controller.state.minutesForDate(DateTime(2026, 3, 2)), 60);
        expect(controller.state.activeSession, isNotNull);
        controller.dispose();

        // Reopening later also finds no stale resumable session: a resume
        // attempt fails instead of reviving yesterday's pause.
        final reopened = StudyProgressController();
        await _waitForLoad(reopened);
        await reopened.endSession(checkOutTime: DateTime(2026, 3, 3, 7));
        await expectLater(reopened.resumeSession(), throwsStateError);
        reopened.dispose();
      },
    );

    test('running session crossing midnight is never touched', () async {
      final controller = StudyProgressController();
      await _waitForLoad(controller);
      await controller.startSession(checkInTime: DateTime(2026, 3, 2, 23));
      controller.dispose();

      final reopened = StudyProgressController();
      await _waitForLoad(reopened);
      expect(reopened.state.activeSession!.isRunning, isTrue);
      // Starting another session still refuses: the running one is intact.
      await expectLater(
        reopened.startSession(checkInTime: DateTime(2026, 3, 3, 6)),
        throwsStateError,
      );
      await reopened.endSession(checkOutTime: DateTime(2026, 3, 3, 7));
      expect(reopened.state.minutesForDate(DateTime(2026, 3, 2)), 60);
      expect(reopened.state.minutesForDate(DateTime(2026, 3, 3)), 420);
      reopened.dispose();
    });

    test('same-day paused session stays resumable', () async {
      final controller = StudyProgressController();
      await _waitForLoad(controller);
      final t0 = DateTime(2026, 3, 4, 10);
      await controller.startSession(checkInTime: t0);
      await controller.pauseSession(at: t0.add(const Duration(minutes: 30)));
      await controller.resumeSession(at: t0.add(const Duration(minutes: 45)));
      expect(controller.state.activeSession!.isRunning, isTrue);
      expect(controller.state.activeSession!.pausedSeconds, 1800);
      expect(
        controller.state.minutesForDate(
          t0,
          now: t0.add(const Duration(minutes: 75)),
        ),
        60,
      );
      controller.dispose();
    });

    test(
      'starting while paused on the same day is rejected, pause kept',
      () async {
        final controller = StudyProgressController();
        await _waitForLoad(controller);
        final dayStart = DateTime(2026, 4, 4, 8);
        final pausedAt = dayStart.add(const Duration(minutes: 30));
        await controller.startSession(checkInTime: dayStart);
        await controller.pauseSession(at: pausedAt);

        await expectLater(
          controller.startSession(
            checkInTime: pausedAt.add(const Duration(minutes: 10)),
          ),
          throwsStateError,
        );

        expect(controller.state.sessions, hasLength(1));
        expect(controller.state.activeSession!.isPaused, isTrue);
        expect(
          controller.state.minutesForDate(
            dayStart,
            now: pausedAt.add(const Duration(minutes: 10)),
          ),
          30,
        );
        await controller.resumeSession(
          at: pausedAt.add(const Duration(minutes: 10)),
        );
        await controller.endSession(
          checkOutTime: pausedAt.add(const Duration(minutes: 30)),
        );
        expect(
          controller.state.minutesForDate(
            dayStart,
            now: pausedAt.add(const Duration(minutes: 30)),
          ),
          50,
        );
        controller.dispose();
      },
    );

    test('goal change persists and applies to new calculations', () async {
      final controller = StudyProgressController();
      await _waitForLoad(controller);
      await controller.setDailyStudyGoalMinutes(360);
      expect(controller.state.dailyStudyGoalMinutes, 360);
      controller.dispose();

      final restored = StudyProgressController();
      await _waitForLoad(restored);
      expect(restored.state.dailyStudyGoalMinutes, 360);
      restored.dispose();
    });
  });
}

Future<void> _waitForLoad(StudyProgressController controller) async {
  for (var attempt = 0; attempt < 20 && !controller.state.isLoaded; attempt++) {
    await Future<void>.delayed(const Duration(milliseconds: 1));
  }
  expect(controller.state.isLoaded, isTrue);
  expect(controller.state.error, isNull);
}
