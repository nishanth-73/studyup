import 'package:supabase_flutter/supabase_flutter.dart';

import '../../progress/data/study_session.dart';

/// Splits one session's segments into per-local-day buckets for the
/// session_days table: [{day: 'yyyy-MM-dd', dayStartUtc, seconds}].
/// Only closed intervals count; a paused session can sync its saved time.
List<Map<String, Object?>> splitSessionDays(StudySession session) {
  final out = <String, Map<String, Object?>>{};
  for (final seg in session.studySegments) {
    final end = seg.endTime;
    if (end == null) continue;
    var cursor = seg.startTime;
    while (cursor.isBefore(end)) {
      final dayStart = DateTime(cursor.year, cursor.month, cursor.day);
      final nextDay = dayStart.add(const Duration(days: 1));
      final sliceEnd = end.isBefore(nextDay) ? end : nextDay;
      final seconds = sliceEnd.difference(cursor).inSeconds;
      if (seconds > 0) {
        final key =
            '${dayStart.year}-${dayStart.month.toString().padLeft(2, '0')}-${dayStart.day.toString().padLeft(2, '0')}';
        final row =
            out[key] ??
            {
              'day': key,
              'day_start_utc': dayStart.toUtc().toIso8601String(),
              'seconds': 0,
            };
        row['seconds'] = (row['seconds']! as int) + seconds;
        out[key] = row;
      }
      cursor = nextDay;
    }
  }
  return out.values.toList();
}

/// Supabase-backed session upload source. Every method assumes an
/// authenticated client; UI gates on backend/auth state first.
class SocialRemote {
  SocialRemote(this._client);

  final SupabaseClient _client;

  String get userId => _uid;

  String get _uid {
    final id = _client.auth.currentUser?.id;
    if (id == null) throw StateError('Not signed in.');
    return id;
  }

  /// Idempotent session upload to the baseline `sessions` table.
  /// Stable local ids are the PK, so retries and re-syncs never duplicate rows.
  /// Splits multi-day intervals into per-calendar-day records using noon UTC
  /// so database aggregation matches Insights date boundaries and timezone rules.
  Future<void> upsertSession(StudySession session) async {
    final now = DateTime.now();
    final checkIn = session.checkInTime;
    final checkOut = session.checkOutTime ?? now;

    var cursor = DateTime(checkIn.year, checkIn.month, checkIn.day);
    final endDay = DateTime(checkOut.year, checkOut.month, checkOut.day);

    final daysToSync = <({String id, String dayKey, int minutes})>[];

    while (!cursor.isAfter(endDay)) {
      final dayStart = cursor;
      final dayEnd = cursor.add(const Duration(days: 1));
      final seconds = session.secondsInRange(dayStart, dayEnd, now);
      final minutes = seconds ~/ 60;
      final dayKey =
          '${cursor.year}-${cursor.month.toString().padLeft(2, '0')}-${cursor.day.toString().padLeft(2, '0')}';

      if (minutes > 0 || (seconds > 0 && session.checkOutTime != null)) {
        final rowId = cursor.isAtSameMomentAs(
                DateTime(checkIn.year, checkIn.month, checkIn.day))
            ? session.id
            : '${session.id}_$dayKey';
        daysToSync.add((
          id: rowId,
          dayKey: dayKey,
          minutes: minutes > 0 ? minutes : 1,
        ));
      }
      cursor = cursor.add(const Duration(days: 1));
    }

    if (daysToSync.isEmpty && session.checkOutTime != null) {
      final dayKey =
          '${checkIn.year}-${checkIn.month.toString().padLeft(2, '0')}-${checkIn.day.toString().padLeft(2, '0')}';
      daysToSync.add((
        id: session.id,
        dayKey: dayKey,
        minutes: 1,
      ));
    }

    for (final item in daysToSync) {
      await _client.from('sessions').upsert({
        'id': item.id,
        'user_id': _uid,
        'started_at': '${item.dayKey}T12:00:00Z',
        'duration_minutes': item.minutes,
        'completed': session.checkOutTime != null,
      }, onConflict: 'id');
    }

    // Trigger an activity ping for realtime friend updates
    try {
      await _client.from('activity_pings').insert({
        'user_id': _uid,
      });
    } catch (_) {}
  }
}
