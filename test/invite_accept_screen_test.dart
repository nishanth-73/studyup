import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:studyup/features/auth/data/auth_controller.dart';
import 'package:studyup/features/community/data/community_models.dart';
import 'package:studyup/features/community/presentation/invite_accept_screen.dart';
import 'package:studyup/features/social/data/social_providers.dart';
import 'package:studyup/features/social/data/social_remote.dart';

/// Invitation landing contract:
/// - opening a link never creates a friendship — only the explicit
///   "Accept invitation" tap calls the authenticated accept RPC;
/// - "Decline" leaves without accepting: no accept call, no stashed token;
/// - signed-out recipients are asked to sign in and the token is stashed
///   (never consumed) so it survives the auth flow;
/// - expired/revoked/used/invalid tokens, self-invites, existing
///   friendships and pending requests all surface as clear messages;
/// - a successful accept refreshes the friends + leaderboard providers.
const _token =
    'aa11bb22cc33dd44ee55ff6600112233445566778899aabbccddeeff00112233';

class _FakeRemote extends SocialRemote {
  _FakeRemote({
    this.preview = const InvitePreview(
      displayName: 'Maya',
      avatarId: 'robo-default',
      valid: true,
      reason: 'ok',
    ),
    this.previewError,
    this.acceptError,
  }) : super(
         SupabaseClient(
           'https://example.supabase.co',
           'test-anon-key',
           // No auth auto-refresh timer inside widget-test fake async.
           authOptions: const AuthClientOptions(autoRefreshToken: false),
         ),
       );

  final InvitePreview preview;
  final Object? previewError;
  final Object? acceptError;
  final previewCalls = <String>[];
  final acceptCalls = <String>[];

  @override
  Future<InvitePreview> previewInvitation(String rawToken) async {
    previewCalls.add(rawToken);
    if (previewError != null) throw previewError!;
    return preview;
  }

  @override
  Future<String> acceptInvitation(String rawToken) async {
    acceptCalls.add(rawToken);
    if (acceptError != null) throw acceptError!;
    return 'Maya';
  }
}

DateTime mondayOf(DateTime d) {
  final day = DateTime(d.year, d.month, d.day);
  return day.subtract(Duration(days: day.weekday - DateTime.monday));
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<void> pumpScreen(
    WidgetTester tester, {
    required _FakeRemote remote,
    String token = _token,
    String? userId = 'me',
    List<Override> extraOverrides = const [],
  }) async {
    final router = GoRouter(
      initialLocation: '/invite/$token',
      routes: [
        GoRoute(
          path: '/invite/:token',
          builder: (_, s) =>
              InviteAcceptScreen(token: s.pathParameters['token'] ?? ''),
        ),
        GoRoute(path: '/home', builder: (_, _) => const Text('HOME')),
        GoRoute(path: '/auth', builder: (_, _) => const Text('AUTH')),
        GoRoute(path: '/community', builder: (_, _) => const Text('COMMUNITY')),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          inviteRemoteProvider.overrideWithValue(remote),
          backendUserIdProvider.overrideWithValue(userId),
          ...extraOverrides,
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  testWidgets('invalid preview shows the reason and creates nothing', (
    tester,
  ) async {
    final remote = _FakeRemote(
      preview: const InvitePreview(
        displayName: '',
        avatarId: '',
        valid: false,
        reason: 'expired',
      ),
    );
    await pumpScreen(tester, remote: remote);
    expect(find.text('Invitation unavailable'), findsOneWidget);
    expect(
      find.text('This invitation expired. Ask for a fresh one.'),
      findsOneWidget,
    );
    expect(remote.acceptCalls, isEmpty);
  });

  testWidgets('used/revoked/garbage tokens map to their own messages', (
    tester,
  ) async {
    for (final (reason, expected) in const [
      ('accepted', 'This invitation was already used.'),
      ('revoked', 'This invitation was revoked by the sender.'),
      ('invalid', 'This invitation link is invalid.'),
    ]) {
      final remote = _FakeRemote(
        preview: InvitePreview(
          displayName: '',
          avatarId: '',
          valid: false,
          reason: reason,
        ),
      );
      await pumpScreen(tester, remote: remote);
      expect(find.text(expected), findsOneWidget, reason: reason);
      expect(remote.acceptCalls, isEmpty, reason: reason);
    }
  });

  testWidgets('preview failure shows the connection message', (tester) async {
    final remote = _FakeRemote(previewError: Exception('network down'));
    await pumpScreen(tester, remote: remote);
    expect(
      find.text('Could not load this invitation. Check your connection.'),
      findsOneWidget,
    );
    expect(remote.acceptCalls, isEmpty);
  });

  testWidgets('signed-out recipient is asked to sign in; token survives', (
    tester,
  ) async {
    final remote = _FakeRemote();
    await pumpScreen(tester, remote: remote, userId: null);
    expect(find.text('You\u2019re invited!'), findsOneWidget);
    expect(find.text('Sign in / Sign up'), findsOneWidget);
    expect(remote.acceptCalls, isEmpty);

    await tester.tap(find.text('Sign in / Sign up'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('AUTH'), findsOneWidget);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('studyup.pendingInviteToken.v1'), _token);
  });

  testWidgets('accept is explicit: nothing before the tap, friend after', (
    tester,
  ) async {
    final remote = _FakeRemote();
    await pumpScreen(tester, remote: remote);
    expect(find.text('Accept invitation'), findsOneWidget);
    // Opening the link alone must never call the accept RPC.
    expect(remote.acceptCalls, isEmpty);

    await tester.tap(find.text('Accept invitation'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Connected!'), findsOneWidget);
    expect(find.textContaining('Maya'), findsWidgets);
    expect(remote.acceptCalls, [_token]);

    await tester.tap(find.text('Open Community'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('COMMUNITY'), findsOneWidget);
  });

  testWidgets('recipient recovers inviter from a short invitation token', (
    tester,
  ) async {
    final shortToken = newInviteToken();
    final link = inviteLinkFor(shortToken);
    final recoveredToken = parseInviteToken(Uri.parse(link));
    expect(recoveredToken, shortToken);

    final remote = _FakeRemote();
    await pumpScreen(tester, remote: remote, token: recoveredToken!);

    expect(remote.previewCalls, [shortToken]);
    expect(
      find.text('Maya invited you to join StudyUp.'),
      findsOneWidget,
    );
    expect(remote.acceptCalls, isEmpty);
  });

  testWidgets('accept and decline are both offered, side by side', (
    tester,
  ) async {
    final remote = _FakeRemote();
    await pumpScreen(tester, remote: remote);
    expect(find.text('Accept invitation'), findsOneWidget);
    expect(find.text('Decline'), findsOneWidget);
    // Merely showing the actions must not touch the server.
    expect(remote.acceptCalls, isEmpty);
  });

  testWidgets('declining leaves without joining the Community', (tester) async {
    final remote = _FakeRemote();
    await pumpScreen(tester, remote: remote);

    await tester.tap(find.text('Decline'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Invitation declined'), findsOneWidget);
    // No accept call: nothing was created server-side.
    expect(remote.acceptCalls, isEmpty);
    expect(remote.previewCalls, [_token]);

    await tester.tap(find.text('Back to StudyUp'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('HOME'), findsOneWidget);
  });

  testWidgets('declining while signed out stashes no token', (tester) async {
    final remote = _FakeRemote();
    await pumpScreen(tester, remote: remote, userId: null);
    expect(find.text('Sign in / Sign up'), findsOneWidget);
    expect(find.text('Decline'), findsOneWidget);

    await tester.tap(find.text('Decline'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Invitation declined'), findsOneWidget);
    expect(remote.acceptCalls, isEmpty);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('studyup.pendingInviteToken.v1'), isNull);
  });

  testWidgets('accept errors map to graceful messages', (tester) async {
    for (final (error, expected) in const [
      ('self invite', 'You cannot accept your own invitation.'),
      ('already friends', 'You are already friends. No duplicate created.'),
      ('expired', 'This invitation expired. Ask for a fresh one.'),
      (
        'request pending',
        'A friend request between you is already pending — check Friends.',
      ),
      ('already accepted', 'This invitation was already used.'),
    ]) {
      final remote = _FakeRemote(acceptError: Exception(error));
      await pumpScreen(tester, remote: remote);
      await tester.tap(find.text('Accept invitation'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text(expected), findsOneWidget, reason: error);
    }
  });

  testWidgets('accepting refreshes the friends + leaderboard providers', (
    tester,
  ) async {
    var friendsBuilds = 0;
    var boardBuilds = 0;
    final week = mondayOf(DateTime.now());
    final remote = _FakeRemote();
    await pumpScreen(
      tester,
      remote: remote,
      extraOverrides: [
        remoteFriendsProvider.overrideWith((ref) {
          friendsBuilds++;
          return const <RemoteFriend>[];
        }),
        // The accept flow refetches the friends-board layer; self stays
        // fully local/live and is merged without any server refresh.
        remoteFriendsBoardProvider(week).overrideWith((ref) {
          boardBuilds++;
          return (
            current: const <LeaderboardEntry>[],
            previous: const <LeaderboardEntry>[],
          );
        }),
      ],
    );
    final container = ProviderScope.containerOf(
      tester.element(find.byType(InviteAcceptScreen)),
    );
    container.listen(remoteFriendsProvider, (_, _) {}, fireImmediately: true);
    container.listen(
      remoteFriendsBoardProvider(week),
      (_, _) {},
      fireImmediately: true,
    );
    expect(friendsBuilds, greaterThanOrEqualTo(1));
    expect(boardBuilds, greaterThanOrEqualTo(1));

    await tester.tap(find.text('Accept invitation'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(friendsBuilds, greaterThanOrEqualTo(2));
    expect(boardBuilds, greaterThanOrEqualTo(2));
  });
}
