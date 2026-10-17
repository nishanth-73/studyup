import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:studyup/features/progress/data/analytics_models.dart';
import 'package:studyup/features/progress/data/study_day.dart';
import 'package:studyup/features/progress/data/study_session.dart';
import 'package:studyup/features/progress/presentation/study_progress_controller.dart';

StudySession _session(String id, DateTime start, DateTime end) => StudySession(
  id: id,
  subjectId: 'general',
  subjectName: 'Daily Study',
  checkInTime: start,
  checkOutTime: end,
);

StudyProgressState _state(List<StudySession> sessions) => StudyProgressState(
  sessions: sessions,
  dailyStudyGoalMinutes: 480,
  isLoaded: true,
);

void main() {
  group('Midnight session splitting (single source of truth)', () {
    test('1: 11 PM - 1 AM gives exactly 1h to each date', () {
      final state = _state([
        _session('s', DateTime(2026, 10, 10, 23), DateTime(2026, 10, 11, 1)),
      ]);
      expect(state.minutesForDate(DateTime(2026, 10, 10)), 60);
      expect(state.minutesForDate(DateTime(2026, 10, 11)), 60);
      // Evening on the first date, Night on the next.
      expect(state.dayPartMinutes(DateTime(2026, 10, 10)), [0, 0, 60, 0]);
      expect(state.dayPartMinutes(DateTime(2026, 10, 11)), [0, 0, 0, 60]);
      // No double counting: week sees 120 total.
      expect(state.minutesForWeek(DateTime(2026, 10, 10)), 120);
    });

    test('2: 5:30 AM - 6:30 AM splits Night / Morning', () {
      final state = _state([
        _session('s', DateTime(2026, 4, 2, 5, 30), DateTime(2026, 4, 2, 6, 30)),
      ]);
      // Index order is [morning, afternoon, evening, night].
      expect(state.dayPartMinutes(DateTime(2026, 4, 2)), [30, 0, 0, 30]);
    });

    test('3: 11:30 AM - 12:30 PM splits Morning / Afternoon', () {
      final parts = splitMinutesByPeriod(
        DateTime(2026, 4, 2, 11, 30),
        DateTime(2026, 4, 2, 12, 30),
      );
      expect(parts, [30, 30, 0, 0]);
    });

    test('4: 5:30 PM - 6:30 PM splits Afternoon / Evening', () {
      final state = _state([
        _session(
          's',
          DateTime(2026, 4, 2, 17, 30),
          DateTime(2026, 4, 2, 18, 30),
        ),
      ]);
      expect(state.dayPartMinutes(DateTime(2026, 4, 2)), [0, 30, 30, 0]);
    });

    test('5: sessions exactly at midnight lose and duplicate nothing', () {
      final state = _state([
        _session('a', DateTime(2026, 10, 10, 23), DateTime(2026, 10, 11)),
        _session('b', DateTime(2026, 10, 11), DateTime(2026, 10, 11, 1)),
        _session('zero', DateTime(2026, 10, 11), DateTime(2026, 10, 11)),
      ]);
      expect(state.minutesForDate(DateTime(2026, 10, 10)), 60);
      expect(state.minutesForDate(DateTime(2026, 10, 11)), 60);
      expect(state.minutesForWeek(DateTime(2026, 10, 10)), 120);
      // Boundary seconds belong to exactly one side.
      expect(
        _session(
          'x',
          DateTime(2026, 10, 10, 23, 59, 30),
          DateTime(2026, 10, 11),
        ).secondsInRange(
          DateTime(2026, 10, 11),
          DateTime(2026, 10, 12),
          DateTime(2026, 10, 12),
        ),
        0,
      );
    });

    test('6: multi-midnight session attributes every date', () {
      final state = _state([
        _session('s', DateTime(2026, 10, 10, 22), DateTime(2026, 10, 12, 2)),
      ]);
      expect(state.minutesForDate(DateTime(2026, 10, 10)), 120);
      expect(state.minutesForDate(DateTime(2026, 10, 11)), 1440);
      expect(state.minutesForDate(DateTime(2026, 10, 12)), 120);
      expect(
        state.minutesForDate(DateTime(2026, 10, 10)) +
            state.minutesForDate(DateTime(2026, 10, 11)) +
            state.minutesForDate(DateTime(2026, 10, 12)),
        1680,
      );
    });

    test('month boundary splits into the actual months', () {
      final state = _state([
        _session('s', DateTime(2026, 10, 31, 23), DateTime(2026, 11, 1, 1)),
      ]);
      expect(state.minutesForDate(DateTime(2026, 10, 31)), 60);
      expect(state.minutesForDate(DateTime(2026, 11, 1)), 60);
      expect(state.minutesForMonth(DateTime(2026, 10, 15)), 60);
      expect(state.minutesForMonth(DateTime(2026, 11, 15)), 60);
    });

    test(
      '7: running session across midnight keeps accruing, never stops',
      () async {
        SharedPreferences.setMockInitialValues({});
        final controller = StudyProgressController();
        for (var i = 0; i < 50 && !controller.state.isLoaded; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 2));
        }
        await controller.startSession(checkInTime: DateTime(2026, 10, 10, 23));
        final tick = DateTime(2026, 10, 11, 1);
        expect(controller.state.activeSession, isNotNull);
        expect(controller.state.activeSession!.isRunning, isTrue);
        expect(
          controller.state.minutesForDate(DateTime(2026, 10, 10), now: tick),
          60,
        );
        expect(
          controller.state.minutesForDate(DateTime(2026, 10, 11), now: tick),
          60,
        );
        await controller.endSession(checkOutTime: tick);
        expect(controller.state.minutesForDate(DateTime(2026, 10, 10)), 60);
        expect(controller.state.minutesForDate(DateTime(2026, 10, 11)), 60);
        controller.dispose();
      },
    );

    test('midnight refresh: new date starts at zero, history intact', () {
      final state = _state([
        _session('s', DateTime(2026, 10, 10, 23), DateTime(2026, 10, 11, 1)),
      ]);
      // "Today" Oct 10 sees its hour; "today" Oct 11 sees its own hour
      // from the same records — nothing deleted, goal untouched.
      expect(state.minutesForDate(DateTime(2026, 10, 10)), 60);
      expect(state.minutesForDate(DateTime(2026, 10, 11)), 60);
      expect(state.minutesForDate(DateTime(2026, 10, 12)), 0);
      expect(state.sessions, hasLength(1));
      expect(state.dailyStudyGoalMinutes, 480);
    });
  });

  group('Period classification', () {
    test('boundaries are exact and mutually exclusive', () {
      // [00:00, 06:00) night.
      expect(timePeriodForHour(0), TimePeriod.night);
      expect(timePeriodForHour(5), TimePeriod.night);
      // [06:00, 12:00) morning.
      expect(timePeriodForHour(6), TimePeriod.morning);
      expect(timePeriodForHour(11), TimePeriod.morning);
      // [12:00, 18:00) afternoon.
      expect(timePeriodForHour(12), TimePeriod.afternoon);
      expect(timePeriodForHour(17), TimePeriod.afternoon);
      // [18:00, 24:00) evening.
      expect(timePeriodForHour(18), TimePeriod.evening);
      expect(timePeriodForHour(23), TimePeriod.evening);
    });

    test('second-accurate splits lose nothing to truncation', () {
      // 5:30:30 -> 6:30:30 = 1770s night + 1830s morning.
      final parts = splitMinutesByPeriod(
        DateTime(2026, 4, 2, 5, 30, 30),
        DateTime(2026, 4, 2, 6, 30, 30),
      );
      expect(parts[2], 0);
      expect(parts[3], 29);
      expect(parts[0], 30);
      expect(parts[1], 0);
    });

    test('midnight study-day helpers use calendar dates', () {
      expect(studyDayFor(DateTime(2026, 10, 11)), DateTime(2026, 10, 11));
      final range = studyDayRange(DateTime(2026, 10, 11));
      expect(range.start, DateTime(2026, 10, 11));
      expect(range.end, DateTime(2026, 10, 12));
      expect(
        nextStudyResetAt(DateTime(2026, 10, 11, 15, 30)),
        DateTime(2026, 10, 12),
      );
    });
  });
}
