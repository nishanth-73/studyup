import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:studyup/features/home/data/home_models.dart';
import 'package:studyup/features/home/presentation/home_controller.dart';
import 'package:studyup/features/subjects/presentation/subjects_controller.dart';

String todayKey() {
  final now = DateTime.now();
  return dateKey(DateTime(now.year, now.month, now.day));
}

Future<void> waitFor(bool Function() condition) async {
  for (var i = 0; i < 200 && !condition(); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
  expect(condition(), isTrue);
}

void main() {
  group('first-run task seeding', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('new user gets editable Study + Eat starters, once', () async {
      final first = HomeController();
      await waitFor(() => first.state.isLoaded);
      final tasks = first.state.tasksByDate[todayKey()] ?? const [];
      expect(tasks.map((t) => t.title), containsAll(['Study', 'Eat']));

      // Starters are normal tasks: complete one, delete the other.
      first.toggleTask(tasks.firstWhere((t) => t.title == 'Study').id);
      first.deleteTask(tasks.firstWhere((t) => t.title == 'Eat').id);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      first.dispose();

      // Relaunch with the same stored data: no duplicates, no resurrection.
      final second = HomeController();
      await waitFor(() => second.state.isLoaded);
      final reloaded = second.state.tasksByDate[todayKey()] ?? const [];
      expect(reloaded.where((t) => t.title == 'Study'), hasLength(1));
      expect(reloaded.any((t) => t.title == 'Eat'), isFalse);
      expect(reloaded.firstWhere((t) => t.title == 'Study').isDone, isTrue);
      second.dispose();
    });

    test('existing tasks are never overwritten or duplicated', () async {
      final first = HomeController();
      await waitFor(() => first.state.isLoaded);
      // Wipe the starters, add a real task, then relaunch.
      for (final task in List.of(
        first.state.tasksByDate[todayKey()] ?? const [],
      )) {
        first.deleteTask(task.id);
      }
      first.addTask(
        title: 'Real homework',
        description: 'My own task',
        startMinutes: 600,
        endMinutes: 660,
      );
      await Future<void>.delayed(const Duration(milliseconds: 50));
      first.dispose();

      final second = HomeController();
      await waitFor(() => second.state.isLoaded);
      final reloaded = second.state.tasksByDate[todayKey()] ?? const [];
      expect(reloaded.map((t) => t.title), ['Real homework']);
      second.dispose();
    });
  });

  group('first-run subject seeding', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('new user gets Mathematics + Physics library, once', () async {
      final first = SubjectsController();
      await waitFor(() => first.state.isNotEmpty);
      expect(first.state.map((s) => s.name), ['Mathematics', 'Physics']);
      final math = first.state.first;
      expect(math.chapters.map((c) => c.title), ['Algebra', 'Calculus']);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      first.dispose();

      final second = SubjectsController();
      await waitFor(() => second.state.isNotEmpty);
      expect(second.state.map((s) => s.name), ['Mathematics', 'Physics']);
      second.dispose();
    });

    test('deleted starters never come back', () async {
      final first = SubjectsController();
      await waitFor(() => first.state.isNotEmpty);
      for (final subject in List.of(first.state)) {
        first.deleteSubject(subject.id);
      }
      await Future<void>.delayed(const Duration(milliseconds: 50));
      first.dispose();

      final second = SubjectsController();
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(second.state.where((s) => !s.archived), isEmpty);
      second.dispose();
    });
  });
}
