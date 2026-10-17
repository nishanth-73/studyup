import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/backend/supabase_config.dart';
import '../../progress/data/study_session.dart';

/// A remote friend (accepted friendship + public profile fields only).
@immutable
class RemoteFriend {
  final String userId;
  final String displayName;
  final String avatarId;
  final int blobVariant;
  final bool leaderboardOptIn;

  const RemoteFriend({
    required this.userId,
    required this.displayName,
    required this.avatarId,
    required this.blobVariant,
    required this.leaderboardOptIn,
  });

  factory RemoteFriend.fromJson(Map<String, dynamic> json) => RemoteFriend(
    userId: json['user_id'] as String,
    displayName: json['display_name'] as String? ?? 'Study buddy',
    avatarId: json['avatar_id'] as String? ?? 'robo-default',
    blobVariant: (json['blob_variant'] as num? ?? 0).toInt(),
    leaderboardOptIn: json['leaderboard_opt_in'] as bool? ?? true,
  );
}

/// One leaderboard row from [leaderboard_scope]: server-computed from
/// validated session data. Streak/level are derived client-side with the
/// standard StudyUp formulas for display.
@immutable
class RemoteBoardRow {
  final String userId;
  final String displayName;
  final String avatarId;
  final int blobVariant;
  final int weekSeconds;
  final int activeDays;
  final int totalSeconds;
  final int streakDays;

  const RemoteBoardRow({
    required this.userId,
    required this.displayName,
    required this.avatarId,
    required this.blobVariant,
    required this.weekSeconds,
    required this.activeDays,
    required this.totalSeconds,
    required this.streakDays,
  });

  factory RemoteBoardRow.fromJson(Map<String, dynamic> json) => RemoteBoardRow(
    userId: json['user_id'] as String,
    displayName: json['display_name'] as String? ?? 'Study buddy',
    avatarId: json['avatar_id'] as String? ?? 'robo-default',
    blobVariant: (json['blob_variant'] as num? ?? 0).toInt(),
    weekSeconds: (json['week_seconds'] as num? ?? 0).toInt(),
    activeDays: (json['active_days'] as num? ?? 0).toInt(),
    totalSeconds: (json['total_seconds'] as num? ?? 0).toInt(),
    streakDays: (json['streak_days'] as num? ?? 0).toInt(),
  );
}

/// Incoming friend request (someone asking to connect with me).
@immutable
class RemoteRequest {
  final String id;
  final String fromId;
  final String fromName;
  final DateTime createdAt;

  const RemoteRequest({
    required this.id,
    required this.fromId,
    required this.fromName,
    required this.createdAt,
  });
}

/// Invitation preview (public fields only — safe before login).
@immutable
class InvitePreview {
  final String displayName;
  final String avatarId;
  final bool valid;
  final String reason; // ok | invalid | expired | revoked | accepted

  const InvitePreview({
    required this.displayName,
    required this.avatarId,
    required this.valid,
    required this.reason,
  });
}

/// Generates an unpredictable 256-bit invitation secret (hex).
String newInviteToken() {
  final random = Random.secure();
  final bytes = List<int>.generate(32, (_) => random.nextInt(256));
  return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
}

/// SHA-256 hex of a raw token — what is stored/transmitted server-side.
String hashInviteToken(String raw) =>
    sha256.convert(utf8.encode(raw)).toString();

/// Builds the shareable invitation URL for a raw token.
String inviteLinkFor(String rawToken, {String? host}) {
  final h = (host ?? SupabaseConfig.inviteHost).trim();
  return 'https://$h/i/$rawToken';
}

/// Parses an invitation token from an incoming link. Accepts an App Link
/// of the form `https://HOST/i/TOKEN` (any host — the token matters) and
/// the custom scheme `studyup://invite/TOKEN` (or `/i/TOKEN`).
/// Returns null for anything else (never throws).
String? parseInviteToken(Uri uri) {
  try {
    if (uri.scheme == SupabaseConfig.inviteScheme || uri.scheme == 'studyup') {
      // studyup://invite/<token> or studyup:///i/<token>
      final segs = uri.pathSegments.where((s) => s.isNotEmpty).toList();
      final host = uri.host.toLowerCase();
      if (host == 'invite' || host == 'i') {
        if (segs.isNotEmpty && _looksLikeToken(segs.first)) {
          return segs.first;
        }
        return null;
      }
      if (segs.length >= 2 &&
          (segs[0] == 'invite' || segs[0] == 'i') &&
          _looksLikeToken(segs[1])) {
        return segs[1];
      }
      return null;
    }
    if (uri.scheme == 'https' || uri.scheme == 'http') {
      final segs = uri.pathSegments;
      if (segs.length == 2 && segs[0] == 'i' && _looksLikeToken(segs[1])) {
        return segs[1];
      }
      return null;
    }
    return null;
  } catch (_) {
    return null;
  }
}

bool _looksLikeToken(String s) =>
    s.length >= 32 && s.length <= 128 && RegExp(r'^[0-9a-fA-F]+$').hasMatch(s);

/// Splits one session's segments into per-local-day buckets for the
/// session_days table: [{day: 'yyyy-MM-dd', dayStartUtc, seconds}].
/// Only closed segments count (active sessions sync on checkout).
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

/// Supabase-backed social data source. Every method assumes an
/// authenticated client; UI gates on backend/auth state first.
/// No demo data enters here — demo fixtures stay in CommunityDemo.
class SocialRemote {
  SocialRemote(this._client);

  final SupabaseClient _client;

  String get _uid {
    final id = _client.auth.currentUser?.id;
    if (id == null) throw StateError('Not signed in.');
    return id;
  }

  Future<void> upsertMyProfile({
    required String displayName,
    required String avatarId,
    required int blobVariant,
    bool? leaderboardOptIn,
    bool? shareLiveStatus,
    bool? shareSubject,
  }) async {
    final row = <String, Object?>{
      'id': _uid,
      'display_name': displayName.trim().isEmpty
          ? 'Student'
          : displayName.trim(),
      'avatar_id': avatarId,
      'blob_variant': blobVariant,
    };
    if (leaderboardOptIn != null) {
      row['leaderboard_opt_in'] = leaderboardOptIn;
    }
    if (shareLiveStatus != null) row['share_live_status'] = shareLiveStatus;
    if (shareSubject != null) row['share_subject'] = shareSubject;
    await _client.from('community_profiles').upsert(row, onConflict: 'id');
  }

  Future<List<RemoteFriend>> myFriends() async {
    final rows = await _client.rpc('my_friends');
    final list = (rows as List).cast<Map<String, dynamic>>();
    return [for (final r in list) RemoteFriend.fromJson(r)];
  }

  Future<List<Map<String, dynamic>>> searchUsers(String query) async {
    final rows = await _client.rpc(
      'search_users',
      params: {'p_query': query.trim()},
    );
    return (rows as List).cast<Map<String, dynamic>>();
  }

  Future<void> sendFriendRequest(String toUserId) async {
    if (toUserId == _uid) throw StateError('You cannot invite yourself.');
    await _client.from('friend_requests').insert({
      'from_id': _uid,
      'to_id': toUserId,
    });
  }

  Future<List<RemoteRequest>> incomingRequests() async {
    final rows = await _client
        .from('friend_requests')
        .select('id, from_id, created_at')
        .eq('to_id', _uid)
        .eq('status', 'pending')
        .order('created_at');
    final out = <RemoteRequest>[];
    for (final r in (rows as List).cast<Map<String, dynamic>>()) {
      final profile = await _client
          .from('community_profiles')
          .select('display_name')
          .eq('id', r['from_id'] as String)
          .maybeSingle();
      out.add(
        RemoteRequest(
          id: r['id'] as String,
          fromId: r['from_id'] as String,
          fromName: (profile?['display_name'] as String?) ?? 'Study buddy',
          createdAt: DateTime.parse(r['created_at'] as String),
        ),
      );
    }
    return out;
  }

  Future<List<RemoteRequest>> outgoingRequests() async {
    final rows = await _client
        .from('friend_requests')
        .select('id, to_id, created_at')
        .eq('from_id', _uid)
        .eq('status', 'pending')
        .order('created_at');
    final out = <RemoteRequest>[];
    for (final r in (rows as List).cast<Map<String, dynamic>>()) {
      final profile = await _client
          .from('community_profiles')
          .select('display_name')
          .eq('id', r['to_id'] as String)
          .maybeSingle();
      out.add(
        RemoteRequest(
          id: r['id'] as String,
          fromId: r['to_id'] as String,
          fromName: (profile?['display_name'] as String?) ?? 'Study buddy',
          createdAt: DateTime.parse(r['created_at'] as String),
        ),
      );
    }
    return out;
  }

  /// Accepts (or declines) an incoming request. Acceptance materializes
  /// the friendship server-side via trigger; senders may only cancel.
  Future<void> respondToRequest(String requestId, bool accept) async {
    await _client
        .from('friend_requests')
        .update({'status': accept ? 'accepted' : 'declined'})
        .eq('id', requestId);
  }

  Future<void> cancelRequest(String requestId) async {
    await _client
        .from('friend_requests')
        .update({'status': 'cancelled'})
        .eq('id', requestId);
  }

  Future<void> removeFriend(String friendId) async {
    final low = _uid.compareTo(friendId) < 0 ? _uid : friendId;
    final high = _uid.compareTo(friendId) < 0 ? friendId : _uid;
    await _client
        .from('friendships')
        .delete()
        .eq('user_low', low)
        .eq('user_high', high);
  }

  /// Creates a single/multi-use invitation server-side and returns the
  /// raw token (shown once — only its hash is stored).
  Future<String> createInvitation({int validDays = 7}) async {
    final raw = newInviteToken();
    await _client.rpc(
      'create_invitation',
      params: {
        'p_token_hash': hashInviteToken(raw),
        'p_expires_at': DateTime.now()
            .add(Duration(days: validDays.clamp(1, 30)))
            .toUtc()
            .toIso8601String(),
      },
    );
    return raw;
  }

  Future<InvitePreview> previewInvitation(String rawToken) async {
    final rows = await _client.rpc(
      'invitation_preview',
      params: {'p_token': rawToken},
    );
    final row = (rows as List).cast<Map<String, dynamic>>().first;
    return InvitePreview(
      displayName: row['display_name'] as String? ?? 'Someone',
      avatarId: row['avatar_id'] as String? ?? 'robo-default',
      valid: row['valid'] as bool? ?? false,
      reason: row['reason'] as String? ?? 'invalid',
    );
  }

  /// Accepts an invitation: validates server-side and creates the
  /// friendship atomically. Returns the new friend's display name.
  Future<String> acceptInvitation(String rawToken) async {
    final rows = await _client.rpc(
      'accept_invitation',
      params: {'p_token': rawToken},
    );
    final row = (rows as List).cast<Map<String, dynamic>>().first;
    return row['display_name'] as String? ?? 'Study buddy';
  }

  Future<void> revokeInvitation(String invitationId) async {
    await _client
        .from('invitations')
        .update({'status': 'revoked'})
        .eq('id', invitationId)
        .eq('created_by', _uid);
  }

  /// Idempotent session upload: stable local ids are the PK, so retries
  /// and re-syncs never duplicate rows.
  Future<void> upsertSession(StudySession session) async {
    if (session.checkOutTime == null) return; // active: syncs on checkout.
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
      'check_out': session.checkOutTime!.toUtc().toIso8601String(),
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

  /// Weekly friends board from [leaderboard_scope]: self + accepted
  /// friends, opted-in only, server-computed aggregates. The app exposes
  /// the friends scope only — the public board is intentionally not shown.
  Future<List<RemoteBoardRow>> leaderboard({required DateTime weekStart}) async {
    final start = weekStart.toUtc().toIso8601String();
    final end = weekStart
        .add(const Duration(days: 7))
        .toUtc()
        .toIso8601String();
    final rows = await _client.rpc(
      'leaderboard_scope',
      params: {'p_scope': 'friends', 'p_start': start, 'p_end': end},
    );
    return [
      for (final r in (rows as List).cast<Map<String, dynamic>>())
        RemoteBoardRow.fromJson(r),
    ];
  }

  /// Daily aggregates for streak math (caller + friends + opt-in
  /// strangers per RLS). Returns {day: 'yyyy-MM-dd', seconds: n}.
  Future<List<Map<String, Object>>> dailyRows({
    required String userId,
    required DateTime from,
    required DateTime to,
  }) async {
    String d(DateTime x) =>
        '${x.year}-${x.month.toString().padLeft(2, '0')}-${x.day.toString().padLeft(2, '0')}';
    final rows = await _client.rpc(
      'daily_rows',
      params: {'p_user_id': userId, 'p_from': d(from), 'p_to': d(to)},
    );
    return [
      for (final r in (rows as List).cast<Map<String, dynamic>>())
        <String, Object>{
          'day': r['day'] as String,
          'seconds': (r['seconds'] as num).toInt(),
        },
    ];
  }

  /// Realtime: refresh UI when my incoming requests change.
  RealtimeChannel subscribeIncomingRequests(void Function() onChange) {
    final channel = _client.channel('incoming-requests');
    channel
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'friend_requests',
          callback: (_) => onChange(),
        )
        .subscribe();
    return channel;
  }

  /// Realtime: refresh UI when my friendships change (accept elsewhere,
  /// removal). RLS scopes rows to involved users; the callback carries
  /// no payload, only a refresh signal.
  RealtimeChannel subscribeFriendships(void Function() onChange) {
    final channel = _client.channel('my-friendships');
    channel
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'friendships',
          callback: (_) => onChange(),
        )
        .subscribe();
    return channel;
  }
}
