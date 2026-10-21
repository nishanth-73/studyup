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

  /// Idempotent session upload: stable local ids are the PK, so retries
  /// and re-syncs never duplicate rows.
  Future<void> upsertSession(StudySession session) async {
    final segments = [
      for (final s in session.studySegments)
        if (s.endTime != null)
          {
            's': s.startTime.toUtc().toIso8601String(),
            'e': s.endTime!.toUtc().toIso8601String(),
          },
    ];
    if (segments.isEmpty) return;
    await _client.from('study_sessions').upsert({
      'id': session.id,
      'user_id': _uid,
      'subject_id': session.subjectId,
      'subject_name': session.subjectName,
      'check_in': session.checkInTime.toUtc().toIso8601String(),
      'check_out': session.checkOutTime?.toUtc().toIso8601String(),
      'paused_seconds': session.pausedSeconds,
      'segments': segments,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }, onConflict: 'id');
    for (final d in splitSessionDays(session)) {
      await _client.from('session_days').upsert({
        'session_id': session.id,
        'user_id': _uid,
        'day': d['day'],
        'day_start_utc': d['day_start_utc'],
        'seconds': d['seconds'],
      }, onConflict: 'session_id,day');
    }
  }
}
