import 'package:flutter/widgets.dart';

import 'robo_geometry.dart';
import 'robo_rig.dart';
import 'robo_types.dart';

/// The short text shown in the speech bubble for [state].
String roboStateLabel(RoboState state) {
  switch (state) {
    case RoboState.idle:
      return 'Idle';
    case RoboState.thinking:
      return 'Thinking...';
    case RoboState.searching:
      return 'Searching...';
    case RoboState.listening:
      return 'Listening...';
    case RoboState.speaking:
      return 'Speaking...';
    case RoboState.working:
      return 'Working...';
    case RoboState.happy:
      return 'Happy!';
    case RoboState.error:
      return 'Error';
    case RoboState.sleeping:
      return 'Sleeping...';
  }
}

const Color _ink = Color(0xFF15161B);

TextStyle roboBubbleTextStyle(double fontSize) => TextStyle(
  inherit: false,
  color: _ink,
  fontSize: fontSize,
  fontWeight: FontWeight.w700,
  height: 1.1,
  decoration: TextDecoration.none,
);

/// Metrics of the bubble for a given avatar size.
class RoboBubbleMetrics {
  RoboBubbleMetrics._(
    this.fontSize,
    this.width,
    this.bodyHeight,
    this.tailTipX,
    this.lines,
  );

  final double fontSize;
  final double width;
  final double bodyHeight;
  final int lines;

  /// x of the pointer tip, relative to the bubble's left edge.
  final double tailTipX;

  /// Measures the widest label so the bubble keeps one stable size while the
  /// text changes, and shrinks the font if it would not fit in [side].
  /// Pass the quote set in [texts] and the bubble also fits the longest
  /// quote: single line when it fits, otherwise two centered lines (words
  /// can never wrap, so an oversized single word shrinks the font instead).
  /// With no texts the result matches the legacy state-label sizing.
  factory RoboBubbleMetrics.forSide(
    double side, {
    List<String> texts = const [],
  }) {
    var font = (side * 0.075).clamp(8.0, 18.0).toDouble();
    double measure(double f, String text) {
      final tp = TextPainter(
        text: TextSpan(text: text, style: roboBubbleTextStyle(f)),
        textDirection: TextDirection.ltr,
        textScaler: TextScaler.noScaling,
      )..layout();
      return tp.width;
    }

    var widest = 0.0;
    for (final s in RoboState.values) {
      final w = measure(font, roboStateLabel(s));
      if (w > widest) widest = w;
    }
    var lines = 1;
    if (texts.isNotEmpty) {
      var longestText = 0.0;
      var longestWord = 0.0;
      for (final t in texts) {
        final w = measure(font, t);
        if (w > longestText) longestText = w;
        for (final word in t.split(' ')) {
          final ww = measure(font, word);
          if (ww > longestWord) longestWord = ww;
        }
      }
      var contentMax = side - 4.0 - font * 1.5;
      if (longestWord > contentMax && longestWord > 0.0) {
        font = font * contentMax / longestWord;
        longestText = 0.0;
        for (final t in texts) {
          final w = measure(font, t);
          if (w > longestText) longestText = w;
        }
        contentMax = side - 4.0 - font * 1.5;
      }
      if (longestText > contentMax) {
        lines = 2;
        if (contentMax > widest) widest = contentMax;
      } else if (longestText > widest) {
        widest = longestText;
      }
    }
    var width = widest + font * 1.5;
    if (width > side - 4.0) {
      font = font * (side - 4.0) / width;
      width = side - 4.0;
    }
    final body = font * 1.1 * lines + font * 0.9;
    return RoboBubbleMetrics._(font, width, body, width * 0.07, lines);
  }
}

class _BubbleShadowLayout extends SingleChildLayoutDelegate {
  const _BubbleShadowLayout(this.offset);
  final Offset offset;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) =>
      constraints.loosen();

  @override
  Offset getPositionForChild(Size size, Size childSize) => offset;

  @override
  bool shouldRelayout(_BubbleShadowLayout old) => old.offset != offset;
}

class _BubblePainter extends CustomPainter {
  const _BubblePainter({
    required this.bodyHeight,
    required this.tipX,
    required this.stroke,
  });

  final double bodyHeight;
  final double tipX;
  final double stroke;

  static Path shape(double w, double bodyH, double tipX, double tailH) {
    final r = bodyH * 0.22;
    final body = Path()
      ..addRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(0, 0, w, bodyH),
          Radius.circular(r),
        ),
      );
    // Pointer: vertical-ish left edge, diagonal right edge, sharp tip,
    // sloping toward the bottom-left like the reference sketch.
    final tail = Path()
      ..moveTo(r * 0.8, bodyH - 1)
      ..lineTo(r * 0.8 + w * 0.24, bodyH - 1)
      ..lineTo(tipX, bodyH + tailH)
      ..close();
    return Path.combine(PathOperation.union, body, tail);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final tailH = size.height - bodyHeight;
    final path = shape(size.width, bodyHeight, tipX, tailH);
    canvas.drawShadow(path, const Color(0xFF000000), 2.0, false);
    canvas.drawPath(path, Paint()..color = const Color(0xFFFFFFFF));
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeJoin = StrokeJoin.round
        ..strokeWidth = stroke
        ..color = _ink,
    );
  }

  @override
  bool shouldRepaint(_BubblePainter old) =>
      old.bodyHeight != bodyHeight || old.tipX != tipX || old.stroke != stroke;
}

/// The speech bubble above the head.
///
/// Placed inside the avatar's square box: it follows the robot's hop and
/// sway, is clamped so it never leaves the box, ignores pointer events, and
/// cross-fades its text whenever the state changes.
class RoboBubble extends StatelessWidget {
  const RoboBubble({
    super.key,
    required this.rig,
    required this.side,
    required this.text,
    this.texts = const [],
  });

  final RoboRig rig;
  final double side;
  final String text;

  /// Full quote set used only for sizing (see [RoboBubbleMetrics]).
  final List<String> texts;

  @override
  Widget build(BuildContext context) {
    final m = RoboBubbleMetrics.forSide(side, texts: texts);
    final k = RoboLayout.scale(side);
    final ground = RoboLayout.groundY(side);

    // Antenna tip and head-top-left of the resting robot, in pixels.
    final antennaTipY =
        ground - (RoboLayout.headTop + RoboLayout.antennaTip) * k;
    final headTopY = ground - RoboLayout.headTop * k;
    final bodyBottom = antennaTipY - side * 0.012;
    final tailH = (headTopY - 2.0 - bodyBottom).clamp(5.0, side).toDouble();
    final totalH = m.bodyHeight + tailH;
    final tipTargetX = side / 2.0 - 0.30 * k;
    final baseLeft = tipTargetX - m.tailTipX;
    final baseTop = bodyBottom - m.bodyHeight;

    final content = IgnorePointer(
      child: SizedBox(
        width: m.width,
        height: totalH,
        child: CustomPaint(
          painter: _BubblePainter(
            bodyHeight: m.bodyHeight,
            tipX: m.tailTipX,
            stroke: (m.fontSize * 0.11).clamp(1.0, 2.0).toDouble(),
          ),
          child: Align(
            alignment: Alignment.topCenter,
            child: SizedBox(
              height: m.bodyHeight,
              child: Center(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 220),
                  transitionBuilder: (child, anim) => FadeTransition(
                    opacity: anim,
                    child: ScaleTransition(
                      scale: Tween<double>(begin: 0.85, end: 1.0).animate(anim),
                      child: child,
                    ),
                  ),
                  child: Text(
                    text,
                    key: ValueKey<String>(text),
                    maxLines: m.lines,
                    softWrap: m.lines > 1,
                    textAlign: TextAlign.center,
                    textScaler: TextScaler.noScaling,
                    style: roboBubbleTextStyle(m.fontSize),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    return Positioned.fill(
      child: AnimatedBuilder(
        animation: rig,
        child: content,
        builder: (context, child) {
          var left = baseLeft + rig.x * 0.5 * k;
          var top = baseTop - rig.lift * 0.5 * k;
          left = left
              .clamp(1.0, (side - m.width - 1.0).clamp(1.0, side))
              .toDouble();
          top = top.clamp(1.0, side).toDouble();
          return CustomSingleChildLayout(
            delegate: _BubbleShadowLayout(Offset(left, top)),
            child: child,
          );
        },
      ),
    );
  }
}
