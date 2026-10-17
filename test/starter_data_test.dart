import 'package:flutter_test/flutter_test.dart';
import 'package:studyup/core/seed/starter_data.dart';
import 'package:studyup/features/home/data/home_models.dart';
import 'package:studyup/features/subjects/data/subjects_models.dart';

void main() {
  group('StarterData.defaultTasks', () {
    test('seeds exactly the Study and Eat examples', () {
      final tasks = StarterData.defaultTasks(DateTime(2026, 10, 12));
      expect(tasks, hasLength(2));
      expect(tasks.map((t) => t.title), ['Study', 'Eat']);
    });

    test('starter tasks carry daytime defaults on the given day', () {
      final tasks = StarterData.defaultTasks(DateTime(2026, 10, 12));
      for (final task in tasks) {
        expect(task.date, DateTime(2026, 10, 12));
        expect(task.endMinutes, greaterThan(task.startMinutes));
      }
    });

    test('starter tasks survive a JSON round-trip (persistence-safe)', () {
      for (final task in StarterData.defaultTasks(DateTime(2026, 10, 12))) {
        final restored = StudyTask.fromJson(task.toJson());
        expect(restored.id, task.id);
        expect(restored.title, task.title);
        expect(restored.description, task.description);
        expect(restored.startMinutes, task.startMinutes);
        expect(restored.endMinutes, task.endMinutes);
        expect(restored.date, task.date);
        expect(restored.isDone, isFalse);
      }
    });
  });

  group('StarterData.defaultSubjects', () {
    test('seeds Mathematics and Physics', () {
      final subjects = StarterData.defaultSubjects();
      expect(subjects.map((s) => s.name), ['Mathematics', 'Physics']);
    });

    test('matches the specified chapters and topics', () {
      final subjects = StarterData.defaultSubjects();
      final math = subjects.firstWhere((s) => s.name == 'Mathematics');
      final physics = subjects.firstWhere((s) => s.name == 'Physics');

      expect(math.chapters.map((c) => c.title), ['Algebra', 'Calculus']);
      expect(math.chapters.expand((c) => c.topics).map((t) => t.name), [
        'Linear Equations',
        'Quadratic Equations',
        'Limits',
        'Derivatives',
      ]);

      expect(physics.chapters.map((c) => c.title), [
        'Mechanics',
        'Electricity',
      ]);
      expect(physics.chapters.expand((c) => c.topics).map((t) => t.name), [
        'Motion',
        "Newton's Laws of Motion",
        'Electric Current',
        "Ohm's Law",
      ]);
    });
    test('starter ids are deterministic (no duplicates on reseed)', () {
      List<String> ids(List<Subject> subjects) => [
        for (final s in subjects) s.id,
      ];
      expect(
        ids(StarterData.defaultSubjects()),
        ids(StarterData.defaultSubjects()),
      );
    });
  });
}
