import 'dart:math' as math;
import 'dart:typed_data';

/// A column-major 4x4 affine transform, just enough for a skeleton hierarchy
/// (translate, rotate, scale, multiply). Methods post-multiply: `m.rotateX(a)`
/// means `m = m * Rx(a)`, so calls read like a scene graph, outermost first.
class RoboMat {
  RoboMat() : m = Float64List(16) {
    m[0] = 1.0;
    m[5] = 1.0;
    m[10] = 1.0;
    m[15] = 1.0;
  }

  RoboMat.from(RoboMat o) : m = Float64List.fromList(o.m);

  final Float64List m;

  RoboMat copy() => RoboMat.from(this);

  void translate(double x, double y, double z) {
    m[12] += m[0] * x + m[4] * y + m[8] * z;
    m[13] += m[1] * x + m[5] * y + m[9] * z;
    m[14] += m[2] * x + m[6] * y + m[10] * z;
  }

  void scale(double sx, double sy, double sz) {
    for (var r = 0; r < 3; r++) {
      m[r] *= sx;
      m[4 + r] *= sy;
      m[8 + r] *= sz;
    }
  }

  void rotateX(double a) {
    final c = math.cos(a);
    final s = math.sin(a);
    for (var r = 0; r < 3; r++) {
      final c1 = m[4 + r];
      final c2 = m[8 + r];
      m[4 + r] = c1 * c + c2 * s;
      m[8 + r] = -c1 * s + c2 * c;
    }
  }

  void rotateY(double a) {
    final c = math.cos(a);
    final s = math.sin(a);
    for (var r = 0; r < 3; r++) {
      final c0 = m[r];
      final c2 = m[8 + r];
      m[r] = c0 * c - c2 * s;
      m[8 + r] = c0 * s + c2 * c;
    }
  }

  void rotateZ(double a) {
    final c = math.cos(a);
    final s = math.sin(a);
    for (var r = 0; r < 3; r++) {
      final c0 = m[r];
      final c1 = m[4 + r];
      m[r] = c0 * c + c1 * s;
      m[4 + r] = -c0 * s + c1 * c;
    }
  }

  double tx(double x, double y, double z) =>
      m[0] * x + m[4] * y + m[8] * z + m[12];
  double ty(double x, double y, double z) =>
      m[1] * x + m[5] * y + m[9] * z + m[13];
  double tz(double x, double y, double z) =>
      m[2] * x + m[6] * y + m[10] * z + m[14];

  /// World z of the local origin (used for depth sorting).
  double get originZ => m[14];
}
