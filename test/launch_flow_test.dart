import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:studyup/features/auth/presentation/auth_screen.dart';
import 'package:studyup/features/avatar/data/user_profile.dart';
import 'package:studyup/features/avatar/presentation/avatar_widgets.dart';
import 'package:studyup/features/avatar/presentation/user_profile_controller.dart';
import 'package:studyup/features/robo/study_robo.dart';
import 'package:studyup/features/onboarding/presentation/onboarding_screen.dart';
import 'package:studyup/features/profile/presentation/profile_screen.dart';
import 'package:studyup/features/profile/presentation/customise_robo_page.dart';
import 'package:studyup/features/profile/presentation/setup_goal_screen.dart';
import 'package:studyup/features/profile/presentation/setup_profile_screen.dart';
import 'package:studyup/features/progress/presentation/study_progress_controller.dart';
import 'package:studyup/features/auth/data/auth_controller.dart';
import 'package:studyup/core/router/startup_gate.dart';

Future<void> _waitForSettled(UserProfileController controller) async {
  for (var attempt = 0; attempt < 50; attempt++) {
    if (!controller.state.isLoading) return;
    await Future<void>.delayed(const Duration(milliseconds: 2));
  }
  fail('Profile did not finish loading.');
}

const _seedSetup = <String, Object?>{
  'ownerId': 'local',
  'displayName': 'Alex',
  'blobName': 'alex',
  'onboardingComplete': false,
  'avatarId': 'avatar1',
  'blobVariant': 0,
  'slidesSeen': true,
  'setupComplete': false,
  'demoSignedIn': false,
  'demoEmail': '',
};

GoRouter _testRouter() => GoRouter(
  initialLocation: '/onboarding',
  routes: [
    GoRoute(path: '/onboarding', builder: (_, _) => const OnboardingScreen()),
    GoRoute(
      path: '/setup-profile',
      builder: (_, _) => const SetupProfileScreen(),
    ),
    GoRoute(path: '/setup-goal', builder: (_, _) => const SetupGoalScreen()),
    GoRoute(path: '/auth', builder: (_, _) => const AuthScreen()),
    GoRoute(
      path: '/home',
      builder: (_, _) => const Scaffold(body: Center(child: Text('HOME'))),
    ),
  ],
);

void main() {
  group('First-launch funnel persistence', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('legacy records migrate completed flags forward', () {
      final done = UserProfile.fromJson({
        'ownerId': 'local',
        'displayName': 'Alex',
        'blobName': 'alex',
        'onboardingComplete': true,
      });
      expect(done.slidesSeen, isTrue);
      expect(done.setupComplete, isTrue);
      expect(done.demoSignedIn, isFalse);
      expect(done.avatarId, 'avatar1');

      final fresh = UserProfile.fromJson({
        'ownerId': 'local',
        'displayName': '',
        'blobName': '',
        'onboardingComplete': false,
      });
      expect(fresh.slidesSeen, isFalse);
      expect(fresh.setupComplete, isFalse);
      expect(fresh.demoSignedIn, isFalse);
    });

    test('new flags survive a JSON round-trip', () {
      const profile = UserProfile(
        displayName: 'Alex',
        blobName: 'alex',
        avatarId: 'avatar3',
        slidesSeen: true,
        setupComplete: false,
        demoSignedIn: false,
        demoEmail: 'a@b.c',
      );
      final restored = UserProfile.fromJson(
        Map<String, Object?>.from(profile.toJson()),
      );
      expect(restored.avatarId, 'avatar3');
      expect(restored.setupComplete, isFalse);
      expect(restored.demoEmail, 'a@b.c');
    });

    test('slides -> setup -> auth stages persist in order', () async {
      final controller = UserProfileController();
      await _waitForSettled(controller);
      expect(controller.state.valueOrNull, isNull);

      await controller.markSlidesSeen();
      var profile = controller.state.valueOrNull!;
      expect(profile.slidesSeen, isTrue);
      expect(profile.setupComplete, isFalse);
      expect(profile.demoSignedIn, isFalse);

      await controller.saveSetupProgress(blobVariant: 1, displayName: 'Alex');
      profile = controller.state.valueOrNull!;
      expect(profile.blobVariant, 1);
      expect(profile.displayName, 'Alex');
      expect(profile.setupComplete, isFalse);

      await controller.completeSetup();
      profile = controller.state.valueOrNull!;
      expect(profile.setupComplete, isTrue);
      expect(profile.onboardingComplete, isTrue);

      await controller.linkAuthenticatedAccount(email: 'alex@example.com');
      profile = controller.state.valueOrNull!;
      expect(profile.demoSignedIn, isFalse);
      expect(profile.demoEmail, 'alex@example.com');

      await expectLater(
        controller.saveSetupProgress(blobVariant: 4, displayName: 'Alex'),
        throwsArgumentError,
      );
      await expectLater(
        controller.saveSetupProgress(blobVariant: 0, displayName: '  '),
        throwsArgumentError,
      );
      await expectLater(controller.updateBlobVariant(-1), throwsArgumentError);
      controller.dispose();
    });
  });

  group('Onboarding screen', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    testWidgets('Next/Previous walk three slides; Skip finishes', (
      tester,
    ) async {
      await tester.pumpWidget(
        ProviderScope(child: MaterialApp.router(routerConfig: _testRouter())),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Track Your Progress'), findsOneWidget);
      // Disabled Previous on slide 1 goes nowhere.
      await tester.tap(find.bySemanticsLabel('Previous slide'));
      await tester.pump();
      expect(find.text('Track Your Progress'), findsOneWidget);

      await tester.tap(find.bySemanticsLabel('Next slide'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Compare Day by Day'), findsOneWidget);

      await tester.tap(find.bySemanticsLabel('Previous slide'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Track Your Progress'), findsOneWidget);

      await tester.tap(find.text('Skip'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text('Make it yours'), findsOneWidget);
    });

    testWidgets('final slide shows Get Started and finishes', (tester) async {
      await tester.pumpWidget(
        ProviderScope(child: MaterialApp.router(routerConfig: _testRouter())),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      for (var i = 0; i < 2; i++) {
        await tester.tap(find.bySemanticsLabel('Next slide'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
      }
      expect(find.text('Study Well, Every Day'), findsOneWidget);
      expect(find.text('Get Started'), findsOneWidget);

      await tester.tap(find.text('Get Started'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text('Make it yours'), findsOneWidget);
    });
  });

  group('Avatar + name setup', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({
        'studyup.userProfile.v1': jsonEncode(_seedSetup),
      });
    });

    testWidgets('empty name blocks; valid choice persists and continues', (
      tester,
    ) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final router = GoRouter(
        initialLocation: '/setup-profile',
        routes: [
          GoRoute(
            path: '/setup-profile',
            builder: (_, _) => const SetupProfileScreen(),
          ),
          GoRoute(
            path: '/setup-goal',
            builder: (_, _) =>
                const Scaffold(body: Center(child: Text('GOAL'))),
          ),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp.router(
            debugShowCheckedModeBanner: false,
            routerConfig: router,
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      await tester.tap(find.text('Continue'));
      await tester.pump();
      expect(find.text('Please enter your name to continue.'), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'Alex');
      // Release field focus: the focused field auto-scrolls into view,
      // which desyncs harness tap coordinates from the grid cells.
      FocusManager.instance.primaryFocus?.unfocus();
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      final avatarOption = find.byKey(const ValueKey('avatar-option-avatar3'));
      await tester.tap(avatarOption);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      await tester.tap(find.text('Continue'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text('GOAL'), findsOneWidget);

      final profile = container.read(userProfileProvider).valueOrNull!;
      expect(profile.displayName, 'Alex');
      expect(profile.setupComplete, isFalse);
      // The chosen PNG portrait persists in the profile record itself.
      expect(profile.avatarId, 'avatar3');
    });
  });

  group('Daily goal setup', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({
        'studyup.userProfile.v1': jsonEncode(_seedSetup),
      });
    });

    testWidgets('8h default; 6h persists 360min and completes setup', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(360, 520);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final router = GoRouter(
        initialLocation: '/setup-goal',
        routes: [
          GoRoute(
            path: '/setup-goal',
            builder: (_, _) => const SetupGoalScreen(),
          ),
          GoRoute(
            path: '/auth',
            builder: (_, _) =>
                const Scaffold(body: Center(child: Text('AUTH'))),
          ),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('Pick Your Daily Goal'), findsOneWidget);
      tester.view.viewInsets = const FakeViewPadding(bottom: 170);
      await tester.pump();
      await tester.scrollUntilVisible(
        find.text('6h'),
        120,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('6h'));
      await tester.pump();
      await tester.scrollUntilVisible(
        find.text('Continue'),
        180,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('Continue'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('AUTH'), findsOneWidget);
      expect(container.read(studyProgressProvider).dailyStudyGoalMinutes, 360);
      expect(
        container.read(userProfileProvider).valueOrNull!.setupComplete,
        isTrue,
      );
    });
  });

  group('Authentication required', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({
        'studyup.userProfile.v1': jsonEncode(_seedSetup),
      });
    });

    testWidgets('missing backend never grants guest access', (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final router = GoRouter(
        initialLocation: '/auth',
        routes: [
          GoRoute(path: '/auth', builder: (_, _) => const AuthScreen()),
          GoRoute(
            path: '/home',
            builder: (_, _) =>
                const Scaffold(body: Center(child: Text('HOME'))),
          ),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(
        find.textContaining('Offline guest access is not available.'),
        findsOneWidget,
      );
      expect(find.text('Continue without an account (offline)'), findsNothing);
      expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, 'Login'))
            .onPressed,
        isNull,
      );
      expect(find.text('HOME'), findsNothing);
      final profile = container.read(userProfileProvider).valueOrNull!;
      expect(profile.demoSignedIn, isFalse);
      expect(profile.demoEmail, isEmpty);
    });

    testWidgets('direct protected route redirects a signed-out user', (
      tester,
    ) async {
      final router = GoRouter(
        initialLocation: '/protected',
        routes: [
          GoRoute(
            path: '/protected',
            builder: (_, _) => const AuthenticatedRoute(
              returnTo: '/protected',
              child: Scaffold(body: Text('PROTECTED')),
            ),
          ),
          GoRoute(path: '/auth', builder: (_, _) => const AuthScreen()),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authSettledProvider.overrideWith((ref) async => true),
            backendUserIdProvider.overrideWithValue(null),
          ],
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('PROTECTED'), findsNothing);
      expect(find.text('Login'), findsWidgets);
    });

    testWidgets('restored authenticated session can open protected route', (
      tester,
    ) async {
      final router = GoRouter(
        initialLocation: '/protected',
        routes: [
          GoRoute(
            path: '/protected',
            builder: (_, _) => const AuthenticatedRoute(
              returnTo: '/protected',
              child: Scaffold(body: Text('PROTECTED')),
            ),
          ),
          GoRoute(path: '/auth', builder: (_, _) => const AuthScreen()),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authSettledProvider.overrideWith((ref) async => true),
            backendUserIdProvider.overrideWithValue('restored-user'),
            localAccountDataAccessProvider.overrideWith(
              (ref, userId) async => userId == 'restored-user',
            ),
          ],
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('PROTECTED'), findsOneWidget);
      expect(find.text('Login'), findsNothing);
    });

    testWidgets('mode switch and placeholders respond', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp.router(
            routerConfig: GoRouter(
              initialLocation: '/auth',
              routes: [
                GoRoute(path: '/auth', builder: (_, _) => const AuthScreen()),
              ],
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      Future<void> tapVisible(String label) async {
        final target = find.text(label);
        await tester.scrollUntilVisible(
          target,
          200,
          scrollable: find.byWidgetPredicate(
            (w) => w is Scrollable && w.axis == Axis.vertical,
          ),
        );
        await tester.pump();
        await tester.tap(target);
        await tester.pump();
      }

      await tapVisible("Don't have an account? Sign up");
      expect(find.text('Sign Up'), findsWidgets);

      await tapVisible('Continue with Google');
      expect(find.text('Continue with Google'), findsOneWidget);
      expect(
        tester
            .widget<OutlinedButton>(
              find.widgetWithText(OutlinedButton, 'Continue with Google'),
            )
            .onPressed,
        isNull,
      );

      await tapVisible('Already have an account? Log in');
      expect(find.text('Forgot Password?'), findsOneWidget);
      await tapVisible('Forgot Password?');
      // Offline demo mode: password reset needs the connected backend.
      expect(
        find.text('Password recovery needs the connected backend.'),
        findsOneWidget,
      );
    });
  });

  group('Profile avatar display', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({
        'studyup.userProfile.v1': jsonEncode({
          ..._seedSetup,
          'avatarId': 'avatar3',
          'blobVariant': 2,
          'setupComplete': true,
          'demoSignedIn': true,
        }),
      });
    });

    testWidgets('saved PNG avatar and name show on Profile', (tester) async {
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final router = GoRouter(
        initialLocation: '/profile',
        routes: [
          GoRoute(path: '/profile', builder: (_, _) => const ProfileScreen()),
          GoRoute(
            path: '/home',
            builder: (_, _) =>
                const Scaffold(body: Center(child: Text('HOME'))),
          ),
          GoRoute(
            path: '/subjects',
            builder: (_, _) =>
                const Scaffold(body: Center(child: Text('SUBJECTS'))),
          ),
          GoRoute(
            path: '/progress',
            builder: (_, _) =>
                const Scaffold(body: Center(child: Text('PROGRESS'))),
          ),
          GoRoute(
            path: '/plan',
            builder: (_, _) =>
                const Scaffold(body: Center(child: Text('PLAN'))),
          ),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp.router(
            debugShowCheckedModeBanner: false,
            routerConfig: router,
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Alex'), findsOneWidget);
      // The saved PNG portrait renders in the header (never the Robo
      // mascot); Robo customisation lives only as one Settings entry and
      // no avatar picker is offered outside initial setup.
      expect(find.byType(UserAvatar), findsWidgets);
      expect(find.text('Customise Robo'), findsOneWidget);
      expect(find.byType(StudyRobo), findsNothing);
      final errors = <Object>[];
      Object? error = tester.takeException();
      while (error != null) {
        errors.add(error);
        error = tester.takeException();
      }
      expect(errors, isEmpty, reason: errors.join('\n---\n'));
    });

    testWidgets('Customise Robo opens its dedicated page', (tester) async {
      final router = GoRouter(
        initialLocation: '/profile',
        routes: [
          GoRoute(path: '/profile', builder: (_, _) => const ProfileScreen()),
          GoRoute(
            path: '/profile/customise-robo',
            builder: (_, _) => const CustomiseRoboPage(),
          ),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp.router(
            debugShowCheckedModeBanner: false,
            routerConfig: router,
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      await tester.tap(find.text('Customise Robo'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      // Dedicated page with all three shapes and the preview.
      expect(find.text('Preview'), findsOneWidget);
      expect(find.byKey(const ValueKey('robo-shape-square')), findsOneWidget);
      expect(find.byKey(const ValueKey('robo-shape-circle')), findsOneWidget);
      expect(find.byKey(const ValueKey('robo-shape-hexagon')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
