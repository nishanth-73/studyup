import 'dart:typed_data';
import 'dart:ui' show PathMetric;
import 'dart:ui' as ui show Gradient, TileMode;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/smil.dart';

/// Decodes every embedded raster image in [scene] once; idempotent.
/// Uses the framework decoder (handles real codec work off-thread).
Future<void> ensureSmilImages(SmilScene scene) async {
  final pending = <SmilImage>[];
  void collect(SmilNode node) {
    switch (node) {
      case SmilGroup(:final children):
        for (final child in children) {
          collect(child);
        }
      case SmilImage(image: null):
        pending.add(node);
      case SmilImage():
        break;
      case SmilLeaf():
        break;
    }
  }

  for (final root in [
    ...scene.roots,
    ...scene.masks.values.expand((m) => m.children),
  ]) {
    collect(root);
  }
  for (final node in pending) {
    node.image = await decodeImageFromList(node.bytes);
  }
}

/// Play-state controller for [SvgArt]. The widget drives itself from the
/// session state; the controller exists for imperative control and tests.
class SvgArtController extends ChangeNotifier {
  _SvgArtState? _state;

  /// Starts (or restarts from the beginning) the loop.
  void play() => _state?.play();

  /// Halts at the resting frame (loop position 0).
  void showRest() => _state?.showRest();

  bool get isPlaying => _state?.isPlaying ?? false;

  void _attach(_SvgArtState state) => _state = state;

  void _detach(_SvgArtState state) {
    if (_state == state) _state = null;
  }

  @override
  void dispose() {
    _state = null;
    super.dispose();
  }
}

/// One animated SVG illustration.
///
/// - Parses [asset] once (shared cache per asset path) into an exact
///   timeline model; the artwork's own loop drives playback.
/// - [autoplay] starts the loop on load (decorative art). Controlled art
///   passes `autoplay: false` and drives [controller] instead.
/// - [scene] injects a pre-parsed scene (tests/previews); skips the
///   asset load but keeps identical playback.
/// - Reduced-motion holds the resting frame.
/// - ViewBox is contained (never stretched); transparent backgrounds stay
///   transparent.
class SvgArt extends StatefulWidget {
  final String asset;
  final SvgArtController? controller;
  final bool autoplay;
  final SmilScene? scene;
  final double? width;
  final double? height;

  const SvgArt({
    super.key,
    required this.asset,
    this.controller,
    this.autoplay = true,
    this.scene,
    this.width,
    this.height,
  });

  @override
  State<SvgArt> createState() => _SvgArtState();
}

class _SvgArtState extends State<SvgArt> with SingleTickerProviderStateMixin {
  static final Map<String, SmilScene> _sceneCache = {};

  late final AnimationController _loop;
  SmilScene? _scene;

  @override
  void initState() {
    super.initState();
    _loop = AnimationController(vsync: this);
    widget.controller?._attach(this);
    _load();
  }

  Future<void> _load() async {
    try {
      SmilScene? scene = widget.scene ?? _sceneCache[widget.asset];
      if (scene == null) {
        scene = SmilScene.parse(await rootBundle.loadString(widget.asset));
        _sceneCache[widget.asset] = scene;
      }
      await ensureSmilImages(scene);
      if (!mounted) return;
      _scene = scene;
      setState(() {});
      if (widget.autoplay) play();
    } catch (error) {
      debugPrint('SvgArt: cannot play ${widget.asset}: $error');
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if ((MediaQuery.maybeDisableAnimationsOf(context) ?? false)) {
      showRest();
    } else if (widget.autoplay && !_loop.isAnimating) {
      play();
    }
  }

  @override
  void didUpdateWidget(SvgArt oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller?._detach(this);
      widget.controller?._attach(this);
    }
  }

  void play() {
    final scene = _scene;
    if (scene == null || scene.loopSeconds <= 0 || !mounted) return;
    _loop.duration = Duration(milliseconds: (scene.loopSeconds * 1000).round());
    _loop.repeat();
  }

  void showRest() {
    _loop.stop();
    if (_loop.value != 0.0) _loop.value = 0.0;
  }

  bool get isPlaying => _loop.isAnimating;

  @override
  void dispose() {
    widget.controller?._detach(this);
    _loop.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scene = _scene;
    if (scene == null) return const SizedBox.shrink();
    return SizedBox(
      width: widget.width,
      height: widget.height,
      child: AnimatedBuilder(
        animation: _loop,
        builder: (context, _) {
          final duration = _loop.duration?.inMilliseconds ?? 0;
          return CustomPaint(
            painter: SmilPainter(
              scene: scene,
              tSeconds: _loop.value * duration / 1000,
            ),
            child: SizedBox(width: widget.width, height: widget.height),
          );
        },
      ),
    );
  }
}

/// Renders a [SmilScene] at loop time [tSeconds].
class SmilPainter extends CustomPainter {
  final SmilScene scene;
  final double tSeconds;

  const SmilPainter({required this.scene, required this.tSeconds});

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width / scene.width < size.height / scene.height
        ? size.width / scene.width
        : size.height / scene.height;
    final dx = (size.width - scene.width * s) / 2;
    final dy = (size.height - scene.height * s) / 2;
    canvas.save();
    canvas.translate(dx, dy);
    canvas.scale(s);
    final t = loopPosition(tSeconds, scene.loopSeconds);
    final tSec = t * scene.loopSeconds;
    for (final node in scene.roots) {
      _paintNode(canvas, node, tSec, 1.0, const [], 0.0, false, false);
    }
    canvas.restore();
  }

  /// Whiten-only `feColorMatrix` as a paint color filter (RGB forced to
  /// white, alpha preserved), optionally scaled by [alpha].
  static ColorFilter _whitenFilter(double alpha) {
    return ColorFilter.matrix([
      0, 0, 0, 0, 1, //
      0, 0, 0, 0, 1, //
      0, 0, 0, 0, 1, //
      0, 0, 0, alpha, 0, //
    ]);
  }

  static ColorFilter? _alphaFilter(double alpha) {
    if (alpha >= 1.0) return null;
    return ColorFilter.matrix([
      1, 0, 0, 0, 0, //
      0, 1, 0, 0, 0, //
      0, 0, 1, 0, 0, //
      0, 0, 0, alpha, 0, //
    ]);
  }

  /// Builds a fill/stroke paint from a solid color or a linear-gradient
  /// reference. Returns null when there is no source. The whiten filter
  /// flattens everything to plain white (alpha preserved).
  Paint? _brushPaint({
    required int? color,
    required String? gradientId,
    required double alpha,
    required PaintingStyle style,
    required BlendMode? blend,
    required bool white,
  }) {
    final paint = Paint()
      ..style = style
      ..blendMode = blend ?? BlendMode.srcOver;
    if (white) {
      paint.color = const Color(0xFFFFFFFF).withValues(alpha: alpha);
      return paint;
    }
    if (gradientId != null) {
      final gradient = scene.gradients[gradientId];
      if (gradient == null) {
        throw StateError('Unknown gradient #$gradientId');
      }
      paint.shader = ui.Gradient.linear(
        Offset(gradient.x1, gradient.y1),
        Offset(gradient.x2, gradient.y2),
        [
          for (final c in gradient.colors)
            Color(c).withValues(alpha: Color(c).a * alpha),
        ],
        gradient.stops,
        ui.TileMode.clamp,
      );
      return paint;
    }
    if (color == null) return null;
    paint.color = Color(color).withValues(alpha: Color(color).a * alpha);
    return paint;
  }

  void _paintNode(
    Canvas canvas,
    SmilNode node,
    double tSec,
    double parentAlpha,
    List<double> parentDash,
    double parentDashOffset,
    bool maskMode,
    bool forceWhite,
  ) {
    switch (node) {
      case SmilGroup(
        :final staticTransform,
        :final transformTracks,
        :final gate,
        :final baseVisible,
        :final clipId,
        :final baseOpacity,
        :final opacityTrack,
        :final motion,
        :final staticDash,
        :final dashTrack,
        :final staticDashOffset,
        :final dashOffsetTrack,
        :final maskId,
        :final filterId,
        :final children,
      ):
        final visible = gate != null
            ? gate.visibleAt(tSec, scene.loopSeconds)
            : baseVisible;
        if (!visible) return;
        var alpha = parentAlpha * baseOpacity;
        if (opacityTrack != null) {
          alpha *= opacityTrack
              .sample(tSec, scene.loopSeconds)
              .first
              .clamp(0.0, 1.0);
        }
        if (alpha <= 0.0) return;
        final white = forceWhite || (!maskMode && filterId != null);
        final mask = (!maskMode && maskId != null) ? scene.masks[maskId] : null;
        if (maskId != null && !maskMode && mask == null) {
          throw StateError('Unknown mask #$maskId');
        }
        if (mask != null) canvas.saveLayer(null, Paint());
        var dash = staticDash ?? parentDash;
        if (dashTrack != null) {
          dash = dashTrack.sample(tSec, scene.loopSeconds);
        }
        var dashOffset = staticDashOffset ?? parentDashOffset;
        if (dashOffsetTrack != null) {
          dashOffset = dashOffsetTrack.sample(tSec, scene.loopSeconds).first;
        }
        canvas.save();
        _concatAffine(canvas, staticTransform);
        _applyTransformTracks(canvas, transformTracks, tSec, scene.loopSeconds);
        if (motion != null) {
          final point = motion.sample(tSec, scene.loopSeconds);
          canvas.translate(point[0], point[1]);
        }
        if (clipId != null) {
          final clip = scene.clips[clipId];
          if (clip == null) {
            throw StateError('Unknown clipPath #$clipId');
          }
          canvas.clipPath(buildGeometryPath(clip.geometry));
        }
        for (final child in children) {
          _paintNode(
            canvas,
            child,
            tSec,
            alpha,
            dash,
            dashOffset,
            maskMode,
            white,
          );
        }
        canvas.restore();
        if (mask != null) {
          for (final child in mask.children) {
            _paintNode(canvas, child, tSec, 1.0, const [], 0.0, true, false);
          }
          canvas.restore();
        }
      case SmilLeaf(
        :final base,
        :final morph,
        :final setFrames,
        :final paint,
        :final baseOpacity,
        :final opacityTrack,
        :final staticTransform,
        :final transformTracks,
        :final gate,
        :final baseVisible,
        :final motion,
        :final maskId,
        :final filterId,
      ):
        final visible = gate != null
            ? gate.visibleAt(tSec, scene.loopSeconds)
            : baseVisible;
        if (!visible) return;
        var alpha = parentAlpha * baseOpacity;
        if (opacityTrack != null) {
          alpha *= opacityTrack
              .sample(tSec, scene.loopSeconds)
              .first
              .clamp(0.0, 1.0);
        }
        if (alpha <= 0.0) return;
        final white = forceWhite || (!maskMode && filterId != null);
        final mask = (!maskMode && maskId != null) ? scene.masks[maskId] : null;
        if (maskId != null && !maskMode && mask == null) {
          throw StateError('Unknown mask #$maskId');
        }
        if (mask != null) canvas.saveLayer(null, Paint());
        final Path geometry;
        if (setFrames != null) {
          final frame = setFrames.frameAt(tSec);
          geometry = buildGeometryPath(
            frame < 0 ? base : setFrames.frames[frame],
          );
        } else if (morph == null) {
          geometry = buildGeometryPath(base);
        } else {
          geometry = _buildMorphPath(morph, tSec, scene.loopSeconds);
        }
        var dash = paint.baseDash.isNotEmpty ? paint.baseDash : parentDash;
        final dashTrack = paint.dashTrack;
        if (dashTrack != null) {
          dash = dashTrack.sample(tSec, scene.loopSeconds);
        }
        var dashOffset = paint.baseDashOffset != 0.0
            ? paint.baseDashOffset
            : parentDashOffset;
        final dashOffsetTrack = paint.dashOffsetTrack;
        if (dashOffsetTrack != null) {
          dashOffset = dashOffsetTrack.sample(tSec, scene.loopSeconds).first;
        }
        // Mask content paints with dstIn so it carves the masked layer.
        final BlendMode? maskBlend = maskMode ? BlendMode.dstIn : null;
        canvas.save();
        _concatAffine(canvas, staticTransform);
        _applyTransformTracks(canvas, transformTracks, tSec, scene.loopSeconds);
        if (motion != null) {
          final point = motion.sample(tSec, scene.loopSeconds);
          canvas.translate(point[0], point[1]);
        }
        if (paint.fill != null || paint.fillGradient != null) {
          final fillPaint = _brushPaint(
            color: paint.fill,
            gradientId: paint.fillGradient,
            alpha: alpha,
            style: PaintingStyle.fill,
            blend: maskBlend,
            white: white,
          );
          if (fillPaint != null) {
            canvas.drawPath(geometry, fillPaint);
          }
        }
        if ((paint.stroke != null || paint.strokeGradient != null) &&
            paint.strokeWidth > 0) {
          final strokePaint =
              _brushPaint(
                color: paint.stroke,
                gradientId: paint.strokeGradient,
                alpha: alpha,
                style: PaintingStyle.stroke,
                blend: maskBlend,
                white: white,
              ) ??
              Paint();
          strokePaint
            ..strokeWidth = paint.strokeWidth
            ..strokeCap = _strokeCap(paint.strokeCap)
            ..strokeJoin = _strokeJoin(paint.strokeJoin);
          canvas.drawPath(
            dash.isEmpty ? geometry : _dashedPath(geometry, dash, dashOffset),
            strokePaint,
          );
        }
        canvas.restore();
        if (mask != null) {
          for (final child in mask.children) {
            _paintNode(canvas, child, tSec, 1.0, const [], 0.0, true, false);
          }
          canvas.restore();
        }
      case SmilImage(
        :final x,
        :final y,
        :final width,
        :final height,
        :final image,
        :final baseOpacity,
        :final opacityTrack,
        :final staticTransform,
        :final transformTracks,
        :final gate,
        :final baseVisible,
        :final motion,
        :final maskId,
        :final filterId,
      ):
        final visible = gate != null
            ? gate.visibleAt(tSec, scene.loopSeconds)
            : baseVisible;
        if (!visible || image == null) return;
        var alpha = parentAlpha * baseOpacity;
        if (opacityTrack != null) {
          alpha *= opacityTrack
              .sample(tSec, scene.loopSeconds)
              .first
              .clamp(0.0, 1.0);
        }
        if (alpha <= 0.0) return;
        final white = forceWhite || (!maskMode && filterId != null);
        final mask = (!maskMode && maskId != null) ? scene.masks[maskId] : null;
        if (maskId != null && !maskMode && mask == null) {
          throw StateError('Unknown mask #$maskId');
        }
        if (mask != null) canvas.saveLayer(null, Paint());
        canvas.save();
        _concatAffine(canvas, staticTransform);
        _applyTransformTracks(canvas, transformTracks, tSec, scene.loopSeconds);
        if (motion != null) {
          final point = motion.sample(tSec, scene.loopSeconds);
          canvas.translate(point[0], point[1]);
        }
        canvas.drawImageRect(
          image,
          Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
          Rect.fromLTWH(x, y, width, height),
          Paint()
            ..blendMode = maskMode ? BlendMode.dstIn : BlendMode.srcOver
            ..colorFilter = white ? _whitenFilter(alpha) : _alphaFilter(alpha),
        );
        canvas.restore();
        if (mask != null) {
          for (final child in mask.children) {
            _paintNode(canvas, child, tSec, 1.0, const [], 0.0, true, false);
          }
          canvas.restore();
        }
    }
  }

  Path _buildMorphPath(MorphTrack morph, double tSec, double loopSeconds) {
    final numbers = morph.sample(tSec, loopSeconds);
    final path = Path();
    var i = 0;
    for (final command in morph.commands) {
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
        case 'Z':
          path.close();
        default:
          throw StateError('Unexpected command $command');
      }
    }
    return path;
  }

  void _concatAffine(Canvas canvas, List<double> m) {
    canvas.transform(
      Float64List.fromList([
        m[0], m[1], 0, 0, //
        m[2], m[3], 0, 0, //
        0, 0, 1, 0, //
        m[4], m[5], 0, 1, //
      ]),
    );
  }

  void _applyTransformTracks(
    Canvas canvas,
    List<TransformTrack> tracks,
    double tSec,
    double loopSeconds,
  ) {
    for (final entry in tracks) {
      switch (entry.kind) {
        case 'translate':
          final pair = entry.track.sample(tSec, loopSeconds);
          canvas.translate(pair[0], pair.length > 1 ? pair[1] : 0.0);
        case 'rotate':
          canvas.rotate(
            entry.track.sample(tSec, loopSeconds).first * 0.017453292519943295,
          );
        case 'scale':
          final pair = entry.track.sample(tSec, loopSeconds);
          canvas.scale(pair[0], pair.length > 1 ? pair[1] : pair[0]);
      }
    }
  }

  StrokeCap _strokeCap(int cap) => switch (cap) {
    1 => StrokeCap.round,
    2 => StrokeCap.square,
    _ => StrokeCap.butt,
  };

  StrokeJoin _strokeJoin(int join) => switch (join) {
    1 => StrokeJoin.round,
    2 => StrokeJoin.bevel,
    _ => StrokeJoin.miter,
  };

  /// Standard dash emulation: on/off runs from [dash] pattern, phase
  /// shifted by [offset]. Restarts per contour like SVG rendering.
  Path _dashedPath(Path source, List<double> dash, double offset) {
    Path dashedForContour(PathMetric metric, double startPhase) {
      var pattern = [for (final d in dash) d < 0 ? 0.0 : d];
      // SVG doubles odd-length patterns so on/off parity repeats evenly.
      if (pattern.length.isOdd) pattern = [...pattern, ...pattern];
      final total = pattern.fold(0.0, (a, b) => a + b);
      final result = Path();
      if (total <= 0 || metric.length <= 0) return result;
      var phase = ((startPhase % total) + total) % total;
      var slot = 0;
      while (phase >= pattern[slot]) {
        phase -= pattern[slot];
        slot = (slot + 1) % pattern.length;
      }
      var slotRemaining = pattern[slot] - phase;
      var on = slot.isEven;
      var distance = 0.0;
      final length = metric.length;
      while (distance < length) {
        final take = (slotRemaining < length - distance)
            ? slotRemaining
            : length - distance;
        if (on && take > 0) {
          result.addPath(
            metric.extractPath(distance, distance + take),
            Offset.zero,
          );
        }
        distance += take;
        slot = (slot + 1) % pattern.length;
        slotRemaining = pattern[slot];
        on = slot.isEven;
      }
      return result;
    }

    final result = Path();
    for (final metric in source.computeMetrics()) {
      result.addPath(dashedForContour(metric, offset), Offset.zero);
    }
    return result;
  }

  @override
  bool shouldRepaint(SmilPainter oldDelegate) =>
      oldDelegate.scene != scene || oldDelegate.tSeconds != tSeconds;
}
