import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';

import 'robo_face.dart';
import 'robo_geometry.dart';
import 'robo_math.dart';
import 'robo_mesh.dart';
import 'robo_palette.dart';
import 'robo_rig.dart';
import 'robo_state_style.dart';
import 'robo_types.dart';

const double _cam = RoboLayout.cameraDistance;
const double _camY = RoboLayout.cameraHeight;

// Body proportions (world units; the robot is ~1.9 tall).
const double _hipY = 0.34;
const double _torsoH = 0.34;
const double _shoulderX = 0.27;
const double _armLen = 0.22;
const double _legLen = 0.25;
const double _hipX = 0.13;

double _lerp(double a, double b, double t) => a + (b - a) * t;
double _clamp(double v, double lo, double hi) =>
    v < lo ? lo : (v > hi ? hi : v);

Color _a(Color c, double a) {
  final v = a < 0.0 ? 0.0 : (a > 1.0 ? 1.0 : a);
  return c.withAlpha((v * 255.0).round());
}

// ignore: deprecated_member_use
int _argb(Color c) => c.value;

/// Surface material for the software lighting.
class _Mat {
  _Mat(
    Color c, {
    this.spec = 0.4,
    this.rim = 0.2,
    this.env = 0.1,
    this.emissive,
    this.glow = 0.0,
  }) : r = ((_argb(c) >> 16) & 255).toDouble(),
       g = ((_argb(c) >> 8) & 255).toDouble(),
       b = (_argb(c) & 255).toDouble();

  final double r;
  final double g;
  final double b;
  final double spec;
  final double rim;
  final double env;
  final Color? emissive;
  final double glow;
}

class _Part {
  _Part(
    this.mesh,
    this.world,
    this.mat,
    this.outline,
    this.bias, {
    this.isHead = false,
  });

  final RoboMesh mesh;
  final RoboMat world;
  final _Mat mat;
  final double outline;
  final double bias;
  final bool isHead;
  double get depth => world.originZ + bias;
}

/// Paints a genuinely three-dimensional Robo.
///
/// Every body part is a real triangle mesh with smooth normals (rounded
/// boxes, a bevelled hexagonal prism, a bevelled disc, spheres) placed by a
/// joint hierarchy (torso -> neck -> head -> antenna, torso -> shoulder ->
/// hand, hip -> leg -> foot). Each frame the painter transforms the vertices
/// by the world matrices, applies a perspective camera, lights every vertex
/// (key, fill, rim, hemispheric ambient, Blinn specular, a sky reflection
/// term) and draws one `Canvas.drawVertices` call per part, preceded by an
/// inflated black "inverted hull" for the cartoon outline. Parts are convex
/// and drawn back to front, so no depth buffer is needed.
///
/// This is a CPU transform/lighting stage feeding Skia/Impeller, not a GPU
/// depth-buffered scene: it needs no plugins and runs on every Flutter
/// platform, at the cost of un-antialiased triangle edges and part-level
/// (not pixel-level) depth sorting.
class RoboPainter extends CustomPainter {
  RoboPainter({
    required this.rig,
    required this.palette,
    this.showAntenna = true,
    this.floorShadow = true,
  }) : super(repaint: rig);

  final RoboRig rig;
  final RoboPalette palette;
  final bool showAntenna;
  final bool floorShadow;

  // Scratch buffers, reused every frame.
  Float32List _pos = Float32List(0);
  Float32List _hull = Float32List(0);
  Int32List _col = Int32List(0);
  Float32List _ndv = Float32List(0);
  Uint16List _idx = Uint16List(0);
  final Paint _black = Paint();

  RoboMesh? _blended;

  // Per-paint projection state.
  double _f = 1.0;
  double _cx = 0.0;
  double _horizon = 0.0;
  Color _bulbColor = const Color(0xFFFFFFFF);
  double _bulbI = 0.0;

  @override
  bool shouldRepaint(RoboPainter old) =>
      old.rig != rig ||
      old.palette != palette ||
      old.showAntenna != showAntenna ||
      old.floorShadow != floorShadow;

  void _ensure(int nv, int ni) {
    if (_pos.length < nv * 2) {
      _pos = Float32List(nv * 2);
      _hull = Float32List(nv * 2);
      _col = Int32List(nv);
      _ndv = Float32List(nv);
    }
    if (_idx.length < ni) _idx = Uint16List(ni);
  }

  // --- head morph ------------------------------------------------------

  RoboMesh _headMesh() {
    final to = RoboMeshes.head(rig.shape);
    final mix = rig.shapeMix;
    if (mix >= 1.0 || rig.previousShape == rig.shape) return to;
    final from = RoboMeshes.head(rig.previousShape);
    var b = _blended;
    if (b == null || b.vertexCount != to.vertexCount) {
      b = RoboMesh(
        Float32List(to.positions.length),
        Float32List(to.normals.length),
        to.indices,
      );
      _blended = b;
    }
    for (var i = 0; i < to.positions.length; i++) {
      b.positions[i] = _lerp(from.positions[i], to.positions[i], mix);
      b.normals[i] = _lerp(from.normals[i], to.normals[i], mix);
    }
    return b;
  }

  // --- paint -----------------------------------------------------------

  @override
  void paint(Canvas canvas, Size size) {
    final side = math.min(size.width, size.height);
    if (side <= 1.0) return;
    final k = RoboLayout.scale(side);
    _f = k * _cam;
    _cx = side / 2.0;
    final ground = RoboLayout.groundY(side);
    _horizon = ground - _camY * k;
    _computeLight();

    canvas.save();
    canvas.translate((size.width - side) / 2.0, (size.height - side) / 2.0);

    if (floorShadow) _paintFloor(canvas, k, ground);

    final shapeT = rig.shapeMix;
    final fromSpec = RoboHeadSpec.of(
      shapeT >= 1.0 ? rig.shape : rig.previousShape,
    );
    final toSpec = RoboHeadSpec.of(rig.shape);
    final mixS = shapeT >= 1.0 ? 1.0 : shapeT;
    final headHalfY = _lerp(fromSpec.halfY, toSpec.halfY, mixS);
    final headHalfZ = _lerp(fromSpec.halfZ, toSpec.halfZ, mixS);

    final j = rig.joints;
    final shell = _Mat(palette.shell, spec: 0.55, rim: 0.25, env: 0.14);
    final trim = _Mat(palette.trim, spec: 0.40, rim: 0.22, env: 0.10);

    // --- skeleton ---
    final root = RoboMat()
      ..translate(rig.x * 0.5, rig.lift * 0.5, 0.0)
      ..scale(rig.sx, rig.sy, rig.sx)
      ..rotateZ(-rig.roll * 0.12);

    final torso = root.copy()
      ..translate(0.0, _hipY, 0.0)
      ..rotateX(j[RoboJoint.torsoPitch])
      ..rotateY(j[RoboJoint.torsoYaw]);

    final parts = <_Part>[];

    parts.add(
      _Part(
        RoboMeshes.torso,
        torso.copy()..translate(0.0, _torsoH / 2.0, 0.0),
        shell,
        0.028,
        0.0,
      ),
    );

    // Head chain: neck -> roll -> pitch -> yaw -> head centre.
    final head = torso.copy()
      ..translate(0.0, _torsoH, 0.0)
      ..rotateZ(-rig.roll)
      ..rotateX(-rig.pitch)
      ..rotateY(rig.yaw)
      ..translate(0.0, headHalfY - 0.03, 0.0);
    parts.add(_Part(_headMesh(), head, shell, 0.03, 0.02, isHead: true));

    // Antenna.
    if (showAntenna) {
      final ant = head.copy()
        ..translate(0.0, headHalfY - 0.02, 0.0)
        ..rotateZ(-rig.antennaX);
      parts.add(
        _Part(
          RoboMeshes.antennaStem,
          ant.copy()..translate(0.0, 0.13, 0.0),
          trim,
          0.016,
          0.05,
        ),
      );
      final bulbMat = _Mat(
        const Color(0xFF2A2D36),
        spec: 0.6,
        rim: 0.1,
        env: 0.1,
        emissive: _bulbColor,
        glow: _bulbI,
      );
      parts.add(
        _Part(
          RoboMeshes.bulb,
          ant.copy()..translate(0.0, 0.28, 0.0),
          bulbMat,
          0.016,
          0.06,
        ),
      );
    }

    // Arms and hands.
    for (final s in const <double>[-1.0, 1.0]) {
      final b = s < 0 ? RoboJoint.armNPitch : RoboJoint.armPPitch;
      final sh = torso.copy()
        ..translate(s * _shoulderX, _torsoH - 0.07, 0.0)
        ..rotateZ(s * j[b + 1])
        ..rotateX(j[b]);
      parts.add(
        _Part(
          RoboMeshes.upperArm,
          sh.copy()..translate(0.0, -_armLen / 2.0, 0.0),
          trim,
          0.022,
          0.0,
        ),
      );
      final wrist = sh.copy()
        ..translate(0.0, -_armLen, 0.0)
        ..rotateX(j[b + 2]);
      parts.add(
        _Part(
          RoboMeshes.hand,
          wrist.copy()..translate(0.0, -0.10, 0.0),
          trim,
          0.022,
          0.03,
        ),
      );
    }

    // Legs and feet.
    for (final s in const <double>[-1.0, 1.0]) {
      final hipJoint = s < 0 ? RoboJoint.legNHip : RoboJoint.legPHip;
      final footJoint = s < 0 ? RoboJoint.footN : RoboJoint.footP;
      final hip = root.copy()
        ..translate(s * _hipX, _hipY, 0.0)
        ..rotateX(j[hipJoint]);
      parts.add(
        _Part(
          RoboMeshes.leg,
          hip.copy()..translate(0.0, -_legLen / 2.0, 0.0),
          trim,
          0.022,
          -0.02,
        ),
      );
      final ankle = hip.copy()
        ..translate(0.0, -_legLen, 0.0)
        ..rotateX(j[footJoint]);
      parts.add(
        _Part(
          RoboMeshes.foot,
          ankle.copy()..translate(0.0, -0.04, 0.05),
          trim,
          0.022,
          0.02,
        ),
      );
    }

    // Back to front.
    parts.sort((p, q) => p.depth.compareTo(q.depth));
    for (final p in parts) {
      _drawMesh(canvas, p.mesh, p.world, p.mat, p.outline);
      if (p.isHead) {
        _paintFacePanel(canvas, p.world, headHalfZ, fromSpec, toSpec, mixS);
      }
    }

    canvas.restore();
  }

  // --- lighting --------------------------------------------------------

  void _computeLight() {
    final m = rig.stateMix;
    final t = rig.time;
    final prev = rig.previousState;
    final cur = rig.state;
    // A calm paused error glows warm white like idle, never alarming red.
    final curStyle = (rig.calmError && cur == RoboState.error)
        ? RoboState.idle
        : cur;
    _bulbColor = Color.lerp(
      RoboStateStyle.bulbColor(prev),
      RoboStateStyle.bulbColor(curStyle),
      m,
    )!;
    _bulbI = _clamp(
      _lerp(
        RoboStateStyle.bulbPulse(prev, t),
        RoboStateStyle.bulbPulse(curStyle, t),
        m,
      ),
      0.0,
      1.0,
    );
  }

  // Normalised key light (upper left, in front) and fill (right).
  static const double _l1x = -0.4991;
  static const double _l1y = 0.6807;
  static const double _l1z = 0.5627;
  static const double _l2x = 0.8200;
  static const double _l2y = 0.1757;
  static const double _l2z = 0.5271;

  int _shade(
    _Mat m,
    double nx,
    double ny,
    double nz,
    double vx,
    double vy,
    double vz,
  ) {
    final d1 = math.max(0.0, nx * _l1x + ny * _l1y + nz * _l1z);
    final d2 = math.max(0.0, nx * _l2x + ny * _l2y + nz * _l2z);
    final amb = 0.30 + 0.26 * (ny * 0.5 + 0.5);
    final lit = amb + d1 * 0.78 + d2 * 0.20;

    var hx = _l1x + vx;
    var hy = _l1y + vy;
    var hz = _l1z + vz;
    final hl = math.sqrt(hx * hx + hy * hy + hz * hz);
    hx /= hl;
    hy /= hl;
    hz /= hl;
    var sp = math.max(0.0, nx * hx + ny * hy + nz * hz);
    sp *= sp;
    sp *= sp;
    sp *= sp;
    sp *= sp;
    sp *= sp; // ^32
    final spec = d1 > 0.0 ? m.spec * sp : 0.0;

    final ndv = math.max(0.0, nx * vx + ny * vy + nz * vz);
    final rimF = 1.0 - ndv;
    final rim = m.rim * rimF * rimF * rimF * (0.4 + 0.6 * math.max(0.0, ny));

    // Sky reflection: a soft bright band where the surface mirrors the top.
    final ry = 2.0 * ndv * ny - vy;
    final envT = _clamp(ry * 0.5 + 0.5, 0.0, 1.0);
    final env = m.env * envT * envT;

    var r = m.r * lit + 255.0 * (spec + rim * 0.6 + env);
    var g = m.g * lit + 255.0 * (spec + rim * 0.7 + env);
    var b = m.b * lit + 255.0 * (spec + rim + env * 1.1);

    final e = m.emissive;
    if (e != null && m.glow > 0.0) {
      final ev = _argb(e);
      final k = m.glow;
      r = _lerp(r, ((ev >> 16) & 255).toDouble(), k);
      g = _lerp(g, ((ev >> 8) & 255).toDouble(), k);
      b = _lerp(b, (ev & 255).toDouble(), k);
    }
    final ri = r < 0.0 ? 0 : (r > 255.0 ? 255 : r.toInt());
    final gi = g < 0.0 ? 0 : (g > 255.0 ? 255 : g.toInt());
    final bi = b < 0.0 ? 0 : (b > 255.0 ? 255 : b.toInt());
    return (0xFF << 24) | (ri << 16) | (gi << 8) | bi;
  }

  // --- mesh drawing ----------------------------------------------------

  /// Transforms, lights and draws [mesh]; with [outline] > 0 an inflated
  /// black hull is drawn first for the cartoon outline.
  void _drawMesh(Canvas c, RoboMesh mesh, RoboMat w, _Mat mat, double outline) {
    final nv = mesh.vertexCount;
    final ni = mesh.indices.length;
    _ensure(nv, ni);
    final p = mesh.positions;
    final nrm = mesh.normals;
    final m = w.m;
    final withHull = outline > 0.0;

    for (var i = 0; i < nv; i++) {
      final i3 = i * 3;
      final px = p[i3];
      final py = p[i3 + 1];
      final pz = p[i3 + 2];
      final wx = m[0] * px + m[4] * py + m[8] * pz + m[12];
      final wy = m[1] * px + m[5] * py + m[9] * pz + m[13];
      final wz = m[2] * px + m[6] * py + m[10] * pz + m[14];
      final n0 = nrm[i3];
      final n1 = nrm[i3 + 1];
      final n2 = nrm[i3 + 2];
      var nx = m[0] * n0 + m[4] * n1 + m[8] * n2;
      var ny = m[1] * n0 + m[5] * n1 + m[9] * n2;
      var nz = m[2] * n0 + m[6] * n1 + m[10] * n2;
      final nl = math.sqrt(nx * nx + ny * ny + nz * nz);
      if (nl > 1e-9) {
        nx /= nl;
        ny /= nl;
        nz /= nl;
      }
      var vx = -wx;
      var vy = _camY - wy;
      var vz = _cam - wz;
      final vl = math.sqrt(vx * vx + vy * vy + vz * vz);
      vx /= vl;
      vy /= vl;
      vz /= vl;
      _ndv[i] = nx * vx + ny * vy + nz * vz;

      final d = math.max(0.5, _cam - wz);
      _pos[i * 2] = _cx + wx * _f / d;
      _pos[i * 2 + 1] = _horizon - (wy - _camY) * _f / d;
      if (withHull) {
        final hx = wx + nx * outline;
        final hy = wy + ny * outline;
        final hz = wz + nz * outline;
        final hd = math.max(0.5, _cam - hz);
        _hull[i * 2] = _cx + hx * _f / hd;
        _hull[i * 2 + 1] = _horizon - (hy - _camY) * _f / hd;
      }
      _col[i] = _shade(mat, nx, ny, nz, vx, vy, vz);
    }

    final idx = mesh.indices;
    if (withHull) {
      var count = 0;
      for (var t = 0; t < ni; t += 3) {
        final a = idx[t];
        final b = idx[t + 1];
        final cc = idx[t + 2];
        if ((_ndv[a] + _ndv[b] + _ndv[cc]) / 3.0 < 0.25) {
          _idx[count++] = a;
          _idx[count++] = b;
          _idx[count++] = cc;
        }
      }
      if (count > 0) {
        _black.color = palette.outline;
        final v = ui.Vertices.raw(
          ui.VertexMode.triangles,
          Float32List.sublistView(_hull, 0, nv * 2),
          indices: Uint16List.sublistView(_idx, 0, count),
        );
        c.drawVertices(v, BlendMode.srcOver, _black);
        v.dispose();
      }
    }

    var count = 0;
    for (var t = 0; t < ni; t += 3) {
      final a = idx[t];
      final b = idx[t + 1];
      final cc = idx[t + 2];
      if ((_ndv[a] + _ndv[b] + _ndv[cc]) / 3.0 > -0.02) {
        _idx[count++] = a;
        _idx[count++] = b;
        _idx[count++] = cc;
      }
    }
    if (count > 0) {
      final v = ui.Vertices.raw(
        ui.VertexMode.triangles,
        Float32List.sublistView(_pos, 0, nv * 2),
        colors: Int32List.sublistView(_col, 0, nv),
        indices: Uint16List.sublistView(_idx, 0, count),
      );
      c.drawVertices(v, BlendMode.srcOver, _black);
      v.dispose();
    }
  }

  // --- face panel ------------------------------------------------------

  List<double> _panelPolygon(
    RoboHeadSpec a,
    RoboHeadSpec b,
    double mix,
    double scale,
    double dx,
    double dy,
  ) {
    const m = 48;
    final xy = List<double>.filled(m * 2, 0.0);
    for (var i = 0; i < m; i++) {
      final th = i * 2.0 * math.pi / m;
      final r = _lerp(a.panel.radiusAt(th), b.panel.radiusAt(th), mix) * scale;
      xy[i * 2] = math.cos(th) * r + dx;
      xy[i * 2 + 1] = math.sin(th) * r + dy;
    }
    return xy;
  }

  Offset _project(RoboMat w, double x, double y, double z) {
    final wx = w.tx(x, y, z);
    final wy = w.ty(x, y, z);
    final wz = w.tz(x, y, z);
    final d = math.max(0.5, _cam - wz);
    return Offset(_cx + wx * _f / d, _horizon - (wy - _camY) * _f / d);
  }

  void _paintFacePanel(
    Canvas c,
    RoboMat head,
    double halfZ,
    RoboHeadSpec a,
    RoboHeadSpec b,
    double mix,
  ) {
    final pw = _lerp(a.panelW, b.panelW, mix);
    final ph = _lerp(a.panelH, b.panelH, mix);
    final unit = _lerp(a.faceUnit, b.faceUnit, mix);

    // Teal rim plate, with the white panel inset and shifted up-right so the
    // teal shows along the left and bottom edges, as in the reference.
    final teal = _panelPolygon(a, b, mix, 1.0, 0.0, 0.0);
    final sx = pw * 0.10;
    final sy = ph * 0.10;
    final white = _panelPolygon(a, b, mix, 0.90, sx, sy);

    final tealW = head.copy()..translate(0.0, 0.0, halfZ + 0.004);
    _drawMesh(
      c,
      buildPlateMesh(teal),
      tealW,
      _Mat(palette.accent, spec: 0.5, rim: 0.0, env: 0.1),
      0.0,
    );
    final whiteW = head.copy()..translate(0.0, 0.0, halfZ + 0.012);
    _drawMesh(
      c,
      buildPlateMesh(white),
      whiteW,
      _Mat(palette.screen, spec: 0.45, rim: 0.0, env: 0.15),
      0.0,
    );

    // Is the panel facing the camera?
    final m = whiteW.m;
    final toCam =
        (-m[12]) * m[8] + (_camY - m[13]) * m[9] + (_cam - m[14]) * m[10];
    if (toCam <= 0.05) return;

    // The face is drawn in 2D and mapped onto the panel plane with the
    // affine transform of its projected axes, so it follows the head's
    // yaw, pitch and roll exactly.
    final o = _project(whiteW, sx, sy, 0.0);
    final px = _project(whiteW, sx + unit, sy, 0.0);
    final py = _project(whiteW, sx, sy - unit, 0.0); // face y points down
    final depth = math.max(0.5, _cam - whiteW.tz(sx, sy, 0.0));
    final nominal = _f / depth;
    final unitPx = unit * nominal;

    final clip = Path();
    for (var i = 0; i < white.length ~/ 2; i++) {
      final q = _project(whiteW, white[i * 2], white[i * 2 + 1], 0.0);
      if (i == 0) {
        clip.moveTo(q.dx, q.dy);
      } else {
        clip.lineTo(q.dx, q.dy);
      }
    }
    clip.close();

    final matrix = Float64List(16);
    matrix[0] = (px.dx - o.dx) / unitPx;
    matrix[1] = (px.dy - o.dy) / unitPx;
    matrix[4] = (py.dx - o.dx) / unitPx;
    matrix[5] = (py.dy - o.dy) / unitPx;
    matrix[10] = 1.0;
    matrix[12] = o.dx;
    matrix[13] = o.dy;
    matrix[15] = 1.0;

    final renderer = RoboFaceRenderer(
      unit: unitPx,
      led: palette.ink,
      errorColor: palette.error,
      accent: palette.accent,
      glow: false,
      halfWidth: pw * 0.9 * nominal,
      halfHeight: ph * 0.9 * nominal,
    );
    final input = RoboFaceInput(
      lookX: rig.lookX,
      lookY: rig.lookY,
      blink: rig.blink,
      time: rig.time,
      since: rig.since,
      seed: rig.seed,
    );

    c.save();
    c.clipPath(clip);
    c.transform(matrix);
    final mixState = rig.stateMix;
    if (mixState < 1.0) {
      renderer.paint(c, rig.previousState, 1.0 - mixState, input);
    }
    renderer.paint(c, rig.state, mixState, input, calmError: rig.calmError);
    c.restore();

    // Soft glass reflection across the upper left of the panel.
    c.save();
    c.clipPath(clip);
    final bounds = clip.getBounds();
    c.drawRect(
      bounds,
      Paint()
        ..shader = ui.Gradient.linear(bounds.topLeft, bounds.center, <Color>[
          _a(const Color(0xFFFFFFFF), 0.30),
          _a(const Color(0xFFFFFFFF), 0.0),
        ]),
    );
    c.restore();
  }

  // --- floor shadow ----------------------------------------------------

  void _paintFloor(Canvas c, double k, double ground) {
    final lift = math.max(0.0, rig.lift);
    final s = _clamp(1.0 - lift * 0.55, 0.45, 1.0);
    final x = _cx + rig.x * 0.5 * k;
    c.drawOval(
      Rect.fromCenter(
        center: Offset(x, ground),
        width: k * 1.9 * s,
        height: k * 0.40 * s,
      ),
      Paint()
        ..color = _a(const Color(0xFF000000), 0.40 * s)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, k * 0.10),
    );
  }
}
