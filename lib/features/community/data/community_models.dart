import 'dart:convert';

import 'package:flutter/foundation.dart';

/// Pure Community domain: models, weekly math, ranking, challenge progress,
/// recap stats, invite-code codec, and permission validation.
///
/// Everything here is framework-free (no SharedPreferences, no Riverpod)
/// so it stays unit-testable. Persistence lives in [CommunityStore];
/// the local user id is supplied by callers (derived from the existing
/// StudyUp profile), and all "server-side" rules (no self-invite, no
/// duplicates, no unauthorized writes) are enforced both here (pure
/// validators) and in the store before any write.
///
/// Privacy: a [CommunityMember] never carries email, phone, tokens, or
/// auth data — only a display name, avatar styling, and study totals the
/// owner explicitly shared via an invite code snapshot.

/// Monday (local midnight) starting the week that contains [date].
/// Matches the existing StudyUp week policy (see study_progress_controller).
DateTime mondayOf(DateTime date) {
  final day = DateTime(date.year, date.month, date.day);
  return day.subtract(Duration(days: day.weekday - DateTime.monday));
}

/// Inclusive-start Monday key used for week-scoped snapshots.
String weekKeyFor(DateTime date) {
  final m = mondayOf(date);
  return '${m.year}-${m.month.toString().padLeft(2, '0')}-${m.day.toString().padLeft(2, '0')}';
}

/// [start, end) bounds of the week containing [date].
({DateTime start, DateTime end}) weekBounds(DateTime date) {
  final start = mondayOf(date);
  return (start: start, end: start.add(const Duration(days: 7)));
}

/// Short human range label, e.g. "Oct 12 – Oct 18".
String weekRangeLabel(DateTime weekStart) {
  const months = [
    '',
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  final end = weekStart.add(const Duration(days: 6));
  return '${months[weekStart.month]} ${weekStart.day} – ${months[end.month]} ${end.day}';
}

// ---------- interval dedup ----------

/// One closed-open studied interval.
@immutable
class StudyInterval {
  final DateTime start;
  final DateTime end;

  const StudyInterval(this.start, this.end);

  int get seconds => end.isAfter(start) ? end.difference(start).inSeconds : 0;
}

/// Merges overlapping/touching intervals and sums them. Guards against
/// double-counted time when session rows overlap (the single-timer
/// invariant should prevent this, but leaderboard/challenge math must
/// never inflate on corrupt or legacy data).
int dedupedSeconds(Iterable<StudyInterval> intervals) {
  final sorted = intervals.where((i) => i.seconds > 0).toList()
    ..sort((a, b) => a.start.compareTo(b.start));
  var total = 0;
  DateTime? curStart;
  DateTime? curEnd;
  for (final i in sorted) {
    if (curStart == null || curEnd == null) {
      curStart = i.start;
      curEnd = i.end;
    } else if (!i.start.isAfter(curEnd)) {
      if (i.end.isAfter(curEnd)) curEnd = i.end;
    } else {
      total += curEnd.difference(curStart).inSeconds;
      curStart = i.start;
      curEnd = i.end;
    }
  }
  if (curStart != null && curEnd != null) {
    total += curEnd.difference(curStart).inSeconds;
  }
  return total;
}

// ---------- members / friendships ----------

/// Public profile of a community member. No contact info, no tokens.
@immutable
class CommunityMember {
  final String id;
  final String displayName;
  final String avatarId;
  final int blobVariant;

  /// Last snapshot of this member's weekly total, shared via invite-code
  /// exchange. Null = no shared data (never guessed or fabricated).
  final String? sharedWeekKey;
  final int sharedWeekSeconds;
  final DateTime? sharedAt;

  /// All-time snapshot (v2 codes): total seconds studied ever and the
  /// current streak at share time. Drives podium level/streak for
  /// friends; null on older snapshots.
  final int? sharedTotalSeconds;
  final int? sharedStreakDays;

  const CommunityMember({
    required this.id,
    required this.displayName,
    this.avatarId = 'robo-default',
    this.blobVariant = 0,
    this.sharedWeekKey,
    this.sharedWeekSeconds = 0,
    this.sharedAt,
    this.sharedTotalSeconds,
    this.sharedStreakDays,
  });

  /// First letter for avatar fallback rendering.
  String get initial =>
      displayName.trim().isEmpty ? '?' : displayName.trim()[0].toUpperCase();

  Map<String, Object?> toJson() => {
    'id': id,
    'displayName': displayName,
    'avatarId': avatarId,
    'blobVariant': blobVariant,
    'sharedWeekKey': sharedWeekKey,
    'sharedWeekSeconds': sharedWeekSeconds,
    'sharedAt': sharedAt?.toIso8601String(),
    'sharedTotalSeconds': sharedTotalSeconds,
    'sharedStreakDays': sharedStreakDays,
  };

  factory CommunityMember.fromJson(Map<String, Object?> json) =>
      CommunityMember(
        id: json['id']! as String,
        displayName: json['displayName'] as String? ?? 'Study buddy',
        avatarId: json['avatarId'] as String? ?? 'robo-default',
        blobVariant: (json['blobVariant'] as num? ?? 0).toInt(),
        sharedWeekKey: json['sharedWeekKey'] as String?,
        sharedWeekSeconds: (json['sharedWeekSeconds'] as num? ?? 0).toInt(),
        sharedAt: json['sharedAt'] == null
            ? null
            : DateTime.tryParse(json['sharedAt']! as String),
        sharedTotalSeconds: (json['sharedTotalSeconds'] as num?)?.toInt(),
        sharedStreakDays: (json['sharedStreakDays'] as num?)?.toInt(),
      );
}

enum FriendRequestStatus { pending, accepted, declined, cancelled }

/// One directional friend request between two member ids.
@immutable
class FriendRequest {
  final String id;
  final String fromId;
  final String fromName;
  final String toId;
  final FriendRequestStatus status;
  final DateTime createdAt;

  const FriendRequest({
    required this.id,
    required this.fromId,
    required this.fromName,
    required this.toId,
    this.status = FriendRequestStatus.pending,
    required this.createdAt,
  });

  Map<String, Object?> toJson() => {
    'id': id,
    'fromId': fromId,
    'fromName': fromName,
    'toId': toId,
    'status': status.name,
    'createdAt': createdAt.toIso8601String(),
  };

  factory FriendRequest.fromJson(Map<String, Object?> json) {
    FriendRequestStatus status;
    try {
      status = FriendRequestStatus.values.byName(json['status']! as String);
    } catch (_) {
      status = FriendRequestStatus.pending;
    }
    return FriendRequest(
      id: json['id']! as String,
      fromId: json['fromId']! as String,
      fromName: json['fromName'] as String? ?? 'Study buddy',
      toId: json['toId']! as String,
      status: status,
      createdAt:
          DateTime.tryParse(json['createdAt'] as String? ?? '') ??
          DateTime(2000),
    );
  }
}

/// Pure friendship/request permission checks. The store re-checks every
/// one of these before writing (never trust the UI layer alone).
class FriendshipRules {
  /// Error message, or null when the request may be sent.
  static String? canSendRequest({
    required String selfId,
    required String targetId,
    required Iterable<String> friendIds,
    required Iterable<String> blockedIds,
    required Iterable<String> blockedByIds,
    required Iterable<FriendRequest> openRequests,
  }) {
    if (targetId.trim().isEmpty) return 'Invite code is empty.';
    if (targetId == selfId) return 'You cannot invite yourself.';
    if (friendIds.contains(targetId)) return 'You are already friends.';
    if (blockedIds.contains(targetId)) {
      return 'Unblock this user before inviting them.';
    }
    if (blockedByIds.contains(targetId)) {
      return 'This invitation cannot be sent.';
    }
    for (final r in openRequests) {
      if (r.status != FriendRequestStatus.pending) continue;
      final samePair =
          (r.fromId == selfId && r.toId == targetId) ||
          (r.fromId == targetId && r.toId == selfId);
      if (samePair) return 'A request is already pending.';
    }
    return null;
  }

  static String? canRespond({
    required String selfId,
    required FriendRequest request,
    required Iterable<String> friendIds,
    required Iterable<String> blockedIds,
  }) {
    if (request.status != FriendRequestStatus.pending) {
      return 'This request was already handled.';
    }
    if (request.toId != selfId) return 'Not authorized for this request.';
    if (friendIds.contains(request.fromId)) return 'Already friends.';
    if (blockedIds.contains(request.fromId)) return 'User is blocked.';
    return null;
  }
}

// ---------- invite codes ----------

/// Invite-code payload shared between devices. Carries only public data:
/// member id, display name, avatar styling, a snapshot of the sender's
/// current-week study seconds, plus (v2) all-time total seconds and the
/// current streak — all real session data at code time, used for the
/// podium/comparison (level derives from the total via the standard
/// [StudyUp level formula](../progress/data/study_gamification.dart)).
@immutable
class InvitePayload {
  final String uid;
  final String name;
  final String avatarId;
  final int blobVariant;
  final String weekKey;
  final int weekSeconds;
  final DateTime issuedAt;

  /// v2 fields; null when the code was generated by an older app.
  final int? totalSeconds;
  final int? streakDays;

  const InvitePayload({
    required this.uid,
    required this.name,
    required this.avatarId,
    required this.blobVariant,
    required this.weekKey,
    required this.weekSeconds,
    required this.issuedAt,
    this.totalSeconds,
    this.streakDays,
  });

  Map<String, Object?> toJson() => {
    'v': 2,
    'uid': uid,
    'name': name,
    'av': avatarId,
    'bv': blobVariant,
    'wk': weekKey,
    'ws': weekSeconds,
    'ts': issuedAt.toIso8601String(),
    if (totalSeconds != null) 'tt': totalSeconds,
    if (streakDays != null) 'st': streakDays,
  };

  static InvitePayload? tryParse(Map<String, Object?> json) {
    try {
      final version = (json['v'] as num? ?? 0).toInt();
      if (version != 1 && version != 2) return null;
      final uid = (json['uid'] as String? ?? '').trim();
      if (uid.isEmpty) return null;
      return InvitePayload(
        uid: uid,
        name: (json['name'] as String? ?? '').trim().isEmpty
            ? 'Study buddy'
            : (json['name']! as String).trim(),
        avatarId: json['av'] as String? ?? 'robo-default',
        blobVariant: (json['bv'] as num? ?? 0).toInt(),
        weekKey: json['wk'] as String? ?? '',
        weekSeconds: (json['ws'] as num? ?? 0).toInt().clamp(0, 7 * 24 * 3600),
        issuedAt:
            DateTime.tryParse(json['ts'] as String? ?? '') ?? DateTime(2000),
        totalSeconds: (json['tt'] as num?)?.toInt(),
        streakDays: (json['st'] as num?)?.toInt(),
      );
    } catch (_) {
      return null;
    }
  }
}

/// Encodes/decodes shareable invite codes. Codes expire after 30 days;
/// expired or malformed codes are rejected (never silently accepted).
///
/// Encoding is uppercase hex of the JSON payload: unambiguous when
/// hand-copied or sent through case-mangling chats (unlike base64, which
/// is case-sensitive). Dashes are visual grouping only.
class InviteCodec {
  static const String prefix = 'SUP1-';
  static const Duration timeToLive = Duration(days: 30);

  /// Returns the payload, or null when the code is malformed, expired,
  /// or issued in the future.
  static InvitePayload? decode(String code, {required DateTime now}) {
    var text = code
        .trim()
        .toUpperCase()
        .replaceAll(' ', '')
        .replaceAll('-', '');
    if (text.startsWith('SUP1')) text = text.substring(4);
    if (text.isEmpty || text.length.isOdd) return null;
    try {
      final bytes = <int>[];
      for (var i = 0; i < text.length; i += 2) {
        bytes.add(int.parse(text.substring(i, i + 2), radix: 16));
      }
      final payload = InvitePayload.tryParse(
        Map<String, Object?>.from(jsonDecode(utf8.decode(bytes)) as Map),
      );
      if (payload == null) return null;
      if (now.difference(payload.issuedAt) > timeToLive) return null;
      if (payload.issuedAt.isAfter(now.add(const Duration(minutes: 5)))) {
        return null;
      }
      return payload;
    } catch (_) {
      return null;
    }
  }
}

/// Uppercase-hex encoder pairing with [InviteCodec.decode].
String encodeInviteCode(InvitePayload payload) {
  final bytes = utf8.encode(jsonEncode(payload.toJson()));
  final hex = bytes
      .map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase())
      .join();
  final chunks = <String>[];
  for (var i = 0; i < hex.length; i += 4) {
    chunks.add(hex.substring(i, (i + 4).clamp(0, hex.length)));
  }
  return '${InviteCodec.prefix}${chunks.join('-')}';
}

// ---------- leaderboard ----------

/// One ranked leaderboard row.
@immutable
class LeaderboardEntry {
  final String memberId;
  final String displayName;
  final String avatarId;
  final int blobVariant;
  final bool isSelf;

  /// Real studied seconds inside the selected week. Counts only when
  /// backed by data: live sessions for self, a matching-week shared
  /// snapshot for friends. Never estimated.
  final int weekSeconds;

  /// False when the member has not shared progress for this week. In the
  /// live friends board an opted-in member's successful zero is real data.
  final bool hasData;

  /// Current study streak in days (app's standard streak definition).
  /// For friends this is the value embedded in their last invite-code
  /// snapshot; null when unknown.
  final int? streakDays;

  /// StudyUp level from the tier thresholds (100–2,500 XP per level).
  /// Self uses the local XP ledger; for friends the server only shares
  /// all-time total seconds, so their level derives from that total
  /// through the same threshold table; null when unknown.
  final int? level;

  final int rank;
  final int? rankMovement;

  const LeaderboardEntry({
    required this.memberId,
    required this.displayName,
    required this.avatarId,
    required this.blobVariant,
    required this.isSelf,
    required this.weekSeconds,
    required this.hasData,
    required this.rank,
    this.rankMovement,
    this.streakDays,
    this.level,
  });
}

class Leaderboard {
  /// Builds ranked entries from per-member weekly seconds. Members
  /// without data sort last (keeping join order among themselves) and
  /// share no rank number pressure: they are listed unranked after the
  /// ranked rows. Ties share a rank (competition ranking: 1, 2, 2, 4).
  static List<LeaderboardEntry> rank({
    required List<LeaderboardEntry> unordered,
    required Map<String, int> previousRanks,
  }) {
    final withData = unordered.where((e) => e.hasData).toList()
      ..sort((a, b) {
        final c = b.weekSeconds.compareTo(a.weekSeconds);
        if (c != 0) return c;
        return a.displayName.toLowerCase().compareTo(
          b.displayName.toLowerCase(),
        );
      });
    final withoutData = unordered.where((e) => !e.hasData).toList();
    final out = <LeaderboardEntry>[];
    var rank = 0;
    var position = 0;
    var lastSeconds = -1;
    for (final e in withData) {
      position += 1;
      if (e.weekSeconds != lastSeconds) {
        rank = position;
        lastSeconds = e.weekSeconds;
      }
      final prev = previousRanks[e.memberId];
      out.add(
        LeaderboardEntry(
          memberId: e.memberId,
          displayName: e.displayName,
          avatarId: e.avatarId,
          blobVariant: e.blobVariant,
          isSelf: e.isSelf,
          weekSeconds: e.weekSeconds,
          hasData: true,
          rank: rank,
          rankMovement: prev == null ? null : prev - rank,
          streakDays: e.streakDays,
          level: e.level,
        ),
      );
    }
    for (final e in withoutData) {
      out.add(
        LeaderboardEntry(
          memberId: e.memberId,
          displayName: e.displayName,
          avatarId: e.avatarId,
          blobVariant: e.blobVariant,
          isSelf: e.isSelf,
          weekSeconds: 0,
          hasData: false,
          rank: 0,
          streakDays: e.streakDays,
          level: e.level,
        ),
      );
    }
    return out;
  }
}

// ---------- live study rooms ----------

/// A virtual accountability room. Explicitly NOT video/audio/chat —
/// members study in parallel and optionally share live status.
@immutable
class StudyRoom {
  final String id;
  final String name;
  final String? subject;
  final String ownerId;
  final DateTime createdAt;
  final bool active;
  final int? focusGoalMinutes;
  final List<String> invitedIds;

  const StudyRoom({
    required this.id,
    required this.name,
    this.subject,
    required this.ownerId,
    required this.createdAt,
    this.active = true,
    this.focusGoalMinutes,
    this.invitedIds = const [],
  });

  Duration ageAt(DateTime now) =>
      now.isAfter(createdAt) ? now.difference(createdAt) : Duration.zero;

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'subject': subject,
    'ownerId': ownerId,
    'createdAt': createdAt.toIso8601String(),
    'active': active,
    'focusGoalMinutes': focusGoalMinutes,
    'invitedIds': invitedIds,
  };

  factory StudyRoom.fromJson(Map<String, Object?> json) => StudyRoom(
    id: json['id']! as String,
    name: json['name'] as String? ?? 'Study room',
    subject: json['subject'] as String?,
    ownerId: json['ownerId']! as String,
    createdAt:
        DateTime.tryParse(json['createdAt'] as String? ?? '') ?? DateTime(2000),
    active: json['active'] as bool? ?? true,
    focusGoalMinutes: (json['focusGoalMinutes'] as num?)?.toInt(),
    invitedIds: (json['invitedIds'] as List<Object?>? ?? const [])
        .map((e) => e.toString())
        .toList(),
  );
}

/// Heartbeat presence for one member in one room. A presence older than
/// [presenceTtl] is stale and must never render as "studying".
@immutable
class RoomPresence {
  final String roomId;
  final String userId;
  final String displayName;
  final DateTime joinedAt;
  final DateTime lastBeatAt;

  /// True only when the member opted into live sharing AND currently
  /// has an active study session. Subject included only with consent.
  final bool studying;
  final String? subject;

  static const Duration presenceTtl = Duration(seconds: 120);

  const RoomPresence({
    required this.roomId,
    required this.userId,
    required this.displayName,
    required this.joinedAt,
    required this.lastBeatAt,
    this.studying = false,
    this.subject,
  });

  bool isFresh(DateTime now) =>
      !now.difference(lastBeatAt).isNegative &&
      now.difference(lastBeatAt) <= presenceTtl;

  /// Displayable "studying" state: fresh heartbeat + opted in + active.
  bool isLiveStudying(DateTime now) => studying && isFresh(now);

  Map<String, Object?> toJson() => {
    'roomId': roomId,
    'userId': userId,
    'displayName': displayName,
    'joinedAt': joinedAt.toIso8601String(),
    'lastBeatAt': lastBeatAt.toIso8601String(),
    'studying': studying,
    'subject': subject,
  };

  factory RoomPresence.fromJson(Map<String, Object?> json) => RoomPresence(
    roomId: json['roomId']! as String,
    userId: json['userId']! as String,
    displayName: json['displayName'] as String? ?? 'Study buddy',
    joinedAt:
        DateTime.tryParse(json['joinedAt'] as String? ?? '') ?? DateTime(2000),
    lastBeatAt:
        DateTime.tryParse(json['lastBeatAt'] as String? ?? '') ??
        DateTime(2000),
    studying: json['studying'] as bool? ?? false,
    subject: json['subject'] as String?,
  );
}

class RoomRules {
  static String? canCreate({required String name}) {
    if (name.trim().isEmpty) return 'Give your room a name.';
    if (name.trim().length > 48) return 'Keep the name under 48 characters.';
    return null;
  }
}

// ---------- challenges ----------

enum ChallengeGoalKind { hours, days }

enum ChallengeParticipation { invited, accepted, declined, left }

/// A time-boxed group goal. Progress always derives from real study
/// sessions bounded to [startDay, endDay]; never manual or hardcoded.
@immutable
class Challenge {
  final String id;
  final String title;
  final ChallengeGoalKind goalKind;

  /// Hours goal stores whole+fractional hours as minutes for precision.
  final int targetMinutes;
  final int targetDays;
  final DateTime startDay;
  final DateTime endDay;
  final String ownerId;
  final DateTime createdAt;
  final Map<String, ChallengeParticipation> participants;

  const Challenge({
    required this.id,
    required this.title,
    required this.goalKind,
    this.targetMinutes = 0,
    this.targetDays = 0,
    required this.startDay,
    required this.endDay,
    required this.ownerId,
    required this.createdAt,
    this.participants = const {},
  });

  bool get isHours => goalKind == ChallengeGoalKind.hours;

  String get goalLabel => isHours
      ? '${(targetMinutes / 60).toStringAsFixed(targetMinutes % 60 == 0 ? 0 : 1)}h total'
      : '$targetDays day${targetDays == 1 ? '' : 's'}';

  bool get isUpcoming => DateTime.now().isBefore(_dayStart(startDay));
  bool get isEnded => !DateTime.now().isBefore(_dayEnd(endDay));

  static DateTime _dayStart(DateTime d) => DateTime(d.year, d.month, d.day);
  static DateTime _dayEnd(DateTime d) =>
      DateTime(d.year, d.month, d.day).add(const Duration(days: 1));

  DateTime get rangeStart => _dayStart(startDay);
  DateTime get rangeEnd => _dayEnd(endDay);

  Duration get timeLeft {
    final now = DateTime.now();
    if (!now.isBefore(rangeEnd)) return Duration.zero;
    if (now.isBefore(rangeStart)) return rangeEnd.difference(rangeStart);
    return rangeEnd.difference(now);
  }

  int acceptedCount() => participants.values
      .where((s) => s == ChallengeParticipation.accepted)
      .length;

  Map<String, Object?> toJson() => {
    'id': id,
    'title': title,
    'goalKind': goalKind.name,
    'targetMinutes': targetMinutes,
    'targetDays': targetDays,
    'startDay': DateTime(
      startDay.year,
      startDay.month,
      startDay.day,
    ).toIso8601String(),
    'endDay': DateTime(endDay.year, endDay.month, endDay.day).toIso8601String(),
    'ownerId': ownerId,
    'createdAt': createdAt.toIso8601String(),
    'participants': participants.map((k, v) => MapEntry(k, v.name)),
  };

  factory Challenge.fromJson(Map<String, Object?> json) {
    ChallengeGoalKind kind;
    try {
      kind = ChallengeGoalKind.values.byName(json['goalKind']! as String);
    } catch (_) {
      kind = ChallengeGoalKind.hours;
    }
    final parts = <String, ChallengeParticipation>{};
    final rawParts = json['participants'] as Map? ?? const {};
    for (final e in rawParts.entries) {
      try {
        parts[e.key.toString()] = ChallengeParticipation.values.byName(
          e.value.toString(),
        );
      } catch (_) {
        parts[e.key.toString()] = ChallengeParticipation.invited;
      }
    }
    return Challenge(
      id: json['id']! as String,
      title: json['title'] as String? ?? 'Challenge',
      goalKind: kind,
      targetMinutes: (json['targetMinutes'] as num? ?? 0).toInt(),
      targetDays: (json['targetDays'] as num? ?? 0).toInt(),
      startDay:
          DateTime.tryParse(json['startDay'] as String? ?? '') ??
          DateTime.now(),
      endDay:
          DateTime.tryParse(json['endDay'] as String? ?? '') ??
          DateTime.now().add(const Duration(days: 7)),
      ownerId: json['ownerId']! as String,
      createdAt:
          DateTime.tryParse(json['createdAt'] as String? ?? '') ??
          DateTime(2000),
      participants: parts,
    );
  }
}

class ChallengeRules {
  static String? validate({
    required String title,
    required ChallengeGoalKind kind,
    required int targetMinutes,
    required int targetDays,
    required DateTime startDay,
    required DateTime endDay,
  }) {
    if (title.trim().isEmpty) return 'Give your challenge a title.';
    if (title.trim().length > 64) return 'Keep the title under 64 characters.';
    final s = DateTime(startDay.year, startDay.month, startDay.day);
    final e = DateTime(endDay.year, endDay.month, endDay.day);
    if (!e.isAfter(s)) return 'End date must be after the start date.';
    if (e.difference(s).inDays > 365) {
      return 'Keep challenges within a year.';
    }
    if (kind == ChallengeGoalKind.hours) {
      if (targetMinutes < 30) return 'Set at least 30 minutes.';
      if (targetMinutes > 100 * 60) return 'Keep the goal under 100 hours.';
    } else {
      final spanDays = e.difference(s).inDays + 1;
      if (targetDays < 1) return 'Set at least 1 day.';
      if (targetDays > spanDays) {
        return 'Target days cannot exceed the date range.';
      }
    }
    return null;
  }
}

/// Progress of one member in a challenge, from real session intervals.
@immutable
class ChallengeProgress {
  /// Deduped studied seconds inside the challenge range.
  final int seconds;
  final int activeDays;

  const ChallengeProgress({required this.seconds, required this.activeDays});

  double fractionOf(Challenge c) {
    if (c.isHours) {
      if (c.targetMinutes <= 0) return 0;
      return (seconds / 60 / c.targetMinutes).clamp(0.0, 1.0);
    }
    if (c.targetDays <= 0) return 0;
    return (activeDays / c.targetDays).clamp(0.0, 1.0);
  }

  bool isComplete(Challenge c) => fractionOf(c) >= 1.0;
}

// ---------- weekly recap & achievements ----------

@immutable
class WeeklyRecap {
  final DateTime weekStart;
  final int totalMinutes;
  final int previousMinutes;
  final int studyDays;
  final int bestDayMinutes;
  final bool hasData;

  const WeeklyRecap({
    required this.weekStart,
    required this.totalMinutes,
    required this.previousMinutes,
    required this.studyDays,
    required this.bestDayMinutes,
    required this.hasData,
  });

  int get deltaMinutes => totalMinutes - previousMinutes;

  /// Days studied out of 7, as 0..1.
  double get consistency => (studyDays / 7).clamp(0.0, 1.0);
}

@immutable
class Achievement {
  final String id;
  final String title;
  final String description;
  final bool earned;

  const Achievement({
    required this.id,
    required this.title,
    required this.description,
    required this.earned,
  });
}

/// Consistency-first badges: sustainable habits over raw hours.
List<Achievement> buildAchievements({
  required WeeklyRecap recap,
  required bool completedChallenge,
  required int bestWeekMinutes,
}) => [
  Achievement(
    id: 'steady-5',
    title: 'Steady Five',
    description: 'Studied on 5+ days this week.',
    earned: recap.studyDays >= 5,
  ),
  Achievement(
    id: 'perfect-7',
    title: 'Perfect Week',
    description: 'Studied every day this week.',
    earned: recap.studyDays >= 7,
  ),
  Achievement(
    id: 'level-up',
    title: 'Level Up',
    description: 'Beat last week\u2019s total.',
    earned:
        recap.hasData && recap.previousMinutes > 0 && recap.deltaMinutes > 0,
  ),
  Achievement(
    id: 'record-week',
    title: 'Personal Record',
    description: 'Biggest week so far.',
    earned:
        recap.hasData &&
        recap.totalMinutes > 0 &&
        recap.totalMinutes >= bestWeekMinutes,
  ),
  Achievement(
    id: 'challenger',
    title: 'Challenger',
    description: 'Completed a study challenge.',
    earned: completedChallenge,
  ),
];

// ---------- privacy ----------

@immutable
class CommunityPrivacy {
  /// Show my totals on the friends leaderboard.
  final bool leaderboardOptIn;

  /// Share live studying status with friends in rooms.
  final bool shareLiveStatus;

  /// Include current subject alongside live status.
  final bool shareSubject;
  final bool friendNotifications;
  final bool challengeNotifications;

  const CommunityPrivacy({
    this.leaderboardOptIn = true,
    this.shareLiveStatus = false,
    this.shareSubject = false,
    this.friendNotifications = true,
    this.challengeNotifications = true,
  });

  CommunityPrivacy copyWith({
    bool? leaderboardOptIn,
    bool? shareLiveStatus,
    bool? shareSubject,
    bool? friendNotifications,
    bool? challengeNotifications,
  }) => CommunityPrivacy(
    leaderboardOptIn: leaderboardOptIn ?? this.leaderboardOptIn,
    shareLiveStatus: shareLiveStatus ?? this.shareLiveStatus,
    shareSubject: shareSubject ?? this.shareSubject,
    friendNotifications: friendNotifications ?? this.friendNotifications,
    challengeNotifications:
        challengeNotifications ?? this.challengeNotifications,
  );

  Map<String, Object?> toJson() => {
    'leaderboardOptIn': leaderboardOptIn,
    'shareLiveStatus': shareLiveStatus,
    'shareSubject': shareSubject,
    'friendNotifications': friendNotifications,
    'challengeNotifications': challengeNotifications,
  };

  factory CommunityPrivacy.fromJson(Map<String, Object?> json) =>
      CommunityPrivacy(
        leaderboardOptIn: json['leaderboardOptIn'] as bool? ?? true,
        shareLiveStatus: json['shareLiveStatus'] as bool? ?? false,
        shareSubject: json['shareSubject'] as bool? ?? false,
        friendNotifications: json['friendNotifications'] as bool? ?? true,
        challengeNotifications: json['challengeNotifications'] as bool? ?? true,
      );
}

/// Formats seconds as "Hh MMm", e.g. 5h 20m / 45m.
String formatHoursMinutes(int totalSeconds) {
  final m = totalSeconds ~/ 60;
  final h = m ~/ 60;
  final rest = m % 60;
  if (h <= 0) return '${rest}m';
  return '${h}h ${rest.toString().padLeft(2, '0')}m';
}
