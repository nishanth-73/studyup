import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:studyup/core/deeplink/invite_links.dart';
import 'package:studyup/core/router/app_router.dart';
import 'package:studyup/core/router/startup_gate.dart';
import 'package:studyup/features/auth/data/auth_controller.dart';
import 'package:studyup/features/community/presentation/invite_accept_screen.dart';
import 'package:studyup/features/social/data/social_providers.dart';
import 'package:studyup/features/social/data/social_remote.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// First-tap invitation routing (production bug: the first tap showed
/// "GoException: no routes for location: https://…/i/…", the second worked).
///
/// Root cause: GoRouter adopts the platform's initial route verbatim, and an
/// App Link hands Android the FULL url — which matches no route. Warm links
/// also raced the router: the cold-start link was navigated before the
/// Router widget existed, so the navigation was lost.
class _PreviewOnlyRemote extends SocialRemote {
  _PreviewOnlyRemote()
    : super(
        SupabaseClient(
          'https://example.supabase.co',
          'test-anon-key',
          authOptions: const AuthClientOptions(autoRefreshToken: false),
        ),
      );

  final acceptCalls = <String>[];

  @override
  Future<InvitePreview> previewInvitation(String rawToken) async =>
      const InvitePreview(
        displayName: 'Ajay',
        avatarId: 'avatar-ajay',
        valid: true,
        reason: 'ok',
      );

  @override
  Future<String> acceptInvitation(String rawToken) async {
    acceptCalls.add(rawToken);
    return 'Ajay';
  }
}

const _code = '74b4d3fa75c98b9fb3df7745c43a2016aa11bb22cc33dd44ee55ff66001122';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('router ignores the platform route so a full App Link cannot 404', () {
    // This flag is the fix for "no routes for location: <full url>": with it
    // false, the App Link url is used as the initial route and throws.
    expect(appRouter.overridePlatformDefaultLocation, isTrue);
    // The invitation route itself is unchanged.
    expect(appRouter.routeInformationParser, isNotNull);
  });

  test('a full production invitation url yields the invitation code', () {
    final uri = Uri.parse('https://studyup-4x7z.vercel.app/i/$_code');
    expect(parseInviteToken(uri), _code);
    // Trailing slash and the /invite/ alias are the same link.
    expect(
      parseInviteToken(Uri.parse('https://studyup-4x7z.vercel.app/i/$_code/')),
      _code,
    );
    expect(
      parseInviteToken(
        Uri.parse('https://studyup-4x7z.vercel.app/invite/$_code'),
      ),
      _code,
    );
    // Custom-scheme fallback still works with no hosting.
    expect(parseInviteToken(Uri.parse('studyup://invite/$_code')), _code);
    // A non-invitation link is not an invitation.
    expect(
      parseInviteToken(Uri.parse('https://studyup-4x7z.vercel.app/')),
      isNull,
    );
  });

  testWidgets('cold start from an invitation link resumes it, never Home', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'studyup.pendingInviteToken.v1': _code,
      'studyup.userProfile.v1':
          '{"ownerId":"me","displayName":"Invoker","blobName":"invoker",'
          '"onboardingComplete":true,"avatarId":"avatar1","slidesSeen":true,'
          '"setupComplete":true,"demoSignedIn":true,"demoEmail":""}',
    });
    final remote = _PreviewOnlyRemote();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          backendLiveProvider.overrideWithValue(true),
          backendUserIdProvider.overrideWithValue('me'),
          authSettledProvider.overrideWith((ref) async => true),
          localAccountDataAccessProvider.overrideWith(
            (ref, userId) async => userId == 'me',
          ),
          socialRemoteProvider.overrideWithValue(null),
          inviteRemoteProvider.overrideWithValue(remote),
          // Keep the gate hermetic: no background sync/link work here.
          sessionSyncTriggerProvider.overrideWith((ref) {}),
          postSignInLinkProvider.overrideWith((ref) async {}),
        ],
        child: const MaterialApp(home: StartupGate()),
      ),
    );
    await tester.pump();
    // First frame: the pending invitation lookup is still in flight. Home
    // must NOT be shown in the meantime (that used to swallow invites).
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('Track Your Progress'), findsNothing);

    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 500));

    // The invitation screen is up on the FIRST attempt, with the inviter's
    // name, the code's preview, and the two explicit actions.
    expect(find.byType(InviteAcceptScreen), findsOneWidget);
    expect(find.textContaining('invited you to join StudyUp'), findsOneWidget);
    expect(find.text('Decline'), findsOneWidget);
    expect(find.text('Accept invitation'), findsOneWidget);
    expect(find.textContaining('GoException'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('opening the invitation never auto-accepts', (tester) async {
    SharedPreferences.setMockInitialValues({
      'studyup.pendingInviteToken.v1': _code,
      'studyup.userProfile.v1':
          '{"ownerId":"me","displayName":"Invoker","blobName":"invoker",'
          '"onboardingComplete":true,"avatarId":"avatar1","slidesSeen":true,'
          '"setupComplete":true,"demoSignedIn":true,"demoEmail":""}',
    });
    final remote = _PreviewOnlyRemote();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          backendLiveProvider.overrideWithValue(true),
          backendUserIdProvider.overrideWithValue('me'),
          authSettledProvider.overrideWith((ref) async => true),
          localAccountDataAccessProvider.overrideWith(
            (ref, userId) async => userId == 'me',
          ),
          socialRemoteProvider.overrideWithValue(null),
          inviteRemoteProvider.overrideWithValue(remote),
          sessionSyncTriggerProvider.overrideWith((ref) {}),
          postSignInLinkProvider.overrideWith((ref) async {}),
        ],
        child: const MaterialApp(home: StartupGate()),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.byType(InviteAcceptScreen), findsOneWidget);
    expect(remote.acceptCalls, isEmpty);
    expect(tester.takeException(), isNull);
  });

  test('the cold-start code survives the sign-in hand-off untouched', () async {
    SharedPreferences.setMockInitialValues({});
    // main() stashes the launch code; the sign-in screen resumes it and the
    // invite screen consumes it exactly once.
    await InviteLinks.stashPending(_code);
    expect(await InviteLinks.peekPending(), _code);
    expect(await InviteLinks.takePending(), _code);
    expect(await InviteLinks.takePending(), isNull);
  });
}
