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
final remoteFriendsProvider = FutureProvider<List<RemoteFriend>>((ref) async {
  final remote = ref.watch(socialRemoteProvider);
  if (remote == null) return const [];
  return remote.myFriends();
});

/// Incoming friend requests from the server.
final remoteIncomingProvider = FutureProvider<List<RemoteRequest>>((ref) async {
  final remote = ref.watch(socialRemoteProvider);
  if (remote == null) return const [];
  return remote.incomingRequests();
});

/// Re-subscribes to incoming-request + friendship changes; invalidates
/// the requests, friends, and leaderboard providers so the UI refreshes
/// live (no polling, no session data broadcast).
final remoteRealtimeProvider = Provider<void>((ref) {
  final remote = ref.watch(socialRemoteProvider);
  if (remote == null) return;
  RealtimeChannel? requestsSub;
  RealtimeChannel? friendsSub;
  try {
    requestsSub = remote.subscribeIncomingRequests(() {
      ref.invalidate(remoteIncomingProvider);
      ref.invalidate(remoteFriendsProvider);
    });
    friendsSub = remote.subscribeFriendships(() {
      ref.invalidate(remoteFriendsProvider);
      ref.invalidate(communityDisplayProvider);
    });
  } catch (_) {
    // Realtime unavailable (offline/blocked) — refresh fallbacks apply.
  }
  ref.onDispose(() async {
    for (final sub in [requestsSub, friendsSub]) {
      try {
        await sub?.unsubscribe();
      } catch (_) {}
    }
  });
});

/// Display ranking for the Community screen.
///
/// LIVE (signed in): the accepted-friends board from [leaderboard_scope]
/// for the selected week — real session-backed data, never mixed with
/// demo fixtures or code snapshots. Ranks + movement are computed once
/// here so podium, comparison, and the full list always agree.
///
/// OFFLINE: the existing local path (self sessions + accepted-snapshot
/// friends + clearly-flagged demo fixtures).
final communityDisplayProvider =
    FutureProvider.family<List<LeaderboardEntry>, DateTime>((
      ref,
      weekStart,
    ) async {
      if (ref.watch(socialLiveProvider)) {
        return _remoteBoard(ref, weekStart);
      }
      return _localBoard(ref, weekStart);
    });

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

Future<List<LeaderboardEntry>> _remoteBoard(Ref ref, DateTime weekStart) async {
  final remote = ref.watch(socialRemoteProvider)!;
  final selfId = ref.watch(backendUserIdProvider)!;
  final prevStart = weekStart.subtract(const Duration(days: 7));
  final rows = await remote.leaderboard(weekStart: weekStart);
  final prev = await remote.leaderboard(weekStart: prevStart);
  final current = [
    for (final r in rows)
      LeaderboardEntry(
        memberId: r.userId,
        displayName: r.displayName,
        avatarId: r.avatarId,
        blobVariant: r.blobVariant,
        isSelf: r.userId == selfId,
        weekSeconds: r.weekSeconds,
        // The server lists self and every accepted friend, even at zero,
        // so the list is complete; the UI labels zero rows honestly.
        hasData: r.weekSeconds > 0 || r.userId == selfId,
        rank: 0,
        streakDays: r.streakDays,
        level: computeStudyLevel(r.totalSeconds ~/ 60).level,
      ),
  ];
  final prevRanked = Leaderboard.rank(
    unordered: [
      for (final r in prev)
        if (r.weekSeconds > 0 || r.userId == selfId)
          LeaderboardEntry(
            memberId: r.userId,
            displayName: r.displayName,
            avatarId: r.avatarId,
            blobVariant: r.blobVariant,
            isSelf: r.userId == selfId,
            weekSeconds: r.weekSeconds,
            hasData: true,
            rank: 0,
          ),
    ],
    previousRanks: const {},
  );
  final prevRanks = {
    for (final e in prevRanked.where((e) => e.hasData)) e.memberId: e.rank,
  };
  return Leaderboard.rank(unordered: current, previousRanks: prevRanks);
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

/// Background trigger: uploads newly ended local sessions whenever the
/// study list changes while signed in (kept alive by [StartupGate]).
/// Idempotent — retries and re-syncs never duplicate rows.
final sessionSyncTriggerProvider = Provider<void>((ref) {
  if (!ref.watch(socialLiveProvider)) return;
  final sessions = ref.watch(studyProgressProvider).sessions;
  final remote = ref.watch(socialRemoteProvider);
  if (remote == null) return;
  unawaited(_syncQuietly(ref, remote, sessions));
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

Future<void> _syncQuietly(
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
    notifier.state = notifier.state.copyWith(
      syncing: pending > 0,
      pending: pending,
      lastError: null,
    );
    if (pending == 0) return;
    final service = SessionSyncService(remote);
    final before = (await service.syncedIds()).length;
    await service.syncAll(sessions);
    final after = (await service.syncedIds()).length;
    if (after > before) {
      // New progress reached the server: refresh the friends board so the
      // uploader sees updated numbers without a manual pull. Peers refresh
      // via realtime; this covers the syncing device itself.
      ref.invalidate(communityDisplayProvider);
    }
    notifier.state = SyncStatus(
      pending: pending - (after - before) < 0 ? 0 : pending - (after - before),
      lastOk: DateTime.now(),
    );
  } catch (error) {
    // Offline or server error: keep the backlog visible; the next
    // trigger retries automatically. Never fake success.
    final current = notifier.state;
    notifier.state = current.copyWith(
      syncing: false,
      lastError: error.toString(),
    );
  }
}

/// Pushes queued local sessions after sign-in (explicit guest migration:
/// history uploads under the new account id; nothing is deleted).
Future<String> syncAfterSignIn(WidgetRef ref) async {
  final remote = ref.read(socialRemoteProvider);
  if (remote == null) return 'Backend not connected.';
  try {
    final sessions = ref.read(studyProgressProvider).sessions;
    final count = await SessionSyncService(remote).syncAll(sessions);
    if (count > 0) ref.invalidate(communityDisplayProvider);
    return 'Synced $count session${count == 1 ? '' : 's'}.';
  } catch (_) {
    return 'Sync failed — will retry automatically.';
  }
}
