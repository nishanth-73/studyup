import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:studyup/core/notifications/notification_prefs.dart';
import 'package:studyup/core/notifications/notification_service.dart';

void main() {
  test('notification initialization is safe and idempotent', () async {
    SharedPreferences.setMockInitialValues({});
    final service = NotificationService.instance;

    await expectLater(service.init(), completes);
    await expectLater(service.init(), completes);
  });

  group('NotifRules.taskReminderFireTime', () {
    test('fires five minutes before the task starts', () {
      final fire = NotifRules.taskReminderFireTime(
        date: DateTime(2026, 10, 12),
        startMinutes: 16 * 60,
        now: DateTime(2026, 10, 12, 8),
      );
      expect(fire, DateTime(2026, 10, 12, 15, 55));
    });

    test('returns null for tasks scheduled in the past', () {
      expect(
        NotifRules.taskReminderFireTime(
          date: DateTime(2026, 10, 12),
          startMinutes: 9 * 60,
          now: DateTime(2026, 10, 12, 12),
        ),
        isNull,
      );
    });

    test('returns null when the fire time is now or past', () {
      // Task at 4:00 PM, now 3:55 PM -> fire time is now, stale.
      expect(
        NotifRules.taskReminderFireTime(
          date: DateTime(2026, 10, 12),
          startMinutes: 16 * 60,
          now: DateTime(2026, 10, 12, 15, 55),
        ),
        isNull,
      );
    });
  });

  group('NotifRules.taskReminderId', () {
    test('is deterministic and positive', () {
      final a = NotifRules.taskReminderId('task-1');
      expect(a, NotifRules.taskReminderId('task-1'));
      expect(a, greaterThanOrEqualTo(0));
      expect(a, lessThan(1 << 31));
    });

    test('saving twice reuses the id (no duplicates)', () {
      expect(
        NotifRules.taskReminderId('u123'),
        NotifRules.taskReminderId('u123'),
      );
    });

    test('distinct tasks get distinct ids', () {
      expect(
        NotifRules.taskReminderId('starter-study'),
        isNot(NotifRules.taskReminderId('starter-eat')),
      );
    });
  });

  test('task reminder body names the actual task', () {
    expect(NotifRules.taskReminderBody('Study'), 'Study starts in 5 minutes.');
  });

  group('NotifRules.shouldNotifyGoal', () {
    test('notifies once when the threshold is first crossed', () {
      expect(
        NotifRules.shouldNotifyGoal(
          minutesToday: 480,
          goalMinutes: 480,
          notifiedDateKey: '',
          todayKey: '2026-10-12',
        ),
        isTrue,
      );
    });

    test('stays silent below the goal', () {
      expect(
        NotifRules.shouldNotifyGoal(
          minutesToday: 479,
          goalMinutes: 480,
          notifiedDateKey: '',
          todayKey: '2026-10-12',
        ),
        isFalse,
      );
    });

    test('never repeats for the same local day', () {
      expect(
        NotifRules.shouldNotifyGoal(
          minutesToday: 600,
          goalMinutes: 480,
          notifiedDateKey: '2026-10-12',
          todayKey: '2026-10-12',
        ),
        isFalse,
      );
    });

    test('notifies again on a new local day', () {
      expect(
        NotifRules.shouldNotifyGoal(
          minutesToday: 500,
          goalMinutes: 480,
          notifiedDateKey: '2026-10-11',
          todayKey: '2026-10-12',
        ),
        isTrue,
      );
    });

    test('never notifies for a non-positive goal', () {
      expect(
        NotifRules.shouldNotifyGoal(
          minutesToday: 100,
          goalMinutes: 0,
          notifiedDateKey: '',
          todayKey: '2026-10-12',
        ),
        isFalse,
      );
    });
  });

  test('session start time formats in local 12-hour clock', () {
    expect(
      NotificationService.formatStartTime(DateTime(2026, 10, 12, 16, 0)),
      '4:00 PM',
    );
    expect(
      NotificationService.formatStartTime(DateTime(2026, 10, 12, 0, 5)),
      '12:05 AM',
    );
  });

  group('notification preferences', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('all three types default to enabled for new users', () async {
      final controller = NotificationPrefsController();
      for (var i = 0; i < 100 && !controller.state.loaded; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      expect(controller.state.loaded, isTrue);
      expect(controller.state.taskReminders, isTrue);
      expect(controller.state.sessionStarted, isTrue);
      expect(controller.state.liveProgress, isTrue);
      expect(controller.state.goalReached, isTrue);
      controller.dispose();
    });

    test('switches persist and reload', () async {
      final controller = NotificationPrefsController();
      for (var i = 0; i < 100 && !controller.state.loaded; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      await controller.setTaskReminders(false);
      await controller.setLiveProgress(false);
      await controller.setGoalReached(false);
      controller.dispose();

      final reloaded = NotificationPrefsController();
      for (var i = 0; i < 100 && !reloaded.state.loaded; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      expect(reloaded.state.taskReminders, isFalse);
      expect(reloaded.state.sessionStarted, isTrue);
      expect(reloaded.state.liveProgress, isFalse);
      expect(reloaded.state.goalReached, isFalse);
      reloaded.dispose();
    });
  });
}
