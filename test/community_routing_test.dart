import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:studyup/core/router/app_router.dart';
import 'package:studyup/features/community/presentation/community_screen.dart';
import 'package:studyup/features/community/presentation/full_leaderboard_screen.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('appRouter opens CommunityScreen directly even when unauthenticated', (tester) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp.router(
          routerConfig: appRouter,
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Navigate to /community
    appRouter.go('/community');
    await tester.pumpAndSettle();

    // Verify CommunityScreen is successfully opened!
    expect(find.byType(CommunityScreen), findsOneWidget);
    expect(find.text('Community'), findsOneWidget);
    expect(find.text('Study circle rankings'), findsOneWidget);
    expect(find.text('TOP 3 THIS WEEK'), findsOneWidget);
    expect(find.text('Leaderboard'), findsOneWidget);
    expect(find.text('Invite Friends'), findsOneWidget);
  });

  testWidgets('appRouter opens /community/leaderboard directly', (tester) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp.router(
          routerConfig: appRouter,
        ),
      ),
    );
    await tester.pumpAndSettle();

    appRouter.go('/community/leaderboard');
    await tester.pumpAndSettle();

    expect(find.byType(FullLeaderboardScreen), findsOneWidget);
    expect(find.text('Leaderboard'), findsOneWidget);
  });
}

