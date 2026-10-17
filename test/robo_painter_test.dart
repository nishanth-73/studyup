import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:studyup/features/robo/robo.dart';
import 'package:studyup/features/robo/robo_painter.dart';
import 'package:studyup/features/robo/robo_rig.dart';

void _paintOnce(RoboPainter painter, double size) {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  painter.paint(canvas, ui.Size(size, size));
  recorder.endRecording().dispose();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('all 27 shape/state combinations paint at small and large sizes', () {
    for (final shape in RoboShape.values) {
      for (final state in RoboState.values) {
        final rig = RoboRig(state: state, shape: shape, seed: 0.5);
        for (var i = 0; i < 90; i++) {
          rig.advance(1 / 60);
        }
        final painter = RoboPainter(rig: rig, palette: RoboPalette.standard);
        for (final size in <double>[24, 48, 64, 100, 160, 220, 480]) {
          expect(
            () => _paintOnce(painter, size),
            returnsNormally,
            reason: '$shape/$state @ $size',
          );
        }
        rig.dispose();
      }
    }
  });

  test('painting works mid-transition and mid-morph', () {
    final rig = RoboRig(state: RoboState.idle, shape: RoboShape.square);
    rig.setState(RoboState.error);
    rig.setShape(RoboShape.hexagon);
    final painter = RoboPainter(rig: rig, palette: RoboPalette.standard);
    for (var i = 0; i < 40; i++) {
      rig.advance(1 / 60);
      expect(() => _paintOnce(painter, 160), returnsNormally);
    }
    rig.dispose();
  });

  test('antenna off, shadow off, custom palette, non-square canvas', () {
    final rig = RoboRig(state: RoboState.thinking, shape: RoboShape.circle);
    final painter = RoboPainter(
      rig: rig,
      palette: RoboPalette.fromShell(const ui.Color(0xFF7CC4FF)),
      showAntenna: false,
      floorShadow: false,
    );
    final recorder = ui.PictureRecorder();
    painter.paint(ui.Canvas(recorder), const ui.Size(300, 180));
    recorder.endRecording().dispose();
    rig.dispose();
  });

  test('palette equality', () {
    expect(
      RoboPalette.fromShell(const ui.Color(0xFF123456)),
      RoboPalette.fromShell(const ui.Color(0xFF123456)),
    );
    expect(
      RoboPalette.fromShell(const ui.Color(0xFF123456)) ==
          RoboPalette.fromShell(const ui.Color(0xFF654321)),
      isFalse,
    );
  });

  test('calm error paints the gentle paused face', () {
    final rig = RoboRig(state: RoboState.error, shape: RoboShape.square);
    rig.calmError = true;
    for (var i = 0; i < 90; i++) {
      rig.advance(1 / 60);
    }
    final painter = RoboPainter(rig: rig, palette: RoboPalette.standard);
    expect(() => _paintOnce(painter, 160), returnsNormally);
    rig.dispose();
  });
}
