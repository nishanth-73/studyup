import 'dart:convert';
import 'dart:async';

import 'package:shared_preferences/shared_preferences.dart';

import '../../progress/data/study_session.dart';
import 'social_remote.dart';

/// Uploads locally saved study intervals to Supabase after sign-in and
/// keeps them in sync afterwards. Offline-first: local tracking is authoritative on
/// device; sync is best-effort and idempotent (stable local ids are the
/// server PK, so retries and re-syncs never duplicate rows).
///
/// Pre-auth local history migration is explicit and safe: on first sign-in,
/// ALL local history uploads under the authenticated account id (nothing is
/// deleted locally); later only sessions not yet marked synced upload.
class SessionSyncService {
  SessionSyncService(this._remote);

  final SocialRemote _remote;

  static const _syncedKey = 'studyup.syncedSessionIds.v1';
  static final Map<String, Future<void>> _userQueues = {};
  static final Map<String, Map<String, String>> _uploadedSnapshots = {};

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

  /// Uploads saved study segments, including paused sessions. Concurrent
  /// changes for one account are serialized so a newer snapshot is not lost.
  Future<int> syncAll(List<StudySession> sessions) {
    final userId = _remote.userId;
    return _enqueue(userId, () => _syncAll(sessions));
  }

  Future<int> _syncAll(List<StudySession> sessions) async {
    final userId = _remote.userId;
    final key = _keyFor(userId);
    final synced = await _syncedIdsFor(key);
    final snapshots = _uploadedSnapshots.putIfAbsent(userId, () => {});
    var count = 0;
    final uploaded = <String>[];
    for (final session in sessions) {
      if (session.checkOutTime != null && synced.contains(session.id)) {
        continue;
      }
      final closedSegments = session.studySegments
          .where((segment) => segment.endTime != null)
          .map((segment) => segment.toJson())
          .toList();
      if (closedSegments.isEmpty) continue;
      final snapshot = jsonEncode({
        'checkOutTime': session.checkOutTime?.toUtc().toIso8601String(),
        'segments': closedSegments,
      });
      if (snapshots[session.id] == snapshot) continue;
      await _remote.upsertSession(session);
      if (session.checkOutTime != null) {
        uploaded.add(session.id);
        snapshots.remove(session.id);
      } else {
        snapshots[session.id] = snapshot;
      }
      count++;
    }
    if (uploaded.isNotEmpty) await _markSynced(key, uploaded);
    return count;
  }

  /// Uploads one freshly ended session immediately (best-effort).
  Future<void> syncOne(StudySession session) {
    if (session.checkOutTime == null) return Future<void>.value();
    final userId = _remote.userId;
    return _enqueue(userId, () async {
      final key = _keyFor(userId);
      await _remote.upsertSession(session);
      await _markSynced(key, [session.id]);
    });
  }

  Future<T> _enqueue<T>(String userId, Future<T> Function() operation) {
    final previous = _userQueues[userId] ?? Future<void>.value();
    final task = previous.then<T>((_) => operation());
    final queueTail = task.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    _userQueues[userId] = queueTail;
    unawaited(
      queueTail.whenComplete(() {
        if (identical(_userQueues[userId], queueTail)) {
          _userQueues.remove(userId);
        }
      }),
    );
    return task;
  }
}
