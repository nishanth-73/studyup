import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' show Path, Image;

/// Generic SMIL-subset scene model for the StudyUp illustration assets.
///
/// Supported subset (exactly what the files use — anything else throws
/// [FormatException] at parse time so gaps fail loudly in tests):
/// - elements: `g`, `path`, `rect`, `ellipse`, `circle`, `defs`
///   (clipPath lookup), `clipPath`
/// - static transforms: `matrix()`, `translate()`, `scale()`, `rotate()`
///   (with optional center), composed in listed order
/// - `display` gates (discrete), `opacity` tracks, path `d` morphs with
///   uniform absolute `M/L/C/Z` structure, numeric `translate`/`rotate`/
///   `scale` transform tracks, `stroke-dasharray`/`stroke-dashoffset`
///   tracks, `animateMotion` drift along a `path` (translation only)
/// - all loops `indefinite`; non-positive durations freeze at base values
///
/// path-data commands supported: M/L/H/V/C/Z (absolute + relative).
class SmilScene {
  final double width;
  final double height;
  final double loopSeconds;
  final List<SmilNode> roots;
  final Map<String, SmilClip> clips;
  final Map<String, SmilMask> masks;
  final Map<String, SmilGradient> gradients;

  /// Filter ids whose effect is exactly "paint white, keep alpha"
  /// (whiten-only `feColorMatrix`), applied as a color override.
  final Set<String> whitenFilters;

  const SmilScene({
    required this.width,
    required this.height,
    required this.loopSeconds,
    required this.roots,
    required this.clips,
    required this.masks,
    required this.gradients,
    required this.whitenFilters,
  });

  factory SmilScene.parse(String svgSource) =>
      _SmilParser(svgSource).parseScene();
}

/// Loop position in [0, 1) for absolute [seconds].
double loopPosition(double seconds, double loopSeconds) {
  if (loopSeconds <= 0) return 0;
  return (seconds % loopSeconds) / loopSeconds;
}

/// Cubic-bezier easing for SMIL `keySplines x1 y1 x2 y2`.
double bezierEase(double x1, double y1, double x2, double y2, double t) {
  if (x1 == 0 && x2 == 1) return t.clamp(0.0, 1.0);
  var s = t.clamp(0.0, 1.0);
  for (var i = 0; i < 8; i++) {
    final x = _bezierComponent(x1, x2, s) - t;
    if (x.abs() < 1e-6) break;
    final dx = _bezierDerivative(x1, x2, s);
    if (dx.abs() < 1e-6) break;
    s = (s - x / dx).clamp(0.0, 1.0);
  }
  return _bezierComponent(y1, y2, s).clamp(0.0, 1.0);
}

double _bezierComponent(double p1, double p2, double s) {
  final u = 1 - s;
  return 3 * u * u * s * p1 + 3 * u * s * s * p2 + s * s * s;
}

double _bezierDerivative(double p1, double p2, double s) {
  final u = 1 - s;
  return 3 * u * u * p1 + 6 * u * s * (p2 - p1) + 3 * s * s * (1 - p2);
}

/// 2D affine `[a, b, c, d, e, f]` (x' = ax + cy + e, y' = bx + dy + f).
List<double> affineMultiply(List<double> m1, List<double> m2) => [
  m1[0] * m2[0] + m1[2] * m2[1],
  m1[1] * m2[0] + m1[3] * m2[1],
  m1[0] * m2[2] + m1[2] * m2[3],
  m1[1] * m2[2] + m1[3] * m2[3],
  m1[0] * m2[4] + m1[2] * m2[5] + m1[4],
  m1[1] * m2[4] + m1[3] * m2[5] + m1[5],
];

List<double> affineTranslate(double x, double y) => [1, 0, 0, 1, x, y];

List<double> affineRotate(double degrees, [double? cx, double? cy]) {
  // Degrees, clockwise positive to match SVG screen space.
  final t = degrees * math.pi / 180;
  final cos = math.cos(t);
  final sin = math.sin(t);
  final rotation = [cos, sin, -sin, cos, 0.0, 0.0];
  if (cx == null || cy == null) return rotation;
  return affineMultiply(
    affineMultiply(affineTranslate(cx, cy), rotation),
    affineTranslate(-cx, -cy),
  );
}

abstract class SmilNode {
  const SmilNode();
}

class SmilGroup extends SmilNode {
  final List<double> staticTransform;
  final List<TransformTrack> transformTracks;
  final GateTrack? gate;
  final bool baseVisible;
  final String? clipId;
  final double baseOpacity;
  final NumericTrack? opacityTrack;
  final MotionTrack? motion;
  final List<double>? staticDash;
  final NumericTrack? dashTrack;
  final double? staticDashOffset;
  final NumericTrack? dashOffsetTrack;
  final String? maskId;
  final String? filterId;
  final List<SmilNode> children;

  const SmilGroup({
    required this.staticTransform,
    required this.transformTracks,
    required this.gate,
    required this.baseVisible,
    required this.clipId,
    required this.baseOpacity,
    required this.opacityTrack,
    required this.motion,
    required this.staticDash,
    required this.dashTrack,
    required this.staticDashOffset,
    required this.dashOffsetTrack,
    required this.maskId,
    required this.filterId,
    required this.children,
  });
}

class SmilLeaf extends SmilNode {
  final ParsedGeometry base;
  final MorphTrack? morph;
  final SmilSetFrames? setFrames;
  final SmilPaint paint;
  final double baseOpacity;
  final NumericTrack? opacityTrack;
  final List<double> staticTransform;
  final List<TransformTrack> transformTracks;
  final GateTrack? gate;
  final bool baseVisible;
  final MotionTrack? motion;
  final String? maskId;
  final String? filterId;

  const SmilLeaf({
    required this.base,
    required this.morph,
    required this.setFrames,
    required this.paint,
    required this.baseOpacity,
    required this.opacityTrack,
    required this.staticTransform,
    required this.transformTracks,
    required this.gate,
    required this.baseVisible,
    required this.motion,
    required this.maskId,
    required this.filterId,
  });
}

class ParsedGeometry {
  final List<String> commands;
  final List<double> numbers;
  const ParsedGeometry(this.commands, this.numbers);
}

class SmilPaint {
  final int? fill;
  final String? fillGradient;
  final int? stroke;
  final String? strokeGradient;
  final double strokeWidth;
  final int strokeCap; // 0 butt, 1 round, 2 square
  final int strokeJoin; // 0 miter, 1 round, 2 bevel
  final List<double> baseDash;
  final NumericTrack? dashTrack;
  final double baseDashOffset;
  final NumericTrack? dashOffsetTrack;

  const SmilPaint({
    required this.fill,
    required this.fillGradient,
    required this.stroke,
    required this.strokeGradient,
    required this.strokeWidth,
    required this.strokeCap,
    required this.strokeJoin,
    required this.baseDash,
    required this.dashTrack,
    required this.baseDashOffset,
    required this.dashOffsetTrack,
  });
}

/// A `userSpaceOnUse` linear gradient: coordinates live in the user
/// space in effect at the referencing element, so the painter creates
/// the shader after applying the element transform. Anything else
/// (radial, transforms, spread != pad) throws at parse time.
class SmilGradient {
  final double x1;
  final double y1;
  final double x2;
  final double y2;
  final List<int> colors;
  final List<double> stops;
  const SmilGradient({
    required this.x1,
    required this.y1,
    required this.x2,
    required this.y2,
    required this.colors,
    required this.stops,
  });
}

/// Fill/stroke source as authored: solid color, gradient reference,
/// or unspecified (inherit from the parent group).
class SmilBrush {
  final int? color;
  final String? gradient;
  const SmilBrush({required this.color, required this.gradient});
}

class SmilClip {
  final ParsedGeometry geometry;
  const SmilClip(this.geometry);
}

/// An SVG `<mask>` subtree. Painted with dstIn blending over the masked
/// content. Luminance masks are approximated by mask alpha, which matches
/// exactly when the mask art is opaque white (true for these assets).
class SmilMask {
  final List<SmilNode> children;
  const SmilMask(this.children);
}

/// Discrete `<set>` frame-swap track (e.g. stepped `d` morphs): at loop
/// time `t` (seconds) the active frame is the last one with
/// `begin <= t`, else the base value. Different frame structures are
/// fine — frames swap, they never interpolate.
class SmilSetFrames {
  final List<double> begins;
  final List<ParsedGeometry> frames;
  const SmilSetFrames(this.begins, this.frames);

  /// Index of the active frame at [tSeconds], or -1 for the base value.
  int frameAt(double tSeconds) {
    var active = -1;
    for (var i = 0; i < begins.length; i++) {
      if (begins[i] <= tSeconds) {
        active = i;
      } else {
        break;
      }
    }
    return active;
  }
}

/// An embedded raster `<image>` leaf (data-URI source only).
class SmilImage extends SmilNode {
  final double x;
  final double y;
  final double width;
  final double height;
  final Uint8List bytes;
  Image? image;
  final double baseOpacity;
  final NumericTrack? opacityTrack;
  final List<double> staticTransform;
  final List<TransformTrack> transformTracks;
  final GateTrack? gate;
  final bool baseVisible;
  final MotionTrack? motion;
  final String? maskId;
  final String? filterId;

  SmilImage({
    required this.x,
    required this.y,
    required this.width,
    required this.height,
    required this.bytes,
    required this.baseOpacity,
    required this.opacityTrack,
    required this.staticTransform,
    required this.transformTracks,
    required this.gate,
    required this.baseVisible,
    required this.motion,
    required this.maskId,
    required this.filterId,
  });
}

/// SMIL timing for one animation element: active indefinitely from
/// [begin] (seconds, may be negative = already mid-flight at t=0),
/// repeating every [dur] seconds ([dur] null means the scene loop).
/// Sampling maps absolute loop time to the 0..1 phase of the current
/// iteration, so negative begins phase-shift instead of freezing.
class TrackTiming {
  final double begin;
  final double? dur;
  const TrackTiming(this.begin, this.dur);

  double localize(double tSeconds, double loopSeconds) {
    final period = dur ?? loopSeconds;
    if (period <= 0) return 0;
    var local = (tSeconds - begin) % period;
    if (local < 0) local += period;
    return (local / period).clamp(0.0, 1.0);
  }
}

/// One animated transform component in document order. Multiple tracks
/// on one element post-multiply in order (SMIL sandwich); a present
/// track list REPLACES the element's static transform entirely
/// (SMIL default `additive="replace"`, which is also how the artwork
/// is authored — animated values bake in their static offsets).
class TransformTrack {
  final String kind;
  final NumericTrack track;
  const TransformTrack(this.kind, this.track);
}

/// Discrete gate: last value whose keyTime has passed.
class GateTrack {
  final List<String> values;
  final List<double> keyTimes;
  final TrackTiming timing;
  const GateTrack(
    this.values,
    this.keyTimes, [
    this.timing = const TrackTiming(0, null),
  ]);

  bool visibleAt(double tSeconds, double loopSeconds) {
    if (values.isEmpty) return true;
    final t = timing.localize(tSeconds, loopSeconds);
    var result = values.first;
    for (var i = 0; i < values.length && i < keyTimes.length; i++) {
      if (keyTimes[i] <= t) {
        result = values[i];
      } else {
        break;
      }
    }
    return result == 'inline';
  }
}

/// Numeric keyframe track. Empty [keyTimes] means a single static value.
class NumericTrack {
  final List<List<double>> values;
  final List<double> keyTimes;
  final List<List<double>> splines;
  final TrackTiming timing;
  const NumericTrack(
    this.values,
    this.keyTimes,
    this.splines, [
    this.timing = const TrackTiming(0, null),
  ]);

  List<double> sample(double tSeconds, double loopSeconds) {
    if (values.length == 1 || keyTimes.isEmpty) return values.first;
    final t = timing.localize(tSeconds, loopSeconds);
    var segment = 0;
    while (segment + 1 < keyTimes.length - 1 && t >= keyTimes[segment + 1]) {
      segment++;
    }
    final last = keyTimes.length - 1;
    if (t >= keyTimes[last] || segment >= last) return values[last];
    final span = keyTimes[segment + 1] - keyTimes[segment];
    final local = span <= 0 ? 1.0 : (t - keyTimes[segment]) / span;
    final spline = segment < splines.length
        ? splines[segment]
        : const [0.0, 0.0, 1.0, 1.0];
    final eased = bezierEase(
      spline[0],
      spline[1],
      spline[2],
      spline[3],
      local.clamp(0.0, 1.0),
    );
    final a = values[segment];
    final b = values[segment + 1];
    return List<double>.generate(a.length, (i) => a[i] + (b[i] - a[i]) * eased);
  }
}

class MorphTrack extends NumericTrack {
  final List<String> commands;
  const MorphTrack(
    this.commands,
    super.values,
    super.keyTimes,
    super.splines, [
    super.timing,
  ]);
}

/// Drift-along-path motion: precomputed cumulative chord lengths.
class MotionTrack {
  final List<double> keyTimes;
  final List<List<double>> splines;
  final List<List<double>> points;
  final List<double> cumulative;
  final double total;
  final TrackTiming timing;

  MotionTrack({
    required this.keyTimes,
    required this.splines,
    required List<List<double>> rawPoints,
    this.timing = const TrackTiming(0, null),
  }) : points = rawPoints,
       cumulative = _cumulative(rawPoints),
       total = _cumulative(rawPoints).isEmpty
           ? 0.0
           : _cumulative(rawPoints).last;

  static List<double> _cumulative(List<List<double>> points) {
    final result = <double>[0.0];
    for (var i = 1; i < points.length; i++) {
      final dx = points[i][0] - points[i - 1][0];
      final dy = points[i][1] - points[i - 1][1];
      result.add(result.last + math.sqrt(dx * dx + dy * dy));
    }
    return result;
  }

  /// Absolute path point at absolute loop time [tSeconds].
  List<double> sample(double tSeconds, double loopSeconds) {
    if (points.isEmpty) return const [0.0, 0.0];
    if (points.length == 1 || total <= 0 || keyTimes.isEmpty) {
      return points.first;
    }
    final t = timing.localize(tSeconds, loopSeconds);
    var segment = 0;
    while (segment + 1 < keyTimes.length - 1 && t >= keyTimes[segment + 1]) {
      segment++;
    }
    final last = keyTimes.length - 1;
    if (t >= keyTimes[last] || segment >= last) return points.last;
    final span = keyTimes[segment + 1] - keyTimes[segment];
    final local = span <= 0 ? 1.0 : (t - keyTimes[segment]) / span;
    final spline = segment < splines.length
        ? splines[segment]
        : const [0.0, 0.0, 1.0, 1.0];
    final eased = bezierEase(
      spline[0],
      spline[1],
      spline[2],
      spline[3],
      local.clamp(0.0, 1.0),
    );
    final target = eased * total;
    var lo = 0;
    while (lo + 1 < cumulative.length - 1 && cumulative[lo + 1] < target) {
      lo++;
    }
    final segLen = cumulative[lo + 1] - cumulative[lo];
    final f = segLen <= 0 ? 0.0 : (target - cumulative[lo]) / segLen;
    return [
      points[lo][0] + (points[lo + 1][0] - points[lo][0]) * f,
      points[lo][1] + (points[lo + 1][1] - points[lo][1]) * f,
    ];
  }
}

// ---------------------------------------------------------------------------
// Parser.
// ---------------------------------------------------------------------------

final _tokenPattern = RegExp(r'[MLHVZCmlhvz]|-?\d*\.?\d+(?:[eE]-?\d+)?');
final _separatorPattern = RegExp(r'[,\s]');

Map<String, String> _parseAttrs(String tag) {
  final attrs = <String, String>{};
  final attrPattern = RegExp(r'([a-zA-Z:-]+)="([^"]*)"');
  for (final match in attrPattern.allMatches(tag)) {
    attrs[match.group(1)!] = match.group(2)!;
  }
  return attrs;
}

List<double> _parseDoubles(String value) => _tokenPattern
    .allMatches(value)
    .map((m) => m.group(0)!)
    .where((t) => double.tryParse(t) != null)
    .map((t) => double.parse(t))
    .toList();

List<double> _parseKeyTimes(String? value) {
  if (value == null || value.trim().isEmpty) return const [];
  return _parseDoubles(value);
}

List<List<double>> _parseKeySplines(String? value) {
  if (value == null || value.trim().isEmpty) return const [];
  final numbers = _parseDoubles(value);
  if (numbers.length % 4 != 0) {
    throw const FormatException('Malformed keySplines');
  }
  return [
    for (var i = 0; i < numbers.length; i += 4) numbers.sublist(i, i + 4),
  ];
}

List<String> _splitValues(String value) => [
  for (final part in value.split(';'))
    if (part.trim().isNotEmpty) part.trim(),
];

const _namedColors = {
  'white': 0xFFFFFFFF,
  'black': 0xFF000000,
  'red': 0xFFFF0000,
  'green': 0xFF008000,
  'blue': 0xFF0000FF,
  'yellow': 0xFFFFFF00,
};

int? _parseColor(String? value) {
  if (value == null || value == 'none') return null;
  final named = _namedColors[value.trim().toLowerCase()];
  if (named != null) return named;
  final match = RegExp(r'#([0-9a-fA-F]{6})').firstMatch(value);
  if (match == null) throw FormatException('Unsupported color: $value');
  return int.parse('FF${match.group(1)}', radix: 16);
}

/// Parses a fill/stroke source. Returns null when the attribute is
/// absent (inherit); `none` maps to an explicitly empty brush.
SmilBrush? _parseBrush(String? value) {
  if (value == null) return null;
  final trimmed = value.trim();
  final gradient = RegExp(r'url\(#([^)]+)\)').firstMatch(trimmed)?.group(1);
  if (gradient != null) {
    return SmilBrush(color: null, gradient: gradient);
  }
  return SmilBrush(color: _parseColor(trimmed), gradient: null);
}

double _parseDuration(String? value) {
  if (value == null) return 0;
  final match = RegExp(r'^(-?[\d.]+)s$').firstMatch(value.trim());
  if (match == null) throw FormatException('Bad duration: $value');
  return double.parse(match.group(1)!);
}

ParsedGeometry _parsePathData(String d) {
  final tokens = <Object>[];
  var pos = 0;
  for (final match in _tokenPattern.allMatches(d)) {
    final gap = d.substring(pos, match.start).replaceAll(_separatorPattern, '');
    if (gap.isNotEmpty) {
      throw FormatException('Unsupported path data: $d');
    }
    pos = match.end;
    final token = match.group(0)!;
    tokens.add(double.tryParse(token) ?? token);
  }
  final tail = d.substring(pos).replaceAll(_separatorPattern, '');
  if (tail.isNotEmpty) {
    throw FormatException('Unsupported path data: $d');
  }
  final commands = <String>[];
  final numbers = <double>[];
  var i = 0;

  double needNumber() {
    if (i >= tokens.length || tokens[i] is! double) {
      throw FormatException('Missing coordinate in: $d');
    }
    return tokens[i++] as double;
  }

  void take(int count) {
    for (var k = 0; k < count; k++) {
      numbers.add(needNumber());
    }
  }

  while (i < tokens.length) {
    final token = tokens[i];
    if (token is! String) {
      throw FormatException('Path must start with a command: $d');
    }
    final upper = token.toUpperCase();
    if (upper != 'M' &&
        upper != 'L' &&
        upper != 'H' &&
        upper != 'V' &&
        upper != 'C' &&
        upper != 'Z') {
      throw FormatException('Unsupported path command: $token');
    }
    commands.add(token);
    i++;
    switch (upper) {
      case 'M':
      case 'L':
        take(2);
        while (i < tokens.length && tokens[i] is double) {
          commands.add(upper == 'M' ? (token == 'M' ? 'L' : 'l') : token);
          take(2);
        }
      case 'H':
      case 'V':
        take(1);
        while (i < tokens.length && tokens[i] is double) {
          commands.add(token);
          take(1);
        }
      case 'C':
        take(6);
        while (i < tokens.length && tokens[i] is double) {
          commands.add(token);
          take(6);
        }
      case 'Z':
        if (i < tokens.length && tokens[i] is double) {
          throw FormatException('Stray coordinate in: $d');
        }
    }
  }
  if (commands.isEmpty) {
    throw FormatException('No path data found in: $d');
  }
  return ParsedGeometry(commands, numbers);
}

/// Absolute M/L/C/Z rewrite (H/V/Q normalized, relative variants and
/// implicit linetos normalized) for morph tracks and motion sampling.
ParsedGeometry _absolutize(ParsedGeometry parsed) {
  final commands = <String>[];
  final numbers = <double>[];
  var x = 0.0;
  var y = 0.0;
  var n = 0;
  final src = parsed.commands;
  final nums = parsed.numbers;

  double next() {
    if (n >= nums.length) throw const FormatException('Truncated path data');
    return nums[n++];
  }

  for (var i = 0; i < src.length; i++) {
    final upper = src[i].toUpperCase();
    final relative = src[i] != upper;
    switch (upper) {
      case 'M':
      case 'L':
        var nx = next();
        var ny = next();
        if (relative) {
          nx += x;
          ny += y;
        }
        commands.add(upper == 'M' && commands.isNotEmpty ? 'L' : 'M');
        numbers.addAll([nx, ny]);
        x = nx;
        y = ny;
      case 'C':
        var ns = [for (var k = 0; k < 6; k++) next()];
        if (relative) {
          ns = [
            ns[0] + x,
            ns[1] + y,
            ns[2] + x,
            ns[3] + y,
            ns[4] + x,
            ns[5] + y,
          ];
        }
        commands.add('C');
        numbers.addAll(ns);
        x = ns[4];
        y = ns[5];
      case 'H':
      case 'V':
        var nx = upper == 'H' ? next() : x;
        var ny = upper == 'V' ? next() : y;
        if (relative) {
          nx += x;
          ny += y;
        }
        commands.add('L');
        numbers.addAll([nx, ny]);
        x = nx;
        y = ny;
      case 'Q':
        var ns = [for (var k = 0; k < 4; k++) next()];
        if (relative) {
          ns = [ns[0] + x, ns[1] + y, ns[2] + x, ns[3] + y];
        }
        // Degree-elevate quadratic to cubic.
        commands.add('C');
        numbers.addAll([
          x + 2 / 3 * (ns[0] - x),
          y + 2 / 3 * (ns[1] - y),
          ns[2] + 2 / 3 * (ns[0] - ns[2]),
          ns[3] + 2 / 3 * (ns[1] - ns[3]),
          ns[2],
          ns[3],
        ]);
        x = ns[2];
        y = ns[3];
      case 'Z':
        commands.add('Z');
      default:
        throw FormatException('Unexpected command ${src[i]}');
    }
  }
  return ParsedGeometry(commands, numbers);
}

bool _sameCommands(List<String> a, List<String> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// Builds a Path from absolutized M/L/C/Z geometry.
Path buildGeometryPath(ParsedGeometry geometry) {
  final path = Path();
  final commands = geometry.commands;
  final numbers = geometry.numbers;
  var i = 0;
  for (final command in commands) {
    switch (command) {
      case 'M':
        path.moveTo(numbers[i], numbers[i + 1]);
        i += 2;
      case 'L':
        path.lineTo(numbers[i], numbers[i + 1]);
        i += 2;
      case 'C':
        path.cubicTo(
          numbers[i],
          numbers[i + 1],
          numbers[i + 2],
          numbers[i + 3],
          numbers[i + 4],
          numbers[i + 5],
        );
        i += 6;
      case 'Q':
        path.quadraticBezierTo(
          numbers[i],
          numbers[i + 1],
          numbers[i + 2],
          numbers[i + 3],
        );
        i += 4;
      case 'Z':
        path.close();
      default:
        throw FormatException('Unexpected command $command');
    }
  }
  return path;
}

enum LeafKind { path, rect, ellipse, circle }

class _SmilParser {
  final String source;
  int pos = 0;
  double maxDuration = 0;
  _SmilParser(this.source);

  SmilScene parseScene() {
    final start = source.indexOf('<svg');
    if (start < 0) throw const FormatException('No <svg> root');
    final openEnd = source.indexOf('>', start);
    final rootAttrs = _parseAttrs(source.substring(start, openEnd + 1));
    final viewBox = _parseDoubles(rootAttrs['viewBox'] ?? '');
    if (viewBox.length != 4) {
      throw const FormatException('viewBox must have 4 numbers');
    }
    pos = openEnd + 1;
    final clips = <String, SmilClip>{};
    final roots = <SmilNode>[];
    while (true) {
      _skipJunk();
      if (_peekStartsWith('</svg>') || pos >= source.length) break;
      if (_peekStartsWith('<defs')) {
        _parseDefs(clips);
        continue;
      }
      roots.add(_parseNode());
    }
    final scene = SmilScene(
      width: viewBox[2],
      height: viewBox[3],
      loopSeconds: maxDuration,
      roots: roots,
      clips: clips,
      masks: masks,
      gradients: gradients,
      whitenFilters: whitenFilters,
    );
    _validateRefs(scene);
    return scene;
  }

  /// Every mask/filter/gradient reference must resolve, and every
  /// filter must be a supported whiten filter — fidelity gaps fail
  /// here, not silently.
  void _validateRefs(SmilScene scene) {
    void checkBrush(String? gradient) {
      if (gradient != null && !scene.gradients.containsKey(gradient)) {
        throw StateError('Unknown gradient #$gradient');
      }
    }

    void checkNode(SmilNode node) {
      switch (node) {
        case SmilGroup(
          :final maskId,
          :final filterId,
          :final children,
          :final clipId,
        ):
          if (clipId != null && !scene.clips.containsKey(clipId)) {
            throw StateError('Unknown clipPath #$clipId');
          }
          if (maskId != null && !scene.masks.containsKey(maskId)) {
            throw StateError('Unknown mask #$maskId');
          }
          if (filterId != null && !scene.whitenFilters.contains(filterId)) {
            throw StateError('Unsupported filter #$filterId');
          }
          for (final child in children) {
            checkNode(child);
          }
        case SmilLeaf(:final maskId, :final filterId, :final paint):
          if (maskId != null && !scene.masks.containsKey(maskId)) {
            throw StateError('Unknown mask #$maskId');
          }
          if (filterId != null && !scene.whitenFilters.contains(filterId)) {
            throw StateError('Unsupported filter #$filterId');
          }
          checkBrush(paint.fillGradient);
          checkBrush(paint.strokeGradient);
        case SmilImage(:final maskId, :final filterId):
          if (maskId != null && !scene.masks.containsKey(maskId)) {
            throw StateError('Unknown mask #$maskId');
          }
          if (filterId != null && !scene.whitenFilters.contains(filterId)) {
            throw StateError('Unsupported filter #$filterId');
          }
      }
    }

    for (final root in scene.roots) {
      checkNode(root);
    }
    for (final mask in scene.masks.values) {
      for (final child in mask.children) {
        checkNode(child);
      }
    }
  }

  void _noteDuration(String? value) {
    if (value == null) return;
    final seconds = _parseDuration(value);
    if (seconds > maxDuration) maxDuration = seconds;
  }

  /// Null when the animation is inactive (non-positive duration).
  /// Indefinite repeats with any begin (even negative = already
  /// mid-flight) stay active with a phase offset — only a bad duration
  /// freezes at base values.
  bool _animActive(String? dur) {
    if (dur != null && _parseDuration(dur) <= 0) return false;
    return true;
  }

  TrackTiming _trackTiming(Map<String, String> attrs) {
    var begin = 0.0;
    if (attrs['begin'] != null) begin = _parseDuration(attrs['begin']);
    double? dur;
    if (attrs['dur'] != null) dur = _parseDuration(attrs['dur']);
    return TrackTiming(begin, dur);
  }

  void _skipJunk() {
    while (pos < source.length) {
      if (source.startsWith('<!--', pos)) {
        final end = source.indexOf('-->', pos + 4);
        if (end < 0) throw const FormatException('Unterminated comment');
        pos = end + 3;
        continue;
      }
      if (source.startsWith('<?', pos)) {
        final end = source.indexOf('?>', pos + 2);
        if (end < 0) throw const FormatException('Unterminated prolog');
        pos = end + 2;
        continue;
      }
      if (source.startsWith('<!', pos)) {
        final end = source.indexOf('>', pos + 2);
        if (end < 0) throw const FormatException('Unterminated decltype');
        pos = end + 1;
        continue;
      }
      if (source[pos].trim().isEmpty) {
        pos++;
        continue;
      }
      break;
    }
  }

  bool _peekStartsWith(String s) => source.startsWith(s, pos);

  String _readTag() {
    final end = source.indexOf('>', pos);
    if (end < 0) throw const FormatException('Unterminated tag');
    final tag = source.substring(pos, end + 1);
    pos = end + 1;
    return tag;
  }

  void _parseDefs(Map<String, SmilClip> clips) {
    final tag = _readTag();
    if (tag.endsWith('/>')) return;
    while (true) {
      _skipJunk();
      if (_peekStartsWith('</defs>')) {
        _readTag();
        return;
      }
      if (_peekStartsWith('<clipPath')) {
        _parseClipPath(clips);
        continue;
      }
      if (_peekStartsWith('<mask')) {
        _parseMask();
        continue;
      }
      if (_peekStartsWith('<filter')) {
        _parseFilter();
        continue;
      }
      if (_peekStartsWith('<linearGradient')) {
        _parseGradient();
        continue;
      }
      _skipSubtree();
    }
  }

  /// Masks/filters referenced by rendered content. Filled during defs
  /// parsing; validated against use-sites in [parseScene].
  final Map<String, SmilMask> masks = {};
  final Set<String> whitenFilters = {};
  final Map<String, SmilGradient> gradients = {};

  double _num(Map<String, String> attrs, String key, double fallback) {
    final raw = attrs[key];
    if (raw == null) return fallback;
    return double.parse(raw.trim().replaceAll('%', '')) /
        (raw.contains('%') ? 100 : 1);
  }

  void _parseGradient() {
    final tag = _readTag();
    final attrs = _parseAttrs(tag);
    final id = attrs['id'];
    if (id == null || id.isEmpty) {
      throw const FormatException('linearGradient without id');
    }
    if (attrs['gradientUnits'] != null &&
        attrs['gradientUnits'] != 'userSpaceOnUse') {
      throw FormatException('Unsupported gradientUnits in #$id');
    }
    if (attrs['gradientTransform'] != null ||
        (attrs['spreadMethod'] != null && attrs['spreadMethod'] != 'pad')) {
      throw FormatException('Unsupported gradient setup in #$id');
    }
    final colors = <int>[];
    final stops = <double>[];
    if (!tag.endsWith('/>')) {
      while (true) {
        _skipJunk();
        if (_peekStartsWith('</linearGradient>')) {
          _readTag();
          break;
        }
        if (_peekStartsWith('<stop')) {
          final stopTag = _readTag();
          final stopAttrs = _parseAttrs(stopTag);
          final color = _parseColor(stopAttrs['stop-color']) ?? 0x00000000;
          var alpha = (color >> 24 & 0xFF) / 255;
          if (stopAttrs['stop-opacity'] != null) {
            alpha *= double.parse(stopAttrs['stop-opacity']!.trim());
          }
          colors.add((color & 0xFFFFFF) | ((alpha * 255).round() << 24));
          stops.add(_num(stopAttrs, 'offset', stops.isEmpty ? 0 : 1));
          if (!stopTag.endsWith('/>')) _expectClose('stop');
          continue;
        }
        throw FormatException('Unsupported gradient child in #$id');
      }
    }
    if (colors.length < 2) throw FormatException('Short gradient #$id');
    gradients[id] = SmilGradient(
      x1: _num(attrs, 'x1', 0),
      y1: _num(attrs, 'y1', 0),
      x2: _num(attrs, 'x2', 1),
      y2: _num(attrs, 'y2', 0),
      colors: colors,
      stops: stops,
    );
  }

  void _parseMask() {
    final tag = _readTag();
    final id = _parseAttrs(tag)['id'];
    if (id == null || id.isEmpty) {
      throw const FormatException('mask without id');
    }
    final children = <SmilNode>[];
    if (!tag.endsWith('/>')) {
      while (true) {
        _skipJunk();
        if (_peekStartsWith('</mask>')) {
          _readTag();
          break;
        }
        children.add(_parseNode());
      }
    }
    if (children.isEmpty) throw FormatException('Empty mask $id');
    masks[id] = SmilMask(children);
  }

  /// Only the whiten-only `feColorMatrix` is supported; anything else
  /// throws so fidelity gaps fail loudly in tests.
  static const _whitenMatrix = [
    0.0,
    0.0,
    0.0,
    0.0,
    1.0,
    0.0,
    0.0,
    0.0,
    0.0,
    1.0,
    0.0,
    0.0,
    0.0,
    0.0,
    1.0,
    0.0,
    0.0,
    0.0,
    1.0,
    0.0,
  ];

  void _parseFilter() {
    final tag = _readTag();
    final id = _parseAttrs(tag)['id'];
    if (id == null || id.isEmpty) {
      throw const FormatException('filter without id');
    }
    var whiten = false;
    if (!tag.endsWith('/>')) {
      while (true) {
        _skipJunk();
        if (_peekStartsWith('</filter>')) {
          _readTag();
          break;
        }
        if (_peekStartsWith('<feColorMatrix')) {
          final matrixTag = _readTag();
          final values = _parseDoubles(_parseAttrs(matrixTag)['values'] ?? '');
          if (values.length == _whitenMatrix.length) {
            var same = true;
            for (var i = 0; i < values.length; i++) {
              if ((values[i] - _whitenMatrix[i]).abs() > 1e-9) {
                same = false;
                break;
              }
            }
            if (same) whiten = true;
          }
          if (!matrixTag.endsWith('/>')) _expectClose('feColorMatrix');
          continue;
        }
        throw FormatException('Unsupported filter primitive in #$id');
      }
    }
    if (!whiten) throw FormatException('Unsupported filter #$id');
    whitenFilters.add(id);
  }

  String? _urlRef(Map<String, String> attrs, String key) {
    final value = attrs[key];
    if (value == null) return null;
    final match = RegExp(r'url\(#([^)]+)\)').firstMatch(value);
    if (match == null) throw FormatException('Bad $key: $value');
    return match.group(1)!;
  }

  void _skipSubtree() {
    _skipJunk();
    if (!_peekStartsWith('<') || _peekStartsWith('</')) {
      throw const FormatException('Expected element');
    }
    final tag = _readTag();
    if (tag.endsWith('/>')) return;
    var depth = 1;
    while (depth > 0) {
      _skipJunk();
      if (pos >= source.length) {
        throw const FormatException('Unterminated subtree');
      }
      if (source.startsWith('</', pos)) {
        final end = source.indexOf('>', pos);
        pos = end + 1;
        depth--;
      } else if (source[pos] == '<') {
        final end = source.indexOf('>', pos);
        final inner = source.substring(pos, end + 1);
        pos = end + 1;
        if (!inner.endsWith('/>') && !inner.startsWith('<!')) {
          depth++;
        }
      } else {
        pos++;
      }
    }
  }

  void _parseClipPath(Map<String, SmilClip> clips) {
    final tag = _readTag();
    final id = _parseAttrs(tag)['id'];
    if (id == null || id.isEmpty) {
      throw const FormatException('clipPath without id');
    }
    final parts = <ParsedGeometry>[];
    if (!tag.endsWith('/>')) {
      while (true) {
        _skipJunk();
        if (_peekStartsWith('</clipPath>')) {
          _readTag();
          break;
        }
        parts.add(_parseClipShape());
      }
    }
    if (parts.isEmpty) throw FormatException('Empty clipPath $id');
    clips[id] = SmilClip(parts.first);
  }

  ParsedGeometry _parseClipShape() {
    if (_peekStartsWith('<rect')) {
      final attrs = _parseAttrs(_readTag());
      return _rectGeometry(attrs);
    }
    if (_peekStartsWith('<ellipse')) {
      final attrs = _parseAttrs(_readTag());
      return _ellipseGeometry(attrs);
    }
    if (_peekStartsWith('<circle')) {
      final attrs = _parseAttrs(_readTag());
      final cx = _attrNum(attrs, 'cx');
      final cy = _attrNum(attrs, 'cy');
      final r = _attrNum(attrs, 'r');
      return ParsedGeometry(
        const ['M', 'L', 'L', 'L', 'Z'],
        [cx - r, cy - r, cx + r, cy - r, cx + r, cy + r, cx - r, cy + r],
      );
    }
    if (_peekStartsWith('<path')) {
      final tag = _readTag();
      final geometry = _absolutize(_parsePathData(_parseAttrs(tag)['d'] ?? ''));
      if (!tag.endsWith('/>')) _expectClose('path');
      return geometry;
    }
    throw FormatException('Unsupported clip shape at offset $pos');
  }

  void _expectClose(String name) {
    while (true) {
      _skipJunk();
      if (_peekStartsWith('</$name>')) {
        _readTag();
        return;
      }
      throw FormatException('Expected </$name>');
    }
  }

  double _attrNum(Map<String, String> attrs, String key) =>
      double.parse((attrs[key] ?? '0').trim());

  SmilNode _parseNode({SmilBrush? fill, SmilBrush? stroke}) {
    _skipJunk();
    if (_peekStartsWith('<g')) return _parseGroup(fill: fill, stroke: stroke);
    if (_peekStartsWith('<path')) {
      return _parseLeaf(LeafKind.path, fill: fill, stroke: stroke);
    }
    if (_peekStartsWith('<rect')) {
      return _parseLeaf(LeafKind.rect, fill: fill, stroke: stroke);
    }
    if (_peekStartsWith('<ellipse')) {
      return _parseLeaf(LeafKind.ellipse, fill: fill, stroke: stroke);
    }
    if (_peekStartsWith('<circle')) {
      return _parseLeaf(LeafKind.circle, fill: fill, stroke: stroke);
    }
    if (_peekStartsWith('<image')) return _parseImage();
    throw FormatException(
      'Unsupported element at offset $pos: ${source.substring(pos, (pos + 40).clamp(0, source.length))}',
    );
  }

  SmilImage _parseImage() {
    final tag = _readTag();
    final attrs = _parseAttrs(tag);
    if (!tag.endsWith('/>')) {
      throw const FormatException('Animated <image> children unsupported');
    }
    var href = attrs['href'] ?? attrs['xlink:href'];
    if (href == null || !href.startsWith('data:image/')) {
      throw FormatException('Only embedded data-URI images supported');
    }
    final comma = href.indexOf(',');
    if (comma < 0) throw const FormatException('Malformed image data URI');
    return SmilImage(
      x: _attrNum(attrs, 'x'),
      y: _attrNum(attrs, 'y'),
      width: _attrNum(attrs, 'width'),
      height: _attrNum(attrs, 'height'),
      bytes: base64Decode(href.substring(comma + 1)),
      baseOpacity: attrs['opacity'] == null
          ? 1.0
          : double.parse(attrs['opacity']!.trim()),
      opacityTrack: null,
      staticTransform: _parseTransformList(attrs['transform']),
      transformTracks: const [],
      gate: null,
      baseVisible: attrs['display'] != 'none',
      motion: null,
      maskId: _urlRef(attrs, 'mask'),
      filterId: _urlRef(attrs, 'filter'),
    );
  }

  SmilGroup _parseGroup({SmilBrush? fill, SmilBrush? stroke}) {
    final tag = _readTag();
    final attrs = _parseAttrs(tag);
    final ownFill = _parseBrush(attrs['fill']);
    final ownStroke = _parseBrush(attrs['stroke']);
    // Presentation attributes inherit down the tree.
    final childFill = ownFill ?? fill;
    final childStroke = ownStroke ?? stroke;
    var staticTransform = _parseTransformList(attrs['transform']);
    final transformTracks = <TransformTrack>[];
    GateTrack? gate;
    final baseVisible = attrs['display'] != 'none';
    final clipId = _urlRef(attrs, 'clip-path');
    final maskId = _urlRef(attrs, 'mask');
    final filterId = _urlRef(attrs, 'filter');
    var baseOpacity = 1.0;
    if (attrs['opacity'] != null) {
      baseOpacity = double.parse(attrs['opacity']!.trim());
    }
    NumericTrack? opacityTrack;
    NumericTrack? dashTrack;
    NumericTrack? dashOffsetTrack;
    MotionTrack? motion;
    final staticDash =
        attrs['stroke-dasharray'] == null ||
            attrs['stroke-dasharray']!.trim() == 'none'
        ? null
        : _parseDoubles(attrs['stroke-dasharray']!);
    final staticDashOffset = attrs['stroke-dashoffset'] == null
        ? null
        : double.parse(attrs['stroke-dashoffset']!.trim());
    final children = <SmilNode>[];
    if (!tag.endsWith('/>')) {
      while (true) {
        _skipJunk();
        if (_peekStartsWith('</g>')) {
          _readTag();
          break;
        }
        if (_peekStartsWith('<animateTransform')) {
          final parsed = _parseTransformAnim();
          if (parsed != null) {
            transformTracks.add(
              TransformTrack(
                parsed.kind,
                NumericTrack(
                  parsed.values,
                  parsed.keyTimes,
                  parsed.splines,
                  parsed.timing,
                ),
              ),
            );
          }
          continue;
        }
        if (_peekStartsWith('<animateMotion')) {
          final parsed = _parseMotion();
          if (parsed != null) motion = parsed;
          continue;
        }
        if (_peekStartsWith('<animate')) {
          _parseElementAnim(
            onDisplay: (values, keyTimes, timing) {
              gate = GateTrack(values, keyTimes, timing);
            },
            onOpacity: (values, keyTimes, splines, timing) {
              opacityTrack = NumericTrack(
                _scalars(values),
                keyTimes,
                splines,
                timing,
              );
            },
            onDash: (values, keyTimes, splines, timing) {
              final lists = _dashLists(values);
              _requireUniform(lists, 'stroke-dasharray');
              dashTrack = NumericTrack(lists, keyTimes, splines, timing);
            },
            onDashOffset: (values, keyTimes, splines, timing) {
              dashOffsetTrack = NumericTrack(
                _scalars(values),
                keyTimes,
                splines,
                timing,
              );
            },
            onUnexpected: (name) {
              throw FormatException('Unsupported group animate: $name');
            },
          );
          continue;
        }
        if (_peekStartsWith('<set')) {
          throw const FormatException('<set> inside <g> unsupported');
        }
        children.add(_parseNode(fill: childFill, stroke: childStroke));
      }
    }
    // SMIL default additive="replace": live transform tracks replace the
    // static transform (animated values bake in their static offsets).
    if (transformTracks.isNotEmpty) {
      staticTransform = const [1, 0, 0, 1, 0, 0];
    }
    // Same for opacity: a live track replaces the static base.
    if (opacityTrack != null) {
      baseOpacity = 1.0;
    }
    return SmilGroup(
      staticTransform: staticTransform,
      transformTracks: transformTracks,
      gate: gate,
      baseVisible: baseVisible,
      clipId: clipId,
      baseOpacity: baseOpacity,
      opacityTrack: opacityTrack,
      motion: motion,
      staticDash: staticDash,
      dashTrack: dashTrack,
      staticDashOffset: staticDashOffset,
      dashOffsetTrack: dashOffsetTrack,
      maskId: maskId,
      filterId: filterId,
      children: children,
    );
  }

  SmilLeaf _parseLeaf(LeafKind kind, {SmilBrush? fill, SmilBrush? stroke}) {
    final tag = _readTag();
    final attrs = _parseAttrs(tag);
    final paint = _parsePaint(attrs);
    final leafFill = paint.fill ?? fill;
    final leafStroke = paint.stroke ?? stroke;
    var baseOpacity = 1.0;
    if (attrs['opacity'] != null) {
      baseOpacity = double.parse(attrs['opacity']!.trim());
    }
    final baseVisible = attrs['display'] != 'none';
    var staticTransform = _parseTransformList(attrs['transform']);
    final transformTracks = <TransformTrack>[];
    GateTrack? gate;
    NumericTrack? opacityTrack;
    NumericTrack? dashTrack;
    NumericTrack? dashOffsetTrack;
    MotionTrack? motion;
    ParsedGeometry? base;
    MorphTrack? morph;
    final setBegins = <double>[];
    final setFrames = <ParsedGeometry>[];
    switch (kind) {
      case LeafKind.path:
        final d = attrs['d'];
        if (d != null && d.trim().isNotEmpty) {
          base = _absolutize(_parsePathData(d));
        } else {
          base = const ParsedGeometry([], []);
        }
      case LeafKind.rect:
        base = _rectGeometry(attrs);
      case LeafKind.ellipse:
        base = _ellipseGeometry(attrs);
      case LeafKind.circle:
        final cx = _attrNum(attrs, 'cx');
        final cy = _attrNum(attrs, 'cy');
        final r = _attrNum(attrs, 'r');
        base = ParsedGeometry(
          const ['M', 'L', 'L', 'L', 'Z'],
          [cx - r, cy - r, cx + r, cy - r, cx + r, cy + r, cx - r, cy + r],
        );
    }
    if (!tag.endsWith('/>')) {
      while (true) {
        _skipJunk();
        if (_peekStartsWith('</path>') ||
            _peekStartsWith('</rect>') ||
            _peekStartsWith('</ellipse>') ||
            _peekStartsWith('</circle>')) {
          _readTag();
          break;
        }
        if (_peekStartsWith('<animateTransform')) {
          final parsed = _parseTransformAnim();
          if (parsed != null) {
            transformTracks.add(
              TransformTrack(
                parsed.kind,
                NumericTrack(
                  parsed.values,
                  parsed.keyTimes,
                  parsed.splines,
                  parsed.timing,
                ),
              ),
            );
          }
          continue;
        }
        if (_peekStartsWith('<animateMotion')) {
          final parsed = _parseMotion();
          if (parsed != null) motion = parsed;
          continue;
        }
        if (_peekStartsWith('<animate')) {
          _parseElementAnim(
            onDisplay: (values, keyTimes, timing) {
              gate = GateTrack(values, keyTimes, timing);
            },
            onOpacity: (values, keyTimes, splines, timing) {
              opacityTrack = NumericTrack(
                _scalars(values),
                keyTimes,
                splines,
                timing,
              );
            },
            onDash: (values, keyTimes, splines, timing) {
              final lists = _dashLists(values);
              _requireUniform(lists, 'stroke-dasharray');
              dashTrack = NumericTrack(lists, keyTimes, splines, timing);
            },
            onDashOffset: (values, keyTimes, splines, timing) {
              dashOffsetTrack = NumericTrack(
                _scalars(values),
                keyTimes,
                splines,
                timing,
              );
            },
            onMorph: (values, keyTimes, splines, timing) {
              morph = _parseMorph(values, keyTimes, splines, timing);
            },
            onUnexpected: (name) {
              throw FormatException('Unsupported leaf animate: $name');
            },
          );
          continue;
        }
        if (_peekStartsWith('<set')) {
          final frame = _parseSet();
          if (frame != null) {
            setBegins.add(frame.begin);
            setFrames.add(frame.geometry);
          }
          continue;
        }
        throw const FormatException('Unexpected element inside leaf');
      }
    }
    // Order set frames by begin so sampling is a linear scan.
    final order = [for (var i = 0; i < setBegins.length; i++) i]
      ..sort((a, b) => setBegins[a].compareTo(setBegins[b]));
    // SMIL default additive="replace": live transform tracks replace the
    // static transform; a live opacity track replaces the static base.
    if (transformTracks.isNotEmpty) {
      staticTransform = const [1, 0, 0, 1, 0, 0];
    }
    if (opacityTrack != null) {
      baseOpacity = 1.0;
    }
    return SmilLeaf(
      base: base,
      morph: morph,
      setFrames: setBegins.isEmpty
          ? null
          : SmilSetFrames(
              [for (final i in order) setBegins[i]],
              [for (final i in order) setFrames[i]],
            ),
      paint: SmilPaint(
        fill: leafFill?.color,
        fillGradient: leafFill?.gradient,
        stroke: leafStroke?.color,
        strokeGradient: leafStroke?.gradient,
        strokeWidth: paint.strokeWidth,
        strokeCap: paint.strokeCap,
        strokeJoin: paint.strokeJoin,
        baseDash: paint.baseDash,
        dashTrack: dashTrack,
        baseDashOffset: paint.baseDashOffset,
        dashOffsetTrack: dashOffsetTrack,
      ),
      baseOpacity: baseOpacity,
      opacityTrack: opacityTrack,
      staticTransform: staticTransform,
      transformTracks: transformTracks,
      gate: gate,
      baseVisible: baseVisible,
      motion: motion,
      maskId: _urlRef(attrs, 'mask'),
      filterId: _urlRef(attrs, 'filter'),
    );
  }

  /// Discrete `<set attributeName="d" to="..." begin="...s">` frame.
  /// Only `d` swaps are supported; anything else throws.
  ({double begin, ParsedGeometry geometry})? _parseSet() {
    final tag = _readTag();
    final attrs = _parseAttrs(tag);
    if (attrs['attributeName'] != 'd') {
      throw FormatException(
        'Unsupported <set> attribute: ${attrs['attributeName']}',
      );
    }
    final beginAttr = attrs['begin'];
    if (beginAttr == null) throw const FormatException('<set> without begin');
    final begin = _parseDuration(beginAttr);
    final to = attrs['to'];
    if (to == null || to.trim().isEmpty) {
      throw const FormatException('<set d> without to');
    }
    if (!tag.endsWith('/>')) _expectClose('set');
    if (begin < 0) return null;
    return (begin: begin, geometry: _absolutize(_parsePathData(to)));
  }

  void _requireUniform(List<List<double>> lists, String what) {
    if (lists.isEmpty) return;
    final length = lists.first.length;
    for (final row in lists) {
      if (row.length != length) {
        throw FormatException('Ragged $what values');
      }
    }
  }

  ({
    String kind,
    List<List<double>> values,
    List<double> keyTimes,
    List<List<double>> splines,
    TrackTiming timing,
  })?
  _parseTransformAnim() {
    final tag = _readTag();
    final attrs = _parseAttrs(tag);
    final type = attrs['type'] ?? '';
    if (type != 'translate' && type != 'rotate' && type != 'scale') {
      throw FormatException('Unsupported animateTransform: $type');
    }
    if (!_animActive(attrs['dur'])) return null;
    _noteDuration(attrs['dur']);
    final rawValues = _splitValues(attrs['values'] ?? '');
    if (!tag.endsWith('/>')) _expectClose('animateTransform');
    final values = [for (final v in rawValues) _parseDoubles(v)];
    _requireUniform(values, 'transform $type');
    final expected = type == 'rotate' ? 1 : 2;
    for (final row in values) {
      if (row.length != expected) {
        throw FormatException('Bad $type values: $rawValues');
      }
    }
    return (
      kind: type,
      values: values,
      keyTimes: _parseKeyTimes(attrs['keyTimes']),
      splines: _parseKeySplines(attrs['keySplines']),
      timing: _trackTiming(attrs),
    );
  }

  MotionTrack? _parseMotion() {
    final tag = _readTag();
    final attrs = _parseAttrs(tag);
    if (!_animActive(attrs['dur'])) {
      if (!tag.endsWith('/>')) _expectClose('animateMotion');
      return null;
    }
    _noteDuration(attrs['dur']);
    final pathAttr = attrs['path'];
    if (pathAttr == null) {
      throw const FormatException('animateMotion without path');
    }
    if (!tag.endsWith('/>')) _expectClose('animateMotion');
    final geometry = _absolutize(_parsePathData(pathAttr));
    final points = _flattenGeometry(geometry);
    return MotionTrack(
      keyTimes: _parseKeyTimes(attrs['keyTimes']),
      splines: _parseKeySplines(attrs['keySplines']),
      rawPoints: points,
      timing: _trackTiming(attrs),
    );
  }

  void _parseElementAnim({
    required void Function(List<String>, List<double>, TrackTiming) onDisplay,
    required void Function(
      List<String>,
      List<double>,
      List<List<double>>,
      TrackTiming,
    )
    onOpacity,
    void Function(List<String>, List<double>, List<List<double>>, TrackTiming)?
    onDash,
    void Function(List<String>, List<double>, List<List<double>>, TrackTiming)?
    onDashOffset,
    void Function(List<String>, List<double>, List<List<double>>, TrackTiming)?
    onMorph,
    required void Function(String) onUnexpected,
  }) {
    final tag = _readTag();
    final attrs = _parseAttrs(tag);
    final name = attrs['attributeName'] ?? '';
    if (!_animActive(attrs['dur'])) {
      if (!tag.endsWith('/>')) _expectClose('animate');
      return;
    }
    _noteDuration(attrs['dur']);
    final rawValues = _splitValues(attrs['values'] ?? '');
    final keyTimes = _parseKeyTimes(attrs['keyTimes']);
    final splines = _parseKeySplines(attrs['keySplines']);
    final timing = _trackTiming(attrs);
    if (!tag.endsWith('/>')) _expectClose('animate');
    switch (name) {
      case 'display':
        onDisplay(rawValues, keyTimes, timing);
      case 'opacity':
        onOpacity(rawValues, keyTimes, splines, timing);
      case 'stroke-dasharray':
        if (onDash == null) throw FormatException('Unexpected dash anim');
        onDash(rawValues, keyTimes, splines, timing);
      case 'stroke-dashoffset':
        if (onDashOffset == null) {
          throw FormatException('Unexpected dash-offset anim');
        }
        onDashOffset(rawValues, keyTimes, splines, timing);
      case 'd':
        if (onMorph == null) throw FormatException('Unexpected d anim');
        onMorph(rawValues, keyTimes, splines, timing);
      default:
        onUnexpected(name);
    }
  }

  List<List<double>> _scalars(List<String> rawValues) => [
    for (final v in rawValues) [double.parse(v.trim())],
  ];

  List<List<double>> _dashLists(List<String> rawValues) => [
    for (final v in rawValues) _parseDoubles(v),
  ];

  MorphTrack _parseMorph(
    List<String> rawValues,
    List<double> keyTimes,
    List<List<double>> splines,
    TrackTiming timing,
  ) {
    if (rawValues.isEmpty) {
      throw const FormatException('Empty d morph');
    }
    final parsed = [for (final v in rawValues) _parsePathData(v.trim())];
    final first = _absolutize(parsed.first);
    final tracks = [first.numbers];
    for (final frame in parsed.skip(1)) {
      final absolute = _absolutize(frame);
      if (!_sameCommands(first.commands, absolute.commands) ||
          absolute.numbers.length != first.numbers.length) {
        throw const FormatException('Morph keyframes differ in structure');
      }
      tracks.add(absolute.numbers);
    }
    if (tracks.length != keyTimes.length) {
      throw FormatException(
        'Morph values/keyTimes mismatch: ${tracks.length} vs ${keyTimes.length}',
      );
    }
    return MorphTrack(first.commands, tracks, keyTimes, splines, timing);
  }

  _PaintParts _parsePaint(Map<String, String> attrs) {
    var cap = 0;
    switch (attrs['stroke-linecap']) {
      case null:
      case 'butt':
        cap = 0;
      case 'round':
        cap = 1;
      case 'square':
        cap = 2;
      default:
        throw FormatException('Bad linecap ${attrs['stroke-linecap']}');
    }
    var join = 0;
    switch (attrs['stroke-linejoin']) {
      case null:
      case 'miter':
        join = 0;
      case 'round':
        join = 1;
      case 'bevel':
        join = 2;
      default:
        throw FormatException('Bad linejoin ${attrs['stroke-linejoin']}');
    }
    return _PaintParts(
      fill: _parseBrush(attrs['fill']),
      stroke: _parseBrush(attrs['stroke']),
      strokeWidth: attrs['stroke-width'] == null
          ? 1.0
          : double.parse(attrs['stroke-width']!.trim()),
      strokeCap: cap,
      strokeJoin: join,
      baseDash: attrs['stroke-dasharray'] == null
          ? const []
          : _parseDoubles(attrs['stroke-dasharray']!),
      baseDashOffset: attrs['stroke-dashoffset'] == null
          ? 0.0
          : double.parse(attrs['stroke-dashoffset']!.trim()),
    );
  }

  ParsedGeometry _rectGeometry(Map<String, String> attrs) {
    double num(String key) => double.parse((attrs[key] ?? '0').trim());
    final x = num('x');
    final y = num('y');
    final w = num('width');
    final h = num('height');
    final rx = attrs.containsKey('rx')
        ? num('rx')
        : (attrs.containsKey('ry') ? num('ry') : 0.0);
    final ry = attrs.containsKey('ry')
        ? num('ry')
        : (attrs.containsKey('rx') ? num('rx') : 0.0);
    if (rx <= 0 || ry <= 0) {
      return ParsedGeometry(
        const ['M', 'L', 'L', 'L', 'Z'],
        [x, y, x + w, y, x + w, y + h, x, y + h],
      );
    }
    return ParsedGeometry(
      const ['M', 'L', 'Q', 'L', 'Q', 'L', 'Q', 'L', 'Q', 'Z'],
      [
        x + rx, y, //
        x + w - rx, y, x + w, y, x + w, y + ry, //
        x + w, y + h - ry, x + w, y + h, x + w - rx, y + h, //
        x + rx, y + h, x, y + h, x, y + h - ry, //
        x, y + ry, x, y, x + rx, y, //
      ],
    );
  }

  ParsedGeometry _ellipseGeometry(Map<String, String> attrs) {
    double num(String key) => double.parse((attrs[key] ?? '0').trim());
    final cx = num('cx');
    final cy = num('cy');
    final rx = num('rx');
    final ry = num('ry');
    const kappa = 0.5522847498307936;
    final kx = rx * kappa;
    final ky = ry * kappa;
    return ParsedGeometry(
      const ['M', 'C', 'C', 'C', 'C', 'Z'],
      [
        cx + rx, cy, //
        cx + rx, cy - ky, cx + kx, cy - ry, cx, cy - ry, //
        cx - kx, cy - ry, cx - rx, cy - ky, cx - rx, cy, //
        cx - rx, cy + ky, cx - kx, cy + ry, cx, cy + ry, //
        cx + kx, cy + ry, cx + rx, cy + ky, cx + rx, cy, //
      ],
    );
  }

  List<double> _parseTransformList(String? value) {
    var result = [1.0, 0.0, 0.0, 1.0, 0.0, 0.0];
    if (value == null || value.trim().isEmpty) return result;
    final opPattern = RegExp(r'(matrix|translate|scale|rotate)\s*\(([^)]*)\)');
    var matched = false;
    for (final match in opPattern.allMatches(value)) {
      matched = true;
      final numbers = _parseDoubles(match.group(2)!);
      List<double> op;
      switch (match.group(1)) {
        case 'matrix':
          if (numbers.length != 6) {
            throw FormatException('Bad matrix: $value');
          }
          op = numbers;
        case 'translate':
          if (numbers.isEmpty || numbers.length > 2) {
            throw FormatException('Bad translate: $value');
          }
          op = [1, 0, 0, 1, numbers[0], numbers.length > 1 ? numbers[1] : 0];
        case 'scale':
          if (numbers.isEmpty || numbers.length > 2) {
            throw FormatException('Bad scale: $value');
          }
          final sy = numbers.length > 1 ? numbers[1] : numbers[0];
          op = [numbers[0], 0, 0, sy, 0, 0];
        case 'rotate':
          if (numbers.isEmpty || numbers.length > 3) {
            throw FormatException('Bad rotate: $value');
          }
          op = _rotateOp(
            numbers[0],
            numbers.length > 2 ? numbers[1] : null,
            numbers.length > 2 ? numbers[2] : null,
          );
        default:
          throw FormatException('Unsupported transform: $value');
      }
      result = affineMultiply(result, op);
    }
    if (!matched && value.trim().isNotEmpty) {
      throw FormatException('Unsupported transform: $value');
    }
    return result;
  }

  List<double> _rotateOp(double degrees, double? cx, double? cy) {
    final t = degrees * math.pi / 180;
    final cos = math.cos(t);
    final sin = math.sin(t);
    final rotation = [cos, sin, -sin, cos, 0.0, 0.0];
    if (cx == null || cy == null) return rotation;
    return affineMultiply(
      affineMultiply(affineTranslate(cx, cy), rotation),
      affineTranslate(-cx, -cy),
    );
  }

  List<List<double>> _flattenGeometry(ParsedGeometry geometry) {
    final path = buildGeometryPath(geometry);
    final points = <List<double>>[];
    for (final metric in path.computeMetrics()) {
      final length = metric.length;
      final steps = (length / 2).ceil().clamp(8, 400);
      for (var i = 0; i <= steps; i++) {
        final tangent = metric.getTangentForOffset(length * i / steps);
        if (tangent == null) continue;
        points.add([tangent.position.dx, tangent.position.dy]);
      }
    }
    if (points.isEmpty) points.add(const [0.0, 0.0]);
    return points;
  }
}

class _PaintParts {
  final SmilBrush? fill;
  final SmilBrush? stroke;
  final double strokeWidth;
  final int strokeCap;
  final int strokeJoin;
  final List<double> baseDash;
  final double baseDashOffset;
  const _PaintParts({
    required this.fill,
    required this.stroke,
    required this.strokeWidth,
    required this.strokeCap,
    required this.strokeJoin,
    required this.baseDash,
    required this.baseDashOffset,
  });
}
