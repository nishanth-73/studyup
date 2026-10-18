import 'package:shared_preferences/shared_preferences.dart';

import '../../progress/data/study_session.dart';
import 'social_remote.dart';

/// Uploads local study sessions to Supabase after sign-in and keeps them
/// in sync afterwards. Offline-first: local tracking is authoritative on
/// device; sync is best-effort and idempotent (stable local ids are the
/// server PK, so retries and re-syncs never duplicate rows).
///
/// Guest migration is explicit and safe: on first sign-in, ALL local
/// history uploads under the new account id (nothing is deleted
/// locally); later only sessions not yet marked synced upload.
class SessionSyncService {
  SessionSyncService(this._remote);

  final SocialRemote _remote;

  static const _syncedKey = 'studyup.syncedSessionIds.v1';
  static final Set<String> _runningUsers = {};

  String _keyFor(String userId) => '$_syncedKey.$userId';

  Future<Set<String>> _syncedIdsFor(String key) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList(key)?.toSet() ?? {};
  }

  /// Ids already confirmed on the server. Public so UI/providers can
  /// report an honest pending count without re-uploading.
  Future<Set<String>> syncedIds() => _syncedIdsFor(_keyFor(_remote.userId));

  Future<void> _markSynced(String key, Iterable<String> ids) async {
    final prefs = await SharedPreferences.getInstance();
    final current = await _syncedIdsFor(key);
    current.addAll(ids);
    await prefs.setStringList(key, current.toList());
  }

  /// Uploads every ended local session not yet synced. Returns the
  /// number uploaded; throws nothing (callers log).
  Future<int> syncAll(List<StudySession> sessions) async {
    final userId = _remote.userId;
    if (!_runningUsers.add(userId)) return 0;
    final key = _keyFor(userId);
    try {
      final synced = await _syncedIdsFor(key);
      var count = 0;
      for (final s in sessions) {
        if (s.checkOutTime == null || synced.contains(s.id)) continue;
        await _remote.upsertSession(s);
        count++;
      }
      if (count > 0) {
        await _markSynced(
          key,
          sessions
              .where((s) => s.checkOutTime != null && !synced.contains(s.id))
              .map((s) => s.id)
              .take(count),
        );
      }
      return count;
    } finally {
      _runningUsers.remove(userId);
    }
  }

  /// Uploads one freshly ended session immediately (best-effort).
  Future<void> syncOne(StudySession session) async {
    if (session.checkOutTime == null) return;
    final userId = _remote.userId;
    if (!_runningUsers.add(userId)) return;
    final key = _keyFor(userId);
    try {
      await _remote.upsertSession(session);
      await _markSynced(key, [session.id]);
    } finally {
      _runningUsers.remove(userId);
    }
  }
}
