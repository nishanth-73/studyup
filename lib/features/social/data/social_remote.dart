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
  Future<void> upsertSession(StudySession session) async {
    int totalMinutes = 0;
    for (final seg in session.studySegments) {
      if (seg.endTime != null) {
        totalMinutes += (seg.endTime!.difference(seg.startTime).inSeconds / 60).round();
      }
    }
    if (totalMinutes == 0 && session.studySegments.any((s) => s.endTime != null)) {
      totalMinutes = 1;
    }
    if (totalMinutes <= 0 && session.checkOutTime == null) return;

    await _client.from('sessions').upsert({
      'id': session.id,
      'user_id': _uid,
      'started_at': session.checkInTime.toUtc().toIso8601String(),
      'duration_minutes': totalMinutes > 0 ? totalMinutes : 1,
      'completed': session.checkOutTime != null,
    }, onConflict: 'id');

    // Trigger an activity ping for realtime friend updates
    try {
      await _client.from('activity_pings').insert({
        'user_id': _uid,
      });
    } catch (_) {}
  }
}
