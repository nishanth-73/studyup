import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:studyup/features/auth/data/auth_controller.dart';
import 'package:studyup/features/community/data/community_models.dart';
import 'package:studyup/features/progress/data/study_gamification.dart';
import 'package:studyup/features/progress/data/study_session.dart';
import 'package:studyup/features/progress/presentation/study_progress_controller.dart';
import 'package:studyup/features/social/data/social_providers.dart';
import 'package:studyup/features/social/data/social_remote.dart';

/// Live (signed-in) Community board contract:
/// - one friends-only board: the client never sends a scope and never
///   falls back to people you are not connected to;
/// - FRIEND rows come from the server; SELF is always built from the live
///   local sessions (the same deduped-seconds/streak/XP-ledger math as the
///   Progress weekly card) — server self rows are ignored, so session
///   start/pause/resume/end show up immediately without any upload;
/// - two weeks are fetched (current + previous) so rank movement works;
/// - server rows carry aggregates only (no tasks, sessions, or emails);
/// - friendship/request realtime events refresh the board and friends.
class _FakeRemote extends SocialRemote {
  _FakeRemote._(this.client) : super(client);

  factory _FakeRemote() => _FakeRemote._(
    SupabaseClient(
      'https://example.supabase.co',
      'test-anon-key',
      // No auth auto-refresh timer inside tests.
      authOptions: const AuthClientOptions(autoRefreshToken: false),
      realtimeClientOptions: const RealtimeClientOptions(
        disconnectOnEmptyChannelsAfter: Duration.zero,
      ),
    ),
  );

  final SupabaseClient client;
  final leaderboardWeeks = <DateTime>[];
  final rowsByWeek = <DateTime, List<RemoteBoardRow>>{};

  /// Accepted friendships, independent of progress. `leaderboard_scope`
  /// only returns friends who studied in the queried week, so this list is
  /// the source of truth for MEMBERSHIP.
  var friends = <RemoteFriend>[];
  int myFriendsCalls = 0;
  int upsertCalls = 0;
  void Function()? friendsChanged;
  void Function()? requestsChanged;

  // The session-sync service keys its "already uploaded" ledger by the
  // authenticated user id; a fake client has none, so supply the one the
  // provider overrides report.
  @override
  String get userId => 'me';

  @override
  Future<void> upsertSession(StudySession session) async {
    upsertCalls++;
  }

  @override
  Future<List<RemoteBoardRow>> leaderboard({
    required DateTime weekStart,
  }) async {
    leaderboardWeeks.add(weekStart);
    return rowsByWeek[weekStart] ?? const [];
  }

  @override
  Future<List<RemoteFriend>> myFriends() async {
    myFriendsCalls++;
    return friends;
  }

  @override
  RealtimeChannel subscribeFriendships(
    void Function() onChange, {
    void Function(RealtimeSubscribeStatus status, Object? error)? onStatus,
  }) {
    friendsChanged = onChange;
    onStatus?.call(RealtimeSubscribeStatus.subscribed, null);
    return client.channel('test-friendships');
  }

  @override
  RealtimeChannel subscribeIncomingRequests(
    void Function() onChange, {
    void Function(RealtimeSubscribeStatus status, Object? error)? onStatus,
  }) {
    requestsChanged = onChange;
    onStatus?.call(RealtimeSubscribeStatus.subscribed, null);
    return client.channel('test-requests');
  }

  @override
  RealtimeChannel subscribeProgressChanges(
    void Function() onChange, {
    void Function(RealtimeSubscribeStatus status, Object? error)? onStatus,
  }) {
    onStatus?.call(RealtimeSubscribeStatus.subscribed, null);
    return client.channel('test-progress');
  }
}

DateTime mondayOf(DateTime d) {
  final day = DateTime(d.year, d.month, d.day);
  return day.subtract(Duration(days: day.weekday - DateTime.monday));
}

ProviderContainer _container(_FakeRemote remote) => ProviderContainer(
  overrides: [
    socialLiveProvider.overrideWithValue(true),
    backendUserIdProvider.overrideWithValue('me'),
    socialRemoteProvider.overrideWithValue(remote),
  ],
);

void main() {
  test(
    'live board fetches current + previous week and maps ranked rows',
    () async {
      SharedPreferences.setMockInitialValues({});
      final week = mondayOf(DateTime.now());
      final prevWeek = week.subtract(const Duration(days: 7));
      final remote = _FakeRemote();
      remote.friends = const [
        RemoteFriend(
          userId: 'f1',
          displayName: 'Nova Friend',
          avatarId: 'avatar2',
          blobVariant: 1,
          leaderboardOptIn: true,
        ),
      ];
      remote.rowsByWeek[week] = const [
        // A stale server self row: local data is empty, so the board must
        // show self at 0 — the ignored server figure would rank self #1.
        RemoteBoardRow(
          userId: 'me',
          displayName: 'Tester',
          avatarId: 'avatar1',
          blobVariant: 0,
          weekSeconds: 999999,
          activeDays: 9,
          totalSeconds: 999999,
          streakDays: 42,
        ),
        RemoteBoardRow(
          userId: 'f1',
          displayName: 'Nova Friend',
          avatarId: 'avatar2',
          blobVariant: 1,
          weekSeconds: 7200,
          activeDays: 2,
          totalSeconds: 7200,
          streakDays: 4,
        ),
      ];
      remote.rowsByWeek[prevWeek] = const [
        RemoteBoardRow(
          userId: 'f1',
          displayName: 'Nova Friend',
          avatarId: 'avatar2',
          blobVariant: 1,
          weekSeconds: 1800,
          activeDays: 1,
          totalSeconds: 5400,
          streakDays: 2,
        ),
      ];
      final container = _container(remote);
      addTearDown(container.dispose);

      // Let the local store finish loading so the board reflects the loaded
      // (empty) session list, and no load completes after teardown.
      final progressSub = container.listen(studyProgressProvider, (_, _) {});
      for (
        var i = 0;
        i < 200 && !container.read(studyProgressProvider).isLoaded;
        i++
      ) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      expect(container.read(studyProgressProvider).isLoaded, isTrue);

      final entries = await container.read(
        communityDisplayProvider(week).future,
      );

      // Current week first, then the previous week — both friends-only.
      expect(remote.leaderboardWeeks, [week, prevWeek]);
      // Friend 7200 (server) outranks self 0 (live local, no sessions yet);
      // the stale server self row is never merged.
      expect(entries.map((e) => e.memberId).toList(), ['f1', 'me']);
      final nova = entries.first;
      expect(nova.displayName, 'Nova Friend');
      expect(nova.isSelf, isFalse);
      expect(nova.rank, 1);
      expect(nova.level, computeStudyLevel(7200 ~/ 60).level);
      final me = entries.last;
      expect(me.isSelf, isTrue);
      expect(me.rank, 2);
      expect(me.weekSeconds, 0);
      expect(me.streakDays, 0);
      expect(me.level, computeStudyLevel(0).level);

      progressSub.close();
    },
  );

  test(
    'live board self is local and live through session events, no upload',
    () async {
      final now = DateTime.now();
      final endedStart = now.subtract(const Duration(hours: 5));
      Map<String, Object?> session({
        required String id,
        required DateTime start,
        DateTime? end,
      }) => {
        'id': id,
        'subjectId': 'general',
        'subjectName': 'Daily Study',
        'checkInTime': start.toIso8601String(),
        'checkOutTime': end?.toIso8601String(),
        'pausedSeconds': 0,
        'studySegments': [
          {
            'startTime': start.toIso8601String(),
            'endTime': end?.toIso8601String(),
          },
        ],
      };
      SharedPreferences.setMockInitialValues({
        'studyup.studySessions.v1': jsonEncode([
          session(
            id: 's-ended',
            start: endedStart,
            end: endedStart.add(const Duration(hours: 1)),
          ),
        ]),
        // Real XP history: level must come from the ledger (150 XP), never
        // from the server's total-seconds approximation.
        'studyup.xpLedger.v1': jsonEncode({
          'days': [
            '2026-09-01',
            '2026-09-02',
            '2026-09-03',
            '2026-09-04',
            '2026-09-05',
            '2026-09-08',
            '2026-09-09',
            '2026-09-10',
            '2026-09-11',
            '2026-09-12',
          ],
          'weeks': ['2026-09-07'],
        }),
      });
      final week = mondayOf(now);
      final prevWeek = week.subtract(const Duration(days: 7));
      final remote = _FakeRemote();
      remote.friends = const [
        RemoteFriend(
          userId: 'f1',
          displayName: 'Nova Friend',
          avatarId: 'avatar2',
          blobVariant: 1,
          leaderboardOptIn: true,
        ),
      ];
      remote.rowsByWeek[week] = const [
        RemoteBoardRow(
          userId: 'me',
          displayName: 'Tester',
          avatarId: 'avatar1',
          blobVariant: 0,
          weekSeconds: 999999,
          activeDays: 9,
          totalSeconds: 999999,
          streakDays: 99,
        ),
        RemoteBoardRow(
          userId: 'f1',
          displayName: 'Nova Friend',
          avatarId: 'avatar2',
          blobVariant: 1,
          weekSeconds: 7200,
          activeDays: 2,
          totalSeconds: 7200,
          streakDays: 4,
        ),
      ];
      remote.rowsByWeek[prevWeek] = const [];
      final container = _container(remote);
      addTearDown(container.dispose);

      final progressSub = container.listen(studyProgressProvider, (_, _) {});
      for (
        var i = 0;
        i < 200 && !container.read(studyProgressProvider).isLoaded;
        i++
      ) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      expect(container.read(studyProgressProvider).isLoaded, isTrue);
      final controller = container.read(studyProgressProvider.notifier);
      final boardSub = container.listen(
        communityDisplayProvider(week),
        (_, _) {},
      );

      Future<LeaderboardEntry> readSelf() async {
        final entries = await container.read(
          communityDisplayProvider(week).future,
        );
        expect(entries.length, 2);
        return entries.firstWhere((e) => e.isSelf);
      }

      // Seeded ended session: 1h local, level from the XP ledger (150 XP),
      // streak 1 — all independent of the stale server self row.
      final seeded = await readSelf();
      expect(seeded.weekSeconds, inInclusiveRange(3595, 3610));
      expect(seeded.streakDays, 1);
      expect(seeded.level, computeStudyLevel(150).level);
      expect(seeded.level, isNot(computeStudyLevel(999999 ~/ 60).level));
      expect(seeded.rank, 2);
      expect(remote.upsertCalls, 0);

      // start → running time joins the board with no upload.
      await controller.startSession();
      await Future<void>.delayed(const Duration(milliseconds: 1100));
      final running = await readSelf();
      expect(running.weekSeconds, greaterThanOrEqualTo(seeded.weekSeconds));

      // pause → the board stops counting; a full second later it is equal.
      await controller.pauseSession();
      await Future<void>.delayed(const Duration(milliseconds: 100));
      final paused = await readSelf();
      await Future<void>.delayed(const Duration(milliseconds: 1100));
      final stillPaused = await readSelf();
      expect(stillPaused.weekSeconds, paused.weekSeconds);

      // resume → counting continues.
      await controller.resumeSession();
      await Future<void>.delayed(const Duration(milliseconds: 1100));
      final resumed = await readSelf();
      expect(resumed.weekSeconds, greaterThan(stillPaused.weekSeconds));

      // end → frozen, still with zero server uploads from this flow.
      await controller.endSession();
      await Future<void>.delayed(const Duration(milliseconds: 100));
      final ended = await readSelf();
      await Future<void>.delayed(const Duration(milliseconds: 1100));
      final stillEnded = await readSelf();
      expect(stillEnded.weekSeconds, ended.weekSeconds);
      expect(remote.upsertCalls, 0);
      // Live self never refetches the friends board (still cached).
      expect(remote.leaderboardWeeks.length, 2);

      boardSub.close();
      progressSub.close();
    },
  );

  test('server rows expose aggregates only — extra fields are ignored', () {
    // Documents the wire contract: even if a private field were ever sent
    // by mistake, it cannot enter the app models (structural, not policy).
    final row = RemoteBoardRow.fromJson(const {
      'user_id': 'u1',
      'display_name': 'A',
      'avatar_id': 'avatar1',
      'blob_variant': 1,
      'week_seconds': 120,
      'active_days': 1,
      'total_seconds': 60,
      'streak_days': 2,
      'email': 'a@b.c',
      'tasks': ['private task'],
      'sessions': [
        {'subject_name': 'Secret'},
      ],
      'segments': [
        {'s': 'x'},
      ],
    });
    expect(row.userId, 'u1');
    expect(row.displayName, 'A');
    expect(row.weekSeconds, 120);
    expect(row.activeDays, 1);
    expect(row.totalSeconds, 60);
    expect(row.streakDays, 2);

    final friend = RemoteFriend.fromJson(const {
      'user_id': 'u2',
      'display_name': 'B',
      'avatar_id': 'avatar2',
      'blob_variant': 0,
      'leaderboard_opt_in': true,
      'email': 'b@c.d',
    });
    expect(friend.userId, 'u2');
    expect(friend.displayName, 'B');
    expect(friend.leaderboardOptIn, isTrue);
  });

  test(
    'friendship changes refetch board; request changes refetch friends',
    () async {
      final week = mondayOf(DateTime.now());
      final remote = _FakeRemote();
      remote.rowsByWeek[week] = const [
        RemoteBoardRow(
          userId: 'f1',
          displayName: 'Nova Friend',
          avatarId: 'avatar2',
          blobVariant: 1,
          weekSeconds: 7200,
          activeDays: 2,
          totalSeconds: 7200,
          streakDays: 4,
        ),
      ];
      remote.rowsByWeek[week.subtract(const Duration(days: 7))] = const [];
      final container = _container(remote);
      addTearDown(container.dispose);

      final boardSub = container.listen(
        communityDisplayProvider(week),
        (_, _) {},
      );
      await container.read(communityDisplayProvider(week).future);
      expect(remote.leaderboardWeeks.length, 2);

      final friendsSub = container.listen(remoteFriendsProvider, (_, _) {});
      await container.read(remoteFriendsProvider.future);
      expect(remote.myFriendsCalls, 1);

      container.read(remoteRealtimeProvider);
      expect(remote.friendsChanged, isNotNull);
      expect(remote.requestsChanged, isNotNull);

      // A friendship appeared/disappeared → the board refetches both weeks.
      remote.friendsChanged!();
      await container.read(communityDisplayProvider(week).future);
      expect(remote.leaderboardWeeks.length, 4);

      // A request arrived → the friends list refetches.
      remote.requestsChanged!();
      await container.read(remoteFriendsProvider.future);
      expect(remote.myFriendsCalls, greaterThanOrEqualTo(2));

      boardSub.close();
      friendsSub.close();
    },
  );

  test(
    'synced progress refreshes the live board without manual pull',
    () async {
      final now = DateTime.now();
      final start = now.subtract(const Duration(hours: 3));
      final sessionDoc = {
        'id': 's-sync-1',
        'subjectId': 'general',
        'subjectName': 'Daily Study',
        'checkInTime': start.toIso8601String(),
        'checkOutTime': start.add(const Duration(hours: 1)).toIso8601String(),
        'pausedSeconds': 3600,
        'studySegments': [
          {
            'startTime': start.toIso8601String(),
            'endTime': start.add(const Duration(hours: 1)).toIso8601String(),
          },
        ],
      };
      SharedPreferences.setMockInitialValues({
        'studyup.studySessions.v1': jsonEncode([sessionDoc]),
      });
      final week = mondayOf(now);
      final remote = _FakeRemote();
      remote.rowsByWeek[week] = const [];
      remote.rowsByWeek[week.subtract(const Duration(days: 7))] = const [];
      final container = _container(remote);
      addTearDown(container.dispose);

      final boardSub = container.listen(
        communityDisplayProvider(week),
        (_, _) {},
      );
      await container.read(communityDisplayProvider(week).future);
      expect(remote.leaderboardWeeks.length, 2);

      // The signed-in sync trigger uploads the ended local session and must
      // refresh the board so the new numbers appear without a manual pull.
      container.listen(sessionSyncTriggerProvider, (_, _) {});
      for (var i = 0; i < 200 && remote.leaderboardWeeks.length < 4; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      expect(remote.upsertCalls, 1);
      expect(remote.leaderboardWeeks.length, greaterThanOrEqualTo(4));

      boardSub.close();
    },
  );

  // ---- membership vs progress -------------------------------------------
  //
  // Production bug: after a friend accepted an invitation, they never
  // appeared in the inviter's Community. `leaderboard_scope('friends')`
  // returned no row for a friend with zero study time in the week, and the
  // client built the board from that fetch alone — so a brand-new friend
  // (zero time, zero XP) was invisible. Friendship is membership, not
  // progress.

  Future<void> waitForLoaded(ProviderContainer container) async {
    container.listen(studyProgressProvider, (_, _) {});
    for (var i = 0; i < 200; i++) {
      if (container.read(studyProgressProvider).isLoaded) break;
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    expect(container.read(studyProgressProvider).isLoaded, isTrue);
  }

  test('a friend with zero study time and zero XP still appears', () async {
    SharedPreferences.setMockInitialValues({});
    final week = mondayOf(DateTime.now());
    final remote = _FakeRemote();
    // Server returns NOTHING: the friend studied zero minutes this week.
    remote.rowsByWeek[week] = const [];
    remote.rowsByWeek[week.subtract(const Duration(days: 7))] = const [];
    remote.friends = const [
      RemoteFriend(
        userId: 'brother',
        displayName: 'Brother',
        avatarId: 'robo-brother',
        blobVariant: 2,
        leaderboardOptIn: true,
      ),
    ];
    final container = _container(remote);
    addTearDown(container.dispose);
    await waitForLoaded(container);

    final entries = await container.read(communityDisplayProvider(week).future);

    final brother = entries.where((e) => e.memberId == 'brother').toList();
    expect(brother, hasLength(1), reason: 'the new friend must be present');
    expect(brother.single.displayName, 'Brother');
    expect(brother.single.avatarId, 'robo-brother');
    expect(brother.single.blobVariant, 2);
    // Honest zeros, not missing data and not invented progress.
    expect(brother.single.weekSeconds, 0);
    expect(brother.single.hasData, isTrue);
    expect(brother.single.level, computeStudyLevel(0).level);
    // A shared zero is real board data, not a fabricated progress value.
    expect(brother.single.rank, 1);
    // Membership is fetched from the friendship list, not from statistics.
    expect(remote.myFriendsCalls, greaterThanOrEqualTo(1));
  });

  test(
    'the accepted friend appears on refresh without an app restart',
    () async {
      SharedPreferences.setMockInitialValues({});
      final week = mondayOf(DateTime.now());
      final remote = _FakeRemote();
      remote.rowsByWeek[week] = const [];
      remote.rowsByWeek[week.subtract(const Duration(days: 7))] = const [];
      final container = _container(remote);
      addTearDown(container.dispose);
      await waitForLoaded(container);

      var entries = await container.read(communityDisplayProvider(week).future);
      expect(
        entries.where((e) => e.memberId == 'brother'),
        isEmpty,
        reason: 'not friends yet',
      );

      // The brother accepts: the server now reports the friendship.
      remote.friends = const [
        RemoteFriend(
          userId: 'brother',
          displayName: 'Brother',
          avatarId: 'robo-brother',
          blobVariant: 0,
          leaderboardOptIn: true,
        ),
      ];
      // Exactly what the realtime friendship event does on the inviter side.
      container.listen(remoteRealtimeProvider, (_, _) {});
      remote.friendsChanged?.call();
      await Future<void>.delayed(const Duration(milliseconds: 50));

      entries = await container.read(communityDisplayProvider(week).future);
      expect(entries.where((e) => e.memberId == 'brother'), hasLength(1));
    },
  );

  test(
    'a friend who later studies gets real statistics, replacing zeros',
    () async {
      SharedPreferences.setMockInitialValues({});
      final week = mondayOf(DateTime.now());
      final prevWeek = week.subtract(const Duration(days: 7));
      final remote = _FakeRemote();
      remote.friends = const [
        RemoteFriend(
          userId: 'brother',
          displayName: 'Brother',
          avatarId: 'robo-brother',
          blobVariant: 0,
          leaderboardOptIn: true,
        ),
      ];
      // First week: server has no row yet (zero progress).
      remote.rowsByWeek[week] = const [];
      remote.rowsByWeek[prevWeek] = const [];
      final container = _container(remote);
      addTearDown(container.dispose);
      await waitForLoaded(container);

      var entries = await container.read(communityDisplayProvider(week).future);
      expect(
        entries.firstWhere((e) => e.memberId == 'brother').hasData,
        isTrue,
      );

      // After real sessions sync up, the server row carries real totals and
      // the membership placeholder is replaced (never duplicated).
      remote.rowsByWeek[week] = const [
        RemoteBoardRow(
          userId: 'brother',
          displayName: 'Brother',
          avatarId: 'robo-brother',
          blobVariant: 0,
          weekSeconds: 5400,
          activeDays: 2,
          totalSeconds: 5400,
          streakDays: 3,
        ),
      ];
      container.invalidate(remoteFriendsBoardProvider);
      await Future<void>.delayed(const Duration(milliseconds: 20));

      entries = await container.read(communityDisplayProvider(week).future);
      final brother = entries.where((e) => e.memberId == 'brother').toList();
      expect(brother, hasLength(1), reason: 'no duplicate rows');
      expect(brother.single.hasData, isTrue);
      expect(brother.single.weekSeconds, 5400);
      expect(brother.single.streakDays, 3);
      expect(brother.single.rank, greaterThan(0));
    },
  );

  test(
    'fewer than three friends and zero progress rank without errors',
    () async {
      SharedPreferences.setMockInitialValues({});
      final week = mondayOf(DateTime.now());
      final remote = _FakeRemote();
      remote.rowsByWeek[week] = const [];
      remote.rowsByWeek[week.subtract(const Duration(days: 7))] = const [];
      // Exactly one friend, who has studied nothing.
      remote.friends = const [
        RemoteFriend(
          userId: 'brother',
          displayName: 'Brother',
          avatarId: 'robo-brother',
          blobVariant: 0,
          leaderboardOptIn: true,
        ),
      ];
      final container = _container(remote);
      addTearDown(container.dispose);
      await waitForLoaded(container);

      final entries = await container.read(
        communityDisplayProvider(week).future,
      );
      // self + the one friend: nothing else is invented.
      expect(entries, hasLength(2));
      expect(entries.where((e) => e.isSelf), hasLength(1));
      final friend = entries.where((e) => !e.isSelf).single;
      expect(friend.memberId, 'brother');
      // An opted-in friend with zero sessions has a real zero and ranks.
      expect(friend.hasData, isTrue);
      expect(friend.rank, greaterThan(0));
      expect(friend.weekSeconds, 0);
    },
  );

  test('a friend who opted out of the leaderboard is still a friend', () async {
    SharedPreferences.setMockInitialValues({});
    final week = mondayOf(DateTime.now());
    final remote = _FakeRemote();
    remote.rowsByWeek[week] = const [];
    remote.rowsByWeek[week.subtract(const Duration(days: 7))] = const [];
    remote.friends = const [
      RemoteFriend(
        userId: 'private',
        displayName: 'Private Friend',
        avatarId: 'robo-private',
        blobVariant: 0,
        leaderboardOptIn: false,
      ),
    ];
    final container = _container(remote);
    addTearDown(container.dispose);
    await waitForLoaded(container);

    final entries = await container.read(communityDisplayProvider(week).future);
    // Membership is not leaderboard consent: a friend who shares no totals
    // is still listed (with honest zeros), which is what stopped the
    // sender/receiver asymmetry. No progress is invented for them.
    final opted = entries.where((e) => e.memberId == 'private').toList();
    expect(opted, hasLength(1));
    expect(opted.single.displayName, 'Private Friend');
    expect(opted.single.weekSeconds, 0);
    expect(opted.single.hasData, isFalse);
    expect(opted.single.rank, 0);
  });
}
