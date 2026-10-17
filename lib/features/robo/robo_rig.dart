import 'dart:math' as math;
import 'dart:ui' show Offset;

import 'package:flutter/animation.dart' show Curves;
import 'package:flutter/foundation.dart';

import 'robo_state_style.dart';
import 'robo_types.dart';

/// How a [RoboRig] advances.
enum RoboMotionMode {
  /// Full animation.
  live,

  /// Animation disabled: the state's canonical still pose is shown. State and
  /// shape changes still ease in, then the rig goes to rest.
  still,

  /// Paused: the current frame is held exactly. If the state or shape changes
  /// while frozen, the new one eases in to its still pose, then holds.
  frozen,
}

class _Spring {
  _Spring([this.x = 0.0]);

  double x;
  double v = 0.0;

  void step(double target, double dt, double freq, double damping) {
    final w = freq * 2.0 * math.pi;
    v += (w * w * (target - x) - 2.0 * damping * w * v) * dt;
    x += v * dt;
  }
}

/// Tiny deterministic PRNG (MINSTD). Products stay below 2^53, so it behaves
/// identically on the VM and on the web.
class _Lcg {
  _Lcg(double seed)
    : _s =
          ((seed.isFinite ? seed.abs() : 0.0) * 1000003.0).floor() %
              2147483646 +
          1;

  int _s;

  double next() {
    _s = (_s * 48271) % 2147483647;
    return _s / 2147483647.0;
  }
}

/// Indices into [RoboRig.joints]. "N" is the robot's side toward screen-left
/// (negative x), "P" toward screen-right (positive x).
///
/// Arm: shoulder pitch (negative swings forward/up), outward roll (positive
/// moves away from the body), elbow (negative bends forward). Leg: hip pitch
/// (negative swings forward), foot pitch. Torso: pitch (positive slouches
/// forward) and yaw.
class RoboJoint {
  RoboJoint._();
  static const int armNPitch = 0;
  static const int armNOut = 1;
  static const int armNElbow = 2;
  static const int armPPitch = 3;
  static const int armPOut = 4;
  static const int armPElbow = 5;
  static const int legNHip = 6;
  static const int legPHip = 7;
  static const int footN = 8;
  static const int footP = 9;
  static const int torsoPitch = 10;
  static const int torsoYaw = 11;
  static const int count = 12;
}

double _clamp(double v, double lo, double hi) =>
    v < lo ? lo : (v > hi ? hi : v);

/// The simulation behind a `RoboAvatar`.
///
/// It owns every moving quantity (pose, eye look, blink, antenna, state and
/// shape cross-fades) and advances them with a fixed 1/120 s step, so given
/// the same seed and the same sequence of `advance(dt)` calls the output is
/// identical. It is a [Listenable]: the painter repaints from it directly,
/// so animation never rebuilds the widget tree.
class RoboRig extends ChangeNotifier {
  RoboRig({
    required RoboState state,
    required RoboShape shape,
    this.seed = 0.0,
    Duration transitionDuration = const Duration(milliseconds: 450),
  }) : _state = state,
       _previousState = state,
       _shape = shape,
       _previousShape = shape,
       _transitionSeconds = _secondsOf(transitionDuration),
       _rand = _Lcg(seed) {
    _nextBlink = 1.0 + _rand.next() * 3.0;
    _nextHop = 6.0 + _rand.next() * 6.0;
  }

  static const double _fixedDt = 1.0 / 120.0;
  static const double _crouchTime = 0.11;
  static const double _settleSeconds = 1.8;

  static double _secondsOf(Duration d) =>
      math.max(0.001, d.inMicroseconds / 1e6);

  /// Desynchronises blinks and glances between several avatars (0..1).
  final double seed;

  final _Lcg _rand;

  // --- public, read by the painter -------------------------------------

  /// Head yaw (radians, + turns toward screen-right).
  double yaw = 0.0;

  /// Head pitch (radians, + looks up).
  double pitch = 0.0;

  /// Head roll (radians, + tilts clockwise).
  double roll = 0.0;

  /// Sideways offset, in head half-sizes.
  double x = 0.0;

  /// Height above rest, in head half-sizes (negative = lowered).
  double lift = 0.0;

  /// Horizontal / vertical squash scales about the head's base.
  double sx = 1.0;
  double sy = 1.0;

  /// Antenna lean (radians, + leans toward screen-right).
  double antennaX = 0.0;

  /// Eye look direction, each roughly in -1..1.
  double lookX = 0.0;
  double lookY = 0.0;

  /// Blink closure, 0 open .. 1 shut.
  double blink = 0.0;

  /// Seconds of live animation since creation.
  double time = 0.0;

  /// Seconds since the current state began.
  double since = 0.0;

  /// Smoothed limb/torso joint angles, see [RoboJoint].
  final List<double> joints = List<double>.filled(RoboJoint.count, 0.0);

  /// 0..1 while the robot is in the air during a hop (legs tuck, arms lift).
  double airborne = 0.0;

  /// Pointer position relative to the avatar centre, each -1..1, or null.
  /// Only used by the follow-the-pointer behaviour of interactive avatars.
  Offset? pointer;

  // --- state ------------------------------------------------------------

  RoboState _state;
  RoboState _previousState;
  RoboShape _shape;
  RoboShape _previousShape;
  double _transitionSeconds;
  double _stateT = 1.0;
  double _shapeT = 1.0;
  RoboMotionMode _mode = RoboMotionMode.live;
  double _stillRun = 0.0;
  bool _frozenChange = false;

  RoboState get state => _state;
  RoboState get previousState => _previousState;
  RoboShape get shape => _shape;
  RoboShape get previousShape => _previousShape;
  RoboMotionMode get mode => _mode;

  /// 0 -> 1 (eased) cross-fade from [previousState] to [state].
  double get stateMix => Curves.easeInOutCubic.transform(_stateT);

  /// 0 -> 1 (eased) morph from [previousShape] to [shape].
  double get shapeMix => Curves.easeInOutCubic.transform(_shapeT);

  /// True while the face cross-fade is running.
  bool get isTransitioning => _stateT < 1.0 || _shapeT < 1.0;

  /// Whether the owner should keep calling [advance].
  bool get isActive {
    if (_mode == RoboMotionMode.live) return true;
    if (_mode == RoboMotionMode.frozen && !_frozenChange) return false;
    return _stillRun > 0.0 || _stateT < 1.0 || _shapeT < 1.0;
  }

  set transitionDuration(Duration d) => _transitionSeconds = _secondsOf(d);

  // springs
  final _Spring _yaw = _Spring();
  final _Spring _pitch = _Spring();
  final _Spring _roll = _Spring();
  final _Spring _sway = _Spring();
  final _Spring _liftS = _Spring();
  final _Spring _sy = _Spring(1.0);
  final _Spring _lx = _Spring();
  final _Spring _ly = _Spring();
  final _Spring _ant = _Spring();
  final List<_Spring> _js = List<_Spring>.generate(
    RoboJoint.count,
    (_) => _Spring(),
  );
  final List<double> _jt = List<double>.filled(RoboJoint.count, 0.0);
  double _lastX = 0.0;
  double _lastRoll = 0.0;

  // targets, written by _computeTargets
  double _tYaw = 0.0;
  double _tPitch = 0.0;
  double _tRoll = 0.0;
  double _tSway = 0.0;
  double _tBob = 0.0;
  double _tLookX = 0.0;
  double _tLookY = 0.0;
  double _tFreq = 1.3;
  double _tDamp = 0.62;
  double _tShake = 0.0;
  double _tBreath = 0.0;
  double _tBreathFreq = 1.9;
  double _tAntBase = 0.0;

  // scripted events
  double _lookYaw = 0.0;
  double _lookPitch = 0.0;
  double _lookCellX = 0.0;
  double _lookCellY = 0.0;
  double _side = 1.0;
  double _nextLook = 0.6;
  double _nextBlink = 1.5;
  double _blinkAge = -1.0;
  double _nextHop = 8.0;
  double _nextSide = 4.0;
  double _nextNod = 2.5;

  // hop
  double _hopAge = -1.0;
  double _hopHeight = 0.0;
  double _hopAir = 0.5;
  double _hopWiggle = 0.0;
  double _hopLift = 0.0;
  double _hopSy = 1.0;
  double _hopRoll = 0.0;
  bool _landed = false;

  // friendly idle greeting wave: one arm raises and the forearm waves a
  // few times using the real arm pitch/roll/elbow joints (never a
  // whole-body spin). Negative age = no wave in progress.
  double _waveAge = -1.0;
  double _waveSide = 1.0;
  double _nextWave = 1.0;

  /// Idle wave duration in seconds (raise, ~4 forearm oscillations, lower).
  static const double waveDuration = 2.6;

  /// 0..1 raise/lower envelope of the idle greeting wave (0 = resting).
  double get waveAmount {
    if (_waveAge < 0.0) return 0.0;
    final up = (_waveAge / 0.45).clamp(0.0, 1.0);
    final down = ((waveDuration - _waveAge) / 0.45).clamp(0.0, 1.0);
    return math.min(up, down);
  }

  /// When true, the error state renders as a calm paused rest: no head
  /// shake, no alarming red, relaxed arms. The resolver keeps reporting
  /// [RoboState.error] — only the presentation softens.
  bool _calmError = false;
  bool get calmError => _calmError;
  set calmError(bool value) {
    if (value == _calmError) return;
    _calmError = value;
    notifyListeners();
  }

  // --- public control ---------------------------------------------------

  /// Selects how the rig advances. See [RoboMotionMode].
  void setMode(RoboMotionMode m) {
    if (m == _mode) return;
    _mode = m;
    _frozenChange = false;
    if (m == RoboMotionMode.still) {
      time = since = RoboStateStyle.stillTime(_state);
      _stillRun = _settleSeconds;
    }
    notifyListeners();
  }

  /// Switches to [next]; the previous face cross-fades out.
  void setState(RoboState next) {
    if (next == _state) return;
    _previousState = _state;
    _state = next;
    _stateT = 0.0;
    since = 0.0;
    _nextLook = 0.0;
    _nextHop =
        time + (next == RoboState.happy ? 0.2 : 3.0 + _rand.next() * 4.0);
    _nextNod = time + 1.2;
    _nextSide = time + 3.0 + _rand.next() * 2.0;
    // Greet shortly after arriving back at idle.
    if (next == RoboState.idle) _nextWave = time + 0.8;
    if (_mode == RoboMotionMode.live && next == RoboState.happy) {
      hop(0.34, wiggle: 1.0);
    }
    _noteChange();
  }

  /// Morphs to [next]; the outline interpolates smoothly.
  void setShape(RoboShape next) {
    if (next == _shape) return;
    _previousShape = _shape;
    _shape = next;
    _shapeT = 0.0;
    _noteChange();
  }

  /// A playful hop (used for taps on interactive avatars).
  void poke() {
    if (_mode != RoboMotionMode.live) return;
    hop(0.36, wiggle: _rand.next() < 0.5 ? 1.0 : -1.0);
  }

  /// Starts a hop of [height] head half-sizes with a small roll wiggle.
  void hop(double height, {double wiggle = 0.0}) {
    if (_hopAge >= 0.0) return;
    _hopAge = 0.0;
    _hopHeight = height;
    _hopWiggle = wiggle;
    _hopAir = 0.40 + height * 0.5;
    _landed = false;
    _ant.v += (_rand.next() - 0.5) * 5.0;
  }

  /// Jumps straight to the settled still pose of the current state.
  void settle() {
    time = since = RoboStateStyle.stillTime(_state);
    _stateT = 1.0;
    _shapeT = 1.0;
    _previousState = _state;
    _previousShape = _shape;
    _hopAge = -1.0;
    _hopLift = 0.0;
    _hopSy = 1.0;
    _hopRoll = 0.0;
    _blinkAge = -1.0;
    blink = 0.0;
    _waveAge = -1.0;
    _computeTargets(still: true);
    _yaw
      ..x = _tYaw
      ..v = 0.0;
    _pitch
      ..x = _tPitch
      ..v = 0.0;
    _roll
      ..x = _tRoll
      ..v = 0.0;
    _sway
      ..x = _tSway
      ..v = 0.0;
    _liftS
      ..x = _tBob
      ..v = 0.0;
    _lx
      ..x = _tLookX
      ..v = 0.0;
    _ly
      ..x = _tLookY
      ..v = 0.0;
    _ant
      ..x = _tAntBase
      ..v = 0.0;
    _sy
      ..x = _breathScale()
      ..v = 0.0;
    for (var i = 0; i < RoboJoint.count; i++) {
      _js[i]
        ..x = _jt[i]
        ..v = 0.0;
    }
    airborne = 0.0;
    _publish();
    _lastX = x;
    _lastRoll = roll;
    _stillRun = 0.0;
    _frozenChange = false;
    notifyListeners();
  }

  /// Advances the simulation by [dt] seconds (capped at 0.1 per call).
  void advance(double dt) {
    if (!(dt > 0.0)) return;
    if (_mode == RoboMotionMode.frozen && !_frozenChange) return;
    final capped = math.min(dt, 0.1);
    final n = math.max(1, (capped / _fixedDt).ceil());
    final h = capped / n;
    for (var i = 0; i < n; i++) {
      _step(h);
    }
    if (_mode != RoboMotionMode.live) {
      _stillRun -= capped;
      if (_stillRun <= 0.0 && _stateT >= 1.0 && _shapeT >= 1.0) {
        _stillRun = 0.0;
        if (_mode == RoboMotionMode.frozen) _frozenChange = false;
      }
    }
    notifyListeners();
  }

  // --- internals --------------------------------------------------------

  void _noteChange() {
    if (_mode != RoboMotionMode.live) {
      if (_mode == RoboMotionMode.frozen) _frozenChange = true;
      time = since = RoboStateStyle.stillTime(_state);
      _stillRun = _settleSeconds;
    }
    notifyListeners();
  }

  double _breathScale() =>
      (1.0 + _tBreath * math.sin(time * _tBreathFreq)) * _hopSy;

  void _step(double dt) {
    final live = _mode == RoboMotionMode.live;
    if (live) {
      time += dt;
      since += dt;
    }
    if (_stateT < 1.0) {
      _stateT = math.min(1.0, _stateT + dt / _transitionSeconds);
    }
    if (_shapeT < 1.0) {
      _shapeT = math.min(1.0, _shapeT + dt / _transitionSeconds);
    }
    if (live) {
      _stepEvents();
      _stepHop(dt);
      _stepBlink(dt);
      if (_waveAge >= 0.0) {
        _waveAge += dt;
        if (_waveAge > waveDuration) _waveAge = -1.0;
      }
    } else {
      _hopAge = -1.0;
      _hopLift = 0.0;
      _hopSy = 1.0;
      _hopRoll = 0.0;
      blink = 0.0;
    }
    _computeTargets(still: !live);

    _yaw.step(_tYaw, dt, _tFreq, _tDamp);
    _pitch.step(_tPitch, dt, _tFreq, _tDamp);
    _roll.step(_tRoll, dt, _tFreq, _tDamp);
    _sway.step(_tSway, dt, 1.2, 0.7);
    _liftS.step(_tBob, dt, 2.5, 0.7);
    _sy.step(_breathScale(), dt, 7.0, 0.55);
    _lx.step(_tLookX, dt, 6.0, 0.85);
    _ly.step(_tLookY, dt, 6.0, 0.85);
    for (var i = 0; i < RoboJoint.count; i++) {
      _js[i].step(_jt[i], dt, 3.0, 0.75);
    }

    _publish();

    // The antenna is a damped spring whipped by how the head moves.
    final xVel = (x - _lastX) / dt;
    final rollVel = (roll - _lastRoll) / dt;
    _lastX = x;
    _lastRoll = roll;
    final drive = _clamp(-(xVel * 0.12 + rollVel * 0.30), -0.9, 0.9);
    _ant.step(drive + _tAntBase, dt, 3.2, 0.17);
    antennaX = _clamp(_ant.x, -0.9, 0.9);
  }

  void _publish() {
    yaw = _yaw.x + _tShake * 1.4;
    pitch = _pitch.x;
    roll = _roll.x + _hopRoll;
    x = _sway.x + _tShake;
    lift = _liftS.x + _hopLift;
    sy = _clamp(_sy.x, 0.7, 1.3);
    sx = 1.0 / math.sqrt(sy);
    lookX = _lx.x;
    lookY = _ly.x;
    antennaX = _clamp(_ant.x, -0.9, 0.9);
    for (var i = 0; i < RoboJoint.count; i++) {
      joints[i] = _js[i].x;
    }
  }

  void _stepEvents() {
    final t = time;
    if (t > _nextLook) {
      _lookYaw = (_rand.next() - 0.5) * 0.75;
      _lookPitch = (_rand.next() - 0.5) * 0.24;
      _lookCellX = _clamp(_lookYaw / 0.30, -1.0, 1.0);
      final r = _rand.next();
      _lookCellY = r < 0.3 ? -0.6 : (r < 0.5 ? 0.6 : 0.0);
      _nextLook = t + 1.4 + _rand.next() * 2.6;
    }
    switch (_state) {
      case RoboState.idle:
        if (t > _nextHop) {
          final w = _rand.next() < 0.35
              ? (_rand.next() < 0.5 ? 1.0 : -1.0)
              : 0.0;
          hop(0.32 + _rand.next() * 0.08, wiggle: w);
          _nextHop = t + 7.0 + _rand.next() * 7.0;
        }
        // Occasional friendly greeting wave (genuine arm joints; see the
        // wave pose in _computeLimbTargets). Spaced well apart so it never
        // distracts, and never reset by widget rebuilds or timer ticks.
        if (t > _nextWave && _waveAge < 0.0) {
          _waveAge = 0.0;
          _waveSide = _rand.next() < 0.5 ? -1.0 : 1.0;
          _nextWave = t + 9.0 + _rand.next() * 8.0;
        }
        break;
      case RoboState.thinking:
        if (t > _nextSide) {
          _side = -_side;
          _nextSide = t + 3.0 + _rand.next() * 2.0;
        }
        break;
      case RoboState.listening:
        if (t > _nextNod) {
          _pitch.v -= 0.9;
          _nextNod = t + 2.0 + _rand.next() * 2.5;
        }
        break;
      case RoboState.working:
        if (t > _nextHop) {
          hop(0.3, wiggle: _rand.next() < 0.5 ? 1.0 : -1.0);
          _nextHop = t + 5.0 + _rand.next() * 3.0;
        }
        break;
      case RoboState.happy:
        if (t > _nextHop) {
          final w = _rand.next() < 0.34
              ? (_rand.next() < 0.5 ? 1.0 : -1.0)
              : 0.0;
          hop(0.42, wiggle: w);
          _nextHop = t + 1.05 + _rand.next() * 0.4;
        }
        break;
      case RoboState.sleeping:
        if (t > _nextNod) {
          _pitch.v -= 0.4;
          _nextNod = t + 5.0 + _rand.next() * 4.0;
        }
        break;
      case RoboState.searching:
      case RoboState.speaking:
      case RoboState.error:
        break;
    }
  }

  void _stepBlink(double dt) {
    if (_blinkAge >= 0.0) {
      _blinkAge += dt;
      if (_blinkAge < 0.07) {
        blink = _blinkAge / 0.07;
      } else if (_blinkAge < 0.20) {
        blink = 1.0 - (_blinkAge - 0.07) / 0.13;
      } else {
        blink = 0.0;
        _blinkAge = -1.0;
      }
    } else if (time > _nextBlink) {
      _blinkAge = 0.0;
      _nextBlink =
          time + (_rand.next() < 0.15 ? 0.32 : 2.0 + _rand.next() * 3.5);
    }
  }

  void _stepHop(double dt) {
    if (_hopAge < 0.0) {
      airborne = 0.0;
      _hopLift = 0.0;
      _hopSy = 1.0;
      _hopRoll = 0.0;
      return;
    }
    _hopAge += dt;
    final a = _hopAge;
    if (a < _crouchTime) {
      airborne = 0.0;
      final k = a / _crouchTime;
      _hopLift = 0.0;
      _hopSy = 1.0 - 0.13 * math.sin(k * math.pi / 2.0);
      _hopRoll = 0.0;
    } else if (a < _crouchTime + _hopAir) {
      final u = (a - _crouchTime) / _hopAir;
      airborne = math.sin(u * math.pi);
      _hopLift = _hopHeight * 4.0 * u * (1.0 - u);
      final rec = math.min(1.0, u * 4.0);
      _hopSy = (0.87 + 0.13 * rec) + 0.06 * math.sin(u * math.pi);
      _hopRoll = _hopWiggle * 0.28 * math.sin(u * 2.0 * math.pi);
    } else {
      airborne = 0.0;
      final e = a - _crouchTime - _hopAir;
      if (e > 0.7) {
        _hopAge = -1.0;
        _hopLift = 0.0;
        _hopSy = 1.0;
        _hopRoll = 0.0;
        return;
      }
      if (!_landed) {
        _landed = true;
        _ant.v +=
            (_rand.next() < 0.5 ? -1.0 : 1.0) * (2.5 + _rand.next() * 2.0);
      }
      _hopLift = 0.0;
      _hopSy = 1.0 - 0.11 * math.exp(-e * 8.0) * math.cos(e * 24.0);
      _hopRoll = 0.0;
    }
  }

  /// Writes the per-state pose targets. Pure apart from reading the current
  /// look/side event values, so a "still" evaluation is deterministic.
  void _computeTargets({required bool still}) {
    final t = time;
    final ts = since;
    final ly = still ? 0.0 : _lookYaw;
    final lp = still ? 0.0 : _lookPitch;
    final lcx = still ? 0.0 : _lookCellX;
    final lcy = still ? 0.0 : _lookCellY;
    final p = still ? null : pointer;

    var yawT = 0.0;
    var pitchT = 0.0;
    var rollT = 0.0;
    var bob = 0.0;
    var lookXT = 0.0;
    var lookYT = 0.0;
    var freq = 1.3;
    var damp = 0.62;
    var shake = 0.0;
    var breath = 0.012;
    var breathFreq = 1.9;
    var antBase = 0.0;
    var follows = false;

    switch (_state) {
      case RoboState.idle:
        yawT = ly;
        pitchT = lp;
        rollT = -ly * 0.16;
        lookXT = lcx;
        lookYT = lcy;
        bob = math.sin(t * 1.9) * 0.035;
        follows = true;
        break;
      case RoboState.thinking:
        final s = _side;
        yawT = 0.24 * s + math.sin(t * 0.9) * 0.05;
        pitchT = 0.17 + math.sin(t * 1.3) * 0.03;
        rollT = -0.13 * s;
        lookXT = 0.9 * s;
        lookYT = -1.0;
        bob = math.sin(t * 1.5) * 0.02;
        freq = 0.9;
        break;
      case RoboState.searching:
        final ph = t * 1.6;
        yawT = math.sin(ph) * 0.55;
        pitchT = -0.04 + math.sin(ph * 2.0) * 0.04;
        rollT = -math.sin(ph) * 0.06;
        lookXT = math.sin(ph + 0.4);
        bob = math.sin(t * 2.0) * 0.02;
        freq = 2.2;
        damp = 0.8;
        break;
      case RoboState.listening:
        yawT = -0.14;
        pitchT = 0.02;
        rollT = 0.17;
        lookYT = -0.3;
        bob = math.sin(t * 1.6) * 0.025;
        follows = true;
        break;
      case RoboState.speaking:
        yawT = math.sin(t * 0.7) * 0.12;
        pitchT =
            0.03 + math.sin(t * 6.3) * 0.025 * (0.5 + 0.5 * math.sin(t * 2.1));
        rollT = math.sin(t * 0.9) * 0.05;
        bob = math.sin(t * 1.9) * 0.02 + math.sin(t * 6.3).abs() * 0.03;
        freq = 1.8;
        follows = true;
        break;
      case RoboState.working:
        yawT = math.sin(t * 0.8) * 0.08;
        pitchT = -0.16;
        rollT = math.sin(t * 0.5) * 0.04;
        lookYT = 1.0;
        bob = math.sin(t * 7.0).abs() * 0.035;
        freq = 2.0;
        break;
      case RoboState.happy:
        yawT = math.sin(t * 2.2) * 0.18;
        rollT = math.sin(t * 4.4) * 0.12;
        pitchT = 0.08;
        bob = math.sin(t * 3.0) * 0.03;
        freq = 1.6;
        follows = true;
        break;
      case RoboState.error:
        final c = (ts % 2.4) / 0.7;
        shake = _calmError
            ? 0.0
            : c < 1.0
            ? math.sin(c * math.pi * 7.0) * 0.18 * (1.0 - c)
            : 0.0;
        pitchT = _calmError ? -0.10 : -0.06;
        rollT = -0.05;
        freq = 1.6;
        break;
      case RoboState.sleeping:
        pitchT = -0.30;
        rollT = 0.13;
        yawT = 0.06;
        bob = math.sin(t * 0.9) * 0.01;
        breath = 0.02;
        breathFreq = 0.9;
        freq = 0.8;
        damp = 0.9;
        antBase = 0.30;
        break;
    }

    if (follows && p != null) {
      final px = _clamp(p.dx, -1.0, 1.0);
      final py = _clamp(p.dy, -1.0, 1.0);
      yawT = px * 0.45;
      pitchT = -py * 0.22;
      rollT = -yawT * 0.12 + (_state == RoboState.listening ? 0.12 : 0.0);
      lookXT = px;
      lookYT = py;
    }

    _tYaw = yawT;
    _tPitch = pitchT;
    _tRoll = rollT;
    _tSway = 0.0;
    _tBob = bob;
    _tLookX = lookXT;
    _tLookY = lookYT;
    _tFreq = freq;
    _tDamp = damp;
    _tShake = shake;
    _tBreath = breath;
    _tBreathFreq = breathFreq;
    _tAntBase = antBase;
    _computeLimbTargets(t, still);
  }

  /// Arm, leg and torso targets. Each state has its own deliberate pose and
  /// rhythm (see the README table); nothing here is random.
  void _computeLimbTargets(double t, bool still) {
    final j = _jt;
    var apN = 0.05;
    var arN = 0.14;
    var aeN = -0.12;
    var apP = 0.05;
    var arP = 0.14;
    var aeP = -0.12;
    var lhN = 0.0;
    var lhP = 0.0;
    var fN = 0.0;
    var fP = 0.0;
    var tp = 0.0;
    var ty = 0.0;
    final air = still ? 0.0 : airborne;

    switch (_state) {
      case RoboState.idle:
        final b = math.sin(t * 1.9);
        apN = 0.05 + 0.04 * b;
        apP = 0.05 - 0.04 * b;
        arN = 0.13 + 0.03 * math.sin(t * 1.9 + 0.6);
        arP = 0.13 + 0.03 * math.sin(t * 1.9 + 0.6);
        tp = 0.015 * b;
        // Greeting wave: raise one arm up-out and oscillate the forearm a
        // few times, blended in/out by the wave envelope.
        final wv = still ? 0.0 : waveAmount;
        if (wv > 0.0) {
          final osc = math.sin(_waveAge * 2.0 * math.pi * 1.6);
          if (_waveSide >= 0.0) {
            apP = apP + (-1.90 - apP) * wv;
            arP = arP + (0.85 - arP) * wv;
            aeP = aeP + ((-0.45 + 0.55 * osc) - aeP) * wv;
          } else {
            apN = apN + (-1.90 - apN) * wv;
            arN = arN + (0.85 - arN) * wv;
            aeN = aeN + ((-0.45 + 0.55 * osc) - aeN) * wv;
          }
        }
        break;
      case RoboState.thinking:
        // One hand to the chin, the other resting on the hip.
        final raised = -1.30 + 0.04 * math.sin(t * 1.7);
        final elbow = -2.00 + 0.06 * math.sin(t * 2.3);
        if (_side >= 0.0) {
          apP = raised;
          arP = -0.12;
          aeP = elbow;
          apN = 0.15;
          arN = 0.30;
          aeN = -0.45;
        } else {
          apN = raised;
          arN = -0.12;
          aeN = elbow;
          apP = 0.15;
          arP = 0.30;
          aeP = -0.45;
        }
        tp = 0.03;
        ty = 0.10 * _side;
        lhN = 0.03;
        lhP = -0.03;
        break;
      case RoboState.searching:
        final ph = t * 1.6;
        final s = math.sin(ph);
        apN = -0.35 + 0.18 * s;
        apP = -0.35 - 0.18 * s;
        arN = 0.40 + 0.10 * s;
        arP = 0.40 - 0.10 * s;
        aeN = -0.70;
        aeP = -0.70;
        ty = 0.25 * s;
        lhN = 0.12 * s;
        lhP = -0.12 * s;
        fN = -lhN * 0.5;
        fP = -lhP * 0.5;
        break;
      case RoboState.listening:
        final m = (roboNoise(t * 3.0) - 0.5) * 0.12;
        apN = -0.28;
        apP = -0.28;
        arN = 0.16;
        arP = 0.16;
        aeN = -0.80 + m;
        aeP = -0.80 - m;
        tp = -0.05;
        break;
      case RoboState.speaking:
        final gN = math.max(0.0, math.sin(t * 2.3));
        final gP = math.max(0.0, math.sin(t * 2.3 + 2.4));
        apN = -0.50 - 0.50 * gN;
        apP = -0.50 - 0.50 * gP;
        arN = 0.25 + 0.30 * gN;
        arP = 0.25 + 0.30 * gP;
        aeN = -0.90 - 0.50 * gN * (0.5 + 0.5 * math.sin(t * 6.0));
        aeP = -0.90 - 0.50 * gP * (0.5 + 0.5 * math.sin(t * 6.0 + 1.0));
        tp = 0.02 * math.sin(t * 2.3);
        ty = 0.06 * math.sin(t * 0.7);
        break;
      case RoboState.working:
        final w = t * 6.0;
        apN = -1.05 + 0.30 * math.sin(w);
        apP = -1.05 - 0.30 * math.sin(w);
        arN = 0.05;
        arP = 0.05;
        aeN = -1.30 + 0.35 * math.sin(w + 1.2);
        aeP = -1.30 - 0.35 * math.sin(w + 1.2);
        tp = -0.14 + 0.03 * math.sin(w * 2.0);
        lhN = 0.07 * math.sin(w * 0.5);
        lhP = -0.07 * math.sin(w * 0.5);
        fN = -lhN * 0.6;
        fP = -lhP * 0.6;
        break;
      case RoboState.happy:
        final wv = t * 7.5;
        apN = -0.20;
        apP = -0.20;
        arN = 2.55 + 0.28 * math.sin(wv);
        arP = 2.55 + 0.28 * math.sin(wv + math.pi);
        aeN = -0.25;
        aeP = -0.25;
        lhN = 0.12 * math.sin(t * 6.6);
        lhP = 0.12 * math.sin(t * 6.6 + math.pi);
        tp = 0.03 * math.sin(t * 3.3);
        break;
      case RoboState.error:
        if (_calmError) {
          // Gentle paused rest (used for a checked-out session): relaxed
          // arms at the sides, soft breathing. The head tilt is set in
          // _computeTargets; the head-shake term below is skipped.
          apN = 0.08;
          apP = 0.08;
          arN = 0.18;
          arP = 0.18;
          aeN = -0.30;
          aeP = -0.30;
          tp = 0.05;
          break;
        }
        // Confused: one hand scratches the head, the other shrugs.
        apP = -1.00 + 0.10 * math.sin(t * 9.0);
        arP = 0.50;
        aeP = -2.20 + 0.12 * math.sin(t * 9.0 + 1.0);
        apN = -0.15;
        arN = 0.90 + 0.05 * math.sin(t * 2.0);
        aeN = -0.60;
        tp = 0.05;
        break;
      case RoboState.sleeping:
        apN = 0.12;
        apP = 0.12;
        arN = 0.10;
        arP = 0.10;
        aeN = -0.20;
        aeP = -0.20;
        tp = 0.20 + 0.02 * math.sin(t * 0.9);
        lhN = -0.06;
        lhP = -0.06;
        fN = 0.10;
        fP = 0.10;
        break;
    }

    // While hopping the legs tuck and the arms lift a little.
    lhN -= 0.5 * air;
    lhP -= 0.5 * air;
    fN += 0.3 * air;
    fP += 0.3 * air;
    arN += 0.25 * air;
    arP += 0.25 * air;

    j[RoboJoint.armNPitch] = apN;
    j[RoboJoint.armNOut] = arN;
    j[RoboJoint.armNElbow] = aeN;
    j[RoboJoint.armPPitch] = apP;
    j[RoboJoint.armPOut] = arP;
    j[RoboJoint.armPElbow] = aeP;
    j[RoboJoint.legNHip] = lhN;
    j[RoboJoint.legPHip] = lhP;
    j[RoboJoint.footN] = fN;
    j[RoboJoint.footP] = fP;
    j[RoboJoint.torsoPitch] = tp;
    j[RoboJoint.torsoYaw] = ty;
  }
}
