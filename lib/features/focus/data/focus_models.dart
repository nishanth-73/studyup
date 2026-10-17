import 'package:flutter/foundation.dart';

import '../../progress/data/study_session.dart';

/// Unified system subject used when the user starts studying without
/// picking a specific subject. Tapping "Quick Start Attendance" creates
/// a focus session assigned to this id.
const String generalStudySubjectId = 'general';
const String generalStudySubjectName = 'General Study';

/// Lightweight, persistable subject representation for the
/// Focus Session = Attendance feature.
///
/// The existing `Subject` class in subjects uses `Color` + `IconData`
/// (non-serializable). This model uses `colorHex` / `iconPath` so it can
/// be stored and passed across the attendance flow. Use
/// [SubjectModel.fromSubject] to adapt existing subjects.
@immutable
class SubjectModel {
  final String id;
  final String name;
  final String colorHex;
  final String iconPath;

  const SubjectModel({
    required this.id,
    required this.name,
    required this.colorHex,
    required this.iconPath,
  });

  /// Default fallback subject for uncategorized study.
  const SubjectModel.generalStudy()
    : id = generalStudySubjectId,
      name = generalStudySubjectName,
      colorHex = '#7B68D9',
      iconPath = 'assets/icons/general_study.svg';

  bool get isGeneralStudy => id == generalStudySubjectId;

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'colorHex': colorHex,
    'iconPath': iconPath,
  };

  factory SubjectModel.fromJson(Map<String, Object?> json) => SubjectModel(
    id: json['id']! as String,
    name: json['name']! as String,
    colorHex: json['colorHex'] as String? ?? '#7B68D9',
    iconPath: json['iconPath'] as String? ?? '',
  );
}

/// Single focus session. This is the atomic unit that drives
/// Daily Attendance: one active timer ticks both the subject's daily
/// progress and the overall daily attendance progress.
@immutable
class FocusSessionModel {
  final String id;
  final String subjectId;
  final DateTime startTime;
  final DateTime? endTime;

  /// Banked studied seconds (pause-aware). See StudySession.
  final int pausedSeconds;

  /// Seconds carried from the previous ended session of the same subject.
  final int carriedSeconds;

  /// Live accrual anchor while running; null while paused/ended.
  final DateTime? resumedAt;
  final List<StudyTimeSegment> studySegments;

  const FocusSessionModel({
    required this.id,
    required this.subjectId,
    required this.startTime,
    this.endTime,
    this.pausedSeconds = 0,
    this.carriedSeconds = 0,
    this.studySegments = const [],
    this.resumedAt,
  });

  bool get isActive => endTime == null;
  bool get isCompleted => endTime != null;
  bool get isPaused => endTime == null && resumedAt == null;
  bool get isRunning => endTime == null && resumedAt != null;

  /// Calendar day this session belongs to (normalized start day).
  DateTime get date => DateTime(startTime.year, startTime.month, startTime.day);

  /// Completed minutes. For an active session pass `now` to get live minutes.
  /// Pause-aware: frozen while paused, exact on resume.
  int durationInMinutesAt(DateTime now) =>
      durationAt(now).inMinutes.clamp(0, 24 * 60);

  /// Persisted/completed minutes. Active sessions report 0 until ended,
  /// use [durationInMinutesAt] for live ticking.
  int get durationInMinutes {
    return endTime == null
        ? 0
        : durationAt(endTime!).inMinutes.clamp(0, 24 * 60);
  }

  Duration durationAt(DateTime now) => _asStudySession().durationAt(now);

  int secondsInRange(DateTime start, DateTime end, DateTime now) =>
      _asStudySession().secondsInRange(start, end, now);

  List<StudyTimeSegment> segmentsAt(DateTime now) =>
      _asStudySession().segmentsAt(now);

  FocusSessionModel copyWith({DateTime? endTime}) => FocusSessionModel(
    id: id,
    subjectId: subjectId,
    startTime: startTime,
    endTime: endTime ?? this.endTime,
    pausedSeconds: pausedSeconds,
    carriedSeconds: carriedSeconds,
    studySegments: studySegments,
    resumedAt: resumedAt,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'subjectId': subjectId,
    'startTime': startTime.toIso8601String(),
    'endTime': endTime?.toIso8601String(),
    'pausedSeconds': pausedSeconds,
    'carriedSeconds': carriedSeconds,
    'studySegments': studySegments.map((segment) => segment.toJson()).toList(),
    'resumedAt': resumedAt?.toIso8601String(),
  };

  factory FocusSessionModel.fromJson(Map<String, Object?> json) {
    // Accept both new keys and legacy StudySession keys for migration.
    final startRaw = json['startTime'] ?? json['checkInTime'];
    final endRaw = json['endTime'] ?? json['checkOutTime'];
    final start = DateTime.parse(startRaw! as String);
    final end = endRaw == null ? null : DateTime.parse(endRaw as String);
    if (!json.containsKey('pausedSeconds')) {
      if (end == null) {
        return FocusSessionModel(
          id: json['id']! as String,
          subjectId: json['subjectId']! as String,
          startTime: start,
          resumedAt: start,
        );
      }
      return FocusSessionModel(
        id: json['id']! as String,
        subjectId: json['subjectId']! as String,
        startTime: start,
        endTime: end,
        pausedSeconds: end.difference(start).inSeconds,
      );
    }
    final resumedRaw = json['resumedAt'];
    return FocusSessionModel(
      id: json['id']! as String,
      subjectId: json['subjectId']! as String,
      startTime: start,
      endTime: end,
      pausedSeconds: (json['pausedSeconds'] as num? ?? 0).toInt(),
      carriedSeconds: (json['carriedSeconds'] as num? ?? 0).toInt(),
      studySegments: (json['studySegments'] as List<Object?>? ?? const [])
          .map(
            (entry) => StudyTimeSegment.fromJson(
              Map<String, Object?>.from(entry! as Map),
            ),
          )
          .toList(growable: false),
      resumedAt: resumedRaw == null
          ? null
          : DateTime.parse(resumedRaw as String),
    );
  }

  /// Adapt from the existing persisted [StudySession].
  factory FocusSessionModel.fromStudySession(StudySession s) =>
      FocusSessionModel(
        id: s.id,
        subjectId: s.subjectId,
        startTime: s.checkInTime,
        endTime: s.checkOutTime,
        pausedSeconds: s.pausedSeconds,
        carriedSeconds: s.carriedSeconds,
        studySegments: s.studySegments,
        resumedAt: s.resumedAt,
      );

  StudySession toStudySession(String subjectName) => StudySession(
    id: id,
    subjectId: subjectId,
    subjectName: subjectName,
    checkInTime: startTime,
    checkOutTime: endTime,
    pausedSeconds: pausedSeconds,
    carriedSeconds: carriedSeconds,
    studySegments: studySegments,
    resumedAt: resumedAt,
  );

  StudySession _asStudySession() => toStudySession('');
}

/// Daily attendance aggregate. Total Daily Attendance = sum of all
/// completed (plus live active) focus session durations for that day.
@immutable
class DailyAttendanceModel {
  final DateTime date;
  final int targetGoalMinutes;
  final List<FocusSessionModel> sessions;

  const DailyAttendanceModel({
    required this.date,
    required this.sessions,
    this.targetGoalMinutes = defaultDailyAttendanceGoalMinutes,
  });

  /// Sum of all durations for the calendar date [date] (midnight to
  /// midnight). Sessions crossing midnight split at the boundary so each
  /// date owns exactly the minutes studied on it.
  int get totalStudiedMinutes {
    final start = DateTime(date.year, date.month, date.day);
    final end = start.add(const Duration(days: 1));
    final now = DateTime.now();
    final seconds = sessions.fold(
      0,
      (total, session) => total + session.secondsInRange(start, end, now),
    );
    return seconds ~/ 60;
  }

  double get progressPercentage {
    if (targetGoalMinutes <= 0) return 0;
    return (totalStudiedMinutes / targetGoalMinutes).clamp(0.0, 1.0);
  }

  /// Unclamped goal achievement for overflow readouts.
  /// e.g. 520 / 480 = 1.0833. Bars still use [progressPercentage].
  double get achievementRatio {
    if (targetGoalMinutes <= 0) return 0;
    final r = totalStudiedMinutes / targetGoalMinutes;
    return r < 0 ? 0 : r;
  }

  /// Normal UI achievement percentage rounded to a whole percent.
  String get achievementLabel {
    final pct = achievementRatio * 100;
    return '${pct.round()}%';
  }

  int get sessionCount {
    final start = DateTime(date.year, date.month, date.day);
    final end = start.add(const Duration(days: 1));
    final now = DateTime.now();
    // Overlap-based like the authoritative session list: a session
    // crossing midnight counts on both dates it touches.
    return sessions.where((s) => s.secondsInRange(start, end, now) > 0).length;
  }

  FocusSessionModel? get activeSession {
    for (final s in sessions) {
      if (s.isActive) return s;
    }
    return null;
  }

  String get progressLabel =>
      '${formatStudyDuration(totalStudiedMinutes)} / ${formatStudyDuration(targetGoalMinutes)} Goal';
}

/// Default daily attendance target: 8 hours.
const int defaultDailyAttendanceGoalMinutes = defaultDailyStudyGoalMinutes;

String formatStudyDuration(int minutes) {
  if (minutes < 60) return '${minutes}m';
  final h = minutes ~/ 60;
  final r = minutes % 60;
  return r == 0 ? '${h}h' : '${h}h ${r}m';
}

/// `3h 45m / 8h 00m` style label used on the Home attendance card.
String formatAttendanceProgress(int studiedMinutes, int goalMinutes) {
  String two(int v) => v.toString().padLeft(2, '0');
  final sh = studiedMinutes ~/ 60;
  final sm = studiedMinutes % 60;
  final gh = goalMinutes ~/ 60;
  final gm = goalMinutes % 60;
  return '${sh}h ${two(sm)}m / ${gh}h ${two(gm)}m Goal';
}
