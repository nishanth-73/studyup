import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:studyup/features/avatar/presentation/avatar_widgets.dart';
import 'package:studyup/features/home/presentation/home_controller.dart';
import 'package:studyup/features/home/presentation/home_screen.dart';
import 'package:studyup/features/profile/presentation/profile_screen.dart';
import 'package:studyup/features/robo/robo_avatar.dart';
import 'package:studyup/features/robo/robo_customize.dart';
import 'package:studyup/features/robo/robo_events.dart';
import 'package:studyup/features/robo/robo_mood.dart';
import 'package:studyup/features/robo/robo_rig.dart';
import 'package:studyup/features/robo/robo_shape.dart';
import 'package:studyup/features/robo/robo_shape_selector.dart';
import 'package:studyup/features/robo/robo_state.dart';
import 'package:studyup/features/robo/robo_types.dart';
import 'package:studyup/features/robo/study_robo.dart';

void main() {
  void expectNoErrors(WidgetTester tester) {
    final errors = <Object>[];
    Object? error = tester.takeException();
    while (error != null) {
      errors.add(error);
      error = tester.takeException();
    }
    expect(errors, isEmpty, reason: errors.join('\n---\n'));
  }

  group('Robo library surface', () {
    test('exactly three shapes, no more', () {
      expect(RoboShape.values, [
        RoboShape.square,
        RoboShape.circle,
        RoboShape.hexagon,
      ]);
      expect(RoboShapeSelector.options.length, 3);
    });

    test('exactly the nine required states, no extras', () {
      expect(RoboState.values, [
        RoboState.idle,
        RoboState.thinking,
        RoboState.searching,
        RoboState.listening,
        RoboState.speaking,
        RoboState.working,
        RoboState.happy,
        RoboState.error,
        RoboState.sleeping,
      ]);
    });

    test('shape names match the required labels', () {
      expect(roboShapeName(RoboShape.square), 'Square');
      expect(roboShapeName(RoboShape.circle), 'Circle');
      expect(roboShapeName(RoboShape.hexagon), 'Hexagon');
    });
  });

  group('RoboShape persistence', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('fresh install defaults to square', () async {
      final controller = RoboShapeController();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(controller.state, RoboShape.square);
      controller.dispose();
    });

    test('selection persists across restarts', () async {
      final first = RoboShapeController();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      await first.select(RoboShape.hexagon);
      expect(first.state, RoboShape.hexagon);
      first.dispose();

      final second = RoboShapeController();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(second.state, RoboShape.hexagon);
      second.dispose();
    });

    test('unknown stored values fall back to square', () {
      expect(decodeShape(null), RoboShape.square);
      expect(decodeShape(''), RoboShape.square);
      expect(decodeShape('blob'), RoboShape.square);
      expect(decodeShape('triangle'), RoboShape.square);
      expect(decodeShape('circle'), RoboShape.circle);
      expect(decodeShape('hexagon'), RoboShape.hexagon);
      expect(encodeShape(RoboShape.circle), 'circle');
    });

    testWidgets('selector offers exactly three shapes and saves', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({});
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: Scaffold(body: RoboShapeSelector())),
        ),
      );
      await tester.pump();
      expect(find.byType(RoboAvatar), findsNWidgets(3));
      await tester.tap(find.byKey(const ValueKey('robo-shape-circle')));
      await tester.pump();
      expect(container.read(roboShapeProvider), RoboShape.circle);
    });
  });

  group('resolveRoboMood priority', () {
    RoboMood base({
      bool running = false,
      bool paused = false,
      double ratio = 0.0,
      int total = 0,
      int done = 0,
    }) => resolveRoboMood(
      sessionRunning: running,
      sessionPaused: paused,
      progressRatio: ratio,
      tasksTotal: total,
      tasksDone: done,
    );

    test('no session and no tasks resolves idle with Hii', () {
      final mood = base();
      expect(mood.state, RoboState.idle);
      expect(mood.quotes, ['Hii!']);
    });

    test('empty task list never counts as all completed', () {
      expect(base(total: 0, done: 0).state, RoboState.idle);
    });

    test('active session at 10% resolves thinking', () {
      final mood = base(running: true, ratio: 0.10);
      expect(mood.state, RoboState.thinking);
      expect(mood.label, 'Thinking...');
      expect(mood.quotes.first, "Let's begin!");
    });

    test('active session at 30% resolves searching', () {
      expect(base(running: true, ratio: 0.30).state, RoboState.searching);
    });

    test('active session at 50% resolves listening', () {
      expect(base(running: true, ratio: 0.50).state, RoboState.listening);
    });

    test('active session at 70% resolves speaking', () {
      expect(base(running: true, ratio: 0.70).state, RoboState.speaking);
    });

    test('active session at 85% resolves working', () {
      final mood = base(running: true, ratio: 0.85);
      expect(mood.state, RoboState.working);
      expect(mood.quotes.first, 'Deep focus!');
    });

    test('active session at 97% and beyond resolves happy', () {
      expect(base(running: true, ratio: 0.97).state, RoboState.happy);
      expect(base(running: true, ratio: 1.50).state, RoboState.happy);
    });

    test('phase boundaries adapt to the configured goal', () {
      // 20% of any goal is the thinking/searching edge.
      expect(base(running: true, ratio: 0.199).state, RoboState.thinking);
      expect(base(running: true, ratio: 0.20).state, RoboState.searching);
      expect(base(running: true, ratio: 0.949).state, RoboState.working);
      expect(base(running: true, ratio: 0.95).state, RoboState.happy);
    });

    test('running sessions outrank task status', () {
      final mood = base(running: true, ratio: 0.05, total: 3, done: 3);
      expect(mood.state, RoboState.thinking);
    });

    test('paused session resolves calm error with restart quote', () {
      final mood = base(paused: true, total: 3, done: 3);
      expect(mood.state, RoboState.error);
      expect(mood.calmError, isTrue);
      expect(mood.label, 'Paused');
      expect(mood.quotes.first, 'Ready to start again?');
    });

    test('tasks waiting and none done resolves sleeping', () {
      final mood = base(total: 3, done: 0);
      expect(mood.state, RoboState.sleeping);
      expect(mood.quotes.first, 'A task is waiting!');
    });

    test('some tasks done resolves working', () {
      final mood = base(total: 3, done: 1);
      expect(mood.state, RoboState.working);
      expect(mood.quotes.first, 'Busy day!');
    });

    test('all tasks done resolves happy', () {
      final mood = base(total: 2, done: 2);
      expect(mood.state, RoboState.happy);
      expect(mood.quotes.first, 'All tasks done!');
    });

    test('mood keys are stable for identical situations', () {
      expect(
        base(running: true, ratio: 0.5).key,
        base(running: true, ratio: 0.5).key,
      );
      expect(
        base(running: true, ratio: 0.5).key,
        isNot(base(running: true, ratio: 0.65).key),
      );
    });
  });

  group('Robo shell color', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('fresh install defaults to StudyUp yellow', () async {
      final controller = RoboColorController();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(controller.state, const Color(0xFFFDD679));
      controller.dispose();
    });

    test('color choice persists across restarts', () async {
      final first = RoboColorController();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      await first.select(const Color(0xFF8BC48A));
      expect(first.state, const Color(0xFF8BC48A));
      first.dispose();

      final second = RoboColorController();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(second.state, const Color(0xFF8BC48A));
      second.dispose();
    });

    test('exactly five shell choices starting with the default', () {
      expect(roboShellChoices.length, 5);
      expect(roboShellChoices.first, const Color(0xFFFDD679));
    });

    testWidgets('tapping a shape opens its customize sheet', (tester) async {
      SharedPreferences.setMockInitialValues({});
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(home: Scaffold(body: RoboShapeSelector())),
        ),
      );
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('robo-shape-circle')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('Customize Robo · Circle'), findsOneWidget);
      expect(find.text('Shell color'), findsOneWidget);
      expectNoErrors(tester);
    });

    testWidgets('picking a swatch persists the shell color', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: Scaffold(body: RoboShapeSelector())),
        ),
      );
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('robo-shape-square')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      await tester.tap(find.byKey(const ValueKey('robo-color-ff8bc48a')));
      await tester.pump();
      expect(container.read(roboShellColorProvider), const Color(0xFF8BC48A));
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getInt(RoboColorController.storageKey), 0xFF8BC48A);
      expectNoErrors(tester);
    });
  });

  group('celebration events', () {
    tearDown(() {
      RoboEvents.instance.reset();
    });

    test('celebrate sets a window that expires via one-shot timer', () async {
      final events = RoboEvents.instance;
      expect(events.isCelebrating(DateTime(2026, 1, 1)), isFalse);
      events.celebrate(duration: const Duration(milliseconds: 20));
      expect(events.isCelebrating(DateTime(2026, 1, 1)), isTrue);
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(events.happyUntil.value, isNull);
    });

    test('re-celebrating extends the window', () {
      final events = RoboEvents.instance;
      final t0 = DateTime(2026, 5, 5, 12);
      events.now = () => t0;
      events.celebrate(duration: const Duration(seconds: 30));
      events.now = () => t0.add(const Duration(seconds: 20));
      events.celebrate(duration: const Duration(seconds: 30));
      expect(events.isCelebrating(t0.add(const Duration(seconds: 40))), isTrue);
      expect(
        events.isCelebrating(t0.add(const Duration(seconds: 55))),
        isFalse,
      );
      events.now = DateTime.now;
    });
  });

  group('Robo rig + avatar wiring', () {
    test('rig advances with time and switches state', () {
      final rig = RoboRig(state: RoboState.working, shape: RoboShape.square);
      addTearDown(rig.dispose);
      rig.advance(0.5);
      expect(rig.time, greaterThan(0));
      rig.setState(RoboState.happy);
      expect(rig.state, RoboState.happy);
      expect(rig.isTransitioning, isTrue);
      rig.setShape(RoboShape.hexagon);
      expect(rig.shape, RoboShape.hexagon);
    });

    testWidgets('all nine states display with animation, then dispose', (
      tester,
    ) async {
      for (final state in RoboState.values) {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: RoboAvatar(shape: RoboShape.circle, state: state, size: 96),
            ),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        expect(find.bySemanticsLabel('Robot, ${state.name}'), findsOneWidget);
        expect(tester.takeException(), isNull);
      }
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      expect(tester.takeException(), isNull);
    });

    testWidgets('every shape renders', (tester) async {
      for (final shape in RoboShape.values) {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(body: RoboAvatar(shape: shape, size: 96)),
          ),
        );
        await tester.pump(const Duration(milliseconds: 100));
        expect(tester.takeException(), isNull);
      }
      await tester.pumpWidget(const SizedBox.shrink());
    });
  });

  group('Home and Profile share one Robo', () {
    GoRouter routerFor(Widget child) {
      return GoRouter(
        initialLocation: '/',
        routes: [GoRoute(path: '/', builder: (_, _) => child)],
      );
    }

    Future<void> pumpScreen(WidgetTester tester, Widget child) async {
      final router = routerFor(child);
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

    testWidgets('Home shows StudyRobo with the saved shape', (tester) async {
      SharedPreferences.setMockInitialValues({
        'studyup.roboShape.v1': 'circle',
      });
      await pumpScreen(tester, const HomeScreen());
      expect(find.byType(StudyRobo), findsOneWidget);
      expect(
        tester.widget<RoboAvatar>(find.byType(RoboAvatar)).shape,
        RoboShape.circle,
      );
      // Robo alone is visually enlarged: a bounded scale wraps StudyRobo
      // while its layout box keeps the exact card-row allocation.
      final scales = find
          .ancestor(
            of: find.byType(StudyRobo),
            matching: find.byType(Transform),
          )
          .evaluate()
          .map((e) => (e.widget as Transform).transform.getMaxScaleOnAxis())
          .toList();
      expect(scales, contains(closeTo(1.5, 1e-9)));
      final box = tester.getSize(
        find
            .ancestor(
              of: find.byType(StudyRobo),
              matching: find.byType(SizedBox),
            )
            .first,
      );
      expect(box, const Size(112, 176));
      Object? error = tester.takeException();
      var guard = 0;
      while (error != null && guard < 20) {
        final text = '$error';
        expect(
          text.contains('google_fonts') || text.contains('Failed to load'),
          isTrue,
          reason: 'Unexpected error: $error',
        );
        error = tester.takeException();
        guard++;
      }
    });

    testWidgets('Profile shows the PNG avatar plus Robo settings entry', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({
        'studyup.userProfile.v1': '{"ownerId":"local","displayName":"Alex","blobName":"alex","avatarId":"avatar3","onboardingComplete":true,"slidesSeen":true,"setupComplete":true,"demoSignedIn":true}',
      });
      await pumpScreen(tester, const ProfileScreen());
      expect(find.byType(StudyRobo), findsNothing);
      // The saved PNG portrait renders in the header; Robo lives only as
      // one Settings entry (no inline previews, no avatar confusion).
      expect(find.byType(UserAvatar), findsWidgets);
      expect(find.text('Customise Robo'), findsOneWidget);
      expect(find.text('Your Blob'), findsNothing);
    });
    testWidgets('enlarged Robo stays on small screens', (tester) async {
      SharedPreferences.setMockInitialValues({});
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await pumpScreen(tester, const HomeScreen());
      expect(find.byType(StudyRobo), findsOneWidget);
      // Layout box is fully inside the 320px viewport; painting may
      // extend only into the fixed gap/padding around it.
      final box = tester.getRect(
        find
            .ancestor(
              of: find.byType(StudyRobo),
              matching: find.byType(SizedBox),
            )
            .first,
      );
      expect(box.left, greaterThanOrEqualTo(0));
      expect(box.right, lessThanOrEqualTo(320));
      Object? error = tester.takeException();
      var guard = 0;
      while (error != null && guard < 20) {
        final text = '$error';
        expect(
          text.contains('google_fonts') || text.contains('Failed to load'),
          isTrue,
          reason: 'Unexpected error: $error',
        );
        error = tester.takeException();
        guard++;
      }
    });
  });

  group('StudyRobo live moods and quotes', () {
    tearDown(() => RoboEvents.instance.reset());
    String runningSession(DateTime start) => jsonEncode([
      {
        'id': 's1',
        'subjectId': 'general',
        'subjectName': 'Daily Study',
        'checkInTime': start.toIso8601String(),
        'checkOutTime': null,
        'pausedSeconds': 0,
        'studySegments': [
          {'startTime': start.toIso8601String(), 'endTime': null},
        ],
        'resumedAt': start.toIso8601String(),
      },
    ]);

    String pausedSession(DateTime start, DateTime pausedAt) => jsonEncode([
      {
        'id': 's1',
        'subjectId': 'general',
        'subjectName': 'Daily Study',
        'checkInTime': start.toIso8601String(),
        'checkOutTime': null,
        'pausedSeconds': pausedAt.difference(start).inSeconds,
        'studySegments': [
          {
            'startTime': start.toIso8601String(),
            'endTime': pausedAt.toIso8601String(),
          },
        ],
        'resumedAt': null,
      },
    ]);

    Map<String, Object?> taskRow(String id, bool done, DateTime day) => {
      'id': id,
      'title': id,
      'description': '',
      'startMinutes': 540,
      'endMinutes': 600,
      'isDone': done,
      'date': day.toIso8601String(),
    };

    String todayKey() {
      final now = DateTime.now();
      final mm = now.month.toString().padLeft(2, '0');
      final dd = now.day.toString().padLeft(2, '0');
      return '${now.year}-$mm-$dd';
    }

    Future<void> pumpMascot(WidgetTester tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(home: Scaffold(body: StudyRobo(size: 120))),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
    }

    testWidgets('idle shows Hii immediately', (tester) async {
      SharedPreferences.setMockInitialValues({
        'studyup.tasks.starterSeeded.v1': true,
      });
      await pumpMascot(tester);
      expect(find.text('Hii!'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('phase label shows first, quote after ~3s', (tester) async {
      final start = DateTime.now().subtract(const Duration(minutes: 30));
      SharedPreferences.setMockInitialValues({
        'studyup.studySessions.v1': runningSession(start),
        'studyup.tasks.starterSeeded.v1': true,
      });
      await pumpMascot(tester);
      // ~6% of the default goal: thinking phase label first.
      expect(find.text('Thinking...'), findsOneWidget);
      expect(find.text("Let's begin!"), findsNothing);
      await tester.pump(const Duration(seconds: 3));
      expect(find.text("Let's begin!"), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('check-out shows Paused, then a restart quote', (tester) async {
      final start = DateTime.now().subtract(const Duration(minutes: 30));
      SharedPreferences.setMockInitialValues({
        'studyup.studySessions.v1': pausedSession(
          start,
          start.add(const Duration(minutes: 10)),
        ),
        'studyup.tasks.starterSeeded.v1': true,
      });
      await pumpMascot(tester);
      expect(find.text('Paused'), findsOneWidget);
      await tester.pump(const Duration(seconds: 3));
      expect(find.text('Ready to start again?'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('check-in again resolves the phase from progress', (
      tester,
    ) async {
      final start = DateTime.now().subtract(const Duration(minutes: 240));
      SharedPreferences.setMockInitialValues({
        'studyup.studySessions.v1': runningSession(start),
        'studyup.tasks.starterSeeded.v1': true,
      });
      await pumpMascot(tester);
      // 50% of the default goal: listening phase.
      expect(find.text('Listening...'), findsOneWidget);
      await tester.pump(const Duration(seconds: 3));
      expect(find.text("I'm all ears!"), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('waiting tasks show Sleeping, then a nudge quote', (
      tester,
    ) async {
      final day = DateTime.now();
      SharedPreferences.setMockInitialValues({
        'studyup.studySessions.v1': jsonEncode([]),
        'studyup.tasks.v1': jsonEncode({
          todayKey(): [taskRow('a', false, day), taskRow('b', false, day)],
        }),
        'studyup.tasks.starterSeeded.v1': true,
      });
      await pumpMascot(tester);
      expect(find.text('Sleeping...'), findsOneWidget);
      await tester.pump(const Duration(seconds: 3));
      expect(find.text('A task is waiting!'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('task add, complete, and delete update the mood', (
      tester,
    ) async {
      final day = DateTime.now();
      SharedPreferences.setMockInitialValues({
        'studyup.studySessions.v1': jsonEncode([]),
        'studyup.tasks.v1': jsonEncode({
          todayKey(): [taskRow('a', false, day)],
        }),
        'studyup.tasks.starterSeeded.v1': true,
      });
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: Scaffold(body: StudyRobo(size: 120))),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Sleeping...'), findsOneWidget);

      final home = container.read(homeControllerProvider.notifier);
      home.toggleTask('a');
      await tester.pump();
      expect(find.text('Happy!'), findsOneWidget);

      home.deleteTask('a');
      await tester.pump();
      expect(find.text('Hii!'), findsOneWidget);
      // Flush the task-completion celebration timer so teardown is clean.
      await tester.pump(const Duration(seconds: 31));
      expect(tester.takeException(), isNull);
    });
  });
}
