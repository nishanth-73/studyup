import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:studyup/core/backend/supabase_config.dart';
import 'package:studyup/features/auth/data/auth_controller.dart';
import 'package:studyup/features/community/data/community_store.dart';
import 'package:studyup/features/community/presentation/community_screen.dart';
import 'package:studyup/features/social/data/social_providers.dart';
import 'package:studyup/features/social/data/social_remote.dart';

/// Live board stub for the friends-only Community test below.
class _BoardRemote extends SocialRemote {
  _BoardRemote._(this.client) : super(client);

  factory _BoardRemote() => _BoardRemote._(
    SupabaseClient(
      'https://example.supabase.co',
      'test-anon-key',
      // No auth auto-refresh timer inside widget-test fake async.
      authOptions: const AuthClientOptions(autoRefreshToken: false),
      realtimeClientOptions: const RealtimeClientOptions(
        disconnectOnEmptyChannelsAfter: Duration.zero,
      ),
    ),
  );

  final SupabaseClient client;

  /// Accepted friends. `leaderboard_scope` only returns friends who studied
  /// in the queried week, so membership comes from this list.
  final friends = <RemoteFriend>[];
  void Function()? progressChanged;

  @override
  Future<List<RemoteFriend>> myFriends() async => friends;

  @override
  Future<List<RemoteBoardRow>> leaderboard({
    required DateTime weekStart,
  }) async => const [
    RemoteBoardRow(
      userId: 'f1',
      displayName: 'Nova Friend',
      avatarId: 'avatar1',
      blobVariant: 1,
      weekSeconds: 7200,
      activeDays: 2,
      totalSeconds: 7200,
      streakDays: 4,
    ),
    RemoteBoardRow(
      userId: 'me',
      displayName: 'Tester',
      avatarId: 'avatar1',
      blobVariant: 1,
      weekSeconds: 3600,
      activeDays: 1,
      totalSeconds: 3600,
      streakDays: 1,
    ),
  ];

  @override
  RealtimeChannel subscribeFriendships(
    void Function() onChange, {
    void Function(RealtimeSubscribeStatus status, Object? error)? onStatus,
  }) {
    onStatus?.call(RealtimeSubscribeStatus.subscribed, null);
    return client.channel('test-friendships');
  }

  @override
  RealtimeChannel subscribeIncomingRequests(
    void Function() onChange, {
    void Function(RealtimeSubscribeStatus status, Object? error)? onStatus,
  }) {
    onStatus?.call(RealtimeSubscribeStatus.subscribed, null);
    return client.channel('test-requests');
  }

  @override
  RealtimeChannel subscribeProgressChanges(
    void Function() onChange, {
    void Function(RealtimeSubscribeStatus status, Object? error)? onStatus,
  }) {
    progressChanged = onChange;
    onStatus?.call(RealtimeSubscribeStatus.subscribed, null);
    return client.channel('test-progress');
  }
}

class _InviteShareRemote extends _BoardRemote {
  _InviteShareRemote()
    : super._(
        SupabaseClient(
          'https://example.supabase.co',
          'test-anon-key',
          authOptions: const AuthClientOptions(autoRefreshToken: false),
          realtimeClientOptions: const RealtimeClientOptions(
            disconnectOnEmptyChannelsAfter: Duration.zero,
          ),
        ),
      );

  static const token = 'abcdef1234567890abcdef1234567890';
  int createInvitationCalls = 0;

  @override
  Future<String> createInvitation({int validDays = 7}) async {
    createInvitationCalls++;
    return token;
  }
}

/// A server whose aggregate query fails, to prove the UI shows a retry
/// state instead of fabricated zeros.
class _FailingRemote extends _BoardRemote {
  _FailingRemote()
    : super._(
        SupabaseClient(
          'https://example.supabase.co',
          'test-anon-key',
          authOptions: const AuthClientOptions(autoRefreshToken: false),
          realtimeClientOptions: const RealtimeClientOptions(
            disconnectOnEmptyChannelsAfter: Duration.zero,
          ),
        ),
      );

  bool failing = true;
  List<RemoteBoardRow> rowsByWeek = const [];

  @override
  Future<List<RemoteBoardRow>> leaderboard({
    required DateTime weekStart,
  }) async {
    if (failing) throw Exception('connection reset');
    return rowsByWeek;
  }
}

/// A signed-in board whose ONLY friend has never studied: the server
/// returns no rows for them, so they exist purely as a friendship.
class _ZeroProgressRemote extends _BoardRemote {
  _ZeroProgressRemote()
    : super._(
        SupabaseClient(
          'https://example.supabase.co',
          'test-anon-key',
          authOptions: const AuthClientOptions(autoRefreshToken: false),
          realtimeClientOptions: const RealtimeClientOptions(
            disconnectOnEmptyChannelsAfter: Duration.zero,
          ),
        ),
      ) {
    friends.add(
      const RemoteFriend(
        userId: 'brother',
        displayName: 'Brother',
        avatarId: 'avatar1',
        blobVariant: 1,
        leaderboardOptIn: true,
      ),
    );
  }

  int sharedSeconds = 0;

  @override
  Future<List<RemoteBoardRow>> leaderboard({
    required DateTime weekStart,
  }) async => sharedSeconds == 0
      ? const []
      : [
          RemoteBoardRow(
            userId: 'brother',
            displayName: 'Brother',
            avatarId: 'avatar1',
            blobVariant: 1,
            weekSeconds: sharedSeconds,
            activeDays: 1,
            totalSeconds: sharedSeconds,
            streakDays: 1,
          ),
        ];
}

/// Regression tests for the Community tab:
/// 1. `type '(dynamic) => dynamic' is not a subtype of
///    `type '(StudyRoom) => bool' of 'test'` — an untyped `data`
///    parameter once sent a dynamic predicate into `List.where`.
///    Every helper below takes typed `CommunityData`/model arguments.
/// 2. The weekly screen: header, current-week caption, podium, comparison,
///    leaderboard, invite.
void main() {
  Map<String, Object?> profileDoc() => {
    'ownerId': 'local',
    'displayName': 'Tester',
    'blobName': 'tester',
    'onboardingComplete': true,
    'blobVariant': 1,
    'avatarId': 'avatar1',
    'slidesSeen': true,
    'setupComplete': true,
    'demoSignedIn': true,
    'demoEmail': 'tester@example.com',
  };

  Map<String, Object?> sessionDoc(DateTime start, Duration length) => {
    'id': 's-${start.millisecondsSinceEpoch}',
    'subjectId': 'general',
    'subjectName': 'Daily Study',
    'checkInTime': start.toIso8601String(),
    'checkOutTime': start.add(length).toIso8601String(),
    'pausedSeconds': length.inSeconds,
    'studySegments': [
      {
        'startTime': start.toIso8601String(),
        'endTime': start.add(length).toIso8601String(),
      },
    ],
  };

  Future<void> pumpCommunity(
    WidgetTester tester, {
    Map<String, Object?>? community,
    List<Map<String, Object?>> sessions = const [],
    List<Override> overrides = const [],
  }) async {
    SharedPreferences.setMockInitialValues({
      'studyup.userProfile.v1': jsonEncode(profileDoc()),
      CommunityStore.storageKey: jsonEncode(
        community ?? const <String, Object?>{},
      ),
      'studyup.studySessions.v1': jsonEncode(sessions),
    });
    final router = GoRouter(
      initialLocation: '/community',
      routes: [
        GoRoute(path: '/community', builder: (_, _) => const CommunityScreen()),
      ],
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: overrides,
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  }

  DateTime mondayOf(DateTime d) {
    final day = DateTime(d.year, d.month, d.day);
    return day.subtract(Duration(days: day.weekday - DateTime.monday));
  }

  testWidgets('shows header, week caption, podium, comparison, invite', (
    tester,
  ) async {
    await pumpCommunity(tester);
    expect(find.text('Community'), findsOneWidget);
    expect(find.text('Grow together, win together.'), findsOneWidget);
    expect(find.textContaining('This Week · Mon–Sun'), findsOneWidget);
    expect(find.byKey(const ValueKey('community-week-picker')), findsOneWidget);
    expect(find.text('Top 3'), findsOneWidget);
    expect(find.text('You vs. Top Friend'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Leaderboard'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Leaderboard'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Invite Friends & Start Competing'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Invite Friends & Start Competing'), findsOneWidget);
    // No rooms/challenges sections remain.
    expect(find.text('Live Study Rooms'), findsNothing);
    expect(find.text('Challenges'), findsNothing);
  });

  testWidgets('shares a clean server invitation URL, never a SUP1 payload', (
    tester,
  ) async {
    final remote = _InviteShareRemote();
    String? sharedText;
    const shareChannel = MethodChannel('dev.fluttercommunity.plus/share');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(shareChannel, (call) async {
          expect(call.method, 'share');
          sharedText =
              (call.arguments as Map<Object?, Object?>)['text'] as String;
          return 'success';
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(shareChannel, null),
    );

    await pumpCommunity(
      tester,
      overrides: [
        socialLiveProvider.overrideWithValue(true),
        socialRemoteProvider.overrideWithValue(remote),
        communityDisplayProvider.overrideWith((ref, weekStart) async => []),
      ],
    );
    await tester.scrollUntilVisible(
      find.text('Invite Friends & Start Competing'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Invite Friends & Start Competing'));
    await tester.pumpAndSettle();

    expect(remote.createInvitationCalls, 1);
    expect(
      sharedText,
      "Join me on StudyUp! Let's track our study progress and compete together: "
      'https://${SupabaseConfig.inviteHost}/i/${_InviteShareRemote.token}',
    );
    expect(sharedText, isNot(contains('SUP1-')));
    expect(sharedText, isNot(contains('"uid"')));
  });

  testWidgets('podium ranks a real session and highlights the user', (
    tester,
  ) async {
    final monday = mondayOf(DateTime.now()).add(const Duration(hours: 10));
    await pumpCommunity(
      tester,
      sessions: [sessionDoc(monday, const Duration(hours: 2))],
    );
    // 2h 00m from the real persisted session, ranked with demo friends.
    expect(find.text('2h 00m'), findsWidgets);
    expect(find.text('You'), findsWidgets);
  });

  testWidgets('podium uses exact rank colors and demo tags', (tester) async {
    await pumpCommunity(tester);
    await tester.scrollUntilVisible(
      find.text('Top 3'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    // Rank blocks: #1 green, #2 orange, #3 blue — never swapped
    // (alpha tints ignored; RGB must match exactly).
    bool hasBlock(Color color) => find
        .byWidgetPredicate(
          (w) =>
              w is Container &&
              w.decoration is BoxDecoration &&
              (((w.decoration! as BoxDecoration).color?.toARGB32() ?? 0) &
                      0xFFFFFF ==
                  color.toARGB32() & 0xFFFFFF),
        )
        .evaluate()
        .isNotEmpty;
    expect(hasBlock(const Color(0xFF8BC48A)), isTrue);
    expect(hasBlock(const Color(0xFFFFA45B)), isTrue);
    expect(hasBlock(const Color(0xFF72A7F7)), isTrue);
    // Demo fixtures are visible and clearly tagged.
    expect(find.text('Maya'), findsWidgets);
    expect(find.text('DEMO'), findsWidgets);
  });

  testWidgets('shows the current Monday-to-Sunday period and picker', (
    tester,
  ) async {
    await pumpCommunity(tester);
    expect(tester.takeException(), isNull);
    expect(find.textContaining('This Week · Mon–Sun'), findsOneWidget);
    expect(find.byIcon(Icons.calendar_month_rounded), findsOneWidget);
  });

  testWidgets('week picker is available and lists selectable weeks', (
    tester,
  ) async {
    await pumpCommunity(tester);

    await tester.tap(find.byKey(const ValueKey('community-week-picker')));
    await tester.pumpAndSettle();

    expect(find.text('Select week'), findsOneWidget);
    expect(find.textContaining('This week'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('choosing a past week updates the Community period', (
    tester,
  ) async {
    await pumpCommunity(tester);
    await tester.tap(find.byKey(const ValueKey('community-week-picker')));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Previous month'));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('W1 ·').first);
    await tester.pumpAndSettle();

    expect(find.textContaining('Week · Mon–Sun'), findsOneWidget);
    expect(find.textContaining('This Week · Mon–Sun'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('offline invite button does not share the encoded payload', (
    tester,
  ) async {
    var shareCalled = false;
    const shareChannel = MethodChannel('dev.fluttercommunity.plus/share');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(shareChannel, (call) async {
          shareCalled = true;
          return 'success';
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(shareChannel, null),
    );

    await pumpCommunity(tester);
    await tester.scrollUntilVisible(
      find.text('Invite Friends & Start Competing'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    // The leaderboard is shorter now that the "Tip:" line is gone, so make
    // sure the button is actually on-screen before tapping it.
    await tester.ensureVisible(find.text('Invite Friends & Start Competing'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Invite Friends & Start Competing'));
    await tester.pumpAndSettle();
    expect(
      find.text(
        'Sign in to create a shareable invitation link. You can still share an invite code from Friends.',
      ),
      findsOneWidget,
    );
    expect(shareCalled, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('skips malformed stored rows instead of crashing', (
    tester,
  ) async {
    await pumpCommunity(
      tester,
      community: {
        'members': {
          'good': {'id': 'good', 'displayName': 'Buddy', 'avatarId': 'avatar2'},
          'bad': 'not-a-member',
        },
        'friendIds': ['good', 'bad', 'missing'],
        'rooms': [
          {'bogus': true},
          'not-a-room',
          42,
        ],
      },
    );
    expect(find.text('Community'), findsOneWidget);
    // 'Buddy' shares no week snapshot → listed unranked below the fold.
    await tester.scrollUntilVisible(
      find.text('Buddy'),
      500,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Buddy'), findsWidgets);
  });

  testWidgets('live board is friends-only: no scope toggle, real rows', (
    tester,
  ) async {
    final remote = _BoardRemote()
      ..friends.add(
        const RemoteFriend(
          userId: 'f1',
          displayName: 'Nova Friend',
          avatarId: 'avatar1',
          blobVariant: 1,
          leaderboardOptIn: true,
        ),
      );
    await pumpCommunity(
      tester,
      overrides: [
        socialLiveProvider.overrideWithValue(true),
        backendUserIdProvider.overrideWithValue('me'),
        socialRemoteProvider.overrideWithValue(remote),
      ],
    );
    // The Friends/Everyone scope toggle is gone: one friends-only board.
    expect(find.text('Everyone'), findsNothing);
    expect(find.text('Friends'), findsNothing);
    // Real server rows render (podium + comparison + ranked list)…
    expect(find.text('Nova Friend'), findsWidgets);
    // …and demo fixtures never leak into the live board.
    expect(find.text('DEMO'), findsNothing);
  });

  testWidgets('a zero-progress friend is listed in Community, not hidden', (
    tester,
  ) async {
    final remote = _ZeroProgressRemote();
    await pumpCommunity(
      tester,
      overrides: [
        socialLiveProvider.overrideWithValue(true),
        backendUserIdProvider.overrideWithValue('me'),
        socialRemoteProvider.overrideWithValue(remote),
      ],
    );
    // The accepted friend with zero study time / zero XP is on screen with
    // their real name — not missing, not faked.
    await tester.scrollUntilVisible(
      find.text('Brother').last,
      400,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Brother'), findsWidgets);
    // No exceptions from the podium/comparison with a single friend.
    expect(find.text('Top 3'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Top 3 and comparison render with one zero-progress friend', (
    tester,
  ) async {
    final remote = _ZeroProgressRemote();
    await pumpCommunity(
      tester,
      overrides: [
        socialLiveProvider.overrideWithValue(true),
        backendUserIdProvider.overrideWithValue('me'),
        socialRemoteProvider.overrideWithValue(remote),
      ],
    );
    // Podium and comparison must not crash with fewer than three friends
    // and no shared data (previously "no routes"/empty-rank edge cases).
    expect(find.text('Top 3'), findsOneWidget);
    expect(find.text('You vs. Top Friend'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Leaderboard'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Leaderboard'), findsOneWidget);
    // Accepted friends live in the ONE leaderboard list — a friend with no
    // study time shows a genuine 0m, not a separate "waiting" card.
    expect(find.text('Brother'), findsWidgets);
    expect(find.text('0m'), findsWidgets);
    expect(find.textContaining('Waiting for shared data'), findsNothing);
    expect(tester.takeException(), isNull);
    // The removed instructional "Tip:" text must stay gone.
    expect(find.textContaining('Tip:'), findsNothing);
  });

  testWidgets('a shared progress event refreshes the open Community board', (
    tester,
  ) async {
    final remote = _ZeroProgressRemote();
    await pumpCommunity(
      tester,
      overrides: [
        socialLiveProvider.overrideWithValue(true),
        backendUserIdProvider.overrideWithValue('me'),
        socialRemoteProvider.overrideWithValue(remote),
      ],
    );
    await tester.scrollUntilVisible(
      find.text('Leaderboard'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('0m'), findsWidgets);

    remote.sharedSeconds = 1800;
    remote.progressChanged?.call();
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pump(const Duration(milliseconds: 600));

    expect(find.text('30m'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a failed board query shows a retry state, never fake zeros', (
    tester,
  ) async {
    final remote = _FailingRemote();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          socialLiveProvider.overrideWithValue(true),
          backendUserIdProvider.overrideWithValue('me'),
          socialRemoteProvider.overrideWithValue(remote),
        ],
        child: MaterialApp.router(
          routerConfig: GoRouter(
            initialLocation: '/community',
            routes: [
              GoRoute(
                path: '/community',
                builder: (_, _) => const CommunityScreen(),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));

    // The failure surfaces as an explicit retry state. It must NOT be
    // rendered as a friend with 0m, and never as "has not shared".
    expect(find.text('Something went wrong'), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
    expect(find.textContaining('Waiting for shared data'), findsNothing);

    // The server recovers: the existing retry path refetches and shows the
    // real totals, with no sign-out and no fresh invitation.
    remote.failing = false;
    remote.rowsByWeek = const [
      RemoteBoardRow(
        userId: 'me',
        displayName: 'Tester',
        avatarId: 'avatar1',
        blobVariant: 1,
        weekSeconds: 3600,
        activeDays: 1,
        totalSeconds: 3600,
        streakDays: 1,
      ),
    ];
    await tester.tap(find.text('Try again'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));

    expect(find.text('Something went wrong'), findsNothing);
    await tester.scrollUntilVisible(
      find.text('Leaderboard'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Leaderboard'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Community picks up a friendship accepted on the other phone', (
    tester,
  ) async {
    final remote = _ZeroProgressRemote()..friends.clear();

    await pumpCommunity(
      tester,
      overrides: [
        socialLiveProvider.overrideWithValue(true),
        backendUserIdProvider.overrideWithValue('me'),
        socialRemoteProvider.overrideWithValue(remote),
      ],
    );
    await tester.scrollUntilVisible(
      find.text('Leaderboard'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Brother'), findsNothing, reason: 'not friends yet');

    // The other phone accepts the invitation: the server now reports it.
    remote.friends.add(
      const RemoteFriend(
        userId: 'brother',
        displayName: 'Brother',
        avatarId: 'avatar1',
        blobVariant: 1,
        leaderboardOptIn: true,
      ),
    );

    // Leaving the tab and coming back must refresh MEMBERSHIP, not just
    // the progress rows — no sign-out, no reinstall.
    await tester.pumpWidget(const SizedBox.shrink());
    await pumpCommunity(
      tester,
      overrides: [
        socialLiveProvider.overrideWithValue(true),
        backendUserIdProvider.overrideWithValue('me'),
        socialRemoteProvider.overrideWithValue(remote),
      ],
    );
    await tester.scrollUntilVisible(
      find.text('Brother').last,
      400,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Brother'), findsWidgets);
    expect(tester.takeException(), isNull);
  });
}
