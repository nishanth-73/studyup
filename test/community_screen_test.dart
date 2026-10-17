import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:studyup/features/auth/data/auth_controller.dart';
import 'package:studyup/features/community/data/community_store.dart';
import 'package:studyup/features/community/presentation/community_controller.dart';
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
    ),
  );

  final SupabaseClient client;

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
  RealtimeChannel subscribeFriendships(void Function() onChange) =>
      client.channel('test-friendships');

  @override
  RealtimeChannel subscribeIncomingRequests(void Function() onChange) =>
      client.channel('test-requests');
}

/// Regression tests for the Community tab:
/// 1. `type '(dynamic) => dynamic' is not a subtype of
///    `type '(StudyRoom) => bool' of 'test'` — an untyped `data`
///    parameter once sent a dynamic predicate into `List.where`.
///    Every helper below takes typed `CommunityData`/model arguments.
/// 2. The redesigned five-element screen: header, week selector, podium,
///    comparison, leaderboard, invite.
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
    expect(
      find.text('Compete & grow together with your study crew'),
      findsOneWidget,
    );
    expect(find.textContaining('This Week'), findsOneWidget);
    expect(find.text('Top 3'), findsOneWidget);
    expect(find.text('You vs. Top Friend'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Leaderboard'), 300);
    expect(find.text('Leaderboard'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Invite Friends & Start Competing'),
      300,
    );
    expect(find.text('Invite Friends & Start Competing'), findsOneWidget);
    // No rooms/challenges sections remain.
    expect(find.text('Live Study Rooms'), findsNothing);
    expect(find.text('Challenges'), findsNothing);
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
    await tester.scrollUntilVisible(find.text('Top 3'), 300);
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

  testWidgets('opens the shared week picker from the header button', (
    tester,
  ) async {
    await pumpCommunity(tester);
    // Only the header calendar button opens the week picker now (the old
    // selector card is gone); dialog has month stepper, locked future.
    await tester.tap(find.byIcon(Icons.calendar_month));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('Select week'), findsOneWidget);
    expect(find.text('Cancel'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.textContaining('This Week'), findsOneWidget);
  });

  testWidgets('shows a historical week with its own label', (tester) async {
    final lastMonday = mondayOf(DateTime.now())
        .subtract(const Duration(days: 7));
    SharedPreferences.setMockInitialValues({
      'studyup.userProfile.v1': jsonEncode(profileDoc()),
      CommunityStore.storageKey: jsonEncode(const <String, Object?>{}),
      'studyup.studySessions.v1': jsonEncode(const []),
    });
    final router = GoRouter(
      initialLocation: '/community',
      routes: [
        GoRoute(path: '/community', builder: (_, _) => const CommunityScreen()),
      ],
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [communityWeekProvider.overrideWith((ref) => lastMonday)],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.textContaining('Last Week'), findsOneWidget);
  });

  testWidgets('invite button generates a code without crashing', (
    tester,
  ) async {
    await pumpCommunity(tester);
    await tester.scrollUntilVisible(
      find.text('Invite Friends & Start Competing'),
      300,
    );
    await tester.tap(find.text('Invite Friends & Start Competing'));
    await tester.pumpAndSettle();
    // share_plus has no real target in widget tests: either the native
    // sheet call resolves or the clipboard fallback runs — both must be
    // crash-free. (Fallback content is covered by codec unit tests.)
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
    await tester.scrollUntilVisible(find.text('Buddy'), 500);
    expect(find.text('Buddy'), findsWidgets);
  });

  testWidgets('live board is friends-only: no scope toggle, real rows', (
    tester,
  ) async {
    await pumpCommunity(
      tester,
      overrides: [
        socialLiveProvider.overrideWithValue(true),
        backendUserIdProvider.overrideWithValue('me'),
        socialRemoteProvider.overrideWithValue(_BoardRemote()),
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
}
