import 'dart:math' as math;
import 'dart:typed_data';

import 'robo_geometry.dart';
import 'robo_types.dart';

/// An indexed triangle mesh with smooth per-vertex normals.
class RoboMesh {
  RoboMesh(this.positions, this.normals, this.indices)
    : vertexCount = positions.length ~/ 3;

  final Float32List positions;
  final Float32List normals;
  final Uint16List indices;
  final int vertexCount;
}

/// Closest-point projection onto a convex 2D "core" shape. Rounding a core
/// with a sphere of radius r (a Minkowski sum) gives a convex solid with
/// smooth bevels, which is how every Robo part is modelled.
abstract class RoboCore2D {
  const RoboCore2D();

  /// Writes the point of the core closest to ([x], [y]) into [out].
  void project(double x, double y, List<double> out);
}

class RoboRectCore extends RoboCore2D {
  const RoboRectCore(this.hx, this.hy);
  final double hx;
  final double hy;

  @override
  void project(double x, double y, List<double> out) {
    out[0] = x < -hx ? -hx : (x > hx ? hx : x);
    out[1] = y < -hy ? -hy : (y > hy ? hy : y);
  }
}

class RoboDiscCore extends RoboCore2D {
  const RoboDiscCore(this.radius);
  final double radius;

  @override
  void project(double x, double y, List<double> out) {
    final d = math.sqrt(x * x + y * y);
    if (d <= radius || d < 1e-12) {
      out[0] = x;
      out[1] = y;
    } else {
      out[0] = x / d * radius;
      out[1] = y / d * radius;
    }
  }
}

/// A flat-topped hexagon (vertices on the x axis) with circumradius [radius].
class RoboHexCore extends RoboCore2D {
  const RoboHexCore(this.radius);
  final double radius;

  @override
  void project(double x, double y, List<double> out) {
    final apothem = radius * math.cos(math.pi / 6);
    var inside = true;
    for (var k = 0; k < 6; k++) {
      final a = math.pi / 6 + k * math.pi / 3;
      if (x * math.cos(a) + y * math.sin(a) > apothem) {
        inside = false;
        break;
      }
    }
    if (inside) {
      out[0] = x;
      out[1] = y;
      return;
    }
    var best = double.infinity;
    for (var k = 0; k < 6; k++) {
      final a0 = k * math.pi / 3;
      final a1 = (k + 1) * math.pi / 3;
      final ax = radius * math.cos(a0);
      final ay = radius * math.sin(a0);
      final bx = radius * math.cos(a1);
      final by = radius * math.sin(a1);
      final ex = bx - ax;
      final ey = by - ay;
      var t = ((x - ax) * ex + (y - ay) * ey) / (ex * ex + ey * ey);
      t = t < 0.0 ? 0.0 : (t > 1.0 ? 1.0 : t);
      final qx = ax + ex * t;
      final qy = ay + ey * t;
      final d = (x - qx) * (x - qx) + (y - qy) * (y - qy);
      if (d < best) {
        best = d;
        out[0] = qx;
        out[1] = qy;
      }
    }
  }
}

double _warp(double t) => math.sin(t * math.pi / 2.0);

/// Builds a convex, smoothly bevelled solid: the core (an extruded 2D shape
/// with half-depth [coreHalfZ]) grown by [radius].
///
/// All meshes built with the same [segments] share one vertex topology, so
/// two of them (square head, hexagon head, ...) can be morphed by
/// interpolating positions and normals.
RoboMesh buildRoundedMesh({
  required RoboCore2D core,
  required double coreHalfX,
  required double coreHalfY,
  required double coreHalfZ,
  required double radius,
  int segments = 12,
}) {
  final n = segments;
  final per = (n + 1) * (n + 1);
  final pos = Float32List(6 * per * 3);
  final nor = Float32List(6 * per * 3);
  final idx = Uint16List(6 * n * n * 6);
  final bx = coreHalfX + radius;
  final by = coreHalfY + radius;
  final bz = coreHalfZ + radius;
  final out = <double>[0.0, 0.0];
  var v = 0;
  var t = 0;
  for (var face = 0; face < 6; face++) {
    final axis = face ~/ 2;
    final sign = face.isEven ? 1.0 : -1.0;
    final base = v;
    for (var i = 0; i <= n; i++) {
      final xi = _warp(i / n * 2.0 - 1.0);
      for (var j = 0; j <= n; j++) {
        final eta = _warp(j / n * 2.0 - 1.0);
        double px;
        double py;
        double pz;
        if (axis == 0) {
          px = sign * bx;
          py = xi * by;
          pz = eta * bz;
        } else if (axis == 1) {
          px = xi * bx;
          py = sign * by;
          pz = eta * bz;
        } else {
          px = xi * bx;
          py = eta * by;
          pz = sign * bz;
        }
        core.project(px, py, out);
        final iz = pz < -coreHalfZ
            ? -coreHalfZ
            : (pz > coreHalfZ ? coreHalfZ : pz);
        var dx = px - out[0];
        var dy = py - out[1];
        var dz = pz - iz;
        final len = math.sqrt(dx * dx + dy * dy + dz * dz);
        if (len < 1e-9) {
          dx = 0.0;
          dy = 0.0;
          dz = 1.0;
        } else {
          dx /= len;
          dy /= len;
          dz /= len;
        }
        pos[v * 3] = out[0] + dx * radius;
        pos[v * 3 + 1] = out[1] + dy * radius;
        pos[v * 3 + 2] = iz + dz * radius;
        nor[v * 3] = dx;
        nor[v * 3 + 1] = dy;
        nor[v * 3 + 2] = dz;
        v++;
      }
    }
    for (var i = 0; i < n; i++) {
      for (var j = 0; j < n; j++) {
        final a = base + i * (n + 1) + j;
        idx[t++] = a;
        idx[t++] = a + 1;
        idx[t++] = a + n + 1;
        idx[t++] = a + 1;
        idx[t++] = a + n + 2;
        idx[t++] = a + n + 1;
      }
    }
  }
  return RoboMesh(pos, nor, idx);
}

/// A flat convex polygon (given as x,y pairs) in the z = 0 plane facing +z.
RoboMesh buildPlateMesh(List<double> xy) {
  final m = xy.length ~/ 2;
  final pos = Float32List((m + 1) * 3);
  final nor = Float32List((m + 1) * 3);
  final idx = Uint16List(m * 3);
  var cx = 0.0;
  var cy = 0.0;
  for (var i = 0; i < m; i++) {
    cx += xy[i * 2];
    cy += xy[i * 2 + 1];
  }
  pos[0] = cx / m;
  pos[1] = cy / m;
  nor[2] = 1.0;
  for (var i = 0; i < m; i++) {
    pos[(i + 1) * 3] = xy[i * 2];
    pos[(i + 1) * 3 + 1] = xy[i * 2 + 1];
    nor[(i + 1) * 3 + 2] = 1.0;
    idx[i * 3] = 0;
    idx[i * 3 + 1] = i + 1;
    idx[i * 3 + 2] = (i + 1) % m + 1;
  }
  return RoboMesh(pos, nor, idx);
}

/// A rounded box centred on the origin.
RoboMesh buildRoundedBox(
  double hx,
  double hy,
  double hz,
  double r, {
  int segments = 8,
}) {
  return buildRoundedMesh(
    core: RoboRectCore(hx - r, hy - r),
    coreHalfX: hx - r,
    coreHalfY: hy - r,
    coreHalfZ: hz - r,
    radius: r,
    segments: segments,
  );
}

/// Lazily built, shared meshes for everything except the head's panel.
class RoboMeshes {
  RoboMeshes._();

  static const int headSegments = 14;

  static final Map<RoboShape, RoboMesh> _heads = <RoboShape, RoboMesh>{};

  static RoboMesh head(RoboShape shape) {
    return _heads.putIfAbsent(shape, () {
      final s = RoboHeadSpec.of(shape);
      return buildRoundedMesh(
        core: s.core,
        coreHalfX: s.coreHalfX,
        coreHalfY: s.coreHalfY,
        coreHalfZ: s.coreHalfZ,
        radius: s.bevel,
        segments: headSegments,
      );
    });
  }

  static final RoboMesh torso = buildRoundedBox(0.20, 0.17, 0.15, 0.08);
  static final RoboMesh upperArm = buildRoundedBox(0.055, 0.115, 0.055, 0.045);
  static final RoboMesh hand = buildRoundedBox(0.085, 0.09, 0.07, 0.045);
  static final RoboMesh leg = buildRoundedBox(0.065, 0.125, 0.065, 0.045);
  static final RoboMesh foot = buildRoundedBox(0.095, 0.05, 0.13, 0.04);
  static final RoboMesh antennaStem = buildRoundedBox(
    0.026,
    0.13,
    0.026,
    0.024,
    segments: 6,
  );
  static final RoboMesh bulb = buildRoundedBox(
    0.07,
    0.07,
    0.07,
    0.07,
    segments: 8,
  );
}
