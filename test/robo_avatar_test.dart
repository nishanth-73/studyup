import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:studyup/features/robo/robo.dart';

Widget _host(Widget child) => Directionality(
  textDirection: TextDirection.ltr,
  child: Center(child: child),
);

void main() {
  testWidgets('renders every shape x state combination', (tester) async {
    await tester.pumpWidget(
      _host(
        SingleChildScrollView(
          child: Wrap(
            children: <Widget>[
              for (final shape in RoboShape.values)
                for (final state in RoboState.values)
                  RoboAvatar(shape: shape, state: state, size: 64),
            ],
          ),
        ),
      ),
    );
    expect(find.byType(RoboAvatar), findsNWidgets(27));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('parent can change state, shape and size', (tester) async {
    Widget build(RoboShape shape, RoboState state, double size) =>
        _host(RoboAvatar(shape: shape, state: state, size: size));

    await tester.pumpWidget(build(RoboShape.square, RoboState.idle, 100));
    await tester.pump(const Duration(milliseconds: 200));
    for (final state in RoboState.values) {
      await tester.pumpWidget(build(RoboShape.square, state, 100));
      await tester.pump(const Duration(milliseconds: 100));
    }
    for (final shape in RoboShape.values) {
      await tester.pumpWidget(build(shape, RoboState.happy, 100));
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.pumpWidget(build(RoboShape.hexagon, RoboState.happy, 220));
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.getSize(find.byType(RoboAvatar)), const Size(220, 220));
    await tester.pumpWidget(build(RoboShape.hexagon, RoboState.happy, 64));
    expect(tester.getSize(find.byType(RoboAvatar)), const Size(64, 64));
    expect(tester.takeException(), isNull);
  });

  testWidgets('animated: false settles and schedules no more frames', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(const RoboAvatar(state: RoboState.thinking, animated: false)),
    );
    await tester.pumpAndSettle();
    expect(tester.binding.hasScheduledFrame, isFalse);

    // A state change eases in once, then the loop stops again.
    await tester.pumpWidget(
      _host(const RoboAvatar(state: RoboState.happy, animated: false)),
    );
    await tester.pumpAndSettle();
    expect(tester.binding.hasScheduledFrame, isFalse);
  });

  testWidgets('animated: true keeps animating by itself', (tester) async {
    await tester.pumpWidget(_host(const RoboAvatar(state: RoboState.idle)));
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.binding.hasScheduledFrame, isTrue);
  });

  testWidgets('paused stops the loop but keeps the state; resume restarts', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(_host(const RoboAvatar(state: RoboState.speaking)));
    await tester.pump(const Duration(milliseconds: 300));

    await tester.pumpWidget(
      _host(const RoboAvatar(state: RoboState.speaking, paused: true)),
    );
    await tester.pumpAndSettle();
    expect(tester.binding.hasScheduledFrame, isFalse);
    expect(find.bySemanticsLabel('Robot, speaking'), findsOneWidget);

    await tester.pumpWidget(_host(const RoboAvatar(state: RoboState.speaking)));
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.binding.hasScheduledFrame, isTrue);
    handle.dispose();
  });

  testWidgets('reduced motion shows the still pose', (tester) async {
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: const RoboAvatar(state: RoboState.searching),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.binding.hasScheduledFrame, isFalse);
  });

  testWidgets('respectReducedMotion: false keeps animating', (tester) async {
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: const RoboAvatar(
            state: RoboState.searching,
            respectReducedMotion: false,
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.binding.hasScheduledFrame, isTrue);
  });

  testWidgets('disposes cleanly while animating', (tester) async {
    await tester.pumpWidget(_host(const RoboAvatar(state: RoboState.working)));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpWidget(_host(const SizedBox()));
    await tester.pump(const Duration(seconds: 1));
    expect(tester.takeException(), isNull);
    expect(tester.binding.hasScheduledFrame, isFalse);
  });

  testWidgets('interactive avatars react to hover and tap', (tester) async {
    await tester.pumpWidget(
      _host(const RoboAvatar(state: RoboState.idle, interactive: true)),
    );
    final gesture = await tester.createGesture(
      kind: ui.PointerDeviceKind.mouse,
    );
    await gesture.addPointer(location: Offset.zero);
    await gesture.moveTo(tester.getCenter(find.byType(RoboAvatar)));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.byType(RoboAvatar));
    await tester.pump(const Duration(milliseconds: 300));
    await gesture.moveTo(const Offset(5, 5));
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.takeException(), isNull);
  });

  testWidgets('semantic label can be overridden', (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(
      _host(const RoboAvatar(semanticLabel: 'Study buddy')),
    );
    expect(find.bySemanticsLabel('Study buddy'), findsOneWidget);
    handle.dispose();
  });

  testWidgets('every state and shape draws visible pixels', (tester) async {
    for (final shape in RoboShape.values) {
      for (final state in RoboState.values) {
        await tester.pumpWidget(
          _host(
            RoboAvatar(shape: shape, state: state, size: 120, animated: false),
          ),
        );
        await tester.pumpAndSettle();
        final boundary = tester.renderObject<RenderRepaintBoundary>(
          find
              .descendant(
                of: find.byType(RoboAvatar),
                matching: find.byType(RepaintBoundary),
              )
              .first,
        );
        final opaque = await tester.runAsync<int>(() async {
          final image = await boundary.toImage();
          final data = await image.toByteData();
          var count = 0;
          if (data != null) {
            for (var i = 3; i < data.lengthInBytes; i += 4) {
              if (data.getUint8(i) > 0) count++;
            }
          }
          image.dispose();
          return count;
        });
        expect(opaque, isNotNull);
        expect(opaque!, greaterThan(500), reason: '$shape/$state');
      }
    }
  });
}
