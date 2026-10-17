import 'package:flutter/foundation.dart';

@immutable
class StudyTask {
  final String id;
  final String title;
  final String description;
  final int startMinutes; // minutes since midnight
  final int endMinutes;
  final bool isDone;
  final DateTime date;

  const StudyTask({
    required this.id,
    required this.title,
    required this.description,
    required this.startMinutes,
    required this.endMinutes,
    required this.date,
    this.isDone = false,
  });

  int get minutes => (endMinutes - startMinutes).clamp(5, 24 * 60);

  StudyTask copyWith({
    bool? isDone,
    String? title,
    String? description,
    int? startMinutes,
    int? endMinutes,
  }) {
    return StudyTask(
      id: id,
      title: title ?? this.title,
      description: description ?? this.description,
      startMinutes: startMinutes ?? this.startMinutes,
      endMinutes: endMinutes ?? this.endMinutes,
      date: date,
      isDone: isDone ?? this.isDone,
    );
  }

  String get durationLabel {
    final m = minutes;
    if (m < 60) return '${m}m';
    final h = m ~/ 60;
    final r = m % 60;
    return r == 0 ? '${h}h' : '${h}h ${r}m';
  }

  static String formatTime(int totalMinutes) {
    final h24 = (totalMinutes ~/ 60) % 24;
    final m = totalMinutes % 60;
    final period = h24 >= 12 ? 'PM' : 'AM';
    var h = h24 % 12;
    if (h == 0) h = 12;
    return '$h:${m.toString().padLeft(2, '0')} $period';
  }

  String get startLabel => formatTime(startMinutes);
  String get endLabel => formatTime(endMinutes);

  Map<String, Object?> toJson() => {
    'id': id,
    'title': title,
    'description': description,
    'startMinutes': startMinutes,
    'endMinutes': endMinutes,
    'isDone': isDone,
    'date': date.toIso8601String(),
  };

  factory StudyTask.fromJson(Map<String, Object?> json) => StudyTask(
    id: json['id']! as String,
    title: json['title'] as String? ?? 'Untitled task',
    description: json['description'] as String? ?? 'No description',
    startMinutes: (json['startMinutes'] as num? ?? 540).toInt(),
    endMinutes: (json['endMinutes'] as num? ?? 600).toInt(),
    date: DateTime.parse(json['date']! as String),
    isDone: json['isDone'] as bool? ?? false,
  );
}

enum DateKind { past, today, future }

String dateKey(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

const List<String> weekdayShort = [
  'Mon',
  'Tue',
  'Wed',
  'Thu',
  'Fri',
  'Sat',
  'Sun',
];
const List<String> weekdayFull = [
  'Monday',
  'Tuesday',
  'Wednesday',
  'Thursday',
  'Friday',
  'Saturday',
  'Sunday',
];

/// Monday of the week containing [day].
DateTime mondayOfWeek(DateTime day) {
  final d = DateTime(day.year, day.month, day.day);
  return d.subtract(Duration(days: d.weekday - 1));
}
