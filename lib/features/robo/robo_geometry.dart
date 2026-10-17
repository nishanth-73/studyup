import 'dart:math' as math;

import 'robo_mesh.dart';
import 'robo_types.dart';

double _pow(double b, double e) => math.pow(b, e).toDouble();

/// A closed outline in polar form `r(theta)`. Used for the face panel, whose
/// outline can be morphed between shapes by interpolating radii per angle.
class RoboProfile {
  /// A superellipse `|x/a|^n + |y/b|^n = 1` (n = 2: ellipse; larger: squarer).
  const RoboProfile.superEllipse({
    required double a,
    required double b,
    required double n,
  }) : _hex = false,
       _a = a,
       _b = b,
       _n = n,
       _p = 0,
       _m = 0;

  /// A flat-topped hexagon with the given [apothem]; larger [softness] gives
  /// sharper corners.
  const RoboProfile.hexagon({required double apothem, required double softness})
    : _hex = true,
      _a = 0,
      _b = 0,
      _n = 0,
      _p = apothem,
      _m = softness;

  final bool _hex;
  final double _a;
  final double _b;
  final double _n;
  final double _p;
  final double _m;

  double radiusAt(double theta) {
    if (!_hex) {
      final c = math.cos(theta).abs() / _a;
      final s = math.sin(theta).abs() / _b;
      return _pow(_pow(c, _n) + _pow(s, _n), -1.0 / _n);
    }
    var sum = 0.0;
    for (var k = 0; k < 6; k++) {
      final d = math.cos(theta - (math.pi / 6 + k * math.pi / 3));
      if (d > 0) sum += _pow(d, _m);
    }
    return _p / _pow(sum, 1.0 / _m);
  }
}

enum RoboCoreKind { rect, disc, hex }

/// Dimensions of one head shape, in world units (the whole robot is about
/// 1.9 units tall).
class RoboHeadSpec {
  const RoboHeadSpec({
    required this.kind,
    required this.coreHalfX,
    required this.coreHalfY,
    required this.coreHalfZ,
    required this.bevel,
    required this.panel,
    required this.panelW,
    required this.panelH,
    required this.faceUnit,
  });

  final RoboCoreKind kind;
  final double coreHalfX;
  final double coreHalfY;
  final double coreHalfZ;
  final double bevel;

  /// Outline of the face panel (in head-local x/y units).
  final RoboProfile panel;

  /// Approximate half extents of the panel, for the white inset offset.
  final double panelW;
  final double panelH;

  /// Half-width of the face drawing area (1.0 face unit), world units.
  final double faceUnit;

  double get halfX => coreHalfX + bevel;
  double get halfY => coreHalfY + bevel;
  double get halfZ => coreHalfZ + bevel;

  RoboCore2D get core {
    switch (kind) {
      case RoboCoreKind.rect:
        return RoboRectCore(coreHalfX, coreHalfY);
      case RoboCoreKind.disc:
        return RoboDiscCore(coreHalfX);
      case RoboCoreKind.hex:
        return RoboHexCore(coreHalfX);
    }
  }

  static const RoboHeadSpec _square = RoboHeadSpec(
    kind: RoboCoreKind.rect,
    coreHalfX: 0.35,
    coreHalfY: 0.29,
    coreHalfZ: 0.15,
    bevel: 0.17,
    panel: RoboProfile.superEllipse(a: 0.40, b: 0.31, n: 5.0),
    panelW: 0.40,
    panelH: 0.31,
    faceUnit: 0.36,
  );

  static const RoboHeadSpec _circle = RoboHeadSpec(
    kind: RoboCoreKind.disc,
    coreHalfX: 0.30,
    coreHalfY: 0.30,
    coreHalfZ: 0.13,
    bevel: 0.22,
    panel: RoboProfile.superEllipse(a: 0.37, b: 0.37, n: 2.0),
    panelW: 0.37,
    panelH: 0.37,
    faceUnit: 0.30,
  );

  static const RoboHeadSpec _hexagon = RoboHeadSpec(
    kind: RoboCoreKind.hex,
    coreHalfX: 0.36,
    coreHalfY: 0.312,
    coreHalfZ: 0.17,
    bevel: 0.15,
    panel: RoboProfile.hexagon(apothem: 0.33, softness: 14),
    panelW: 0.38,
    panelH: 0.33,
    faceUnit: 0.30,
  );

  static RoboHeadSpec of(RoboShape shape) {
    switch (shape) {
      case RoboShape.square:
        return _square;
      case RoboShape.circle:
        return _circle;
      case RoboShape.hexagon:
        return _hexagon;
    }
  }
}

/// Fixed layout constants shared by the painter and the speech bubble.
class RoboLayout {
  RoboLayout._();

  /// Distance of the camera from the robot's centre plane.
  static const double cameraDistance = 6.0;

  /// Camera height above the ground (world units).
  static const double cameraHeight = 0.9;

  /// Neck height (top of the torso) in world units.
  static const double neckY = 0.68;

  /// Highest point of any head shape (world units).
  static const double headTop = 1.70;

  /// Antenna tip height above [headTop].
  static const double antennaTip = 0.33;

  /// Pixels per world unit at the robot's centre plane.
  static double scale(double side) => side * 0.34;

  /// Screen y of the ground at the robot's centre plane.
  static double groundY(double side) => side * 0.93;
}
