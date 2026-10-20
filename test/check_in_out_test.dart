import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:studyup/features/progress/presentation/progress_screen.dart';
import 'package:studyup/features/progress/presentation/study_progress_controller.dart';
import 'package:studyup/features/svg_art/presentation/svg_art.dart';

void main() {
  group('Check In / Check Out session flow', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('checkIn starts a session when none is active', () async {
      final controller = StudyProgressController();
      await _waitForLoad(controller);
      final t0 = DateTime(2026, 6, 1, 10, 0, 0);
      await controller.checkIn(at: t0);

      final active = controller.state.activeSession;
      expect(active, isNotNull);
      expect(active!.isRunning, isTrue);
      expect(active.checkInTime, t0);
      expect(
        active.durationAt(t0.add(const Duration(seconds: 5))).inSeconds,
        5,
      );
      controller.dispose();
    });

    test('checkOut pauses and freezes elapsed time', () async {
      final controller = StudyProgressController();
      await _waitForLoad(controller);
      final t0 = DateTime(2026, 6, 1, 10, 0, 0);
      await controller.checkIn(at: t0);
      await controller.checkOut(at: t0.add(const Duration(seconds: 10)));

      final active = controller.state.activeSession!;
      expect(active.isPaused, isTrue);
      expect(active.pausedSeconds, 10);
      // Time stops accumulating as soon as check-out is processed.
      expect(active.durationAt(t0.add(const Duration(hours: 5))).inSeconds, 10);
      controller.dispose();
    });

    test('checkIn resumes the same paused session', () async {
      final controller = StudyProgressController();
      await _waitForLoad(controller);
      final t0 = DateTime(2026, 6, 1, 10, 0, 0);
      await controller.checkIn(at: t0);
      await controller.checkOut(at: t0.add(const Duration(seconds: 10)));
      final pausedId = controller.state.activeSession!.id;

      // Resume 50 wall-seconds later: same record, no double counting.
      await controller.checkIn(at: t0.add(const Duration(seconds: 60)));
      final resumed = controller.state.activeSession!;
      expect(resumed.id, pausedId);
      expect(resumed.isRunning, isTrue);
      expect(
        resumed.durationAt(t0.add(const Duration(seconds: 65))).inSeconds,
        15,
      );
      controller.dispose();
    });

    test('checkIn while running never duplicates the session', () async {
      final controller = StudyProgressController();
      await _waitForLoad(controller);
      final t0 = DateTime(2026, 6, 1, 10, 0, 0);
      await controller.checkIn(at: t0);
      // Rapid repeated taps: serialized no-ops, still exactly one session.
      await Future.wait([
        controller.checkIn(at: t0.add(const Duration(seconds: 1))),
        controller.checkIn(at: t0.add(const Duration(seconds: 2))),
        controller.checkIn(at: t0.add(const Duration(seconds: 3))),
      ]);
      expect(controller.state.sessions.length, 1);
      expect(controller.state.activeSession!.isRunning, isTrue);
      controller.dispose();
    });

    test(
      'direct concurrent starts are serialized and cannot duplicate',
      () async {
        final controller = StudyProgressController();
        await _waitForLoad(controller);
        final t0 = DateTime(2026, 6, 1, 10, 0, 0);

        await expectLater(
          Future.wait([
            controller.startSession(checkInTime: t0),
            controller.startSession(
              checkInTime: t0.add(const Duration(seconds: 1)),
            ),
          ]),
          throwsStateError,
        );

        expect(controller.state.sessions, hasLength(1));
        expect(controller.state.activeSession!.checkInTime, t0);
        controller.dispose();
      },
    );

    test('checkOut is a safe no-op with no session or when paused', () async {
      final controller = StudyProgressController();
      await _waitForLoad(controller);
      // No session at all: no crash, no records created.
      await controller.checkOut();
      expect(controller.state.sessions, isEmpty);

      final t0 = DateTime(2026, 6, 1, 10, 0, 0);
      await controller.checkIn(at: t0);
      await controller.checkOut(at: t0.add(const Duration(seconds: 7)));
      // Already paused: no additional time is banked.
      await controller.checkOut(at: t0.add(const Duration(seconds: 70)));
      expect(controller.state.activeSession!.pausedSeconds, 7);
      controller.dispose();
    });

    test('elapsed time accumulates across check-out/check-in cycles', () async {
      final controller = StudyProgressController();
      await _waitForLoad(controller);
      final t0 = DateTime(2026, 6, 1, 10, 0, 0);
      await controller.checkIn(at: t0);
      await controller.checkOut(at: t0.add(const Duration(minutes: 20)));
      await controller.checkIn(at: t0.add(const Duration(minutes: 50)));
      await controller.checkOut(at: t0.add(const Duration(minutes: 65)));
      expect(
        controller.state.minutesForDate(
          DateTime(2026, 6, 1),
          now: t0.add(const Duration(minutes: 65)),
        ),
        35,
      );
      controller.dispose();
    });
  });

  group('Today’s Session progress indicator', () {
    const timerChannel = MethodChannel('studyup/study_timer');

    setUp(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(timerChannel, (_) async => null);
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(timerChannel, null);
    });

    String sessionJson(DateTime at) => jsonEncode([
      {
        'id': 's1',
        'subjectId': 'general',
        'subjectName': 'Daily Study',
        'checkInTime': at.toIso8601String(),
        'checkOutTime': null,
        'pausedSeconds': 0,
        'studySegments': [
          {'startTime': at.toIso8601String(), 'endTime': null},
        ],
        'resumedAt': at.toIso8601String(),
      },
    ]);

    Future<ProviderContainer> pumpProgress(WidgetTester tester) async {
      final start = DateTime.now().subtract(const Duration(minutes: 5));
      SharedPreferences.setMockInitialValues({
        'studyup.studySessions.v1': sessionJson(start),
        'studyup.notif.liveProgress.v1': false,
      });
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: ProgressScreen()),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      return container;
    }

    testWidgets('shows the circular progress ring while studying and paused', (
      tester,
    ) async {
      final container = await pumpProgress(tester);
      final ring = find.byKey(const ValueKey('today-session-goal-ring'));
      expect(ring, findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsWidgets);
      expect(find.byType(SvgArt), findsNothing);

      await container.read(studyProgressProvider.notifier).checkOut();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(ring, findsOneWidget);
      expect(find.byType(SvgArt), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('ring remains available after resuming a paused session', (
      tester,
    ) async {
      final container = await pumpProgress(tester);
      final notifier = container.read(studyProgressProvider.notifier);
      await notifier.checkOut();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      await notifier.checkIn();
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(
        find.byKey(const ValueKey('today-session-goal-ring')),
        findsOneWidget,
      );
      expect(find.byType(SvgArt), findsNothing);

      // Leave the session paused so the 1s ticker stops teardown-clean.
      await notifier.checkOut();
      await tester.pump();
      expect(
        find.byKey(const ValueKey('today-session-goal-ring')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });
  });
}

Future<void> _waitForLoad(StudyProgressController controller) async {
  for (var attempt = 0; attempt < 20 && !controller.state.isLoaded; attempt++) {
    await Future<void>.delayed(const Duration(milliseconds: 1));
  }
  expect(controller.state.isLoaded, isTrue);
  expect(controller.state.error, isNull);
}
