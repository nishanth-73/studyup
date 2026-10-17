import 'package:flutter/foundation.dart';

const int defaultDailyStudyGoalMinutes = 480;

/// Single shared daily session identity. All new sessions use this
/// subject id so every completed session contributes to the one daily
/// goal, attendance, and charts. Historical rows keep their stored
/// subject ids/names untouched.
const String dailyStudySubjectId = 'general';
const String dailyStudySubjectName = 'Daily Study';

@immutable
class StudyTimeSegment {
  final DateTime startTime;
  final DateTime? endTime;

  const StudyTimeSegment({required this.startTime, this.endTime});

  Duration durationAt(DateTime now) {
    final end = endTime ?? now;
    return end.isAfter(startTime) ? end.difference(startTime) : Duration.zero;
  }

  int secondsInRange(DateTime start, DateTime end, DateTime now) {
    final segmentEnd = endTime ?? now;
    final overlapStart = startTime.isAfter(start) ? startTime : start;
    final overlapEnd = segmentEnd.isBefore(end) ? segmentEnd : end;
    return overlapEnd.isAfter(overlapStart)
        ? overlapEnd.difference(overlapStart).inSeconds
        : 0;
  }

  Map<String, Object?> toJson() => {
    'startTime': startTime.toIso8601String(),
    'endTime': endTime?.toIso8601String(),
  };

  factory StudyTimeSegment.fromJson(Map<String, Object?> json) =>
      StudyTimeSegment(
        startTime: DateTime.parse(json['startTime']! as String),
        endTime: json['endTime'] == null
            ? null
            : DateTime.parse(json['endTime']! as String),
      );
}

@immutable
class StudySession {
  final String id;
  final String subjectId;
  final String subjectName;
  final DateTime checkInTime;
  final DateTime? checkOutTime;

  /// Total study seconds banked before the current run, retained for older
  /// stored sessions and as a quick persisted timer value.
  final int pausedSeconds;

  /// Legacy restart seed. New sessions never carry time from an older row.
  final int carriedSeconds;

  /// Active intervals are the source for pause-aware date and subject totals.
  final List<StudyTimeSegment> studySegments;

  /// Live accrual anchor while running; null while paused or ended.
  final DateTime? resumedAt;

  const StudySession({
    required this.id,
    required this.subjectId,
    required this.subjectName,
    required this.checkInTime,
    this.checkOutTime,
    this.pausedSeconds = 0,
    this.carriedSeconds = 0,
    this.studySegments = const [],
    this.resumedAt,
  });

  bool get isActive => checkOutTime == null;

  bool get isPaused => checkOutTime == null && resumedAt == null;

  bool get isRunning => checkOutTime == null && resumedAt != null;

  Duration durationAt(DateTime now) {
    if (studySegments.isNotEmpty) {
      return studySegments.fold<Duration>(
        Duration.zero,
        (total, segment) => total + segment.durationAt(now),
      );
    }
    if (checkOutTime != null) {
      if (pausedSeconds > 0) return Duration(seconds: pausedSeconds);
      if (carriedSeconds > 0) return Duration.zero;
      return checkOutTime!.difference(checkInTime);
    }
    final anchor = resumedAt;
    final live = anchor == null || !now.isAfter(anchor)
        ? 0
        : now.difference(anchor).inSeconds;
    return Duration(seconds: pausedSeconds + live);
  }

  int secondsInRange(DateTime start, DateTime end, DateTime now) {
    final segments = segmentsAt(now);
    return segments.fold(
      0,
      (total, segment) => total + segment.secondsInRange(start, end, now),
    );
  }

  List<StudyTimeSegment> segmentsAt(DateTime now) {
    if (studySegments.isNotEmpty) return studySegments;

    // Older persisted sessions have banked duration but no interval history.
    // Place their banked time from check-in, and retain a running anchor when
    // available. Legacy rows without pause data remain wall-clock intervals.
    if (pausedSeconds > 0) {
      return [
        StudyTimeSegment(
          startTime: checkInTime,
          endTime: checkInTime.add(Duration(seconds: pausedSeconds)),
        ),
        if (isRunning) StudyTimeSegment(startTime: resumedAt!),
      ];
    }
    if (carriedSeconds > 0) {
      return [if (isRunning) StudyTimeSegment(startTime: resumedAt!)];
    }
    if (isPaused) return const [];
    if (isRunning && resumedAt!.isAfter(checkInTime)) {
      return [StudyTimeSegment(startTime: resumedAt!)];
    }
    return [StudyTimeSegment(startTime: checkInTime, endTime: checkOutTime)];
  }

  DateTime? get lastStudyTime {
    for (final segment in studySegments.reversed) {
      if (segment.endTime != null) return segment.endTime;
    }
    if (pausedSeconds > 0) {
      return checkInTime.add(Duration(seconds: pausedSeconds));
    }
    return null;
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'subjectId': subjectId,
    'subjectName': subjectName,
    'checkInTime': checkInTime.toIso8601String(),
    'checkOutTime': checkOutTime?.toIso8601String(),
    'pausedSeconds': pausedSeconds,
    'studySegments': studySegments.map((segment) => segment.toJson()).toList(),
    'resumedAt': resumedAt?.toIso8601String(),
  };

  factory StudySession.fromJson(Map<String, Object?> json) {
    final checkIn = DateTime.parse(json['checkInTime']! as String);
    final checkOut = json['checkOutTime'] == null
        ? null
        : DateTime.parse(json['checkOutTime']! as String);
    if (!json.containsKey('pausedSeconds')) {
      if (checkOut == null) {
        return StudySession(
          id: json['id']! as String,
          subjectId: json['subjectId']! as String,
          subjectName: json['subjectName']! as String,
          checkInTime: checkIn,
          studySegments: [StudyTimeSegment(startTime: checkIn)],
          resumedAt: checkIn,
        );
      }
      return StudySession(
        id: json['id']! as String,
        subjectId: json['subjectId']! as String,
        subjectName: json['subjectName']! as String,
        checkInTime: checkIn,
        checkOutTime: checkOut,
        pausedSeconds: checkOut.difference(checkIn).inSeconds,
        studySegments: [
          StudyTimeSegment(startTime: checkIn, endTime: checkOut),
        ],
      );
    }
    final resumedRaw = json['resumedAt'];
    final segmentData = json['studySegments'] as List<Object?>? ?? const [];
    return StudySession(
      id: json['id']! as String,
      subjectId: json['subjectId']! as String,
      subjectName: json['subjectName']! as String,
      checkInTime: checkIn,
      checkOutTime: checkOut,
      pausedSeconds: (json['pausedSeconds'] as num? ?? 0).toInt(),
      carriedSeconds: (json['carriedSeconds'] as num? ?? 0).toInt(),
      studySegments: segmentData
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
}
