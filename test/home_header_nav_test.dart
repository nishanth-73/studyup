import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:studyup/core/widgets/bottom_nav.dart';
import 'package:studyup/core/widgets/date_picker_sheet.dart';
import 'package:studyup/features/home/presentation/home_controller.dart';
import 'package:studyup/features/home/presentation/home_screen.dart';
import 'package:studyup/features/notifications/presentation/notification_center_screen.dart';
import 'package:studyup/features/profile/presentation/profile_screen.dart';

/// Home header composition + bottom navigation contract:
/// - top-left PNG avatar opens Profile (single Profile entry point),
/// - top-right bell opens the in-app notification center,
/// - the bottom navigation has exactly Home, Subjects, and Progress.
void main() {
  GoRouter testRouter() {
    final router = GoRouter(
      initialLocation: '/home',
      routes: [
        GoRoute(path: '/home', builder: (_, _) => const HomeScreen()),
        GoRoute(path: '/profile', builder: (_, _) => const ProfileScreen()),
        GoRoute(
          path: '/notifications',
          builder: (_, _) => const NotificationCenterScreen(),
        ),
      ],
    );
    return router;
  }

  Future<void> pumpHome(WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({
      'studyup.userProfile.v1': jsonEncode({
        'ownerId': 'local',
        'displayName': 'Alex',
        'blobName': 'alex',
        'onboardingComplete': true,
        'avatarId': 'avatar2',
        'blobVariant': 0,
        'slidesSeen': true,
        'setupComplete': true,
        'demoSignedIn': false,
        'demoEmail': '',
      }),
      'studyup.tasks.starterSeeded.v1': true,
    });
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final router = testRouter();
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
    await tester.pump(const Duration(milliseconds: 500));
  }

  testWidgets('header shows name, avatar, date-free layout, and bell', (
    tester,
  ) async {
    await pumpHome(tester);
    // Name only in the middle: no time-of-day greeting text.
    expect(find.text('Alex'), findsOneWidget);
    expect(find.textContaining('Good '), findsNothing);
    // Tapping the avatar opens Profile (its header shows the name).
    await tester.tap(find.bySemanticsLabel('Open Profile').first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Alex'), findsWidgets);
    expect(find.text('Settings'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('bell opens the in-app notification center', (tester) async {
    await pumpHome(tester);
    await tester.tap(find.bySemanticsLabel('Open notifications').first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    // Real center content (empty state with no stored rows yet).
    expect(find.text('Notifications'), findsWidgets);
    expect(find.textContaining('Nothing here yet'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('red dot appears for unread rows, clears on open', (
    tester,
  ) async {
    Finder redDot() => find.byWidgetPredicate(
      (w) =>
          w is Container &&
          w.constraints?.maxWidth == 9 &&
          (w.decoration as BoxDecoration?)?.color == Colors.red,
    );
    SharedPreferences.setMockInitialValues({
      'studyup.userProfile.v1': jsonEncode({
        'ownerId': 'local',
        'displayName': 'Alex',
        'blobName': 'alex',
        'onboardingComplete': true,
        'avatarId': 'avatar2',
        'blobVariant': 0,
        'slidesSeen': true,
        'setupComplete': true,
        'demoSignedIn': false,
        'demoEmail': '',
      }),
      'studyup.tasks.starterSeeded.v1': true,
      'studyup.notif.centerItems.v1': jsonEncode([
        {
          'id': 'goal:2026-10-13',
          'kind': 'goalReached',
          'title': 'Daily goal reached',
          'body': '480 of 480 min studied today.',
          'at': '2026-10-13T20:00:00.000',
          'dayKey': '2026-10-13',
          'read': false,
        },
      ]),
    });
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final router = testRouter();
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
    await tester.pump(const Duration(milliseconds: 500));
    // Unread row stored: the bell carries the red dot.
    expect(redDot(), findsOneWidget);
    // Opening the center marks the row read and clears the dot.
    await tester.tap(find.bySemanticsLabel('Open notifications').first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Daily goal reached'), findsOneWidget);
    // Back home: dot gone, and the row stays read across reloads.
    await tester.tap(find.byIcon(Icons.arrow_back_rounded).first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(redDot(), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('bottom nav has exactly Home, Subjects, and Progress', (
    tester,
  ) async {
    await pumpHome(tester);
    // No Add action or Quiz tab remains, and Community is gone.
    expect(find.bySemanticsLabel('Add'), findsNothing);
    expect(find.bySemanticsLabel('Quiz'), findsNothing);
    expect(find.bySemanticsLabel('Community'), findsNothing);
    final nav = find.byType(CustomBottomNav);
    expect(nav, findsOneWidget);
    for (final label in const ['Home', 'Subjects', 'Progress']) {
      expect(
        find.descendant(of: nav, matching: find.bySemanticsLabel(label)),
        findsOneWidget,
      );
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('date picker sits before Add Task and opens the calendar', (
    tester,
  ) async {
    await pumpHome(tester);
    // Only the calendar picker remains next to Add Task.
    expect(find.byTooltip('Previous day'), findsNothing);
    expect(find.byTooltip('Next day'), findsNothing);
    expect(find.byTooltip('Choose a date'), findsOneWidget);
    // Tapping the calendar opens the shared bottom-sheet calendar.
    await tester.tap(find.byTooltip('Choose a date'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Choose a date'), findsWidgets);
    expect(find.byType(PickerSheetFrame), findsOneWidget);
    // Dismiss without choosing: selection is unchanged.
    await tester.tap(find.text('Cancel'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(PickerSheetFrame), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('picking a future date opens the Add Task sheet', (tester) async {
    await pumpHome(tester);
    await tester.tap(find.byTooltip('Choose a date'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    final sheet = find.byType(PickerSheetFrame);
    expect(sheet, findsOneWidget);
    // Step two months forward: day 1 of that month is always future.
    for (var i = 0; i < 2; i++) {
      await tester.tap(find.byTooltip('Next month'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
    }
    await tester.tap(
      find.descendant(of: sheet, matching: find.text('1')).first,
    );
    await tester.pump();
    await tester.tap(find.descendant(of: sheet, matching: find.text('Done')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    // Add sheet opened immediately for the future date.
    expect(find.textContaining('Add task —'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('past date with no tasks shows the done message', (tester) async {
    SharedPreferences.setMockInitialValues({
      'studyup.userProfile.v1': jsonEncode({
        'ownerId': 'local',
        'displayName': 'Alex',
        'blobName': 'alex',
        'onboardingComplete': true,
        'avatarId': 'avatar2',
        'blobVariant': 0,
        'slidesSeen': true,
        'setupComplete': true,
        'demoSignedIn': false,
        'demoEmail': '',
      }),
      'studyup.tasks.starterSeeded.v1': true,
      'studyup.tasks.v1': jsonEncode({}),
    });
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final router = testRouter();
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
    await tester.pump(const Duration(milliseconds: 500));
    container
        .read(homeControllerProvider.notifier)
        .selectDate(DateTime(2023, 5, 17));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('No tasks done for that day'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
