import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../auth/data/auth_controller.dart';
import '../../avatar/presentation/user_profile_controller.dart';
import '../../progress/data/study_gamification.dart';
import '../../progress/data/study_session.dart';
import '../../progress/presentation/study_progress_controller.dart';
import '../../social/data/social_remote.dart';
import '../../../core/notifications/notification_service.dart';
import '../data/community_models.dart';
import '../data/community_store.dart';

/// Local member id derived from the existing StudyUp profile. Stable per
/// device: verified email when signed in, otherwise the profile name.
String communitySelfIdOf({String? email, String? blobName, String? name}) {
  final e = (email ?? '').trim().toLowerCase();
  if (e.isNotEmpty) return 'u-$e';
  final b = (blobName ?? '').trim().toLowerCase();
  if (b.isNotEmpty) return 'u-$b';
  final n = (name ?? '').trim().toLowerCase();
  if (n.isNotEmpty) return 'u-$n';
  return 'u-local';
}

/// Deduped studied seconds in [start, end) across sessions. Intervals are
/// clamped then merged so overlapping rows can never inflate totals;
/// paused time is excluded by construction (segments only cover active
/// study).
int studiedSecondsInRange(
  List<StudySession> sessions,
  DateTime start,
  DateTime end,
  DateTime now,
) {
  final intervals = <StudyInterval>[];
  for (final s in sessions) {
    for (final seg in s.segmentsAt(now)) {
      final segEnd = seg.endTime ?? now;
      final oStart = seg.startTime.isAfter(start) ? seg.startTime : start;
      final oEnd = segEnd.isBefore(end) ? segEnd : end;
      if (oEnd.isAfter(oStart)) intervals.add(StudyInterval(oStart, oEnd));
    }
  }
  return dedupedSeconds(intervals);
}

/// Distinct local days with at least a minute studied in range.
int activeDaysInRange(
  List<StudySession> sessions,
  DateTime start,
  DateTime end,
  DateTime now,
) {
  var days = 0;
  var day = DateTime(start.year, start.month, start.day);
  final last = DateTime(end.year, end.month, end.day);
  while (day.isBefore(last)) {
    final next = day.add(const Duration(days: 1));
    if (studiedSecondsInRange(sessions, day, next, now) >= 60) days++;
    day = next;
  }
  return days;
}

/// One self row built from the live local session list — the exact same
/// deduped-seconds, streak, and XP-ledger level math the Progress screen's
/// weekly card and level card use. Both the offline board and the live
/// (signed-in) board build self through this helper, so Community can
/// never disagree with Progress, and self needs no server round-trip.
LeaderboardEntry liveSelfLeaderboardEntry({
  required StudyProgressState progress,
  required String memberId,
  required String displayName,
  required String avatarId,
  required int blobVariant,
  required DateTime weekStart,
  required DateTime now,
}) {
  final streak = computeStudyStreak(
    minutesForDay: (day) => progress.minutesForDate(day, now: now),
    today: now,
    earliestDay: earliestStudyDay(progress.sessions, now),
  );
  return LeaderboardEntry(
    memberId: memberId,
    displayName: displayName,
    avatarId: avatarId,
    blobVariant: blobVariant,
    isSelf: true,
    weekSeconds: studiedSecondsInRange(
      progress.sessions,
      weekStart,
      weekStart.add(const Duration(days: 7)),
      now,
    ),
    hasData: true,
    rank: 0,
    streakDays: streak.current,
    level: computeStudyLevel(progress.xp.totalXp).level,
  );
}

final communityStoreProvider = Provider<CommunityStore>(
  (_) => CommunityStore(),
);

/// Self identity resolved from the StudyUp profile.
final communitySelfProvider =
    Provider<({String id, String name, String avatarId, int blob})>((ref) {
      final profile = ref.watch(userProfileProvider).valueOrNull;
      final name = (profile?.displayName ?? '').trim();
      return (
        id: communitySelfIdOf(
          email: profile?.demoEmail,
          blobName: profile?.blobName,
          name: name.isEmpty ? null : name,
        ),
        name: name.isEmpty ? 'Student' : name,
        avatarId: profile?.avatarId ?? 'robo-default',
        blob: profile?.blobVariant ?? 0,
      );
    });

class CommunityController extends StateNotifier<AsyncValue<CommunityData>> {
  final Ref _ref;
  final CommunityStore _store;

  CommunityController(this._ref, this._store)
    : super(const AsyncValue.loading()) {
    _init();
  }

  Future<void> _init() async {
    try {
      await _store.load();
      final self = _ref.read(communitySelfProvider);
      await _store.ensureSelf(
        id: self.id,
        displayName: self.name,
        avatarId: self.avatarId,
        blobVariant: self.blob,
      );
      state = AsyncValue.data(_store.data);
      // Best-effort: keep the server profile row matching the local
      // profile (rename/avatar changes propagate on next open).
      try {
        final userId = _ref.read(backendUserIdProvider);
        if (userId != null) {
          await SocialRemote(Supabase.instance.client).upsertMyProfile(
            displayName: self.name,
            avatarId: self.avatarId,
            blobVariant: self.blob,
          );
        }
      } catch (_) {}
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  Future<void> refresh() async {
    await _store.load();
    state = AsyncValue.data(_store.data);
  }

  void _apply(CommunityData data) {
    state = AsyncValue.data(data);
  }

  Future<void> _notifyIfEnabled({
    required String id,
    required String title,
    required String body,
    required bool allowed,
  }) async {
    if (!allowed) return;
    try {
      await NotificationService.instance.recordCommunityEvent(
        id: id,
        title: title,
        body: body,
      );
    } catch (_) {}
  }

  // ---------- invites / friends ----------

  Future<String> myInviteCode() async {
    final self = _ref.read(communitySelfProvider);
    final progress = _ref.read(studyProgressProvider);
    final now = DateTime.now();
    final bounds = weekBounds(now);
    final seconds = studiedSecondsInRange(
      progress.sessions,
      bounds.start,
      bounds.end,
      now,
    );
    // All-time total + current streak for the podium/comparison (same
    // streak + level math the Progress screen uses).
    final totalSeconds = progress.sessions.fold<int>(
      0,
      (sum, s) => sum + s.durationAt(s.checkOutTime ?? now).inSeconds,
    );
    final streak = computeStudyStreak(
      minutesForDay: (day) => progress.minutesForDate(day, now: now),
      today: now,
      earliestDay: earliestStudyDay(progress.sessions, now),
    );
    final code = await _store.refreshMyInviteCode(
      selfId: self.id,
      displayName: self.name,
      avatarId: self.avatarId,
      blobVariant: self.blob,
      weekSeconds: seconds,
      totalSeconds: totalSeconds,
      streakDays: streak.current,
      now: now,
    );
    state = AsyncValue.data(_store.data);
    return code;
  }

  Future<String?> redeemCode(String code) async {
    final self = _ref.read(communitySelfProvider);
    final out = await _store.stageInviteCode(
      selfId: self.id,
      code: code,
      now: DateTime.now(),
    );
    _apply(out.data);
    return out.error;
  }

  Future<String?> acceptRequest(String requestId) async {
    final self = _ref.read(communitySelfProvider);
    final out = await _store.acceptRequest(
      selfId: self.id,
      requestId: requestId,
    );
    _apply(out.data);
    if (out.ok) {
      await _notifyIfEnabled(
        id: 'community:friend:$requestId',
        title: out.eventTitle ?? 'Friend added',
        body: out.eventBody ?? 'You have a new study buddy.',
        allowed: _store.data.privacy.friendNotifications,
      );
    }
    return out.error;
  }

  Future<String?> declineRequest(String requestId) async {
    final self = _ref.read(communitySelfProvider);
    final out = await _store.declineRequest(
      selfId: self.id,
      requestId: requestId,
    );
    _apply(out.data);
    return out.error;
  }

  Future<String?> removeFriend(String friendId) async {
    final self = _ref.read(communitySelfProvider);
    final out = await _store.removeFriend(selfId: self.id, friendId: friendId);
    _apply(out.data);
    return out.error;
  }

  Future<String?> blockUser(String userId) async {
    final self = _ref.read(communitySelfProvider);
    final out = await _store.blockUser(selfId: self.id, userId: userId);
    _apply(out.data);
    return out.error;
  }

  Future<String?> unblockUser(String userId) async {
    final out = await _store.unblockUser(userId: userId);
    _apply(out.data);
    return out.error;
  }

  Future<String?> reportUser(String userId, String reason) async {
    final self = _ref.read(communitySelfProvider);
    final out = await _store.reportUser(
      selfId: self.id,
      userId: userId,
      reason: reason,
    );
    _apply(out.data);
    if (out.ok) {
      await _notifyIfEnabled(
        id: 'community:report:$userId',
        title: out.eventTitle ?? 'Report received',
        body: out.eventBody ?? 'Thanks for keeping Community safe.',
        allowed: true,
      );
    }
    return out.error;
  }

  // ---------- rooms ----------

  Future<String?> createRoom({
    required String name,
    String? subject,
    int? focusGoalMinutes,
    required List<String> inviteIds,
  }) async {
    final self = _ref.read(communitySelfProvider);
    final out = await _store.createRoom(
      selfId: self.id,
      name: name,
      subject: subject,
      focusGoalMinutes: focusGoalMinutes,
      inviteIds: inviteIds,
      now: DateTime.now(),
    );
    _apply(out.data);
    return out.error;
  }

  /// Joins a room and posts presence. Live status/subject reflect the
  /// real session state AND privacy consent — never guessed.
  Future<String?> joinRoom(String roomId) async {
    final self = _ref.read(communitySelfProvider);
    final progress = _ref.read(studyProgressProvider);
    final active = progress.activeSession;
    final privacy = _store.data.privacy;
    final studying = privacy.shareLiveStatus && active != null;
    String? subject;
    // `studying == true` promotes `active` to non-null via flow analysis.
    if (studying && privacy.shareSubject) {
      subject = active.subjectName;
    }
    final out = await _store.joinRoom(
      selfId: self.id,
      displayName: self.name,
      roomId: roomId,
      studying: studying,
      subject: subject,
      now: DateTime.now(),
    );
    _apply(out.data);
    return out.error;
  }

  Future<void> heartbeat(String roomId) async {
    final self = _ref.read(communitySelfProvider);
    final progress = _ref.read(studyProgressProvider);
    final active = progress.activeSession;
    final privacy = _store.data.privacy;
    final studying = privacy.shareLiveStatus && active != null;
    String? subject;
    // `studying == true` promotes `active` to non-null via flow analysis.
    if (studying && privacy.shareSubject) {
      subject = active.subjectName;
    }
    await _store.heartbeat(
      selfId: self.id,
      roomId: roomId,
      displayName: self.name,
      studying: studying,
      subject: subject,
      now: DateTime.now(),
    );
    state = AsyncValue.data(_store.data);
  }

  Future<void> leaveRoom(String roomId) async {
    final self = _ref.read(communitySelfProvider);
    final out = await _store.leaveRoom(selfId: self.id, roomId: roomId);
    _apply(out.data);
  }

  Future<String?> endRoom(String roomId) async {
    final self = _ref.read(communitySelfProvider);
    final out = await _store.endRoom(selfId: self.id, roomId: roomId);
    _apply(out.data);
    return out.error;
  }

  // ---------- challenges ----------

  Future<String?> createChallenge({
    required String title,
    required ChallengeGoalKind kind,
    required int targetMinutes,
    required int targetDays,
    required DateTime startDay,
    required DateTime endDay,
    required List<String> inviteIds,
  }) async {
    final self = _ref.read(communitySelfProvider);
    final out = await _store.createChallenge(
      selfId: self.id,
      title: title,
      kind: kind,
      targetMinutes: targetMinutes,
      targetDays: targetDays,
      startDay: startDay,
      endDay: endDay,
      inviteIds: inviteIds,
      now: DateTime.now(),
    );
    _apply(out.data);
    if (out.ok) {
      await _notifyIfEnabled(
        id: 'community:challenge-created:${out.data.challenges.last.id}',
        title: out.eventTitle ?? 'Challenge created',
        body: out.eventBody ?? title,
        allowed: _store.data.privacy.challengeNotifications,
      );
    }
    return out.error;
  }

  Future<String?> respondChallenge(String challengeId, bool accept) async {
    final self = _ref.read(communitySelfProvider);
    final out = await _store.respondChallenge(
      selfId: self.id,
      challengeId: challengeId,
      accept: accept,
    );
    _apply(out.data);
    return out.error;
  }

  Future<String?> leaveChallenge(String challengeId) async {
    final self = _ref.read(communitySelfProvider);
    final out = await _store.leaveChallenge(
      selfId: self.id,
      challengeId: challengeId,
    );
    _apply(out.data);
    return out.error;
  }

  Future<String?> deleteChallenge(String challengeId) async {
    final self = _ref.read(communitySelfProvider);
    final out = await _store.deleteChallenge(
      selfId: self.id,
      challengeId: challengeId,
    );
    _apply(out.data);
    return out.error;
  }

  /// Records that a milestone notification was shown, so milestones
  /// never notify twice. Returns true when this fraction is new.
  Future<bool> claimMilestone(String challengeId, int percent) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      const key = 'studyup.community.milestones.v1';
      final raw = prefs.getString(key);
      final map = <String, Object?>{};
      if (raw != null && raw.isNotEmpty) {
        map.addAll(Map<String, Object?>.from(jsonDecode(raw) as Map));
      }
      final seen = ((map[challengeId] as List?) ?? const [])
          .map((e) => (e as num).toInt())
          .toSet();
      if (seen.contains(percent)) return false;
      seen.add(percent);
      map[challengeId] = seen.toList();
      await prefs.setString(key, jsonEncode(map));
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> updatePrivacy(CommunityPrivacy privacy) async {
    await _store.updatePrivacy(privacy);
    state = AsyncValue.data(_store.data);
  }
}

final communityControllerProvider =
    StateNotifierProvider<CommunityController, AsyncValue<CommunityData>>((
      ref,
    ) {
      return CommunityController(ref, ref.watch(communityStoreProvider));
    });

// ---------- selectors ----------

/// Ranked weekly leaderboard. Self uses live deduped session data;
/// friends use shared snapshots only when the snapshot week matches the
/// selected week (otherwise "no shared data" — never guessed).
final leaderboardProvider = Provider.family<List<LeaderboardEntry>, DateTime>((
  ref,
  weekStart,
) {
  final community = ref.watch(communityControllerProvider).valueOrNull;
  final progress = ref.watch(studyProgressProvider);
  final self = ref.watch(communitySelfProvider);
  final now = DateTime.now();
  if (community == null) return const [];
  final prevStart = weekStart.subtract(const Duration(days: 7));
  final selectedKey = weekKeyFor(weekStart);

  int selfSeconds(DateTime s, DateTime e) =>
      studiedSecondsInRange(progress.sessions, s, e, now);

  // Previous-week ranks for movement (only where data exists).
  final prevSeconds = <String, int>{};
  if (community.privacy.leaderboardOptIn) {
    prevSeconds[self.id] = selfSeconds(
      prevStart,
      prevStart.add(const Duration(days: 7)),
    );
  }
  for (final f in community.friends) {
    final m = community.members[f.id];
    if (m?.sharedWeekKey == weekKeyFor(prevStart)) {
      prevSeconds[f.id] = m!.sharedWeekSeconds;
    }
  }
  final prevRanked = prevSeconds.entries.where((e) => e.value > 0).toList()
    ..sort((a, b) => b.value.compareTo(a.value));
  final prevRanks = <String, int>{};
  var pr = 0;
  var pp = 0;
  var plast = -1;
  for (final e in prevRanked) {
    pp++;
    if (e.value != plast) {
      pr = pp;
      plast = e.value;
    }
    prevRanks[e.key] = pr;
  }

  final unordered = <LeaderboardEntry>[];
  if (community.privacy.leaderboardOptIn) {
    // Same helper as the live board: live sessions + XP-ledger level.
    unordered.add(
      liveSelfLeaderboardEntry(
        progress: progress,
        memberId: self.id,
        displayName: self.name,
        avatarId: self.avatarId,
        blobVariant: self.blob,
        weekStart: weekStart,
        now: now,
      ),
    );
  }
  for (final fid in community.friendIds) {
    final m = community.members[fid];
    if (m == null) continue;
    final matches = m.sharedWeekKey == selectedKey;
    unordered.add(
      LeaderboardEntry(
        memberId: m.id,
        displayName: m.displayName,
        avatarId: m.avatarId,
        blobVariant: m.blobVariant,
        isSelf: false,
        weekSeconds: matches ? m.sharedWeekSeconds : 0,
        hasData: matches && m.sharedWeekSeconds > 0,
        rank: 0,
        streakDays: m.sharedStreakDays,
        level: m.sharedTotalSeconds == null
            ? null
            : computeStudyLevel(m.sharedTotalSeconds! ~/ 60).level,
      ),
    );
  }
  return Leaderboard.rank(unordered: unordered, previousRanks: prevRanks);
});

/// Community leaderboard week (Monday 00:00 local). Community always
/// shows the current week; the value is refreshed on foreground resume so
/// an app kept open across Monday rolls over to the new leaderboard.
final communityWeekProvider = StateProvider<DateTime>(
  (ref) => mondayOf(DateTime.now()),
);

/// This-week recap derived from real sessions.
final weeklyRecapProvider = Provider<WeeklyRecap>((ref) {
  final progress = ref.watch(studyProgressProvider);
  final now = DateTime.now();
  final bounds = weekBounds(now);
  final prev = bounds.start.subtract(const Duration(days: 7));
  int dayMinutes(DateTime day) =>
      studiedSecondsInRange(
        progress.sessions,
        day,
        day.add(const Duration(days: 1)),
        now,
      ) ~/
      60;
  var studyDays = 0;
  var bestDay = 0;
  for (var i = 0; i < 7; i++) {
    final m = dayMinutes(bounds.start.add(Duration(days: i)));
    if (m > 0) studyDays++;
    if (m > bestDay) bestDay = m;
  }
  final total =
      studiedSecondsInRange(progress.sessions, bounds.start, bounds.end, now) ~/
      60;
  final previous =
      studiedSecondsInRange(
        progress.sessions,
        prev,
        prev.add(const Duration(days: 7)),
        now,
      ) ~/
      60;
  return WeeklyRecap(
    weekStart: bounds.start,
    totalMinutes: total,
    previousMinutes: previous,
    studyDays: studyDays,
    bestDayMinutes: bestDay,
    hasData: progress.sessions.isNotEmpty,
  );
});

/// Best week ever (for the Personal Record badge).
final bestWeekMinutesProvider = Provider<int>((ref) {
  final progress = ref.watch(studyProgressProvider);
  final now = DateTime.now();
  if (progress.sessions.isEmpty) return 0;
  var first = now;
  // Bound the scan: sessions carry check-in times; use earliest segment.
  for (final s in progress.sessions) {
    if (s.checkInTime.isBefore(first)) first = s.checkInTime;
  }
  var best = 0;
  var start = mondayOf(first);
  final end = mondayOf(now).add(const Duration(days: 7));
  while (!start.isAfter(end)) {
    final m =
        studiedSecondsInRange(
          progress.sessions,
          start,
          start.add(const Duration(days: 7)),
          now,
        ) ~/
        60;
    if (m > best) best = m;
    start = start.add(const Duration(days: 7));
  }
  return best;
});

/// Self progress inside one challenge's range (deduped, bounded).
final challengeProgressProvider = Provider.family<ChallengeProgress, String>((
  ref,
  challengeId,
) {
  final community = ref.watch(communityControllerProvider).valueOrNull;
  final progress = ref.watch(studyProgressProvider);
  final now = DateTime.now();
  final challenge = community?.challenges
      .where((c) => c.id == challengeId)
      .firstOrNull;
  if (challenge == null) {
    return const ChallengeProgress(seconds: 0, activeDays: 0);
  }
  return ChallengeProgress(
    seconds: studiedSecondsInRange(
      progress.sessions,
      challenge.rangeStart,
      challenge.rangeEnd.isAfter(now) ? now : challenge.rangeEnd,
      now,
    ),
    activeDays: activeDaysInRange(
      progress.sessions,
      challenge.rangeStart,
      challenge.rangeEnd.isAfter(now) ? now : challenge.rangeEnd,
      now,
    ),
  );
});
