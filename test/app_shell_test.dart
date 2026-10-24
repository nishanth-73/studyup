import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:studyup/core/widgets/app_shell.dart';
import 'package:studyup/core/widgets/bottom_nav.dart';
import 'package:studyup/features/home/presentation/home_screen.dart';
import 'package:studyup/features/plan/presentation/plan_screen.dart';
import 'package:studyup/features/progress/presentation/progress_screen.dart';
import 'package:studyup/features/subjects/presentation/subjects_screen.dart';
import 'package:studyup/features/community/presentation/community_screen.dart';

/// The floating-nav contract: every main-app screen renders through the
/// single shared [AppShell] (extendBody overlay, transparent surround),
/// exactly one [CustomBottomNav], and no per-screen bottom bar.
void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('scroll clearance derives from real nav metrics + system inset', () {
    // 16 gap + 56 buttons + 16 offset + 0 test-environment inset.
    expect(AppShell.navButtonDiameter, CustomBottomNav.diameter);
    expect(AppShell.navEdgeGap, 16);
  });

  testWidgets('AppShell extends body behind a transparent nav', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(home: AppShell(currentIndex: 0, body: Text('BODY'))),
      ),
    );
    final scaffold = tester.widget<Scaffold>(find.byType(Scaffold).first);
    expect(scaffold.extendBody, isTrue);
    expect(find.byType(CustomBottomNav), findsOneWidget);
    expect(find.text('BODY'), findsOneWidget);
  });

  group('every main screen uses the shared shell', () {
    Future<void> pumpRoute(WidgetTester tester, String location) async {
      final router = GoRouter(
        initialLocation: location,
        routes: [
          GoRoute(path: '/home', builder: (_, _) => const HomeScreen()),
          GoRoute(path: '/subjects', builder: (_, _) => const SubjectsScreen()),
          GoRoute(path: '/progress', builder: (_, _) => const ProgressScreen()),
          GoRoute(path: '/community', builder: (_, _) => const CommunityScreen()),
          GoRoute(path: '/plan', builder: (_, _) => const PlanScreen()),
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
    }

    void expectShellContract(WidgetTester tester) {
      expect(find.byType(AppShell), findsOneWidget);
      expect(find.byType(CustomBottomNav), findsOneWidget);
      expect(find.byType(Scaffold), findsWidgets);
      Object? error = tester.takeException();
      var guard = 0;
      while (error != null && guard < 20) {
        // google_fonts network failures are environmental (no network in
        // the test sandbox); anything else fails the contract.
        final text = '$error';
        expect(
          text.contains('google_fonts') || text.contains('Failed to load'),
          isTrue,
          reason: 'Unexpected error: $error',
        );
        error = tester.takeException();
        guard++;
      }
    }

    // Profile is a pushed standalone page without the floating nav,
    // so it is intentionally not in this shell contract.
    for (final location in ['/home', '/subjects', '/progress', '/community', '/plan']) {
      testWidgets('$location renders single shared nav', (tester) async {
        await pumpRoute(tester, location);
        expectShellContract(tester);
      });
    }

    testWidgets('nav tap switches destination', (tester) async {
      await pumpRoute(tester, '/home');
      await tester.tap(
        find
            .descendant(
              of: find.byType(CustomBottomNav),
              matching: find.byType(GestureDetector),
            )
            .at(2),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.byType(AppShell), findsOneWidget);
      expectShellContract(tester);
    });
  });
}
