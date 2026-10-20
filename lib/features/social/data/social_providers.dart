import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/backend/supabase_client.dart';
import '../../auth/data/auth_controller.dart';
import '../../community/data/community_demo.dart';
import '../../community/data/community_models.dart';
import '../../community/presentation/community_controller.dart';
import '../../progress/data/study_gamification.dart';
import '../../progress/data/study_session.dart';
import '../../progress/presentation/study_progress_controller.dart';
import 'session_sync.dart';
import 'social_remote.dart';

/// Live when the backend is configured AND the user is signed in.
/// Only then may any server call run; otherwise the app stays on the
/// local/demo path and says so in the UI.
final socialLiveProvider = Provider<bool>((ref) {
  return ref.watch(backendLiveProvider) &&
      ref.watch(backendUserIdProvider) != null;
});

final socialRemoteProvider = Provider<SocialRemote?>((ref) {
  if (!ref.watch(socialLiveProvider)) return null;
  return SocialRemote(Supabase.instance.client);
});

/// Remote for the invitation landing. Unlike [socialRemoteProvider] this
/// also exists BEFORE sign-in: the preview is public, and the accept call
/// authenticates the recipient only when they explicitly tap Accept.
final inviteRemoteProvider = Provider<SocialRemote?>((ref) {
  if (!ref.watch(backendReadyProvider)) return null;
  return SocialRemote(Supabase.instance.client);
});

/// Accepted friends from the server (never demo data).
final remoteFriendsProvider = FutureProvider.autoDispose<List<RemoteFriend>>((
  ref,
) async {
  final remote = ref.watch(socialRemoteProvider);
  if (remote == null) return const [];
  return remote.myFriends();
});

/// Incoming friend requests from the server.
final remoteIncomingProvider = FutureProvider.autoDispose<List<RemoteRequest>>((
  ref,
) async {
  final remote = ref.watch(socialRemoteProvider);
  if (remote == null) return const [];
  return remote.incomingRequests();
});

/// Re-subscribes to incoming-request + friendship changes; invalidates
/// the requests, friends, and leaderboard providers so the UI refreshes
/// live (no polling, no session data broadcast).
final remoteRealtimeProvider = Provider.autoDispose<void>((ref) {
  final remote = ref.watch(socialRemoteProvider);
  if (remote == null) return;
  final subscriptions = <RealtimeChannel>[];
  final connected = <String, bool>{
    'requests': false,
    'friendships': false,
    'progress': false,
  };
  var disposed = false;
  Timer? refreshDebounce;
  Timer? fallbackRefresh;

  void refreshAll() {
    if (disposed) return;
    ref.invalidate(remoteIncomingProvider);
    ref.invalidate(remoteFriendsProvider);
    ref.invalidate(remoteFriendsBoardProvider);
  }

  void scheduleRefresh() {
    if (disposed) return;
    refreshDebounce?.cancel();
    refreshDebounce = Timer(const Duration(milliseconds: 300), refreshAll);
  }

  void updateConnection(
    String key,
    RealtimeSubscribeStatus status,
    Object? error,
  ) {
    if (disposed) return;
    final isConnected = status == RealtimeSubscribeStatus.subscribed;
    connected[key] = isConnected;
    if (isConnected) {
      if (connected.values.every((value) => value)) {
        fallbackRefresh?.cancel();
        fallbackRefresh = null;
      }
      return;
    }

    debugPrint(
      error == null
          ? '[community] realtime $key subscription $status'
          : '[community] realtime $key subscription $status: $error',
    );
    fallbackRefresh ??= Timer.periodic(
      const Duration(seconds: 60),
      (_) => refreshAll(),
    );
    scheduleRefresh();
  }

  try {
    subscriptions.add(
      remote.subscribeIncomingRequests(
        () {
          if (disposed) return;
          ref.invalidate(remoteIncomingProvider);
        },
        onStatus: (status, error) =>
            updateConnection('requests', status, error),
      ),
    );
    subscriptions.add(
      remote.subscribeFriendships(
        () {
          if (disposed) return;
          ref.invalidate(remoteFriendsProvider);
          ref.invalidate(remoteFriendsBoardProvider);
        },
        onStatus: (status, error) =>
            updateConnection('friendships', status, error),
      ),
    );
    subscriptions.add(
      remote.subscribeProgressChanges(
        () {
          if (disposed) return;
          scheduleRefresh();
        },
        onStatus: (status, error) =>
            updateConnection('progress', status, error),
      ),
    );
  } catch (error) {
    debugPrint('[community] could not create realtime subscriptions: $error');
    fallbackRefresh ??= Timer.periodic(
      const Duration(seconds: 60),
      (_) => refreshAll(),
    );
    scheduleRefresh();
  }

  ref.onDispose(() async {
    disposed = true;
    refreshDebounce?.cancel();
    fallbackRefresh?.cancel();
    for (final subscription in subscriptions) {
      try {
        await subscription.unsubscribe();
      } catch (error) {
        debugPrint('[community] realtime unsubscribe failed: $error');
      }
    }
  });
});

/// Display ranking for the Community screen.
///
/// LIVE (signed in): friend rows come from [remoteFriendsBoardProvider]
/// (the friends scope of [leaderboard_scope] — real session-backed data,
/// never mixed with demo fixtures or code snapshots). SELF is always
/// computed locally from the live session list through
/// [liveSelfLeaderboardEntry] — the same single source of truth as the
/// Progress weekly card — so session start/pause/resume/end appear
/// immediately and the board never waits for an upload. Ranks + movement
/// are computed once here so podium, comparison, and the full list always
/// agree.
///
/// OFFLINE: the existing local path (self sessions + accepted-snapshot
/// friends + clearly-flagged demo fixtures).
///
/// autoDispose: leaving and returning to Community refetches fresh server
/// numbers instead of showing a stale cached board.
final communityDisplayProvider = FutureProvider.autoDispose
    .family<List<LeaderboardEntry>, DateTime>((ref, weekStart) async {
      if (ref.watch(socialLiveProvider)) {
        return _remoteBoard(ref, weekStart);
      }
      return _localBoard(ref, weekStart);
    });

/// Friends-only server rows for [weekStart] plus the week before, straight
/// from the friends scope of [leaderboard_scope] (aggregates only). SELF
/// IS NEVER RANKED FROM THIS FETCH: self is local and live, so this layer
/// can stay cached while sessions tick and only refetches on explicit
/// invalidation (friendship changes, sync completions, resume) or on the
/// next Community visit (autoDispose).
final remoteFriendsBoardProvider = FutureProvider.autoDispose
    .family<
      ({List<LeaderboardEntry> current, List<LeaderboardEntry> previous}),
      DateTime
    >((ref, weekStart) async {
      final remote = ref.watch(socialRemoteProvider)!;
      final selfId = ref.watch(backendUserIdProvider)!;
      final rows = await remote.leaderboard(weekStart: weekStart);
      final prev = await remote.leaderboard(
        weekStart: weekStart.subtract(const Duration(days: 7)),
      );
      return (
        current: [
          for (final r in rows)
            if (r.userId != selfId) _friendEntry(r),
        ],
        previous: [
          for (final r in prev)
            if (r.userId != selfId && r.weekSeconds > 0) _friendEntry(r),
        ],
      );
    });

LeaderboardEntry _friendEntry(RemoteBoardRow r) => LeaderboardEntry(
  memberId: r.userId,
  displayName: r.displayName,
  avatarId: r.avatarId,
  blobVariant: r.blobVariant,
  isSelf: false,
  weekSeconds: r.weekSeconds,
  // The server lists every accepted friend, even at zero; zero rows are
  // listed but unranked so "no data this week" is never shown as effort.
  hasData: r.weekSeconds > 0,
  rank: 0,
  streakDays: r.streakDays,
  level: computeStudyLevel(r.totalSeconds ~/ 60).level,
);

LeaderboardEntry _unranked(LeaderboardEntry e) => LeaderboardEntry(
  memberId: e.memberId,
  displayName: e.displayName,
  avatarId: e.avatarId,
  blobVariant: e.blobVariant,
  isSelf: e.isSelf,
  weekSeconds: e.weekSeconds,
  hasData: e.hasData,
  rank: 0,
  streakDays: e.streakDays,
  level: e.level,
);

/// An accepted friend that the leaderboard fetch did not return.
///
/// Friendship is MEMBERSHIP, not progress and not leaderboard consent.
/// `leaderboard_scope('friends')` only returns friends who (a) opted into
/// the leaderboard and (b) logged time in the queried week, so two whole
/// classes of real friends were missing from the Community screen — most
/// visibly the asymmetry reported in production: the sender (who may share
/// no leaderboard totals) was visible to nobody, while the receiver looked
/// fine. Their profile comes from `my_friends()` — a real row, real name,
/// real avatar — with honest zeros, so a friend never disappears because
/// their progress (or their sharing preference) is empty.
LeaderboardEntry _friendWithoutStats(RemoteFriend f) => LeaderboardEntry(
  memberId: f.userId,
  displayName: f.displayName,
  avatarId: f.avatarId,
  blobVariant: f.blobVariant,
  isSelf: false,
  weekSeconds: 0,
  hasData: f.leaderboardOptIn,
  rank: 0,
  streakDays: 0,
  level: computeStudyLevel(0).level,
);

Future<List<LeaderboardEntry>> _remoteBoard(Ref ref, DateTime weekStart) async {
  final base = await ref.watch(remoteFriendsBoardProvider(weekStart).future);
  // Accepted friends, independent of progress. Watching the friendship
  // list here is also what makes a new friend appear on the Community
  // screen as soon as the relationship is created (realtime invalidation,
  // post-accept refresh, or the next visit) without an app restart.
  final friends = await ref.watch(remoteFriendsProvider.future);
  final friendsById = {for (final friend in friends) friend.userId: friend};
  final selfId = ref.watch(backendUserIdProvider)!;
  final self = ref.watch(communitySelfProvider);
  final progress = ref.watch(studyProgressProvider);
  final now = DateTime.now();
  // Live local self — recomputed on every session event and tick, so the
  // board tracks the Progress weekly card exactly, upload or not.
  LeaderboardEntry selfFor(DateTime start) => liveSelfLeaderboardEntry(
    progress: progress,
    memberId: selfId,
    displayName: self.name,
    avatarId: self.avatarId,
    blobVariant: self.blob,
    weekStart: start,
    now: now,
  );
  final withMembers = <LeaderboardEntry>[
    for (final entry in base.current)
      if (friendsById.containsKey(entry.memberId))
        LeaderboardEntry(
          memberId: entry.memberId,
          displayName: entry.displayName,
          avatarId: entry.avatarId,
          blobVariant: entry.blobVariant,
          isSelf: false,
          weekSeconds: entry.weekSeconds,
          hasData: friendsById[entry.memberId]!.leaderboardOptIn,
          rank: 0,
          streakDays: entry.streakDays,
          level: entry.level,
        ),
    for (final f in friends)
      if (f.userId != selfId &&
          !base.current.any((e) => e.memberId == f.userId))
        _friendWithoutStats(f),
  ];
  final prevStart = weekStart.subtract(const Duration(days: 7));
  final prevRanked = Leaderboard.rank(
    unordered: [...base.previous, selfFor(prevStart)],
    previousRanks: const {},
  );
  final prevRanks = {
    for (final e in prevRanked.where((e) => e.hasData)) e.memberId: e.rank,
  };
  return Leaderboard.rank(
    unordered: [selfFor(weekStart), ...withMembers],
    previousRanks: prevRanks,
  );
}

Future<List<LeaderboardEntry>> _localBoard(Ref ref, DateTime weekStart) async {
  final real = ref.watch(leaderboardProvider(weekStart));
  final realPrev = ref.watch(
    leaderboardProvider(weekStart.subtract(const Duration(days: 7))),
  );
  final current = [
    ...real.map(_unranked),
    ...CommunityDemo.demoEntriesForWeek(weekStart),
  ];
  final prev = [
    ...realPrev.where((e) => e.hasData).map(_unranked),
    ...CommunityDemo.demoEntriesForWeek(
      weekStart.subtract(const Duration(days: 7)),
    ),
  ];
  final prevRanked = Leaderboard.rank(unordered: prev, previousRanks: const {});
  final prevRanks = {
    for (final e in prevRanked.where((e) => e.hasData)) e.memberId: e.rank,
  };
  return Leaderboard.rank(unordered: current, previousRanks: prevRanks);
}

/// Background trigger: uploads newly saved closed intervals whenever the
/// study list changes while signed in (kept alive for the app lifetime).
/// Idempotent — retries and re-syncs never duplicate rows.
final sessionSyncTriggerProvider = Provider<void>((ref) {
  if (!ref.watch(socialLiveProvider)) return;
  final sessions = ref.watch(
    studyProgressProvider.select((state) => state.sessions),
  );
  final remote = ref.watch(socialRemoteProvider);
  if (remote == null) return;
  var disposed = false;
  var retryDelay = const Duration(seconds: 15);
  Timer? retryTimer;

  Future<void> sync() async {
    final succeeded = await _syncQuietly(ref, remote, sessions);
    if (disposed) return;
    retryTimer?.cancel();
    if (succeeded) {
      retryDelay = const Duration(seconds: 15);
      return;
    }
    retryTimer = Timer(retryDelay, sync);
    retryDelay = Duration(
      seconds: (retryDelay.inSeconds * 2).clamp(15, 120).toInt(),
    );
  }

  ref.onDispose(() {
    disposed = true;
    retryTimer?.cancel();
  });
  unawaited(sync());
});

/// Honest sync state for the UI: in-flight, unsynced backlog count, and
/// the last failure (cleared on the next success). Never claims server
/// data is present when it is not.
@immutable
class SyncStatus {
  final bool syncing;
  final int pending;
  final String? lastError;
  final DateTime? lastOk;

  const SyncStatus({
    this.syncing = false,
    this.pending = 0,
    this.lastError,
    this.lastOk,
  });

  SyncStatus copyWith({
    bool? syncing,
    int? pending,
    String? lastError,
    DateTime? lastOk,
  }) => SyncStatus(
    syncing: syncing ?? this.syncing,
    pending: pending ?? this.pending,
    lastError: lastError,
    lastOk: lastOk ?? this.lastOk,
  );
}

final syncStatusProvider = StateProvider<SyncStatus>((_) => const SyncStatus());

Future<bool> _syncQuietly(
  Ref ref,
  SocialRemote remote,
  List<StudySession> sessions,
) async {
  final notifier = ref.read(syncStatusProvider.notifier);
  try {
    final synced = await SessionSyncService(remote).syncedIds();
    final pending = sessions
        .where((s) => s.checkOutTime != null && !synced.contains(s.id))
        .length;
    final hasSavedIntervals = sessions.any(
      (session) =>
          session.studySegments.any((segment) => segment.endTime != null),
    );
    notifier.state = notifier.state.copyWith(
      syncing: pending > 0 || hasSavedIntervals,
      pending: pending,
      lastError: null,
    );
    final service = SessionSyncService(remote);
    final uploaded = await service.syncAll(sessions);
    final after = await service.syncedIds();
    if (uploaded > 0) {
      // New progress reached the server: refetch the friends board so the
      // uploader sees freshly shared friend numbers without a manual pull
      // (self is always live locally). Peers refresh via realtime; this
      // covers the syncing device itself.
      ref.invalidate(remoteFriendsBoardProvider);
    }
    final remaining = sessions
        .where((s) => s.checkOutTime != null && !after.contains(s.id))
        .length;
    notifier.state = SyncStatus(
      pending: remaining,
      lastOk: uploaded > 0 ? DateTime.now() : notifier.state.lastOk,
    );
    return true;
  } catch (error) {
    // Offline or server error: retain the backlog; the trigger retries with
    // bounded backoff. Never fake success.
    final current = notifier.state;
    notifier.state = current.copyWith(
      syncing: false,
      lastError: error.toString(),
    );
    return false;
  }
}

/// Pushes queued local sessions after sign-in: local history uploads under
/// the authenticated account id; nothing is deleted.
Future<String> syncAfterSignIn(WidgetRef ref) async {
  final remote = ref.read(socialRemoteProvider);
  if (remote == null) return 'Backend not connected.';
  try {
    final sessions = ref.read(studyProgressProvider).sessions;
    final count = await SessionSyncService(remote).syncAll(sessions);
    if (count > 0) ref.invalidate(remoteFriendsBoardProvider);
    return 'Synced $count session${count == 1 ? '' : 's'}.';
  } catch (_) {
    return 'Sync failed — will retry automatically.';
  }
}
