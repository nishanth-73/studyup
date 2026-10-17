import 'package:flutter/material.dart';

import '../../features/home/data/home_models.dart';
import '../../features/subjects/data/subjects_models.dart';
import '../../core/theme/app_colors.dart';

/// First-run starter content. Pure builders (no storage) so they are easy
/// to unit-test; persistence/once-only gating lives in the controllers.
class StarterData {
  /// Two editable example tasks for a genuinely new user. Times are
  /// daytime defaults on [day] and use the normal task-creation path.
  static List<StudyTask> defaultTasks(DateTime day) {
    final d = DateTime(day.year, day.month, day.day);
    return [
      StudyTask(
        id: 'starter-study',
        title: 'Study',
        description: 'Example task — edit or delete me',
        startMinutes: 16 * 60,
        endMinutes: 17 * 60,
        date: d,
      ),
      StudyTask(
        id: 'starter-eat',
        title: 'Eat',
        description: 'Example task — edit or delete me',
        startMinutes: 13 * 60,
        endMinutes: 13 * 60 + 30,
        date: d,
      ),
    ];
  }

  /// Editable starter subject library: Mathematics + Physics with example
  /// chapters and topics. Fixed readable ids (no timestamps) so seeding is
  /// deterministic and never duplicated.
  static List<Subject> defaultSubjects() => [
    Subject(
      id: 'starter-subject-mathematics',
      name: 'Mathematics',
      meta: 'Example subject — edit or delete me',
      weekHours: '',
      totalHours: '',
      color: AppColors.cta,
      icon: Icons.calculate,
      chapters: const [
        Chapter(
          id: 'starter-chapter-algebra',
          title: 'Algebra',
          topics: [
            Topic(id: 'starter-topic-linear', name: 'Linear Equations'),
            Topic(id: 'starter-topic-quadratic', name: 'Quadratic Equations'),
          ],
        ),
        Chapter(
          id: 'starter-chapter-calculus',
          title: 'Calculus',
          topics: [
            Topic(id: 'starter-topic-limits', name: 'Limits'),
            Topic(id: 'starter-topic-derivatives', name: 'Derivatives'),
          ],
        ),
      ],
    ),
    Subject(
      id: 'starter-subject-physics',
      name: 'Physics',
      meta: 'Example subject — edit or delete me',
      weekHours: '',
      totalHours: '',
      color: AppColors.blue,
      icon: Icons.science,
      chapters: const [
        Chapter(
          id: 'starter-chapter-mechanics',
          title: 'Mechanics',
          topics: [
            Topic(id: 'starter-topic-motion', name: 'Motion'),
            Topic(id: 'starter-topic-newton', name: "Newton's Laws of Motion"),
          ],
        ),
        Chapter(
          id: 'starter-chapter-electricity',
          title: 'Electricity',
          topics: [
            Topic(id: 'starter-topic-current', name: 'Electric Current'),
            Topic(id: 'starter-topic-ohm', name: "Ohm's Law"),
          ],
        ),
      ],
    ),
  ];
}
