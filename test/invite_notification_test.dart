import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:studyup/core/notifications/notification_service.dart';
import 'package:studyup/features/auth/data/auth_controller.dart';
import 'package:studyup/features/community/presentation/invite_accept_screen.dart';
import 'package:studyup/features/social/data/social_providers.dart';
import 'package:studyup/features/social/data/social_remote.dart';

/// Invitation notifications (production bug: none ever appeared).
///
/// The invitation path never called the existing community-event
/// notification mechanism, so opening a link and accepting it were both
/// silent. These tests pin:
///   - "invitation received" when a valid link is opened,
///   - "invitation accepted" ONLY after the server confirms,
///   - nothing on a failed accept,
///   - exactly one notification per event however often the link is tapped.
class _Remote extends SocialRemote {
  _Remote({this.preview, this.acceptError})
    : super(
        SupabaseClient(
          'https://example.supabase.co',
          'test-anon-key',
          authOptions: const AuthClientOptions(autoRefreshToken: false),
        ),
      );

  final InvitePreview? preview;
  final Object? acceptError;
  int previewCalls = 0;
  int acceptCalls = 0;

  @override
  Future<InvitePreview> previewInvitation(String rawToken) async {
    previewCalls++;
    return preview ??
        const InvitePreview(
          displayName: 'Ajay',
          avatarId: 'avatar-ajay',
          valid: true,
          reason: 'ok',
        );
  }

  @override
  Future<String> acceptInvitation(String rawToken) async {
    acceptCalls++;
    if (acceptError != null) throw acceptError!;
    return 'Ajay';
  }
}

const _token = '74b4d3fa75c98b9fb3df7745c43a2016aa11bb22cc33dd44ee55ff66001122';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<void> pumpInvite(
    WidgetTester tester,
    _Remote remote, {
    String? userId = 'me',
  }) async {
    final router = GoRouter(
      initialLocation: '/invite/$_token',
      routes: [
        GoRoute(
          path: '/invite/:token',
          builder: (_, s) =>
              InviteAcceptScreen(token: s.pathParameters['token'] ?? ''),
        ),
        GoRoute(path: '/home', builder: (_, _) => const Text('HOME')),
        GoRoute(path: '/auth', builder: (_, _) => const Text('AUTH')),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          inviteRemoteProvider.overrideWithValue(remote),
          backendUserIdProvider.overrideWithValue(userId),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  testWidgets('opening a valid invitation notifies "invitation received"', (
    tester,
  ) async {
    final remote = _Remote();
    await pumpInvite(tester, remote);

    expect(find.text('Accept invitation'), findsOneWidget);
    final items = await NotificationService.instance.loadCenterItems();
    final received = items.where((i) => i.title == 'New StudyUp invitation');
    expect(received, hasLength(1));
    expect(received.single.body, contains('Ajay'));
    // …and nothing claims success before the server confirms.
    expect(items.where((i) => i.title == 'Invitation accepted'), isEmpty);
  });

  testWidgets('a failed accept shows no success notification', (tester) async {
    final remote = _Remote(acceptError: Exception('already accepted'));
    await pumpInvite(tester, remote);
    await tester.tap(find.text('Accept invitation'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.textContaining('already used'), findsOneWidget);
    final items = await NotificationService.instance.loadCenterItems();
    // Received-notice may exist; acceptance must NOT.
    expect(items.where((i) => i.title == 'Invitation accepted'), isEmpty);
  });

  testWidgets('accepting notifies only after the server confirms', (
    tester,
  ) async {
    final remote = _Remote();
    await pumpInvite(tester, remote);
    await tester.tap(find.text('Accept invitation'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('Connected!'), findsOneWidget);
    final items = await NotificationService.instance.loadCenterItems();
    final accepted = items.where((i) => i.title == 'Invitation accepted');
    expect(accepted, hasLength(1));
    expect(accepted.single.body, contains('Ajay'));
    // The received-notice and the accepted-notice are distinct entries.
    expect(
      items.where((i) => i.title == 'New StudyUp invitation'),
      hasLength(1),
    );
    expect(remote.acceptCalls, 1);
  });

  testWidgets('repeated taps on the same link never duplicate notifications', (
    tester,
  ) async {
    final remote = _Remote();
    await pumpInvite(tester, remote);
    final first = await NotificationService.instance.loadCenterItems();
    expect(
      first.where((i) => i.title == 'New StudyUp invitation'),
      hasLength(1),
    );

    // Re-opening the same link (the "tapped twice" case) upserts the same
    // id instead of adding a second row.
    await NotificationService.instance.recordCommunityEvent(
      id: 'invite-received:${hashInviteToken(_token)}',
      title: 'New StudyUp invitation',
      body: 'Ajay invited you to join StudyUp.',
    );
    await NotificationService.instance.recordCommunityEvent(
      id: 'invite-accepted:${hashInviteToken(_token)}',
      title: 'Invitation accepted',
      body: 'You and Ajay are now study buddies on StudyUp.',
    );
    await NotificationService.instance.recordCommunityEvent(
      id: 'invite-accepted:${hashInviteToken(_token)}',
      title: 'Invitation accepted',
      body: 'You and Ajay are now study buddies on StudyUp.',
    );
    final after = await NotificationService.instance.loadCenterItems();
    expect(
      after.where((i) => i.title == 'New StudyUp invitation'),
      hasLength(1),
    );
    expect(after.where((i) => i.title == 'Invitation accepted'), hasLength(1));
  });

  testWidgets('an invalid invitation produces no notification', (tester) async {
    final remote = _Remote(
      preview: const InvitePreview(
        displayName: '',
        avatarId: '',
        valid: false,
        reason: 'expired',
      ),
    );
    await pumpInvite(tester, remote);

    expect(find.text('Invitation unavailable'), findsOneWidget);
    final items = await NotificationService.instance.loadCenterItems();
    expect(items, isEmpty);
  });
}
