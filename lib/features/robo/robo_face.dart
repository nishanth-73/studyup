import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';

import 'robo_state_style.dart';
import 'robo_types.dart';

/// Live parameters a face needs, copied out of the rig each frame.
class RoboFaceInput {
  const RoboFaceInput({
    required this.lookX,
    required this.lookY,
    required this.blink,
    required this.time,
    required this.since,
    required this.seed,
  });

  final double lookX;
  final double lookY;
  final double blink;
  final double time;
  final double since;
  final double seed;
}

class _Led {
  const _Led(this.path, this.alpha, this.stroke, this.color);

  final Path path;
  final double alpha;

  /// Stroke width in pixels, or 0 for a filled shape.
  final double stroke;
  final Color? color;
}

Color _a(Color c, double a) {
  final v = a < 0.0 ? 0.0 : (a > 1.0 ? 1.0 : a);
  return c.withAlpha((v * 255.0).round());
}

double _clamp(double v, double lo, double hi) =>
    v < lo ? lo : (v > hi ? hi : v);

const Color _white = Color(0xFFFFFFFF);
const Color _pink = Color(0xFFFF8CC8);

/// Draws one face (a state's eyes, mouth and effects) as LED-like vector
/// shapes around the origin of the canvas.
///
/// Coordinates inside the face methods are in "face units": 1.0 equals
/// [unit] pixels (the half-width of the face area). Every shape is collected
/// first, then drawn in two passes: a blurred glow pass and a crisp core
/// pass, so glow costs one blurred draw per shape and nothing else.
class RoboFaceRenderer {
  RoboFaceRenderer({
    required this.unit,
    required this.led,
    required this.errorColor,
    required this.accent,
    required this.glow,
    required this.halfWidth,
    required this.halfHeight,
  });

  /// Pixels per face unit.
  final double unit;

  /// Base LED colour.
  final Color led;

  /// LED colour of the error face.
  final Color errorColor;

  /// Accent colour for the equaliser and the scan beam.
  final Color accent;

  /// How much the core of each shape is lightened toward white (0 for ink on
  /// a bright panel).
  final double coreBlend = 0.0;

  /// Whether to draw the blurred glow pass (skipped at tiny sizes).
  final bool glow;

  /// Half extents of the screen in pixels, for screen-wide effects.
  final double halfWidth;
  final double halfHeight;

  final List<_Led> _leds = <_Led>[];

  /// The LED colour used by [state].
  Color colorFor(RoboState state, {bool calmError = false}) =>
      state == RoboState.error && !calmError ? errorColor : led;

  /// Draws [state]'s face at [opacity] (0..1). When [calmError] is true,
  /// the error state renders as a gentle paused face (neutral eyes plus
  /// a small reassuring smile, normal LED colour) instead of the alarming
  /// red XX face.
  void paint(
    Canvas canvas,
    RoboState state,
    double opacity,
    RoboFaceInput f, {
    bool calmError = false,
  }) {
    if (opacity <= 0.004) return;
    _leds.clear();
    final calm = calmError && state == RoboState.error;
    final base = colorFor(state, calmError: calmError);
    if (calm) {
      _calmPause(f);
      _flush(canvas, base, opacity);
      return;
    }
    switch (state) {
      case RoboState.idle:
        _eyes(f, h: 0.42);
        break;
      case RoboState.thinking:
        _thinking(f);
        break;
      case RoboState.searching:
        _beam(canvas, accent, opacity, f.time);
        _eyes(f, h: 0.42);
        break;
      case RoboState.listening:
        _listening(f);
        break;
      case RoboState.speaking:
        _speaking(f);
        break;
      case RoboState.working:
        _working(f);
        break;
      case RoboState.happy:
        _happy(f);
        break;
      case RoboState.error:
        _error(f);
        break;
      case RoboState.sleeping:
        _sleeping(f);
        break;
    }
    _flush(canvas, base, opacity);
  }

  // --- primitives --------------------------------------------------------

  double _u(double v) => v * unit;

  void _fill(Path p, double alpha, {Color? color}) {
    _leds.add(_Led(p, alpha, 0.0, color));
  }

  void _stroke(Path p, double width, double alpha, {Color? color}) {
    _leds.add(_Led(p, alpha, math.max(1.0, _u(width)), color));
  }

  void _pill(
    double cx,
    double cy,
    double w,
    double h,
    double alpha, {
    double? top,
    double? bottom,
    Color? color,
  }) {
    final rect = Rect.fromCenter(
      center: Offset(_u(cx), _u(cy)),
      width: _u(w),
      height: _u(h),
    );
    final r = math.min(w, h) / 2.0;
    final rt = _u(top ?? math.min(0.09, r));
    final rb = _u(bottom ?? math.min(0.09, r));
    final rr = RRect.fromRectAndCorners(
      rect,
      topLeft: Radius.circular(rt),
      topRight: Radius.circular(rt),
      bottomLeft: Radius.circular(rb),
      bottomRight: Radius.circular(rb),
    );
    _fill(Path()..addRRect(rr), alpha, color: color);
  }

  Offset _p(double x, double y) => Offset(_u(x), _u(y));

  // --- shared eyes -------------------------------------------------------

  /// Two block eyes that follow the look direction and close on a blink.
  void _eyes(
    RoboFaceInput f, {
    double h = 0.42,
    double w = 0.30,
    double dy = 0.0,
    double top = 0.09,
    double bottom = 0.09,
    double lookScale = 1.0,
    double alpha = 1.0,
  }) {
    final openH = math.max(0.06, h * (1.0 - f.blink * 0.93));
    final shiftX = f.lookX * 0.11 * lookScale;
    final shiftY = f.lookY * 0.09 * lookScale;
    for (final side in const <double>[-1.0, 1.0]) {
      _pill(
        side * 0.40 + shiftX,
        -0.12 + dy + shiftY,
        w,
        openH,
        alpha,
        top: top,
        bottom: bottom,
      );
    }
  }

  // --- the nine faces ----------------------------------------------------

  void _thinking(RoboFaceInput f) {
    // Heavy-lidded eyes (flat top) looking up toward the side it is turned to.
    _eyes(f, h: 0.32, dy: -0.05, top: 0.025);
    for (var i = 0; i < 3; i++) {
      final p = (f.time * 1.6 - i * 0.22) % 1.0;
      final pulse = p < 0.35 ? math.sin(p / 0.35 * math.pi) : 0.0;
      final r = 0.05 + 0.025 * pulse;
      final c = _p(-0.24 + i * 0.24, 0.46 - pulse * 0.04);
      _fill(
        Path()..addOval(Rect.fromCircle(center: c, radius: _u(r))),
        0.30 + 0.70 * pulse,
      );
    }
  }

  void _listening(RoboFaceInput f) {
    _eyes(f, h: 0.52, w: 0.31, dy: -0.10, lookScale: 0.6);
    final bar = accent;
    for (var i = 0; i < 9; i++) {
      final centre = 1.0 - (i - 4).abs() / 6.5;
      final level = roboNoise(f.time * 7.0 + i * 1.9 + f.seed * 10.0) * centre;
      final h = 0.05 + level * 0.30;
      _pill((i - 4) * 0.145, 0.52 - h / 2.0, 0.085, h, 0.88, color: bar);
    }
  }

  void _speaking(RoboFaceInput f) {
    _eyes(f, h: 0.36, dy: -0.14);
    final t = f.time;
    final env = math.max(
      0.0,
      math.sin(t * 2.1) * 0.5 + math.sin(t * 3.7 + 1.0) * 0.5,
    );
    final open = _clamp(roboNoise(t * 11.0) * (0.35 + env) * 1.1, 0.0, 1.0);
    final mh = 0.07 + open * 0.27;
    final mw = 0.58 - open * 0.20;
    _pill(0, 0.40, mw, mh, 1.0);
  }

  void _working(RoboFaceInput f) {
    // Flat, focused eyes looking down at the job, and a progress bar.
    _eyes(f, h: 0.15, w: 0.34, top: 0.05, bottom: 0.05);
    final p = (f.since / 2.6) % 1.0;
    final fill = p * 12.0;
    final whole = fill.floor();
    for (var i = 0; i < 12; i++) {
      double a;
      if (i < whole) {
        a = 0.95;
      } else if (i == whole) {
        a = 0.14 + 0.81 * (fill - whole);
      } else {
        a = 0.14;
      }
      _pill((i - 5.5) * 0.095, 0.44, 0.075, 0.09, a, top: 0.02, bottom: 0.02);
    }
  }

  void _happy(RoboFaceInput f) {
    final hop = -math.max(0.0, math.sin(f.time * 5.6)) * 0.05;
    for (final side in const <double>[-1.0, 1.0]) {
      final cx = side * 0.40;
      final caret = Path()
        ..moveTo(_u(cx - 0.15), _u(-0.06 + hop))
        ..quadraticBezierTo(
          _u(cx),
          _u(-0.30 + hop),
          _u(cx + 0.15),
          _u(-0.06 + hop),
        );
      _stroke(caret, 0.095, 1.0);
      _pill(side * 0.64, 0.24 + hop, 0.12, 0.06, 0.35, color: _pink);
    }
    final smile = Path()
      ..moveTo(_u(-0.28), _u(0.30 + hop))
      ..quadraticBezierTo(_u(0.0), _u(0.56 + hop), _u(0.28), _u(0.30 + hop));
    _stroke(smile, 0.08, 0.92);
  }

  void _error(RoboFaceInput f) {
    final on = math.sin(f.time * 7.0) > -0.6 ? 1.0 : 0.55;
    for (final side in const <double>[-1.0, 1.0]) {
      final cx = side * 0.40;
      final cross = Path()
        ..moveTo(_u(cx - 0.13), _u(-0.25))
        ..lineTo(_u(cx + 0.13), _u(0.01))
        ..moveTo(_u(cx + 0.13), _u(-0.25))
        ..lineTo(_u(cx - 0.13), _u(0.01));
      _stroke(cross, 0.085, on);
    }
    final zig = Path()..moveTo(_u(-0.30), _u(0.46));
    for (var i = 1; i <= 6; i++) {
      zig.lineTo(_u(-0.30 + i * 0.10), _u(i.isOdd ? 0.40 : 0.50));
    }
    _stroke(zig, 0.06, 0.85);
  }

  /// Gentle paused face: neutral block eyes plus a small reassuring
  /// smile, drawn in the normal LED colour (never alarming red).
  void _calmPause(RoboFaceInput f) {
    _eyes(f, h: 0.42);
    final smile = Path()
      ..moveTo(_u(-0.22), _u(0.30))
      ..quadraticBezierTo(_u(0.0), _u(0.48), _u(0.22), _u(0.30));
    _stroke(smile, 0.08, 0.92);
  }

  void _sleeping(RoboFaceInput f) {
    // Shut eyes: gentle downward arcs, dim.
    for (final side in const <double>[-1.0, 1.0]) {
      final cx = side * 0.40;
      final arc = Path()
        ..moveTo(_u(cx - 0.15), _u(-0.10))
        ..quadraticBezierTo(_u(cx), _u(0.04), _u(cx + 0.15), _u(-0.10));
      _stroke(arc, 0.075, 0.45);
    }
    // A big and a small "z" rising and fading (drawn as strokes, not text).
    for (var i = 0; i < 2; i++) {
      final p = ((f.time + i * 1.1) / 2.2) % 1.0;
      final v = math.sin(p * math.pi) * 0.6;
      if (v < 0.02) continue;
      final s = i == 0 ? 0.11 : 0.075;
      final x = 0.68 + p * 0.12;
      final y = -0.05 - p * 0.55;
      final z = Path()
        ..moveTo(_u(x - s), _u(y - s))
        ..lineTo(_u(x + s), _u(y - s))
        ..lineTo(_u(x - s), _u(y + s))
        ..lineTo(_u(x + s), _u(y + s));
      _stroke(z, 0.045, v);
    }
  }

  /// A beam sweeping across the whole screen with a fading trail.
  void _beam(Canvas canvas, Color base, double opacity, double t) {
    final ph = t * 1.6 + 0.4;
    final x = -halfWidth + (math.sin(ph) * 0.5 + 0.5) * (2.0 * halfWidth);
    final dir = math.cos(ph) > 0.0 ? 1.0 : -1.0;
    final trail = -dir * _u(0.6);
    final tail = x + trail;
    final rect = Rect.fromLTRB(
      math.min(x, tail),
      -halfHeight,
      math.max(x, tail),
      halfHeight,
    );
    final paint = Paint()
      ..shader = ui.Gradient.linear(Offset(tail, 0), Offset(x, 0), <Color>[
        _a(base, 0.0),
        _a(base, 0.42 * opacity),
      ]);
    canvas.drawRect(rect, paint);
    final line = Paint()
      ..color = _a(Color.lerp(base, _white, 0.4)!, 0.6 * opacity);
    canvas.drawRect(
      Rect.fromLTRB(x - _u(0.012), -halfHeight, x + _u(0.012), halfHeight),
      line,
    );
  }

  // --- drawing -----------------------------------------------------------

  void _flush(Canvas canvas, Color base, double opacity) {
    if (glow) {
      final blur = MaskFilter.blur(BlurStyle.normal, unit * 0.13);
      for (final l in _leds) {
        final p = Paint()
          ..maskFilter = blur
          ..color = _a(l.color ?? base, l.alpha * opacity * 0.6);
        if (l.stroke > 0.0) {
          p
            ..style = PaintingStyle.stroke
            ..strokeWidth = l.stroke * 1.25
            ..strokeCap = StrokeCap.round
            ..strokeJoin = StrokeJoin.round;
        }
        canvas.drawPath(l.path, p);
      }
    }
    for (final l in _leds) {
      final core = Color.lerp(l.color ?? base, _white, coreBlend)!;
      final p = Paint()..color = _a(core, l.alpha * opacity);
      if (l.stroke > 0.0) {
        p
          ..style = PaintingStyle.stroke
          ..strokeWidth = l.stroke
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round;
      }
      canvas.drawPath(l.path, p);
    }
  }
}
