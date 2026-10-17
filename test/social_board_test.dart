import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:studyup/features/auth/data/auth_controller.dart';
import 'package:studyup/features/progress/data/study_gamification.dart';
import 'package:studyup/features/progress/data/study_session.dart';
import 'package:studyup/features/social/data/social_providers.dart';
import 'package:studyup/features/social/data/social_remote.dart';

/// Live (signed-in) Community board contract:
/// - one friends-only board: the client never sends a scope and never
///   falls back to people you are not connected to;
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
    ),
  );

  final SupabaseClient client;
  final leaderboardWeeks = <DateTime>[];
  final rowsByWeek = <DateTime, List<RemoteBoardRow>>{};
  int myFriendsCalls = 0;
  int upsertCalls = 0;
  void Function()? friendsChanged;
  void Function()? requestsChanged;

  @override
  Future<void> upsertSession(StudySession session) async {
    upsertCalls++;
  }

  @override
  Future<List<RemoteBoardRow>> leaderboard({required DateTime weekStart}) async {
    leaderboardWeeks.add(weekStart);
    return rowsByWeek[weekStart] ?? const [];
  }

  @override
  Future<List<RemoteFriend>> myFriends() async {
    myFriendsCalls++;
    return const [];
  }

  @override
  RealtimeChannel subscribeFriendships(void Function() onChange) {
    friendsChanged = onChange;
    return client.channel('test-friendships');
  }

  @override
  RealtimeChannel subscribeIncomingRequests(void Function() onChange) {
    requestsChanged = onChange;
    return client.channel('test-requests');
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
  test('live board fetches current + previous week and maps ranked rows', () async {
    final week = mondayOf(DateTime.now());
    final prevWeek = week.subtract(const Duration(days: 7));
    final remote = _FakeRemote();
    remote.rowsByWeek[week] = const [
      RemoteBoardRow(
        userId: 'me',
        displayName: 'Tester',
        avatarId: 'avatar1',
        blobVariant: 0,
        weekSeconds: 3600,
        activeDays: 1,
        totalSeconds: 5400,
        streakDays: 3,
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

    final entries = await container.read(communityDisplayProvider(week).future);

    // Current week first, then the previous week — both friends-only.
    expect(remote.leaderboardWeeks, [week, prevWeek]);
    // Ranked by real week seconds: friend 7200, self 3600.
    expect(entries.map((e) => e.memberId).toList(), ['f1', 'me']);
    final nova = entries.first;
    expect(nova.displayName, 'Nova Friend');
    expect(nova.isSelf, isFalse);
    expect(nova.rank, 1);
    expect(nova.level, computeStudyLevel(7200 ~/ 60).level);
    final me = entries.last;
    expect(me.isSelf, isTrue);
    expect(me.rank, 2);
  });

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

  test('friendship changes refetch board; request changes refetch friends', () async {
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

    final boardSub = container.listen(communityDisplayProvider(week), (_, _) {});
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
  });

  test('synced progress refreshes the live board without manual pull', () async {
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

    final boardSub = container.listen(communityDisplayProvider(week), (_, _) {});
    await container.read(communityDisplayProvider(week).future);
    expect(remote.leaderboardWeeks.length, 2);

    // The signed-in sync trigger uploads the ended local session and must
    // refresh the board so the new numbers appear without a manual pull.
    container.listen(sessionSyncTriggerProvider, (_, _) {});
    for (
      var i = 0;
      i < 200 && remote.leaderboardWeeks.length < 4;
      i++
    ) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    expect(remote.upsertCalls, 1);
    expect(remote.leaderboardWeeks.length, greaterThanOrEqualTo(4));

    boardSub.close();
  });
}
