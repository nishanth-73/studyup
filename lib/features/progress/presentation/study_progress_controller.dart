import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/study_gamification.dart';
import '../data/study_session.dart';
import '../data/study_day.dart' show nextStudyResetAt;
import '../../../core/notifications/notification_service.dart';
import '../../robo/robo_events.dart';

@immutable
class StudyProgressState {
  final List<StudySession> sessions;
  final int dailyStudyGoalMinutes;

  /// Append-only XP award ledger (10 per goal-met day, 50 per full-goal
  /// week). XP is the sum of its awards; nothing ever resets it.
  final XpLedger xp;
  final bool isLoaded;
  final Object? error;

  const StudyProgressState({
    this.sessions = const [],
    this.dailyStudyGoalMinutes = defaultDailyStudyGoalMinutes,
    this.xp = const XpLedger(),
    this.isLoaded = false,
    this.error,
  });

  StudySession? get activeSession {
    for (final session in sessions) {
      if (session.isActive) return session;
    }
    return null;
  }

  int minutesForDate(DateTime date, {DateTime? now}) {
    final start = DateTime(date.year, date.month, date.day);
    final end = start.add(const Duration(days: 1));
    return _minutesInRange(start, end, now ?? DateTime.now());
  }

  /// Sessions touching the calendar date [date] (midnight to midnight).
  /// A session crossing midnight counts toward both dates — no separate
  /// check-in needed per date.
  int sessionCountForDate(DateTime date, {DateTime? now}) {
    final start = DateTime(date.year, date.month, date.day);
    final end = start.add(const Duration(days: 1));
    final time = now ?? DateTime.now();
    return sessions
        .where((session) => session.secondsInRange(start, end, time) > 0)
        .length;
  }

  int minutesForWeek(DateTime date, {DateTime? now}) {
    final start = _monday(date);
    return _minutesInRange(
      start,
      start.add(const Duration(days: 7)),
      now ?? DateTime.now(),
    );
  }

  int minutesForMonth(DateTime date, {DateTime? now}) {
    final start = DateTime(date.year, date.month);
    return _minutesInRange(
      start,
      DateTime(date.year, date.month + 1),
      now ?? DateTime.now(),
    );
  }

  int minutesForSubject(String subjectId, {DateTime? now}) {
    final time = now ?? DateTime.now();
    final seconds = sessions
        .where((session) => session.subjectId == subjectId)
        .fold(
          0,
          (total, session) => total + session.durationAt(time).inSeconds,
        );
    return seconds ~/ 60;
  }

  int minutesForSubjectInWeek(
    String subjectId,
    DateTime date, {
    DateTime? now,
  }) {
    final start = _monday(date);
    final end = start.add(const Duration(days: 7));
    return minutesForSubjectInRange(subjectId, start, end, now: now);
  }

  /// Strict subjectId-isolated overlap minutes in [start, end).
  /// General sessions (`general`) never leak into subject totals: only rows
  /// with `session.subjectId == subjectId` are counted.
  int minutesForSubjectInRange(
    String subjectId,
    DateTime start,
    DateTime end, {
    DateTime? now,
  }) {
    final time = now ?? DateTime.now();
    final seconds = sessions
        .where((session) => session.subjectId == subjectId)
        .fold(
          0,
          (total, session) => total + session.secondsInRange(start, end, time),
        );
    return seconds ~/ 60;
  }

  /// Strict subjectId-isolated session count touching [start, end).
  int sessionCountForSubjectInRange(
    String subjectId,
    DateTime start,
    DateTime end, {
    DateTime? now,
  }) {
    final time = now ?? DateTime.now();
    return sessions
        .where(
          (session) =>
              session.subjectId == subjectId &&
              session.secondsInRange(start, end, time) > 0,
        )
        .length;
  }

  /// Subject minutes for one calendar date (midnight to midnight).
  int minutesForSubjectOnDate(String subjectId, DateTime day, {DateTime? now}) {
    final start = DateTime(day.year, day.month, day.day);
    return minutesForSubjectInRange(
      subjectId,
      start,
      start.add(const Duration(days: 1)),
      now: now,
    );
  }

  /// Subject session count for one calendar date (midnight to midnight).
  int sessionCountForSubjectOnDate(
    String subjectId,
    DateTime day, {
    DateTime? now,
  }) {
    final start = DateTime(day.year, day.month, day.day);
    return sessionCountForSubjectInRange(
      subjectId,
      start,
      start.add(const Duration(days: 1)),
      now: now,
    );
  }

  /// Per-day subject minutes for a Mon–Sun week (midnight buckets, matching
  /// the global weekly chart so per-subject weeks sum to the global week).
  List<int> minutesByWeekdayForSubject(
    String subjectId,
    DateTime date, {
    DateTime? now,
  }) {
    final monday = _monday(date);
    return List.generate(7, (index) {
      final day = monday.add(Duration(days: index));
      return minutesForSubjectInRange(
        subjectId,
        day,
        day.add(const Duration(days: 1)),
        now: now,
      );
    });
  }

  /// Subject minutes in a calendar month.
  int minutesForSubjectInMonth(
    String subjectId,
    DateTime date, {
    DateTime? now,
  }) {
    final start = DateTime(date.year, date.month);
    final end = DateTime(date.year, date.month + 1);
    return minutesForSubjectInRange(subjectId, start, end, now: now);
  }

  /// Subject weekly buckets inside a calendar month (same bucketing as the
  /// global monthly chart).
  List<int> minutesByMonthWeekForSubject(
    String subjectId,
    DateTime date, {
    DateTime? now,
  }) {
    final count = (DateTime(date.year, date.month + 1, 0).day + 6) ~/ 7;
    return List.generate(count, (index) {
      final start = DateTime(date.year, date.month, index * 7 + 1);
      final end = DateTime(date.year, date.month, (index + 1) * 7 + 1);
      return minutesForSubjectInRange(subjectId, start, end, now: now);
    });
  }

  List<int> minutesByWeekday(DateTime date, {DateTime? now}) {
    final monday = _monday(date);
    return List.generate(
      7,
      (index) => minutesForDate(monday.add(Duration(days: index)), now: now),
    );
  }

  List<int> minutesByMonthWeek(DateTime date, {DateTime? now}) {
    final count = (DateTime(date.year, date.month + 1, 0).day + 6) ~/ 7;
    return List.generate(count, (index) {
      final start = DateTime(date.year, date.month, index * 7 + 1);
      final end = DateTime(date.year, date.month, (index + 1) * 7 + 1);
      return _minutesInRange(start, end, now ?? DateTime.now());
    });
  }

  /// Daily visual completion for one calendar date: the day's actual
  /// percentage against the shared goal, capped at 100 for display.
  /// e.g. 240/480 -> 50.0, 540/480 -> 100.0 (actual 112.5 preserved
  /// separately in the stored minutes). Feeds the weekly bars and,
  /// averaged over Mon–Sun, the monthly chart.
  double cappedDailyPercentage(DateTime date, {DateTime? now}) {
    final time = now ?? DateTime.now();
    final goal = dailyStudyGoalMinutes <= 0 ? 480 : dailyStudyGoalMinutes;
    final start = DateTime(date.year, date.month, date.day);
    final minutes = _minutesInRange(
      start,
      start.add(const Duration(days: 1)),
      time,
    );
    return (minutes / goal * 100).clamp(0.0, 100.0);
  }

  /// Weekly-average progress per Mon–Sun week overlapping the viewed
  /// calendar month. Each value = mean of the 7 capped daily visual
  /// percentages (Mon + Tue + … + Sun) / 7, so the monthly chart consumes
  /// exactly what the weekly chart displays. First/last weeks may include
  /// adjacent-month days — always 7 days, always / 7.
  List<double> monthWeekAveragePercentages(DateTime date, {DateTime? now}) {
    final time = now ?? DateTime.now();
    final monthEnd = DateTime(date.year, date.month + 1);
    final first = DateTime(date.year, date.month);
    var monday = first.subtract(Duration(days: first.weekday - 1));
    final weeks = <double>[];
    while (monday.isBefore(monthEnd)) {
      var sum = 0.0;
      for (var offset = 0; offset < 7; offset++) {
        sum += cappedDailyPercentage(
          monday.add(Duration(days: offset)),
          now: time,
        );
      }
      weeks.add(sum / 7);
      monday = monday.add(const Duration(days: 7));
    }
    return weeks;
  }

  List<int> dayPartMinutes(DateTime date, {DateTime? now}) {
    final start = DateTime(date.year, date.month, date.day);
    final end = start.add(const Duration(days: 1));
    return _partsInRange(start, end, now ?? DateTime.now());
  }

  List<int> _partsInRange(DateTime start, DateTime end, DateTime time) {
    final partSeconds = List<int>.filled(4, 0);

    for (final session in sessions) {
      for (final studySegment in session.segmentsAt(time)) {
        var cursor = studySegment.startTime;
        final studyEnd = studySegment.endTime ?? time;
        if (!studyEnd.isAfter(cursor)) continue;
        while (cursor.isBefore(studyEnd)) {
          final nextHour = DateTime(
            cursor.year,
            cursor.month,
            cursor.day,
            cursor.hour + 1,
          );
          final segmentEnd = nextHour.isBefore(studyEnd) ? nextHour : studyEnd;
          final overlapStart = cursor.isAfter(start) ? cursor : start;
          final overlapEnd = segmentEnd.isBefore(end) ? segmentEnd : end;
          if (overlapEnd.isAfter(overlapStart)) {
            partSeconds[_dayPartIndex(cursor.hour)] += overlapEnd
                .difference(overlapStart)
                .inSeconds;
          }
          cursor = segmentEnd;
        }
      }
    }
    return [for (final seconds in partSeconds) seconds ~/ 60];
  }

  int _minutesInRange(DateTime start, DateTime end, DateTime now) {
    final seconds = sessions.fold(
      0,
      (total, session) => total + session.secondsInRange(start, end, now),
    );
    return seconds ~/ 60;
  }

  StudyProgressState copyWith({
    List<StudySession>? sessions,
    int? dailyStudyGoalMinutes,
    XpLedger? xp,
    bool? isLoaded,
    Object? error,
    bool clearError = false,
  }) => StudyProgressState(
    sessions: sessions ?? this.sessions,
    dailyStudyGoalMinutes: dailyStudyGoalMinutes ?? this.dailyStudyGoalMinutes,
    xp: xp ?? this.xp,
    isLoaded: isLoaded ?? this.isLoaded,
    error: clearError ? null : error ?? this.error,
  );
}

int _dayPartIndex(int hour) {
  if (hour >= 6 && hour < 12) return 0;
  if (hour >= 12 && hour < 18) return 1;
  if (hour >= 18) return 2;
  return 3;
}

DateTime _monday(DateTime date) => DateTime(
  date.year,
  date.month,
  date.day,
).subtract(Duration(days: date.weekday - 1));

class StudyProgressController extends StateNotifier<StudyProgressState> {
  StudyProgressController() : super(const StudyProgressState()) {
    unawaited(_load());
  }

  static const _storageKey = 'studyup.studySessions.v1';
  static const _dailyGoalStorageKey = 'studyup.dailyStudyGoalMinutes.v1';
  static const _xpStorageKey = 'studyup.xpLedger.v1';
  Timer? _activeTicker;
  Future<void> _writeQueue = Future<void>.value();

  /// Serializes XP evaluations so concurrent saves/ticks can never
  /// overwrite each other's awards (each run re-reads the latest ledger).
  Future<void> _xpQueue = Future<void>.value();

  /// Serializes check-in/check-out operations so rapid repeated taps can
  /// never create duplicate sessions or overlapping timers: each operation
  /// observes the state left by the previous one. Errors propagate to the
  /// caller while the queue itself stays alive.
  Future<void> _opQueue = Future<void>.value();

  Future<void> _enqueue(Future<void> Function() op) {
    final next = _opQueue.catchError((Object _) {}).then((_) => op());
    _opQueue = next.catchError((Object _) {});
    return next;
  }

  Future<void> _load() async {
    try {
      final preferences = await SharedPreferences.getInstance();
      final raw = preferences.getString(_storageKey);
      final goal =
          preferences.getInt(_dailyGoalStorageKey) ??
          defaultDailyStudyGoalMinutes;
      final rawXp = preferences.getString(_xpStorageKey);
      var storedXp = const XpLedger();
      if (rawXp != null) {
        try {
          storedXp = XpLedger.fromJson(
            Map<String, Object?>.from(jsonDecode(rawXp) as Map),
          );
        } catch (_) {
          // Corrupt ledger: rebuilt from the real history below.
          storedXp = const XpLedger();
        }
      }
      final sessions = raw == null
          ? <StudySession>[]
          : (jsonDecode(raw) as List<Object?>)
                .map(
                  (entry) => StudySession.fromJson(
                    Map<String, Object?>.from(entry! as Map),
                  ),
                )
                .toList();
      if (sessions.where((session) => session.isActive).length > 1) {
        throw const FormatException(
          'Stored study data contains more than one active session.',
        );
      }
      if (!mounted) return;
      state = state.copyWith(
        sessions: sessions,
        dailyStudyGoalMinutes: goal,
        xp: storedXp,
        isLoaded: true,
      );
      _syncTicker();
      await _enqueue(() async {
        await _finalizeStalePaused(DateTime.now());
      });
      if (!mounted) return;
      // Adopt any persisted running session into the live timer (restarts
      // the service after process death); re-post a paused session's
      // frozen status; clear the tray when nothing is active.
      await _adoptLiveTimer(DateTime.now());
      if (!mounted) return;
      // Full rescan: calculates every goal-met day and full-goal week
      // from real session history: backfills users who studied before
      // this feature shipped, adopts time that accrued while a paused or
      // killed timer crossed day/week boundaries, and re-derives a
      // corrupt ledger. Ledger set-membership keeps it duplicate-free.
      await _syncXp(DateTime.now(), full: true);
    } catch (error, stackTrace) {
      if (!mounted) return;
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stackTrace,
          library: 'study progress',
          context: ErrorDescription('while loading persisted study sessions'),
        ),
      );
      state = state.copyWith(isLoaded: true, error: error);
    }
  }

  /// Reconciles the tray with persisted state on app start/restart:
  /// running sessions resume ticking, paused ones re-post their frozen
  /// status, and a stale entry with no session behind it is cleared.
  Future<void> _adoptLiveTimer(DateTime now) async {
    final active = state.activeSession;
    if (active == null) {
      await NotificationService.instance.cancelLiveTimer();
      return;
    }
    if (active.isRunning) {
      await _pushLiveTimer(now, fresh: false);
      return;
    }
    final today = DateTime(now.year, now.month, now.day);
    var elapsed = 0;
    for (final session in state.sessions) {
      elapsed += session.secondsInRange(today, now, now);
    }
    await NotificationService.instance.pauseLiveTimer(
      elapsedSec: elapsed,
      goalMinutes: state.dailyStudyGoalMinutes,
      dayKey: notifDateKey(now),
    );
  }

  /// Clears a stale paused session once a midnight boundary has passed
  /// while it stayed paused. Only the resumable state is cleared: the row
  /// is ended exactly at its pause moment so the studied duration already
  /// banked stays saved in history. Running sessions are never touched.
  /// Returns true when a stale session was finalized.
  Future<bool> _finalizeStalePaused(DateTime now) async {
    final active = state.activeSession;
    if (active == null || active.resumedAt != null) return false;
    final pauseTime =
        active.lastStudyTime ??
        active.checkInTime.add(Duration(seconds: active.pausedSeconds));
    if (nextStudyResetAt(pauseTime).isAfter(now)) return false;
    var endedAt = pauseTime;
    if (endedAt.isAfter(now)) endedAt = now;
    await _save([
      for (final session in state.sessions)
        if (session.id == active.id)
          StudySession(
            id: session.id,
            subjectId: session.subjectId,
            subjectName: session.subjectName,
            checkInTime: session.checkInTime,
            checkOutTime: endedAt,
            pausedSeconds: session.pausedSeconds,
            carriedSeconds: session.carriedSeconds,
            studySegments: session.studySegments,
            resumedAt: null,
          )
        else
          session,
    ]);
    return true;
  }

  /// Starts the single daily study session immediately. There is no
  /// subject selection: every session is recorded under the shared daily
  /// identity so all charts, attendance, and statistics consume the same
  /// real data against the one daily goal.
  Future<void> startSession({DateTime? checkInTime}) =>
      _enqueue(() => _startSession(checkInTime: checkInTime));

  Future<void> _startSession({DateTime? checkInTime}) async {
    if (!state.isLoaded) {
      throw StateError('Study data is still loading.');
    }
    if (state.error != null) {
      throw StateError('Study data could not be loaded: ${state.error}');
    }
    final checkIn = checkInTime ?? DateTime.now();
    await _finalizeStalePaused(checkIn);
    if (state.activeSession != null) {
      throw StateError('End the active study session before starting another.');
    }
    final session = StudySession(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      subjectId: dailyStudySubjectId,
      subjectName: dailyStudySubjectName,
      checkInTime: checkIn,
      pausedSeconds: 0,
      studySegments: [StudyTimeSegment(startTime: checkIn)],
      resumedAt: checkIn,
    );
    await _save([...state.sessions, session]);
  }

  /// Freeze the active timer and persist banked seconds. The daily total
  /// keeps the saved progress; nothing resets to 0.
  Future<void> pauseSession({DateTime? at}) =>
      _enqueue(() => _pauseSession(at: at));

  Future<void> _pauseSession({DateTime? at}) async {
    if (!state.isLoaded || state.error != null) {
      throw StateError('Study data is not ready.');
    }
    final now = at ?? DateTime.now();
    await _finalizeStalePaused(now);
    final active = state.activeSession;
    if (active == null) {
      throw StateError('There is no active study session.');
    }
    if (active.resumedAt == null) {
      throw StateError('The session is already paused.');
    }
    if (!now.isAfter(active.resumedAt!)) {
      throw StateError('Pause time must be after the session resumed.');
    }
    await _save([
      for (final session in state.sessions)
        if (session.id == active.id)
          StudySession(
            id: session.id,
            subjectId: session.subjectId,
            subjectName: session.subjectName,
            checkInTime: session.checkInTime,
            pausedSeconds:
                session.pausedSeconds +
                now.difference(active.resumedAt!).inSeconds,
            carriedSeconds: session.carriedSeconds,
            studySegments: [
              for (final segment in session.studySegments)
                segment.endTime == null
                    ? StudyTimeSegment(
                        startTime: segment.startTime,
                        endTime: now,
                      )
                    : segment,
            ],
            resumedAt: null,
          )
        else
          session,
    ]);
  }

  /// Resume a paused session from the exact banked elapsed value.
  Future<void> resumeSession({DateTime? at}) =>
      _enqueue(() => _resumeSession(at: at));

  Future<void> _resumeSession({DateTime? at}) async {
    if (!state.isLoaded || state.error != null) {
      throw StateError('Study data is not ready.');
    }
    final now = at ?? DateTime.now();
    await _finalizeStalePaused(now);
    final active = state.activeSession;
    if (active == null) {
      throw StateError('There is no active study session.');
    }
    if (active.resumedAt != null) {
      throw StateError('The session is already running.');
    }
    final lastStudyTime = active.lastStudyTime;
    if (lastStudyTime != null && now.isBefore(lastStudyTime)) {
      throw StateError('Resume time cannot be before the last study time.');
    }
    await _save([
      for (final session in state.sessions)
        if (session.id == active.id)
          StudySession(
            id: session.id,
            subjectId: session.subjectId,
            subjectName: session.subjectName,
            checkInTime: session.checkInTime,
            pausedSeconds: session.pausedSeconds,
            carriedSeconds: session.carriedSeconds,
            studySegments: [
              ...session.studySegments,
              StudyTimeSegment(startTime: now),
            ],
            resumedAt: now,
          )
        else
          session,
    ]);
  }

  /// CHECK IN: the single entry point for the two-button session flow.
  /// - No active session -> starts a new study session (existing
  ///   start logic).
  /// - Paused session -> resumes that same session (existing resume
  ///   logic; no new record).
  /// - Already running -> safe no-op (never a duplicate session).
  /// Rapid repeated taps are serialized, so each tap observes the state
  /// left by the previous one. A successful start/resume also (re)starts
  /// the persistent Live Progress notification from the same timestamps.
  Future<void> checkIn({DateTime? at}) {
    return _enqueue(() async {
      if (!state.isLoaded) {
        throw StateError('Study data is still loading.');
      }
      if (state.error != null) {
        throw StateError('Study data could not be loaded: ${state.error}');
      }
      final stamp = at ?? DateTime.now();
      final active = state.activeSession;
      if (active == null) {
        await _startSession(checkInTime: stamp);
        await _pushLiveTimer(stamp, fresh: true);
      } else if (active.isPaused) {
        await _resumeSession(at: stamp);
        await _pushLiveTimer(stamp, fresh: false);
      }
      // Already running: no-op.
    });
  }

  /// CHECK OUT: pauses a running session immediately using the existing
  /// pause logic (timer stops, duration banked, state persisted), then
  /// pauses the Live Progress notification on the frozen values.
  /// Paused or absent sessions are a safe no-op: no time is added and no
  /// invalid records are created.
  Future<void> checkOut({DateTime? at}) {
    return _enqueue(() async {
      if (!state.isLoaded || state.error != null) {
        throw StateError('Study data is not ready.');
      }
      final active = state.activeSession;
      if (active == null || active.isPaused) return;
      final stamp = at ?? DateTime.now();
      await _pauseSession(at: stamp);
      final today = DateTime(stamp.year, stamp.month, stamp.day);
      var elapsed = 0;
      final end = stamp.isBefore(today)
          ? today
          : stamp; // clamp: same-day portion only
      for (final session in state.sessions) {
        elapsed += session.secondsInRange(today, end, stamp);
      }
      await NotificationService.instance.pauseLiveTimer(
        elapsedSec: elapsed,
        goalMinutes: state.dailyStudyGoalMinutes,
        dayKey: notifDateKey(stamp),
      );
      // No explicit upload here: the ended session is picked up immediately
      // by sessionSyncTriggerProvider, which StudyUpApp keeps alive for the
      // whole app lifetime (watching it only from the startup gate left
      // finished sessions stranded on the device).
    });
  }

  /// Computes foreground-service parameters from the single source of
  /// truth (persisted segments): today's banked seconds strictly before
  /// the live anchor, so the tray and the Home card can never disagree.
  ({int bankedSec, DateTime anchor, String dayKey}) _liveTimerParams(
    DateTime now,
  ) {
    final active = state.activeSession!;
    final today = DateTime(now.year, now.month, now.day);
    var anchor = active.resumedAt ?? now;
    if (anchor.isAfter(now)) anchor = now;
    final end = anchor.isBefore(today) ? today : anchor;
    var banked = 0;
    if (end.isAfter(today)) {
      for (final session in state.sessions) {
        banked += session.secondsInRange(today, end, now);
      }
    }
    return (bankedSec: banked, anchor: anchor, dayKey: notifDateKey(now));
  }

  Future<void> _pushLiveTimer(DateTime now, {required bool fresh}) async {
    final active = state.activeSession;
    if (active == null || active.isPaused) return;
    final params = _liveTimerParams(now);
    final service = NotificationService.instance;
    if (fresh) {
      await service.startLiveTimer(
        bankedTodaySec: params.bankedSec,
        anchorUtc: params.anchor,
        goalMinutes: state.dailyStudyGoalMinutes,
        dayKey: params.dayKey,
      );
    } else {
      await service.updateLiveTimer(
        bankedTodaySec: params.bankedSec,
        anchorUtc: params.anchor,
        goalMinutes: state.dailyStudyGoalMinutes,
        dayKey: params.dayKey,
      );
    }
  }

  Future<void> endSession({DateTime? checkOutTime}) =>
      _enqueue(() => _endSession(checkOutTime: checkOutTime));

  Future<void> _endSession({DateTime? checkOutTime}) async {
    if (!state.isLoaded || state.error != null) {
      throw StateError('Study data is not ready.');
    }
    final endedAt = checkOutTime ?? DateTime.now();
    await _finalizeStalePaused(endedAt);
    final active = state.activeSession;
    if (active == null) {
      throw StateError('There is no active study session.');
    }
    if (!endedAt.isAfter(active.checkInTime)) {
      throw StateError('The end time must be after the check-in time.');
    }
    if (active.resumedAt != null && !endedAt.isAfter(active.resumedAt!)) {
      throw StateError('The end time must be after the session resumed.');
    }
    final finalSeconds = active.durationAt(endedAt).inSeconds;
    await _save([
      for (final session in state.sessions)
        if (session.id == active.id)
          StudySession(
            id: session.id,
            subjectId: session.subjectId,
            subjectName: session.subjectName,
            checkInTime: session.checkInTime,
            checkOutTime: endedAt,
            pausedSeconds: finalSeconds,
            carriedSeconds: session.carriedSeconds,
            studySegments: [
              for (final segment in session.studySegments)
                segment.endTime == null
                    ? StudyTimeSegment(
                        startTime: segment.startTime,
                        endTime: endedAt,
                      )
                    : segment,
            ],
            resumedAt: null,
          )
        else
          session,
    ]);
    // Permanently ended: nothing left to time, so clear the tray entry.
    await NotificationService.instance.cancelLiveTimer();
  }

  Future<void> setDailyStudyGoalMinutes(int minutes) async {
    if (minutes <= 0) throw ArgumentError.value(minutes, 'minutes');
    final preferences = await SharedPreferences.getInstance();
    final saved = await preferences.setInt(_dailyGoalStorageKey, minutes);
    if (!saved) throw StateError('Could not persist the daily study goal.');
    state = state.copyWith(dailyStudyGoalMinutes: minutes);
    // A running timer keeps counting against the new goal: push fresh
    // parameters so the tray progress matches immediately.
    if (state.activeSession?.isRunning ?? false) {
      final now = DateTime.now();
      final params = _liveTimerParams(now);
      unawaited(
        NotificationService.instance.updateLiveTimer(
          bankedTodaySec: params.bankedSec,
          anchorUtc: params.anchor,
          goalMinutes: minutes,
          dayKey: params.dayKey,
        ),
      );
    }
    // Goal change re-evaluates against actual recorded time using the same
    // once-per-day record: lowering the goal after a big study day notifies
    // at most once; raising it simply stops notifying until reached again.
    unawaited(_checkGoalReached(DateTime.now()));
    // XP awards re-derive against the new goal: lowering it can award
    // past days/weeks that now qualify; awards already earned stay.
    unawaited(_syncXp(DateTime.now(), full: true));
  }

  Future<void> _save(List<StudySession> sessions) async {
    final preferences = await SharedPreferences.getInstance();
    final encoded = jsonEncode(
      sessions.map((session) => session.toJson()).toList(),
    );
    final write = _writeQueue.catchError((Object _) {}).then((_) async {
      final saved = await preferences.setString(_storageKey, encoded);
      if (!saved) throw StateError('Could not persist study sessions.');
    });
    _writeQueue = write;
    await write;
    state = state.copyWith(
      sessions: List.unmodifiable(sessions),
      isLoaded: true,
      clearError: true,
    );
    _syncTicker();
    // Daily-goal check runs on the same saved data the charts consume, so
    // timer math, XP awards, and progress displays stay consistent. The
    // service persists the notified day, surviving restarts without
    // re-notifying; the XP ledger does the same for awards.
    unawaited(_checkGoalReached(DateTime.now()));
  }

  /// Serialized XP evaluation: awards newly qualified days/weeks and
  /// persists the ledger only when it actually changed.
  Future<void> _syncXp(DateTime now, {bool full = false}) {
    final next = _xpQueue
        .catchError((Object _) {})
        .then((_) => _syncXpNow(now, full: full));
    _xpQueue = next.catchError((Object _) {});
    return next;
  }

  Future<void> _syncXpNow(DateTime now, {required bool full}) async {
    try {
      // The queue is fire-and-forget: a controller can be disposed while a
      // sync is still pending (tests, provider teardown), so bail quietly.
      if (!mounted) return;
      if (!state.isLoaded || state.error != null) return;
      if (state.dailyStudyGoalMinutes <= 0) return;
      final updated = syncXpAwards(
        ledger: state.xp,
        dailyGoalMinutes: state.dailyStudyGoalMinutes,
        now: now,
        minutesForDay: (day) => state.minutesForDate(day, now: now),
        minutesForWeek: (monday) => state.minutesForWeek(monday, now: now),
        earliestDay: earliestStudyDay(state.sessions, now),
        full: full,
      );
      if (identical(updated, state.xp)) return;
      final preferences = await SharedPreferences.getInstance();
      final saved = await preferences.setString(
        _xpStorageKey,
        jsonEncode(updated.toJson()),
      );
      // Even if persisting fails the awards are safe: a missing/corrupt
      // ledger is rebuilt from the same history on the next full rescan,
      // which yields the identical (deduplicated) award set.
      if (!saved) return;
      // Disposal can happen while the write was in flight; the ledger is
      // already persisted, and a disposed controller has no UI to update.
      if (!mounted) return;
      state = state.copyWith(xp: updated);
    } catch (error, stackTrace) {
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stackTrace,
          library: 'study progress',
          context: ErrorDescription('while updating XP awards'),
        ),
      );
    }
  }

  /// Evaluates today's actual recorded minutes against the shared goal.
  /// Cross-midnight sessions split by the app's real midnight-bucket
  /// aggregation ([minutesForDate]), so each local day notifies at most
  /// once, on the day it actually crosses the goal. Also refreshes the XP
  /// ledger (same ticker cadence), so a day's 10 XP lands the moment the
  /// goal is crossed — from a save or from the throttled 30s tick.
  Future<void> _checkGoalReached(DateTime now) async {
    try {
      await _syncXp(now);
      if (!mounted) return;
      final today = DateTime(now.year, now.month, now.day);
      final minutes = state.minutesForDate(today, now: now);
      final crossed = await NotificationService.instance.maybeNotifyGoalReached(
        minutesToday: minutes,
        goalMinutes: state.dailyStudyGoalMinutes,
        now: now,
      );
      // First crossing of the shared daily goal today: Robo celebrates
      // briefly (self-expiring; see RoboEvents), and the in-app center
      // records its once-per-day goal row.
      if (crossed) {
        RoboEvents.instance.celebrate();
        await NotificationService.instance.recordGoalReached(
          minutesToday: minutes,
          goalMinutes: state.dailyStudyGoalMinutes,
          now: now,
        );
      }
    } catch (error, stackTrace) {
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stackTrace,
          library: 'study progress',
          context: ErrorDescription('while checking the daily goal'),
        ),
      );
    }
  }

  void _syncTicker() {
    _activeTicker?.cancel();
    // Tick only while time actually accrues; paused display stays frozen.
    if (state.activeSession?.resumedAt == null) return;
    var ticks = 0;
    _activeTicker = Timer.periodic(const Duration(seconds: 1), (_) {
      state = state.copyWith();
      // Throttled goal evaluation while a session runs: at most one
      // bookkeeping check per 30s, still gated once-per-day downstream,
      // so long uninterrupted sessions notify without waiting for pause.
      ticks++;
      if (ticks % 30 == 0) unawaited(_checkGoalReached(DateTime.now()));
    });
  }

  @override
  void dispose() {
    _activeTicker?.cancel();
    super.dispose();
  }
}

final studyProgressProvider =
    StateNotifierProvider<StudyProgressController, StudyProgressState>(
      (ref) => StudyProgressController(),
    );
