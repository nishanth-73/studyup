import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:studyup/features/home/presentation/home_screen.dart';
import 'package:studyup/features/robo/robo_avatar.dart';
import 'package:studyup/features/profile/presentation/profile_screen.dart';
import 'package:studyup/features/profile/presentation/setup_profile_screen.dart';

GoRouter _router() => GoRouter(
  initialLocation: '/home',
  routes: [
    GoRoute(path: '/home', builder: (_, _) => const HomeScreen()),
    GoRoute(
      path: '/subjects',
      builder: (_, _) => const Scaffold(body: Text('S')),
    ),
    GoRoute(
      path: '/subject/:id',
      builder: (_, _) => const Scaffold(body: Text('D')),
    ),
    GoRoute(
      path: '/progress',
      builder: (_, _) => const Scaffold(body: Text('P')),
    ),
    GoRoute(path: '/profile', builder: (_, _) => const ProfileScreen()),
    GoRoute(
      path: '/plan',
      builder: (_, _) => const Scaffold(body: Text('L')),
    ),
    GoRoute(
      path: '/setup-profile',
      builder: (_, _) => const SetupProfileScreen(),
    ),
    GoRoute(
      path: '/setup-goal',
      builder: (_, _) => const Scaffold(body: Text('G')),
    ),
  ],
);

Future<void> _pump(WidgetTester tester, String location, String name) async {
  final router = _router();
  addTearDown(router.dispose);
  router.go(location);
  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp.router(
        debugShowCheckedModeBanner: false,
        routerConfig: router,
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(seconds: 2));
  Object? e = tester.takeException();
  while (e != null) {
    // ignore: avoid_print
    print('$name EXC: $e');
    e = tester.takeException();
  }
  expect(
    find.byType(RoboAvatar),
    findsNWidgets(
      name == 'profile'
          ? 0 // PNG avatar header; Robo customisation removed.
          : name == 'setup'
          ? 0 // PNG avatar picker.
          : 1, // Home Robo in the mascot area.
    ),
  );
  await expectLater(
    find.byType(MaterialApp),
    matchesGoldenFile('goldens/restore_$name.png'),
  );
}

void main() {
  testWidgets('restore goldens', (tester) async {
    SharedPreferences.setMockInitialValues({
      'studyup.userProfile.v1': '{"ownerId":"local","displayName":"Alex","blobName":"alex","onboardingComplete":true,"avatarId":"avatar3","blobVariant":2,"slidesSeen":true,"setupComplete":true,"demoSignedIn":true,"demoEmail":""}',
      // Goldens capture the post-prompt app: the one-time notification
      // explanation dialog is covered separately, not in every screenshot.
      'studyup.notif.permissionPrompted.v1': true,
    });
    tester.view.physicalSize = const Size(1080, 1920);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await _pump(tester, '/home', 'home');
    await _pump(tester, '/profile', 'profile');
    await _pump(tester, '/setup-profile', 'setup');
    // flutter_test blocks real HTTP, so google_fonts runtime fetches fail
    // asynchronously. Settle fully, then drain every straggler so late
    // font errors cannot fail the run after the goldens already matched.
    await tester.pump(const Duration(seconds: 5));
    Object? leftover = tester.takeException();
    while (leftover != null) {
      // ignore: avoid_print
      print('restore teardown EXC: $leftover');
      leftover = tester.takeException();
    }
  });
}
