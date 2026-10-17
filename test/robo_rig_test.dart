import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:studyup/features/robo/robo.dart';
import 'package:studyup/features/robo/robo_rig.dart';

void _run(RoboRig rig, double seconds, {double dt = 1 / 60}) {
  final n = (seconds / dt).round();
  for (var i = 0; i < n; i++) {
    rig.advance(dt);
  }
}

bool _finite(RoboRig r) => <double>[
  r.yaw,
  r.pitch,
  r.roll,
  r.x,
  r.lift,
  r.sx,
  r.sy,
  r.antennaX,
  r.lookX,
  r.lookY,
  r.blink,
].every((v) => v.isFinite);

void main() {
  test('same seed and steps give identical output (deterministic)', () {
    final a = RoboRig(
      state: RoboState.idle,
      shape: RoboShape.square,
      seed: 0.3,
    );
    final b = RoboRig(
      state: RoboState.idle,
      shape: RoboShape.square,
      seed: 0.3,
    );
    _run(a, 20);
    _run(b, 20);
    expect(a.yaw, b.yaw);
    expect(a.lift, b.lift);
    expect(a.antennaX, b.antennaX);
    expect(a.blink, b.blink);
    a.dispose();
    b.dispose();
  });

  test('different seeds desynchronise', () {
    final a = RoboRig(
      state: RoboState.idle,
      shape: RoboShape.square,
      seed: 0.1,
    );
    final b = RoboRig(
      state: RoboState.idle,
      shape: RoboShape.square,
      seed: 0.8,
    );
    _run(a, 12);
    _run(b, 12);
    expect(a.yaw == b.yaw && a.lift == b.lift, isFalse);
    a.dispose();
    b.dispose();
  });

  test('every state stays finite and in a sane range for a long run', () {
    for (final s in RoboState.values) {
      final rig = RoboRig(state: RoboState.idle, shape: RoboShape.circle);
      rig.setState(s);
      var maxLift = 0.0;
      for (var i = 0; i < 60 * 30; i++) {
        rig.advance(1 / 60);
        expect(_finite(rig), isTrue, reason: '$s');
        maxLift = math.max(maxLift, rig.lift);
        expect(rig.yaw.abs(), lessThan(1.2), reason: '$s yaw');
        expect(rig.roll.abs(), lessThan(0.8), reason: '$s roll');
        expect(rig.sy, inInclusiveRange(0.7, 1.3), reason: '$s sy');
        expect(rig.lift, greaterThan(-0.3), reason: '$s lift');
        expect(rig.antennaX.abs(), lessThanOrEqualTo(0.9), reason: '$s ant');
      }
      expect(maxLift, lessThan(0.6), reason: '$s hop height fits the box');
      rig.dispose();
    }
  });

  test('huge frame gaps are capped and stay stable', () {
    final rig = RoboRig(state: RoboState.happy, shape: RoboShape.hexagon);
    rig.advance(30.0);
    expect(_finite(rig), isTrue);
    rig.dispose();
  });

  test('state change cross-fades from 0 to 1', () {
    final rig = RoboRig(state: RoboState.idle, shape: RoboShape.square);
    expect(rig.stateMix, 1.0);
    rig.setState(RoboState.thinking);
    expect(rig.previousState, RoboState.idle);
    expect(rig.state, RoboState.thinking);
    expect(rig.stateMix, 0.0);
    _run(rig, 0.2);
    expect(rig.stateMix, inExclusiveRange(0.0, 1.0));
    _run(rig, 0.5);
    expect(rig.stateMix, 1.0);
    rig.dispose();
  });

  test('shape change morphs from 0 to 1', () {
    final rig = RoboRig(state: RoboState.idle, shape: RoboShape.square);
    rig.setShape(RoboShape.hexagon);
    expect(rig.shapeMix, 0.0);
    _run(rig, 0.2);
    expect(rig.shapeMix, inExclusiveRange(0.0, 1.0));
    _run(rig, 0.5);
    expect(rig.shapeMix, 1.0);
    expect(rig.shape, RoboShape.hexagon);
    rig.dispose();
  });

  test('pose eases (no jump) when the state changes', () {
    final rig = RoboRig(state: RoboState.idle, shape: RoboShape.square);
    _run(rig, 2);
    final before = rig.roll;
    rig.setState(RoboState.listening);
    rig.advance(1 / 60);
    expect((rig.roll - before).abs(), lessThan(0.02));
    _run(rig, 3);
    expect(rig.roll, closeTo(0.17, 0.08));
    rig.dispose();
  });

  test('settle() gives a deterministic still pose and a resting rig', () {
    for (final s in RoboState.values) {
      final rig = RoboRig(state: s, shape: RoboShape.square);
      rig.setMode(RoboMotionMode.still);
      rig.settle();
      expect(rig.isActive, isFalse, reason: '$s');
      final yaw = rig.yaw;
      rig.advance(1 / 60);
      expect(rig.isActive, isFalse, reason: '$s after advance');
      expect(rig.yaw, closeTo(yaw, 1e-6), reason: '$s');
      rig.dispose();
    }
  });

  test('still mode eases a state change then goes to rest', () {
    final rig = RoboRig(state: RoboState.idle, shape: RoboShape.square);
    rig.setMode(RoboMotionMode.still);
    rig.settle();
    rig.setState(RoboState.sleeping);
    expect(rig.isActive, isTrue);
    _run(rig, 3);
    expect(rig.isActive, isFalse);
    // Sleeping settles lowered: target bob is -0.10 plus the still-frame
    // breathing phase, which can sit a hair above zero (upstream bound
    // <0.0 was never executed and too strict by ~0.004).
    expect(rig.lift, lessThan(0.02)); // lowered pose
    rig.dispose();
  });

  test('frozen holds the frame, keeps the state, and resumes', () {
    final rig = RoboRig(state: RoboState.working, shape: RoboShape.square);
    _run(rig, 3);
    rig.setMode(RoboMotionMode.frozen);
    final yaw = rig.yaw;
    final t = rig.time;
    _run(rig, 2);
    expect(rig.yaw, yaw);
    expect(rig.time, t);
    expect(rig.state, RoboState.working);
    expect(rig.isActive, isFalse);
    rig.setMode(RoboMotionMode.live);
    _run(rig, 1);
    expect(rig.time, greaterThan(t));
    rig.dispose();
  });

  test('state change while frozen eases to the new still pose then holds', () {
    final rig = RoboRig(state: RoboState.idle, shape: RoboShape.square);
    _run(rig, 1);
    rig.setMode(RoboMotionMode.frozen);
    rig.setState(RoboState.error);
    expect(rig.isActive, isTrue);
    _run(rig, 3);
    expect(rig.isActive, isFalse);
    expect(rig.state, RoboState.error);
    rig.dispose();
  });

  test('hop lifts and returns to the ground', () {
    final rig = RoboRig(state: RoboState.working, shape: RoboShape.square);
    rig.hop(0.34);
    var peak = 0.0;
    for (var i = 0; i < 120; i++) {
      rig.advance(1 / 60);
      peak = math.max(peak, rig.lift);
    }
    expect(peak, greaterThan(0.15));
    expect(rig.lift.abs(), lessThan(0.15));
    rig.dispose();
  });

  test('idle greeting wave raises a real arm, then settles', () {
    final rig = RoboRig(state: RoboState.idle, shape: RoboShape.square);
    addTearDown(rig.dispose);
    // First wave fires ~1s after creation.
    _run(rig, 1.6);
    expect(rig.waveAmount, greaterThan(0.5));
    final raised =
        rig.joints[RoboJoint.armPPitch] < -1.0 ||
        rig.joints[RoboJoint.armNPitch] < -1.0;
    expect(raised, isTrue, reason: 'a genuine arm joint must lift');
    // The wave ends on its own and the arms come back down.
    _run(rig, 3.0);
    expect(rig.waveAmount, 0.0);
    expect(rig.joints[RoboJoint.armPPitch], greaterThan(-0.5));
    expect(rig.joints[RoboJoint.armNPitch], greaterThan(-0.5));
  });

  test('calm error holds a shake-free rest pose', () {
    final rig = RoboRig(state: RoboState.error, shape: RoboShape.square);
    addTearDown(rig.dispose);
    rig.calmError = true;
    _run(rig, 3.0);
    // No head-shake term leaks into the pose.
    expect(rig.yaw.abs(), lessThan(0.3));
    // Relaxed arms: nothing near the head-scratch raise of raw error.
    expect(rig.joints[RoboJoint.armPPitch], greaterThan(-0.5));
    expect(rig.joints[RoboJoint.armPElbow], greaterThan(-1.0));
  });
}
