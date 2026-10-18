import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:studyup/features/home/data/home_models.dart';
import 'package:studyup/features/profile/presentation/profile_detail_pages.dart';
import 'package:studyup/features/profile/presentation/profile_screen.dart';
import 'package:studyup/features/progress/presentation/progress_screen.dart';

GoRouter profileRouter() {
  final router = GoRouter(
    initialLocation: '/profile',
    routes: [
      GoRoute(path: '/profile', builder: (_, _) => const ProfileScreen()),
      GoRoute(
        path: '/profile/notifications',
        builder: (_, _) => const NotificationsPage(),
      ),
      GoRoute(
        path: '/profile/privacy',
        builder: (_, _) => const PrivacyDataPage(),
      ),
      GoRoute(path: '/profile/help', builder: (_, _) => const HelpPage()),
      GoRoute(
        path: '/profile/feedback',
        builder: (_, _) => const FeedbackPage(),
      ),
    ],
  );
  return router;
}

Future<void> pumpProfile(WidgetTester tester) async {
  SharedPreferences.setMockInitialValues({});
  final router = profileRouter();
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

Future<void> goBack(WidgetTester tester) async {
  await tester.tap(find.byIcon(Icons.arrow_back_rounded).first);
  await tester.pumpAndSettle();
}

/// Test double for path_provider: documents dir is the system temp dir.
class _FakePathProvider extends PathProviderPlatform {
  @override
  Future<String?> getApplicationDocumentsPath() async =>
      Directory.systemTemp.path;
}

/// Settings rows sit below the fold in a lazy ListView: scroll until
/// each row is built, then tap it.
Future<void> tapRow(WidgetTester tester, String label) async {
  final row = find.text(label);
  await tester.scrollUntilVisible(
    row,
    300,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
  await tester.tap(row);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

void expectNoErrors(WidgetTester tester) {
  final errors = <Object>[];
  Object? error = tester.takeException();
  while (error != null) {
    errors.add(error);
    error = tester.takeException();
  }
  expect(errors, isEmpty, reason: errors.join('\n---\n'));
}

void main() {
  group('Profile detail pages', () {
    testWidgets('Notifications row opens switches page and back works', (
      tester,
    ) async {
      await pumpProfile(tester);
      expectNoErrors(tester);
      // Inline controls are gone from Profile itself.
      expect(find.text('Task reminders'), findsNothing);

      await tapRow(tester, 'Notifications');
      expectNoErrors(tester);
      expect(find.text('Task reminders'), findsOneWidget);
      expect(find.text('Live progress'), findsOneWidget);
      expect(find.text('Daily goal reached'), findsOneWidget);
      expect(find.byType(Switch), findsNWidgets(3));

      await goBack(tester);
      expectNoErrors(tester);
      expect(find.text('Task reminders'), findsNothing);
      expect(find.text('Privacy & data'), findsOneWidget);
    });

    testWidgets('removed rows are gone; Help and Feedback open', (
      tester,
    ) async {
      await pumpProfile(tester);
      expect(find.text('Appearance'), findsNothing);
      expect(find.text('Study reminders'), findsNothing);

      await tapRow(tester, 'Help');
      expectNoErrors(tester);
      // Compact guide: four expandable topics, no search, no shortcuts.
      expect(find.byType(TextField), findsNothing);
      expect(find.text('Open Home'), findsNothing);
      expect(find.text('Open Progress'), findsNothing);
      expect(find.text('Open Profile'), findsNothing);
      for (final topic in [
        'Home',
        'Subjects',
        'Focus & sessions',
        'Progress',
      ]) {
        expect(find.text(topic), findsOneWidget);
      }
      // Expanding a topic reveals its short bullet lines.
      await tester.tap(find.text('Home'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Schedule Task'), findsOneWidget);
      await tester.tap(find.text('Home'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Schedule Task'), findsNothing);
      await goBack(tester); // guide -> profile

      await tapRow(tester, 'Feedback');
      expectNoErrors(tester);
      expect(find.text('Send feedback'), findsOneWidget);
      await goBack(tester);
      expectNoErrors(tester);
    });

    testWidgets('Feedback validates and keeps draft when backend missing', (
      tester,
    ) async {
      await pumpProfile(tester);
      await tapRow(tester, 'Feedback');

      // Empty submit shows inline errors, claims nothing.
      await tester.tap(find.text('Send feedback'));
      await tester.pump();
      expect(find.text('Add a short subject (min 3 characters).'), findsOneWidget);
      expect(
        find.text('Tell us a little more (min 10 characters).'),
        findsOneWidget,
      );

      await tester.enterText(find.byType(TextField).at(0), 'Timer bug');
      await tester.enterText(
        find.byType(TextField).at(1),
        'The timer kept running after pause.',
      );
      await tester.tap(find.text('Send feedback'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expectNoErrors(tester);
      // No endpoint configured in tests: the draft is preserved and the
      // user gets an honest configuration message — never a fake "sent".
      expect(find.text('Timer bug'), findsOneWidget);
      expect(find.byType(SnackBar), findsOneWidget);

      final prefs = await SharedPreferences.getInstance();
      // Nothing is recorded as "sent"; the draft is kept for retry.
      expect(prefs.getString('studyup.feedback.v1'), isNull);
      expect(prefs.getString('studyup.feedback.draft.v1'), isNotNull);
    });

    testWidgets('Privacy page shows stored-data docs and actions', (
      tester,
    ) async {
      await pumpProfile(tester);
      await tapRow(tester, 'Privacy & data');
      expectNoErrors(tester);
      expect(find.text('Your Data'), findsOneWidget);
      expect(find.text('Data Storage & Services'), findsOneWidget);
      expect(find.textContaining('not encrypted'), findsOneWidget);
      // Technical service names and removed sections stay out of user copy.
      expect(find.textContaining('Supabase'), findsNothing);
      expect(find.text('Your rights & choices'), findsNothing);
      expect(find.text('Copy data as JSON'), findsNothing);
      // Offline test env: demo mode, exit keeps data. The action rows sit
      // below the fold in the lazy list: scroll them into view first.
      await tester.scrollUntilVisible(
        find.text('Erase local data'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pump();
      expect(find.text('Exit demo'), findsOneWidget);
      expect(find.text('Erase local data'), findsOneWidget);
      // The ListView builds lazily: scrolling this far disposes the header
      // row (and its back arrow), so scroll back up before navigating out.
      await tester.scrollUntilVisible(
        find.byIcon(Icons.arrow_back_rounded),
        -300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pump();
      await goBack(tester);
    });

    testWidgets('Sign out with no profile explains honestly', (tester) async {
      await pumpProfile(tester);
      await tapRow(tester, 'Privacy & data');
      await tapRow(tester, 'Exit demo');
      await tester.pump();
      expect(
        find.text('No profile is signed in on this device.'),
        findsOneWidget,
      );
    });

    testWidgets('Erase asks confirmation; Cancel keeps all data', (
      tester,
    ) async {
      await pumpProfile(tester);
      SharedPreferences.setMockInitialValues({'probe.keep': 'yes'});
      await tapRow(tester, 'Privacy & data');
      await tapRow(tester, 'Erase local data');
      await tester.pump();
      // Confirmation explains scope and warns it cannot be undone.
      expect(find.text('Erase local data?'), findsOneWidget);
      expect(find.textContaining('cannot be undone'), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);
      expect(find.text('Erase Data'), findsOneWidget);

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(find.text('Erase local data?'), findsNothing);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('probe.keep'), 'yes');
      expectNoErrors(tester);
    });

    testWidgets('Erase confirm wipes local storage', (tester) async {
      // path_provider has no test double: serve the documents dir from temp.
      final previous = PathProviderPlatform.instance;
      PathProviderPlatform.instance = _FakePathProvider();
      addTearDown(() => PathProviderPlatform.instance = previous);
      // The native study-timer service never answers in tests: mock it
      // (on a real device it cancels the live tray entry and returns).
      const timerChannel = MethodChannel('studyup/study_timer');
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(timerChannel, (_) async => null);
      addTearDown(
        () => messenger.setMockMethodCallHandler(timerChannel, null),
      );
      await pumpProfile(tester);
      SharedPreferences.setMockInitialValues({'probe.keep': 'yes'});
      await tapRow(tester, 'Privacy & data');
      await tapRow(tester, 'Erase local data');
      await tester.pump();
      await tester.tap(find.text('Erase Data'));
      // The erase touches real async work (file stat, platform channels)
      // which only completes in the real async zone; bounded pumps then
      // rebuild (pumpAndSettle would spin on the restarted 1s ticker).
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(seconds: 3));
      });
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 1200));
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('probe.keep'), isNull);
      expect(find.text('All local data erased.'), findsOneWidget);
      // The confirm path navigates to '/' which the test router does not
      // define — that navigation error is a harness artifact, not app
      // behavior (the real router defines '/'). The wipe itself is done.
      final errors = <Object>[];
      Object? error = tester.takeException();
      while (error != null) {
        errors.add(error);
        error = tester.takeException();
      }
      expect(
        errors.every(
          (e) => e.toString().contains('no routes for location'),
        ),
        isTrue,
        reason: errors.join('\n---\n'),
      );
    });
  });

  group('Proxy removed sections', () {
    String todayKey() {
      final now = DateTime.now();
      return dateKey(DateTime(now.year, now.month, now.day));
    }

    Map<String, Object?> taskRow(String id, bool done) {
      final now = DateTime.now();
      final day = DateTime(now.year, now.month, now.day);
      return {
        'id': id,
        'title': id,
        'description': '',
        'startMinutes': 540,
        'endMinutes': 600,
        'isDone': done,
        'date': day.toIso8601String(),
      };
    }

    Future<void> pumpProgress(WidgetTester tester) async {
      tester.view.physicalSize = const Size(800, 1800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final router = GoRouter(
        initialLocation: '/progress',
        routes: [
          GoRoute(path: '/progress', builder: (_, _) => const ProgressScreen()),
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
      await tester.pump(const Duration(milliseconds: 500));
    }

    testWidgets('study statistics and streak/level are gone', (tester) async {
      SharedPreferences.setMockInitialValues({
        'studyup.tasks.v1': jsonEncode({
          todayKey(): [
            taskRow('a', true),
            taskRow('b', true),
            taskRow('c', false),
            taskRow('d', false),
          ],
        }),
        'studyup.tasks.starterSeeded.v1': true,
      });
      await pumpProgress(tester);
      expectNoErrors(tester);
      // Removed sections stay absent.
      expect(find.text('Study Statistics'), findsNothing);
      expect(find.text('Scheduled today'), findsNothing);
      expect(find.text('Attended today'), findsNothing);
      expect(find.text('Missed today'), findsNothing);
      expect(find.text('Attendance today'), findsNothing);
      expect(find.text('Streak & Level'), findsNothing);
      expect(find.text('Day streak'), findsNothing);
      // Old goal-percentage summary cards are gone.
      expect(find.text('Sessions today'), findsNothing);
      // Useful session content is preserved.
      expect(find.text("Today's Session"), findsOneWidget);
    });

    testWidgets('empty day has no statistics cards', (tester) async {
      SharedPreferences.setMockInitialValues({
        'studyup.tasks.v1': jsonEncode({todayKey(): []}),
        'studyup.tasks.starterSeeded.v1': true,
        'studyup.studySessions.v1': jsonEncode([]),
      });
      await pumpProgress(tester);
      expectNoErrors(tester);
      expect(find.text('Study Statistics'), findsNothing);
      expect(find.text('nothing scheduled'), findsNothing);
      expect(find.text('Day streak'), findsNothing);
      expect(find.text('Level 1'), findsNothing);
      expect(find.text('Streak & Level'), findsNothing);
      expect(find.text("Today's Session"), findsOneWidget);
    });

    testWidgets('level card shows tier + XP with no progress bar', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({
        'studyup.tasks.v1': jsonEncode({todayKey(): []}),
        'studyup.tasks.starterSeeded.v1': true,
        'studyup.studySessions.v1': jsonEncode([]),
      });
      await pumpProgress(tester);
      expectNoErrors(tester);
      await tester.scrollUntilVisible(
        find.text('Novice'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pump();
      // Level amount, tier name and total XP are shown.
      expect(find.text('Level'), findsOneWidget);
      expect(find.text('Novice'), findsOneWidget);
      expect(find.text('0 XP'), findsOneWidget);
      // The old per-level XP progress bar and label are gone.
      expect(find.byType(LinearProgressIndicator), findsNothing);
      expect(find.text('Study level'), findsNothing);
    });
  });
}
