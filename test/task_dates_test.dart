import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:studyup/core/notifications/notification_service.dart';
import 'package:studyup/features/home/data/home_models.dart';
import 'package:studyup/features/home/presentation/home_controller.dart';
import 'package:studyup/features/home/presentation/home_screen.dart'
    show selectedDateLabel, shouldAutoOpenAddSheet;

Map<String, Object?> taskRow(String id, String title, bool done) {
  final now = DateTime.now();
  final day = DateTime(now.year, now.month, now.day);
  return {
    'id': id,
    'title': title,
    'description': 'desc $id',
    'startMinutes': 540,
    'endMinutes': 600,
    'isDone': done,
    'date': day.toIso8601String(),
  };
}

Future<void> waitFor(bool Function() condition) async {
  for (var i = 0; i < 200 && !condition(); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
  expect(condition(), isTrue);
}

void main() {
  group('task dates: past, today, and future stay isolated', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({
        'studyup.tasks.starterSeeded.v1': true,
        'studyup.tasks.v1': jsonEncode({
          '2023-05-17': [
            {
              'id': 'past-1',
              'title': 'Old homework',
              'description': 'from last year',
              'startMinutes': 540,
              'endMinutes': 600,
              'isDone': false,
              'date': DateTime(2023, 5, 17).toIso8601String(),
            },
          ],
        }),
      });
    });

    test('past tasks load on their date with fields intact', () async {
      final ctrl = HomeController();
      await waitFor(() => ctrl.state.isLoaded);
      ctrl.selectDate(DateTime(2023, 5, 17));
      final tasks = ctrl.state.selectedTasks;
      expect(tasks, hasLength(1));
      expect(tasks.single.title, 'Old homework');
      expect(tasks.single.description, 'from last year');
      expect(tasks.single.isDone, isFalse);
      expect(ctrl.state.selectedKind, DateKind.past);
      ctrl.dispose();
    });

    test('toggle/edit/delete on a past date touch only that date', () async {
      final ctrl = HomeController();
      await waitFor(() => ctrl.state.isLoaded);
      ctrl.selectDate(DateTime(2023, 5, 17));
      ctrl.toggleTask('past-1');
      expect(ctrl.state.selectedTasks.single.isDone, isTrue);
      ctrl.editTask(
        taskId: 'past-1',
        title: 'Old homework (revised)',
        description: 'from last year',
        startMinutes: 600,
        endMinutes: 660,
      );
      final edited = ctrl.state.selectedTasks.single;
      expect(edited.title, 'Old homework (revised)');
      expect(edited.startMinutes, 600);
      // Nothing leaked into today.
      final now = DateTime.now();
      ctrl.selectDate(DateTime(now.year, now.month, now.day));
      expect(ctrl.state.selectedTasks, isEmpty);
      // Delete back on the past date.
      ctrl.selectDate(DateTime(2023, 5, 17));
      ctrl.deleteTask('past-1');
      expect(ctrl.state.selectedTasks, isEmpty);
      ctrl.dispose();
    });

    test('future tasks save against the exact selected date', () async {
      final ctrl = HomeController();
      await waitFor(() => ctrl.state.isLoaded);
      final future = DateTime.now().add(const Duration(days: 400));
      final day = DateTime(future.year, future.month, future.day);
      ctrl.selectDate(day);
      expect(ctrl.state.selectedKind, DateKind.future);
      ctrl.addTask(
        title: 'Far-future plan',
        description: 'next year',
        startMinutes: 540,
        endMinutes: 600,
      );
      expect(ctrl.state.tasksByDate[dateKey(day)], hasLength(1));
      // Returning later shows them again; today stays untouched.
      final now = DateTime.now();
      ctrl.selectDate(DateTime(now.year, now.month, now.day));
      expect(ctrl.state.selectedTasks, isEmpty);
      ctrl.selectDate(day);
      expect(ctrl.state.selectedTasks.single.title, 'Far-future plan');
      ctrl.dispose();
    });

    test('tasks survive an app restart on their dates', () async {
      final first = HomeController();
      await waitFor(() => first.state.isLoaded);
      first.selectDate(DateTime(2023, 5, 17));
      first.toggleTask('past-1');
      await Future<void>.delayed(const Duration(milliseconds: 50));
      first.dispose();

      final second = HomeController();
      await waitFor(() => second.state.isLoaded);
      second.selectDate(DateTime(2023, 5, 17));
      expect(second.state.selectedTasks.single.isDone, isTrue);
      expect(second.state.tasksByDate.containsKey('2023-05-17'), isTrue);
      second.dispose();
    });
  });

  group('calendar correctness', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({
        'studyup.tasks.starterSeeded.v1': true,
        'studyup.tasks.v1': jsonEncode({}),
      });
    });

    test('month/year boundaries navigate by exact day', () async {
      final ctrl = HomeController();
      await waitFor(() => ctrl.state.isLoaded);
      ctrl.selectDate(DateTime(2024, 12, 31));
      expect(dateKey(ctrl.state.selectedDate), '2024-12-31');
      ctrl.selectDate(ctrl.state.selectedDate.add(const Duration(days: 1)));
      expect(dateKey(ctrl.state.selectedDate), '2025-01-01');
      expect(ctrl.state.selectedKind, isNotNull);
      ctrl.dispose();
    });

    test('leap day stores and reloads tasks', () async {
      final ctrl = HomeController();
      await waitFor(() => ctrl.state.isLoaded);
      ctrl.selectDate(DateTime(2024, 2, 29));
      ctrl.addTask(
        title: 'Leap task',
        description: 'Feb 29',
        startMinutes: 540,
        endMinutes: 600,
      );
      expect(dateKey(DateTime(2024, 2, 29)), '2024-02-29');
      expect(ctrl.state.tasksByDate['2024-02-29'], hasLength(1));
      await Future<void>.delayed(const Duration(milliseconds: 50));
      ctrl.dispose();

      final second = HomeController();
      await waitFor(() => second.state.isLoaded);
      second.selectDate(DateTime(2024, 2, 29));
      expect(second.state.selectedTasks.single.title, 'Leap task');
      second.dispose();
    });

    test('selectedDateLabel shows full date with relative hints', () {
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      expect(selectedDateLabel(today), contains('Today'));
      expect(
        selectedDateLabel(today.subtract(const Duration(days: 1))),
        contains('Yesterday'),
      );
      expect(
        selectedDateLabel(today.add(const Duration(days: 1))),
        contains('Tomorrow'),
      );
      expect(selectedDateLabel(DateTime(2023, 5, 17)), 'Wed, 17 May 2023');
      expect(selectedDateLabel(DateTime(2024, 2, 29)), contains('2024'));
    });
  });

  group('auto-open rule for future dates', () {
    test('only future days open the sheet immediately', () {
      final now = DateTime(2026, 5, 17, 12);
      final today = DateTime(2026, 5, 17);
      expect(shouldAutoOpenAddSheet(today, now), isFalse);
      expect(shouldAutoOpenAddSheet(DateTime(2026, 5, 16), now), isFalse);
      expect(shouldAutoOpenAddSheet(DateTime(2026, 5, 18), now), isTrue);
      expect(shouldAutoOpenAddSheet(DateTime(2023, 5, 17), now), isFalse);
      expect(shouldAutoOpenAddSheet(DateTime(2027, 1, 5), now), isTrue);
    });
  });

  group('reminder timing follows the real due date', () {
    test('past tasks never produce a fire time', () {
      final now = DateTime(2026, 5, 17, 12);
      expect(
        NotifRules.taskReminderFireTime(
          date: DateTime(2023, 5, 17),
          startMinutes: 540,
          now: now,
        ),
        isNull,
      );
      // A task later today still fires five minutes before start.
      expect(
        NotifRules.taskReminderFireTime(
          date: DateTime(2026, 5, 17),
          startMinutes: 13 * 60,
          now: now,
        ),
        DateTime(2026, 5, 17, 12, 55),
      );
      // Future dates schedule normally.
      expect(
        NotifRules.taskReminderFireTime(
          date: DateTime(2027, 1, 5),
          startMinutes: 540,
          now: now,
        ),
        DateTime(2027, 1, 5, 8, 55),
      );
    });
  });
}
