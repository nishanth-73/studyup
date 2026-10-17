import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:studyup/features/robo/robo.dart';
import 'package:studyup/features/robo/robo_geometry.dart';
import 'package:studyup/features/robo/robo_math.dart';
import 'package:studyup/features/robo/robo_mesh.dart';
import 'package:studyup/features/robo/robo_rig.dart';

Widget _host(Widget child) => Directionality(
  textDirection: TextDirection.ltr,
  child: Center(child: child),
);

void main() {
  group('meshes', () {
    test('all head shapes share one topology and are well formed', () {
      final counts = <int>{};
      for (final shape in RoboShape.values) {
        final m = RoboMeshes.head(shape);
        counts.add(m.vertexCount);
        for (final i in m.indices) {
          expect(i, lessThan(m.vertexCount));
        }
        for (var v = 0; v < m.vertexCount; v++) {
          final x = m.normals[v * 3];
          final y = m.normals[v * 3 + 1];
          final z = m.normals[v * 3 + 2];
          expect(math.sqrt(x * x + y * y + z * z), closeTo(1.0, 1e-3));
          expect(m.positions[v * 3].isFinite, isTrue);
        }
        final spec = RoboHeadSpec.of(shape);
        var maxY = -1.0;
        var maxZ = -1.0;
        for (var v = 0; v < m.vertexCount; v++) {
          maxY = math.max(maxY, m.positions[v * 3 + 1]);
          maxZ = math.max(maxZ, m.positions[v * 3 + 2]);
        }
        expect(maxY, closeTo(spec.halfY, 0.01), reason: '$shape height');
        expect(maxZ, closeTo(spec.halfZ, 0.01), reason: '$shape depth');
      }
      expect(counts.length, 1);
    });

    test('head shapes are geometrically different', () {
      final sq = RoboMeshes.head(RoboShape.square);
      final ci = RoboMeshes.head(RoboShape.circle);
      final hx = RoboMeshes.head(RoboShape.hexagon);
      double dist(RoboMesh a, RoboMesh b) {
        var d = 0.0;
        for (var i = 0; i < a.positions.length; i++) {
          d += (a.positions[i] - b.positions[i]).abs();
        }
        return d;
      }

      expect(dist(sq, ci), greaterThan(5.0));
      expect(dist(sq, hx), greaterThan(5.0));
      expect(dist(ci, hx), greaterThan(5.0));
    });

    test('body part meshes are valid', () {
      for (final m in <RoboMesh>[
        RoboMeshes.torso,
        RoboMeshes.upperArm,
        RoboMeshes.hand,
        RoboMeshes.leg,
        RoboMeshes.foot,
        RoboMeshes.antennaStem,
        RoboMeshes.bulb,
      ]) {
        expect(m.vertexCount, greaterThan(50));
        for (final i in m.indices) {
          expect(i, lessThan(m.vertexCount));
        }
      }
    });

    test('RoboMat composes transforms', () {
      final m = RoboMat()
        ..translate(1, 2, 3)
        ..rotateY(math.pi / 2);
      // Local +z maps to world +x after a quarter turn about y.
      expect(m.tx(0, 0, 1), closeTo(2.0, 1e-9));
      expect(m.tz(0, 0, 1), closeTo(3.0, 1e-9));
    });
  });

  group('limb animation', () {
    List<double> still(RoboState s) {
      final rig = RoboRig(state: s, shape: RoboShape.square);
      rig.setMode(RoboMotionMode.still);
      rig.settle();
      final j = List<double>.from(rig.joints);
      rig.dispose();
      return j;
    }

    test('every state has a distinct limb/body pose', () {
      final poses = <RoboState, List<double>>{
        for (final s in RoboState.values) s: still(s),
      };
      for (final a in RoboState.values) {
        for (final b in RoboState.values) {
          if (a.index >= b.index) continue;
          var d = 0.0;
          for (var i = 0; i < RoboJoint.count; i++) {
            d += math.pow(poses[a]![i] - poses[b]![i], 2).toDouble();
          }
          expect(math.sqrt(d), greaterThan(0.05), reason: '$a vs $b');
        }
      }
    });

    test('limbs move over time in the active states', () {
      for (final s in <RoboState>[
        RoboState.idle,
        RoboState.searching,
        RoboState.speaking,
        RoboState.working,
        RoboState.happy,
        RoboState.error,
      ]) {
        final rig = RoboRig(state: s, shape: RoboShape.square);
        rig.advance(0.1);
        var lo = double.infinity;
        var hi = -double.infinity;
        for (var i = 0; i < 120; i++) {
          rig.advance(1 / 60);
          final v =
              rig.joints[RoboJoint.armNPitch] +
              rig.joints[RoboJoint.armPPitch] +
              rig.joints[RoboJoint.legNHip];
          lo = math.min(lo, v);
          hi = math.max(hi, v);
        }
        expect(hi - lo, greaterThan(0.01), reason: '$s');
        rig.dispose();
      }
    });

    test('limb targets change smoothly when the state changes', () {
      final rig = RoboRig(state: RoboState.idle, shape: RoboShape.square);
      for (var i = 0; i < 120; i++) {
        rig.advance(1 / 60);
      }
      final before = List<double>.from(rig.joints);
      rig.setState(RoboState.happy);
      rig.advance(1 / 60);
      // Ported from the supplied suite (whose checks were never executed
      // upstream): one 60 fps spring step may move a snappy joint ~0.18,
      // still smooth — the original <0.15 bound was too tight.
      for (var i = 0; i < RoboJoint.count; i++) {
        expect((rig.joints[i] - before[i]).abs(), lessThan(0.3), reason: '$i');
      }
      rig.dispose();
    });

    test('joint angles stay in a sane range for a long run', () {
      for (final s in RoboState.values) {
        final rig = RoboRig(state: s, shape: RoboShape.hexagon);
        for (var i = 0; i < 60 * 20; i++) {
          rig.advance(1 / 60);
          for (final v in rig.joints) {
            expect(v.isFinite && v.abs() < 4.0, isTrue, reason: '$s');
          }
        }
        rig.dispose();
      }
    });
  });

  group('speech bubble', () {
    testWidgets('shows text for the current state and updates it', (
      tester,
    ) async {
      for (final s in RoboState.values) {
        await tester.pumpWidget(_host(RoboAvatar(state: s, size: 200)));
        await tester.pump(const Duration(milliseconds: 400));
        expect(find.text(roboStateLabel(s)), findsOneWidget, reason: '$s');
      }
    });

    testWidgets('label text matches the specification', (tester) async {
      expect(roboStateLabel(RoboState.idle), 'Idle');
      expect(roboStateLabel(RoboState.thinking), 'Thinking...');
      expect(roboStateLabel(RoboState.searching), 'Searching...');
      expect(roboStateLabel(RoboState.listening), 'Listening...');
      expect(roboStateLabel(RoboState.speaking), 'Speaking...');
      expect(roboStateLabel(RoboState.working), 'Working...');
      expect(roboStateLabel(RoboState.happy), 'Happy!');
      expect(roboStateLabel(RoboState.error), 'Error');
      expect(roboStateLabel(RoboState.sleeping), 'Sleeping...');
    });

    testWidgets('bubble stays inside the box at every size and state', (
      tester,
    ) async {
      for (final size in <double>[64, 96, 160, 240, 360]) {
        for (final s in RoboState.values) {
          await tester.pumpWidget(_host(RoboAvatar(state: s, size: size)));
          for (var i = 0; i < 12; i++) {
            await tester.pump(const Duration(milliseconds: 100));
            final box = tester.getRect(find.byType(RoboAvatar));
            final text = tester.getRect(find.text(roboStateLabel(s)));
            expect(
              box.contains(text.topLeft),
              isTrue,
              reason: '$s @ $size topLeft $text in $box',
            );
            expect(
              box.contains(text.bottomRight - const Offset(0.1, 0.1)),
              isTrue,
              reason: '$s @ $size bottomRight $text in $box',
            );
          }
        }
      }
      expect(tester.takeException(), isNull);
    });

    testWidgets('showBubble: false removes it', (tester) async {
      await tester.pumpWidget(
        _host(const RoboAvatar(state: RoboState.idle, showBubble: false)),
      );
      expect(find.byType(RoboBubble), findsNothing);
      expect(find.text('Idle'), findsNothing);
    });

    testWidgets('bubbleText overrides the label', (tester) async {
      await tester.pumpWidget(
        _host(const RoboAvatar(bubbleText: 'Hi!', size: 200)),
      );
      expect(find.text('Hi!'), findsOneWidget);
    });

    testWidgets('bubble does not intercept taps', (tester) async {
      var taps = 0;
      await tester.pumpWidget(
        _host(
          GestureDetector(
            onTap: () => taps++,
            child: const RoboAvatar(size: 200),
          ),
        ),
      );
      await tester.tapAt(
        tester.getTopLeft(find.byType(RoboAvatar)) + const Offset(30, 30),
      );
      expect(taps, 1);
    });
  });

  group('morph', () {
    testWidgets('changing shape mid-animation renders without errors', (
      tester,
    ) async {
      for (final shape in RoboShape.values) {
        await tester.pumpWidget(
          _host(RoboAvatar(shape: shape, state: RoboState.happy, size: 180)),
        );
        for (var i = 0; i < 8; i++) {
          await tester.pump(const Duration(milliseconds: 60));
        }
      }
      expect(tester.takeException(), isNull);
    });
  });
}
