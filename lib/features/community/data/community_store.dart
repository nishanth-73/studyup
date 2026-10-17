import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'community_models.dart';

/// Full local community snapshot. Single JSON doc, single writer.
@immutable
class CommunityData {
  final Map<String, CommunityMember> members;
  final List<String> friendIds;
  final List<String> blockedIds;
  final List<FriendRequest> incoming;
  final List<FriendRequest> outgoing;
  final List<StudyRoom> rooms;
  final List<RoomPresence> presence;
  final List<Challenge> challenges;
  final CommunityPrivacy privacy;
  final String? myInviteCode;
  final List<String> reports;

  const CommunityData({
    this.members = const {},
    this.friendIds = const [],
    this.blockedIds = const [],
    this.incoming = const [],
    this.outgoing = const [],
    this.rooms = const [],
    this.presence = const [],
    this.challenges = const [],
    this.privacy = const CommunityPrivacy(),
    this.myInviteCode,
    this.reports = const [],
  });

  List<CommunityMember> get friends => [
    for (final id in friendIds)
      if (members[id] != null) members[id]!,
  ];

  List<FriendRequest> get pendingIncoming =>
      incoming.where((r) => r.status == FriendRequestStatus.pending).toList();
  List<FriendRequest> get pendingOutgoing =>
      outgoing.where((r) => r.status == FriendRequestStatus.pending).toList();

  /// Fresh presence per room (stale heartbeats excluded).
  List<RoomPresence> freshPresence(String roomId, DateTime now) =>
      presence.where((p) => p.roomId == roomId && p.isFresh(now)).toList();

  Map<String, Object?> toJson() => {
    'members': members.map((k, v) => MapEntry(k, v.toJson())),
    'friendIds': friendIds,
    'blockedIds': blockedIds,
    'incoming': incoming.map((r) => r.toJson()).toList(),
    'outgoing': outgoing.map((r) => r.toJson()).toList(),
    'rooms': rooms.map((r) => r.toJson()).toList(),
    'presence': presence.map((p) => p.toJson()).toList(),
    'challenges': challenges.map((c) => c.toJson()).toList(),
    'privacy': privacy.toJson(),
    'myInviteCode': myInviteCode,
    'reports': reports,
  };

  factory CommunityData.fromJson(Map<String, Object?> json) {
    final members = <String, CommunityMember>{};
    final rawMembers = json['members'] as Map? ?? const {};
    for (final e in rawMembers.entries) {
      try {
        members[e.key.toString()] = CommunityMember.fromJson(
          Map<String, Object?>.from(e.value as Map),
        );
      } catch (_) {
        // Skip corrupt member rows; never fail the whole doc.
      }
    }
    List<FriendRequest> requests(Object? raw) {
      final out = <FriendRequest>[];
      for (final e in (raw as List<Object?>? ?? const [])) {
        try {
          out.add(FriendRequest.fromJson(Map<String, Object?>.from(e! as Map)));
        } catch (_) {}
      }
      return out;
    }

    return CommunityData(
      members: members,
      friendIds: ((json['friendIds'] as List?) ?? const [])
          .map((e) => e.toString())
          .toList(),
      blockedIds: ((json['blockedIds'] as List?) ?? const [])
          .map((e) => e.toString())
          .toList(),
      incoming: requests(json['incoming']),
      outgoing: requests(json['outgoing']),
      rooms: _parseRooms(json['rooms']),
      presence: _parsePresence(json['presence']),
      challenges: _parseChallenges(json['challenges']),
      privacy: json['privacy'] == null
          ? const CommunityPrivacy()
          : CommunityPrivacy.fromJson(
              Map<String, Object?>.from(json['privacy'] as Map),
            ),
      myInviteCode: json['myInviteCode'] as String?,
      reports: ((json['reports'] as List?) ?? const [])
          .map((e) => e.toString())
          .toList(),
    );
  }
}

List<StudyRoom> _parseRooms(Object? raw) {
  final out = <StudyRoom>[];
  for (final e in (raw as List?) ?? const []) {
    try {
      out.add(StudyRoom.fromJson(Map<String, Object?>.from(e! as Map)));
    } catch (_) {}
  }
  return out;
}

List<RoomPresence> _parsePresence(Object? raw) {
  final out = <RoomPresence>[];
  for (final e in (raw as List?) ?? const []) {
    try {
      out.add(RoomPresence.fromJson(Map<String, Object?>.from(e! as Map)));
    } catch (_) {}
  }
  return out;
}

List<Challenge> _parseChallenges(Object? raw) {
  final out = <Challenge>[];
  for (final e in (raw as List?) ?? const []) {
    try {
      out.add(Challenge.fromJson(Map<String, Object?>.from(e! as Map)));
    } catch (_) {}
  }
  return out;
}

/// Result of a store mutation: updated data or a user-facing error.@immutable
class CommunityOutcome {
  final CommunityData data;
  final String? error;
  final String? eventTitle;
  final String? eventBody;

  const CommunityOutcome(
    this.data, {
    this.error,
    this.eventTitle,
    this.eventBody,
  });

  bool get ok => error == null;
}

/// SharedPreferences-backed community repository.
///
/// Until cloud sync is configured, this device is the source of truth:
/// friendships form through invite-code exchange, and friend study
/// totals come only from snapshots the friend's app shared inside their
/// code — never invented. Every mutation re-validates permissions
/// (self-invite, duplicates, blocked, ownership) before writing, mirroring
/// the Row Level Security rules in supabase/migrations.
class CommunityStore {
  static const storageKey = 'studyup.community.v1';

  CommunityData _data = const CommunityData();
  bool _loaded = false;

  CommunityData get data => _data;

  Future<void> load() async {
    if (_loaded) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(storageKey);
      if (raw != null && raw.isNotEmpty) {
        _data = CommunityData.fromJson(
          Map<String, Object?>.from(jsonDecode(raw) as Map),
        );
      }
    } catch (_) {
      _data = const CommunityData();
    }
    _pruneStalePresence(DateTime.now());
    _loaded = true;
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(storageKey, jsonEncode(_data.toJson()));
  }

  String _newId(String prefix) =>
      '$prefix-${DateTime.now().microsecondsSinceEpoch}';

  void _pruneStalePresence(DateTime now) {
    _data = CommunityData(
      members: _data.members,
      friendIds: _data.friendIds,
      blockedIds: _data.blockedIds,
      incoming: _data.incoming,
      outgoing: _data.outgoing,
      rooms: _data.rooms,
      presence: _data.presence
          .where(
            (p) =>
                p.isFresh(now) ||
                now.difference(p.lastBeatAt).inHours < 24 &&
                    _data.rooms.any((r) => r.id == p.roomId && r.active),
          )
          .toList(),
      challenges: _data.challenges,
      privacy: _data.privacy,
      myInviteCode: _data.myInviteCode,
      reports: _data.reports,
    );
  }

  // ---------- identity ----------

  Future<void> ensureSelf({
    required String id,
    required String displayName,
    required String avatarId,
    required int blobVariant,
  }) async {
    await load();
    final existing = _data.members[id];
    final members = Map<String, CommunityMember>.from(_data.members);
    members[id] = CommunityMember(
      id: id,
      displayName: displayName,
      avatarId: avatarId,
      blobVariant: blobVariant,
      sharedWeekKey: existing?.sharedWeekKey,
      sharedWeekSeconds: existing?.sharedWeekSeconds ?? 0,
      sharedAt: existing?.sharedAt,
    );
    _data = CommunityData(
      members: members,
      friendIds: _data.friendIds,
      blockedIds: _data.blockedIds,
      incoming: _data.incoming,
      outgoing: _data.outgoing,
      rooms: _data.rooms,
      presence: _data.presence,
      challenges: _data.challenges,
      privacy: _data.privacy,
      myInviteCode: _data.myInviteCode,
      reports: _data.reports,
    );
    await _save();
  }

  // ---------- invites ----------

  /// Creates (or refreshes) this device's shareable invite code,
  /// embedding a snapshot of the real current-week total plus the
  /// all-time total and current streak (v2 fields for podium/level).
  Future<String> refreshMyInviteCode({
    required String selfId,
    required String displayName,
    required String avatarId,
    required int blobVariant,
    required int weekSeconds,
    int? totalSeconds,
    int? streakDays,
    required DateTime now,
  }) async {
    await load();
    final code = encodeInviteCode(
      InvitePayload(
        uid: selfId,
        name: displayName,
        avatarId: avatarId,
        blobVariant: blobVariant,
        weekKey: weekKeyFor(now),
        weekSeconds: weekSeconds,
        issuedAt: now,
        totalSeconds: totalSeconds,
        streakDays: streakDays,
      ),
    );
    _data = CommunityData(
      members: _data.members,
      friendIds: _data.friendIds,
      blockedIds: _data.blockedIds,
      incoming: _data.incoming,
      outgoing: _data.outgoing,
      rooms: _data.rooms,
      presence: _data.presence,
      challenges: _data.challenges,
      privacy: _data.privacy,
      myInviteCode: code,
      reports: _data.reports,
    );
    await _save();
    return code;
  }

  /// Validates an entered code and stages it as an incoming request from
  /// the code owner (sharing a code = consent to connect). The user then
  /// accepts or declines it like any request.
  Future<CommunityOutcome> stageInviteCode({
    required String selfId,
    required String code,
    required DateTime now,
  }) async {
    await load();
    final payload = InviteCodec.decode(code, now: now);
    if (payload == null) {
      return CommunityOutcome(
        _data,
        error: 'That code is invalid or expired. Ask for a fresh one.',
      );
    }
    final err = FriendshipRules.canSendRequest(
      selfId: selfId,
      targetId: payload.uid,
      friendIds: _data.friendIds,
      blockedIds: _data.blockedIds,
      blockedByIds: const [],
      openRequests: [..._data.incoming, ..._data.outgoing],
    );
    if (err != null) return CommunityOutcome(_data, error: err);
    // Upsert the sender's public profile + snapshot (public by sharing).
    final members = Map<String, CommunityMember>.from(_data.members);
    members[payload.uid] = CommunityMember(
      id: payload.uid,
      displayName: payload.name,
      avatarId: payload.avatarId,
      blobVariant: payload.blobVariant,
      sharedWeekKey: payload.weekKey,
      sharedWeekSeconds: payload.weekSeconds,
      sharedAt: payload.issuedAt,
      sharedTotalSeconds: payload.totalSeconds,
      sharedStreakDays: payload.streakDays,
    );
    final request = FriendRequest(
      id: _newId('req'),
      fromId: payload.uid,
      fromName: payload.name,
      toId: selfId,
      createdAt: now,
    );
    _data = CommunityData(
      members: members,
      friendIds: _data.friendIds,
      blockedIds: _data.blockedIds,
      incoming: [..._data.incoming, request],
      outgoing: _data.outgoing,
      rooms: _data.rooms,
      presence: _data.presence,
      challenges: _data.challenges,
      privacy: _data.privacy,
      myInviteCode: _data.myInviteCode,
      reports: _data.reports,
    );
    await _save();
    return CommunityOutcome(_data);
  }

  Future<CommunityOutcome> acceptRequest({
    required String selfId,
    required String requestId,
  }) async {
    await load();
    final idx = _data.incoming.indexWhere((r) => r.id == requestId);
    if (idx < 0) return CommunityOutcome(_data, error: 'Request not found.');
    final request = _data.incoming[idx];
    final err = FriendshipRules.canRespond(
      selfId: selfId,
      request: request,
      friendIds: _data.friendIds,
      blockedIds: _data.blockedIds,
    );
    if (err != null) return CommunityOutcome(_data, error: err);
    final incoming = List<FriendRequest>.from(_data.incoming);
    incoming[idx] = FriendRequest(
      id: request.id,
      fromId: request.fromId,
      fromName: request.fromName,
      toId: request.toId,
      status: FriendRequestStatus.accepted,
      createdAt: request.createdAt,
    );
    final friends = List<String>.from(_data.friendIds);
    if (!friends.contains(request.fromId)) friends.add(request.fromId);
    _data = CommunityData(
      members: _data.members,
      friendIds: friends,
      blockedIds: _data.blockedIds,
      incoming: incoming,
      outgoing: _data.outgoing,
      rooms: _data.rooms,
      presence: _data.presence,
      challenges: _data.challenges,
      privacy: _data.privacy,
      myInviteCode: _data.myInviteCode,
      reports: _data.reports,
    );
    await _save();
    return CommunityOutcome(
      _data,
      eventTitle: 'Friend added',
      eventBody: '${request.fromName} is now your study buddy.',
    );
  }

  Future<CommunityOutcome> declineRequest({
    required String selfId,
    required String requestId,
  }) async {
    await load();
    final idx = _data.incoming.indexWhere((r) => r.id == requestId);
    if (idx < 0) return CommunityOutcome(_data, error: 'Request not found.');
    final request = _data.incoming[idx];
    if (request.toId != selfId ||
        request.status != FriendRequestStatus.pending) {
      return CommunityOutcome(_data, error: 'Not authorized.');
    }
    final incoming = List<FriendRequest>.from(_data.incoming);
    incoming[idx] = FriendRequest(
      id: request.id,
      fromId: request.fromId,
      fromName: request.fromName,
      toId: request.toId,
      status: FriendRequestStatus.declined,
      createdAt: request.createdAt,
    );
    _data = CommunityData(
      members: _data.members,
      friendIds: _data.friendIds,
      blockedIds: _data.blockedIds,
      incoming: incoming,
      outgoing: _data.outgoing,
      rooms: _data.rooms,
      presence: _data.presence,
      challenges: _data.challenges,
      privacy: _data.privacy,
      myInviteCode: _data.myInviteCode,
      reports: _data.reports,
    );
    await _save();
    return CommunityOutcome(_data);
  }

  Future<CommunityOutcome> removeFriend({
    required String selfId,
    required String friendId,
  }) async {
    await load();
    if (!_data.friendIds.contains(friendId)) {
      return CommunityOutcome(_data, error: 'Not in your friends list.');
    }
    final friends = List<String>.from(_data.friendIds)..remove(friendId);
    // Retire any open requests between the pair; drop stale presence.
    List<FriendRequest> retire(List<FriendRequest> list) => [
      for (final r in list)
        if (r.status == FriendRequestStatus.pending &&
            ((r.fromId == selfId && r.toId == friendId) ||
                (r.fromId == friendId && r.toId == selfId)))
          FriendRequest(
            id: r.id,
            fromId: r.fromId,
            fromName: r.fromName,
            toId: r.toId,
            status: FriendRequestStatus.cancelled,
            createdAt: r.createdAt,
          )
        else
          r,
    ];
    _data = CommunityData(
      members: _data.members,
      friendIds: friends,
      blockedIds: _data.blockedIds,
      incoming: retire(_data.incoming),
      outgoing: retire(_data.outgoing),
      rooms: _data.rooms,
      presence: _data.presence.where((p) => p.userId != friendId).toList(),
      challenges: _data.challenges,
      privacy: _data.privacy,
      myInviteCode: _data.myInviteCode,
      reports: _data.reports,
    );
    await _save();
    return CommunityOutcome(_data);
  }

  Future<CommunityOutcome> blockUser({
    required String selfId,
    required String userId,
  }) async {
    await load();
    if (userId == selfId) {
      return CommunityOutcome(_data, error: 'You cannot block yourself.');
    }
    final blocked = List<String>.from(_data.blockedIds);
    if (!blocked.contains(userId)) blocked.add(userId);
    final out = await removeFriend(selfId: selfId, friendId: userId);
    // removeFriend errors when not friends — still persist the block.
    final base = out.ok ? out.data : _data;
    _data = CommunityData(
      members: base.members,
      friendIds: base.friendIds,
      blockedIds: blocked,
      incoming: base.incoming,
      outgoing: base.outgoing,
      rooms: base.rooms,
      presence: base.presence,
      challenges: base.challenges,
      privacy: base.privacy,
      myInviteCode: base.myInviteCode,
      reports: base.reports,
    );
    await _save();
    return CommunityOutcome(_data);
  }

  Future<CommunityOutcome> unblockUser({required String userId}) async {
    await load();
    final blocked = List<String>.from(_data.blockedIds)..remove(userId);
    _data = CommunityData(
      members: _data.members,
      friendIds: _data.friendIds,
      blockedIds: blocked,
      incoming: _data.incoming,
      outgoing: _data.outgoing,
      rooms: _data.rooms,
      presence: _data.presence,
      challenges: _data.challenges,
      privacy: _data.privacy,
      myInviteCode: _data.myInviteCode,
      reports: _data.reports,
    );
    await _save();
    return CommunityOutcome(_data);
  }

  /// Queues a moderation report locally. Reviewed when cloud sync is
  /// configured (see supabase/README); the reported user is blocked
  /// immediately on this device.
  Future<CommunityOutcome> reportUser({
    required String selfId,
    required String userId,
    required String reason,
  }) async {
    await load();
    final out = await blockUser(selfId: selfId, userId: userId);
    final base = out.ok ? out.data : _data;
    _data = CommunityData(
      members: base.members,
      friendIds: base.friendIds,
      blockedIds: base.blockedIds,
      incoming: base.incoming,
      outgoing: base.outgoing,
      rooms: base.rooms,
      presence: base.presence,
      challenges: base.challenges,
      privacy: base.privacy,
      myInviteCode: base.myInviteCode,
      reports: [...base.reports, '$userId: ${reason.trim()}'],
    );
    await _save();
    return CommunityOutcome(
      _data,
      eventTitle: 'Report received',
      eventBody: 'Thanks — this report is queued for review.',
    );
  }

  // ---------- rooms ----------

  Future<CommunityOutcome> createRoom({
    required String selfId,
    required String name,
    String? subject,
    int? focusGoalMinutes,
    required List<String> inviteIds,
    required DateTime now,
  }) async {
    await load();
    final err = RoomRules.canCreate(name: name);
    if (err != null) return CommunityOutcome(_data, error: err);
    final invites = inviteIds
        .where((id) => _data.friendIds.contains(id))
        .toSet()
        .toList();
    final room = StudyRoom(
      id: _newId('room'),
      name: name.trim(),
      subject: subject?.trim().isEmpty ?? true ? null : subject!.trim(),
      ownerId: selfId,
      createdAt: now,
      focusGoalMinutes: focusGoalMinutes,
      invitedIds: invites,
    );
    _data = CommunityData(
      members: _data.members,
      friendIds: _data.friendIds,
      blockedIds: _data.blockedIds,
      incoming: _data.incoming,
      outgoing: _data.outgoing,
      rooms: [..._data.rooms, room],
      presence: _data.presence,
      challenges: _data.challenges,
      privacy: _data.privacy,
      myInviteCode: _data.myInviteCode,
      reports: _data.reports,
    );
    await _save();
    return CommunityOutcome(_data);
  }

  Future<CommunityOutcome> joinRoom({
    required String selfId,
    required String displayName,
    required String roomId,
    required bool studying,
    String? subject,
    required DateTime now,
  }) async {
    await load();
    final room = _data.rooms.where((r) => r.id == roomId).firstOrNull;
    if (room == null || !room.active) {
      return CommunityOutcome(_data, error: 'Room is no longer active.');
    }
    final presence = List<RoomPresence>.from(_data.presence)
      ..removeWhere((p) => p.roomId == roomId && p.userId == selfId)
      ..add(
        RoomPresence(
          roomId: roomId,
          userId: selfId,
          displayName: displayName,
          joinedAt: now,
          lastBeatAt: now,
          studying: studying,
          subject: subject,
        ),
      );
    _data = CommunityData(
      members: _data.members,
      friendIds: _data.friendIds,
      blockedIds: _data.blockedIds,
      incoming: _data.incoming,
      outgoing: _data.outgoing,
      rooms: _data.rooms,
      presence: presence,
      challenges: _data.challenges,
      privacy: _data.privacy,
      myInviteCode: _data.myInviteCode,
      reports: _data.reports,
    );
    await _save();
    return CommunityOutcome(_data);
  }

  Future<void> heartbeat({
    required String selfId,
    required String roomId,
    required String displayName,
    required bool studying,
    String? subject,
    required DateTime now,
  }) async {
    await load();
    final idx = _data.presence.indexWhere(
      (p) => p.roomId == roomId && p.userId == selfId,
    );
    if (idx < 0) return;
    final presence = List<RoomPresence>.from(_data.presence);
    final old = presence[idx];
    presence[idx] = RoomPresence(
      roomId: old.roomId,
      userId: old.userId,
      displayName: displayName,
      joinedAt: old.joinedAt,
      lastBeatAt: now,
      studying: studying,
      subject: subject,
    );
    _data = CommunityData(
      members: _data.members,
      friendIds: _data.friendIds,
      blockedIds: _data.blockedIds,
      incoming: _data.incoming,
      outgoing: _data.outgoing,
      rooms: _data.rooms,
      presence: presence,
      challenges: _data.challenges,
      privacy: _data.privacy,
      myInviteCode: _data.myInviteCode,
      reports: _data.reports,
    );
    await _save();
  }

  Future<CommunityOutcome> leaveRoom({
    required String selfId,
    required String roomId,
  }) async {
    await load();
    _data = CommunityData(
      members: _data.members,
      friendIds: _data.friendIds,
      blockedIds: _data.blockedIds,
      incoming: _data.incoming,
      outgoing: _data.outgoing,
      rooms: _data.rooms,
      presence: _data.presence
          .where((p) => !(p.roomId == roomId && p.userId == selfId))
          .toList(),
      challenges: _data.challenges,
      privacy: _data.privacy,
      myInviteCode: _data.myInviteCode,
      reports: _data.reports,
    );
    await _save();
    return CommunityOutcome(_data);
  }

  Future<CommunityOutcome> endRoom({
    required String selfId,
    required String roomId,
  }) async {
    await load();
    final idx = _data.rooms.indexWhere((r) => r.id == roomId);
    if (idx < 0) return CommunityOutcome(_data, error: 'Room not found.');
    final room = _data.rooms[idx];
    if (room.ownerId != selfId) {
      return CommunityOutcome(_data, error: 'Only the host can end a room.');
    }
    final rooms = List<StudyRoom>.from(_data.rooms);
    rooms[idx] = StudyRoom(
      id: room.id,
      name: room.name,
      subject: room.subject,
      ownerId: room.ownerId,
      createdAt: room.createdAt,
      active: false,
      focusGoalMinutes: room.focusGoalMinutes,
      invitedIds: room.invitedIds,
    );
    _data = CommunityData(
      members: _data.members,
      friendIds: _data.friendIds,
      blockedIds: _data.blockedIds,
      incoming: _data.incoming,
      outgoing: _data.outgoing,
      rooms: rooms,
      presence: _data.presence.where((p) => p.roomId != roomId).toList(),
      challenges: _data.challenges,
      privacy: _data.privacy,
      myInviteCode: _data.myInviteCode,
      reports: _data.reports,
    );
    await _save();
    return CommunityOutcome(_data);
  }

  // ---------- challenges ----------

  Future<CommunityOutcome> createChallenge({
    required String selfId,
    required String title,
    required ChallengeGoalKind kind,
    required int targetMinutes,
    required int targetDays,
    required DateTime startDay,
    required DateTime endDay,
    required List<String> inviteIds,
    required DateTime now,
  }) async {
    await load();
    final err = ChallengeRules.validate(
      title: title,
      kind: kind,
      targetMinutes: targetMinutes,
      targetDays: targetDays,
      startDay: startDay,
      endDay: endDay,
    );
    if (err != null) return CommunityOutcome(_data, error: err);
    final participants = <String, ChallengeParticipation>{
      selfId: ChallengeParticipation.accepted,
    };
    for (final id in inviteIds.toSet()) {
      if (id == selfId || !_data.friendIds.contains(id)) continue;
      participants[id] = ChallengeParticipation.invited;
    }
    final challenge = Challenge(
      id: _newId('chg'),
      title: title.trim(),
      goalKind: kind,
      targetMinutes: targetMinutes,
      targetDays: targetDays,
      startDay: startDay,
      endDay: endDay,
      ownerId: selfId,
      createdAt: now,
      participants: participants,
    );
    _data = CommunityData(
      members: _data.members,
      friendIds: _data.friendIds,
      blockedIds: _data.blockedIds,
      incoming: _data.incoming,
      outgoing: _data.outgoing,
      rooms: _data.rooms,
      presence: _data.presence,
      challenges: [..._data.challenges, challenge],
      privacy: _data.privacy,
      myInviteCode: _data.myInviteCode,
      reports: _data.reports,
    );
    await _save();
    return CommunityOutcome(
      _data,
      eventTitle: 'Challenge created',
      eventBody: '${challenge.title} is on.',
    );
  }

  Future<CommunityOutcome> respondChallenge({
    required String selfId,
    required String challengeId,
    required bool accept,
  }) async {
    await load();
    final idx = _data.challenges.indexWhere((c) => c.id == challengeId);
    if (idx < 0) return CommunityOutcome(_data, error: 'Challenge not found.');
    final challenge = _data.challenges[idx];
    if (challenge.participants[selfId] != ChallengeParticipation.invited) {
      return CommunityOutcome(
        _data,
        error: 'No pending invitation for you here.',
      );
    }
    final participants = Map<String, ChallengeParticipation>.from(
      challenge.participants,
    );
    participants[selfId] = accept
        ? ChallengeParticipation.accepted
        : ChallengeParticipation.declined;
    final challenges = List<Challenge>.from(_data.challenges);
    challenges[idx] = Challenge(
      id: challenge.id,
      title: challenge.title,
      goalKind: challenge.goalKind,
      targetMinutes: challenge.targetMinutes,
      targetDays: challenge.targetDays,
      startDay: challenge.startDay,
      endDay: challenge.endDay,
      ownerId: challenge.ownerId,
      createdAt: challenge.createdAt,
      participants: participants,
    );
    _data = CommunityData(
      members: _data.members,
      friendIds: _data.friendIds,
      blockedIds: _data.blockedIds,
      incoming: _data.incoming,
      outgoing: _data.outgoing,
      rooms: _data.rooms,
      presence: _data.presence,
      challenges: challenges,
      privacy: _data.privacy,
      myInviteCode: _data.myInviteCode,
      reports: _data.reports,
    );
    await _save();
    return CommunityOutcome(_data);
  }

  Future<CommunityOutcome> leaveChallenge({
    required String selfId,
    required String challengeId,
  }) async {
    await load();
    final idx = _data.challenges.indexWhere((c) => c.id == challengeId);
    if (idx < 0) return CommunityOutcome(_data, error: 'Challenge not found.');
    final challenge = _data.challenges[idx];
    if (challenge.ownerId == selfId) {
      return CommunityOutcome(
        _data,
        error: 'Owners cannot leave — delete the challenge instead.',
      );
    }
    if (challenge.participants[selfId] == null) {
      return CommunityOutcome(_data, error: 'You are not in this challenge.');
    }
    final participants = Map<String, ChallengeParticipation>.from(
      challenge.participants,
    );
    participants[selfId] = ChallengeParticipation.left;
    final challenges = List<Challenge>.from(_data.challenges);
    challenges[idx] = Challenge(
      id: challenge.id,
      title: challenge.title,
      goalKind: challenge.goalKind,
      targetMinutes: challenge.targetMinutes,
      targetDays: challenge.targetDays,
      startDay: challenge.startDay,
      endDay: challenge.endDay,
      ownerId: challenge.ownerId,
      createdAt: challenge.createdAt,
      participants: participants,
    );
    _data = CommunityData(
      members: _data.members,
      friendIds: _data.friendIds,
      blockedIds: _data.blockedIds,
      incoming: _data.incoming,
      outgoing: _data.outgoing,
      rooms: _data.rooms,
      presence: _data.presence,
      challenges: challenges,
      privacy: _data.privacy,
      myInviteCode: _data.myInviteCode,
      reports: _data.reports,
    );
    await _save();
    return CommunityOutcome(_data);
  }

  Future<CommunityOutcome> deleteChallenge({
    required String selfId,
    required String challengeId,
  }) async {
    await load();
    final idx = _data.challenges.indexWhere((c) => c.id == challengeId);
    if (idx < 0) return CommunityOutcome(_data, error: 'Challenge not found.');
    if (_data.challenges[idx].ownerId != selfId) {
      return CommunityOutcome(
        _data,
        error: 'Only the owner can delete a challenge.',
      );
    }
    if (_data.challenges[idx].isEnded) {
      return CommunityOutcome(
        _data,
        error: 'Completed challenges stay as history.',
      );
    }
    final challenges = List<Challenge>.from(_data.challenges)..removeAt(idx);
    _data = CommunityData(
      members: _data.members,
      friendIds: _data.friendIds,
      blockedIds: _data.blockedIds,
      incoming: _data.incoming,
      outgoing: _data.outgoing,
      rooms: _data.rooms,
      presence: _data.presence,
      challenges: challenges,
      privacy: _data.privacy,
      myInviteCode: _data.myInviteCode,
      reports: _data.reports,
    );
    await _save();
    return CommunityOutcome(_data);
  }

  // ---------- privacy ----------

  Future<void> updatePrivacy(CommunityPrivacy privacy) async {
    await load();
    _data = CommunityData(
      members: _data.members,
      friendIds: _data.friendIds,
      blockedIds: _data.blockedIds,
      incoming: _data.incoming,
      outgoing: _data.outgoing,
      rooms: _data.rooms,
      presence: _data.presence,
      challenges: _data.challenges,
      privacy: privacy,
      myInviteCode: _data.myInviteCode,
      reports: _data.reports,
    );
    await _save();
  }
}
