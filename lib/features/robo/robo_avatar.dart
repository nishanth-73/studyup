import 'package:flutter/gestures.dart' show PointerHoverEvent;
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import 'robo_bubble.dart';
import 'robo_painter.dart';
import 'robo_palette.dart';
import 'robo_rig.dart';
import 'robo_types.dart';

/// An animated Robo mascot drawn natively with a `CustomPainter`.
///
/// The widget is fully controlled by its parent: change [shape] or [state]
/// and Robo eases into the new look. It knows nothing about the app around
/// it.
///
/// ```dart
/// RoboAvatar(
///   shape: RoboShape.square,
///   state: RoboState.happy,
///   size: 160,
/// )
/// ```
///
/// Animation runs from a single `Ticker` per avatar and repaints the
/// painter directly, so frames never rebuild the widget tree. The ticker is
/// stopped whenever nothing is moving (animation disabled, or paused), and
/// is muted automatically when the avatar is off-screen (`TickerMode`).
class RoboAvatar extends StatefulWidget {
  const RoboAvatar({
    super.key,
    this.shape = RoboShape.square,
    this.state = RoboState.idle,
    this.size = 160.0,
    this.color,
    this.trimColor,
    this.inkColor,
    this.screenColor,
    this.accentColor,
    this.showBubble = true,
    this.bubbleText,
    this.bubbleTexts = const [],
    this.animated = true,
    this.paused = false,
    this.interactive = false,
    this.speed = 1.0,
    this.transitionDuration = const Duration(milliseconds: 450),
    this.calmError = false,
    this.showAntenna = true,
    this.floorShadow = true,
    this.seed = 0.0,
    this.respectReducedMotion = true,
    this.semanticLabel,
  }) : assert(size > 0.0, 'size must be positive'),
       assert(speed >= 0.0, 'speed must not be negative');

  /// Head outline: [RoboShape.square], [RoboShape.circle] or
  /// [RoboShape.hexagon]. Changing it morphs smoothly.
  final RoboShape shape;

  /// What Robo is doing. Changing it cross-fades the face and eases the pose.
  final RoboState state;

  /// Side length of the square box Robo and its bubble are drawn in, in
  /// logical pixels. Hops, tilts, limbs and the bubble stay inside it.
  final double size;

  /// Body (head and torso) colour. Defaults to a dark graphite.
  final Color? color;

  /// Colour of the arms, hands, legs, feet and antenna. Derived from
  /// [color] if null.
  final Color? trimColor;

  /// Colour of the eyes and mouth. Defaults to near-black.
  final Color? inkColor;

  /// Colour of the face panel. Defaults to off-white.
  final Color? screenColor;

  /// Accent: the panel's inset edge, equaliser and scan beam (teal).
  final Color? accentColor;

  /// Whether to show the speech bubble above the head. It is drawn inside
  /// the [size] box and never overflows it.
  final bool showBubble;

  /// Overrides the bubble text. By default the text describes [state].
  final String? bubbleText;

  /// Full candidate bubble texts used only to size the bubble so longer
  /// quotes fit (two centered lines when needed). Defaults to the state
  /// labels, preserving the legacy sizing.
  final List<String> bubbleTexts;

  /// When false, no motion loop runs: Robo shows the canonical still pose of
  /// its [state] (state/shape changes still ease in once, then settle).
  final bool animated;

  /// When true, the current frame is held exactly and the state is kept.
  /// Setting it back to false resumes from where it stopped. If [state] or
  /// [shape] change while paused, the new one eases in to its still pose and
  /// then holds.
  final bool paused;

  /// When true, Robo's eyes and head follow a hovering pointer and a tap
  /// makes it hop. Off by default so it never intercepts parent gestures.
  final bool interactive;

  /// Multiplier on animation speed (1 = normal, 0 = frozen time).
  final double speed;

  /// How long face cross-fades and shape morphs take.
  final Duration transitionDuration;

  /// When true, the error state renders as a calm paused rest (no shake,
  /// no alarming red): neutral eyes, small smile, warm antenna glow.
  /// The resolver still reports [RoboState.error]; only the presentation
  /// softens. Used for checked-out sessions.
  final bool calmError;

  /// Whether to draw the antenna stem and light. A small knob remains when
  /// false.
  final bool showAntenna;

  /// Whether to draw the soft floor shadow under the head.
  final bool floorShadow;

  /// 0..1. Desynchronises blinks, glances and hops between several avatars.
  /// Read once, when the avatar is first built.
  final double seed;

  /// When true (default), the platform "reduce motion"/"disable animations"
  /// accessibility setting shows the still pose, like `animated: false`.
  final bool respectReducedMotion;

  /// Accessibility label. Defaults to "Robot, `<state>`".
  final String? semanticLabel;

  @override
  State<RoboAvatar> createState() => _RoboAvatarState();
}

class _RoboAvatarState extends State<RoboAvatar>
    with SingleTickerProviderStateMixin {
  late final RoboRig _rig;
  late final Ticker _ticker;
  Duration _lastElapsed = Duration.zero;
  bool _mediaReduced = false;
  bool _initialised = false;

  @override
  void initState() {
    super.initState();
    _rig = RoboRig(
      state: widget.state,
      shape: widget.shape,
      seed: widget.seed,
      transitionDuration: widget.transitionDuration,
    );
    _rig.calmError = widget.calmError;
    _ticker = createTicker(_onTick);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _mediaReduced = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    _applyMode();
  }

  @override
  void didUpdateWidget(RoboAvatar oldWidget) {
    super.didUpdateWidget(oldWidget);
    _rig.transitionDuration = widget.transitionDuration;
    _rig.setShape(widget.shape);
    _rig.setState(widget.state);
    _rig.calmError = widget.calmError;
    _applyMode();
  }

  RoboMotionMode _desiredMode() {
    final reduced = widget.respectReducedMotion && _mediaReduced;
    if (!widget.animated || reduced) return RoboMotionMode.still;
    if (widget.paused) return RoboMotionMode.frozen;
    return RoboMotionMode.live;
  }

  void _applyMode() {
    final target = _desiredMode();
    _rig.setMode(target);
    if (!_initialised) {
      _initialised = true;
      if (target != RoboMotionMode.live) _rig.settle();
    }
    _syncTicker();
  }

  void _syncTicker() {
    if (_rig.isActive) {
      if (!_ticker.isActive) {
        _lastElapsed = Duration.zero;
        _ticker.start();
      }
    } else if (_ticker.isActive) {
      _ticker.stop();
    }
  }

  void _onTick(Duration elapsed) {
    final dt = (elapsed - _lastElapsed).inMicroseconds / 1e6;
    _lastElapsed = elapsed;
    _rig.advance(dt * widget.speed);
    if (!_rig.isActive) _ticker.stop();
  }

  void _onHover(PointerHoverEvent e) {
    final s = widget.size;
    _rig.pointer = Offset(
      (e.localPosition.dx / s - 0.5) * 2.0,
      (e.localPosition.dy / s - 0.5) * 2.0,
    );
  }

  @override
  void dispose() {
    _ticker.dispose();
    _rig.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette =
        (widget.color == null &&
            widget.trimColor == null &&
            widget.inkColor == null &&
            widget.screenColor == null &&
            widget.accentColor == null)
        ? RoboPalette.standard
        : RoboPalette.fromShell(
            widget.color ?? RoboPalette.defaultShell,
            trim: widget.trimColor,
            ink: widget.inkColor,
            screen: widget.screenColor,
            accent: widget.accentColor,
          );

    Widget child = RepaintBoundary(
      child: CustomPaint(
        size: Size.square(widget.size),
        isComplex: true,
        willChange: true,
        painter: RoboPainter(
          rig: _rig,
          palette: palette,
          showAntenna: widget.showAntenna,
          floorShadow: widget.floorShadow,
        ),
      ),
    );

    if (widget.interactive) {
      child = MouseRegion(
        onHover: _onHover,
        onExit: (_) => _rig.pointer = null,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _rig.poke,
          child: child,
        ),
      );
    }

    if (widget.showBubble) {
      child = Stack(
        children: <Widget>[
          Positioned.fill(child: child),
          RoboBubble(
            rig: _rig,
            side: widget.size,
            text: widget.bubbleText ?? roboStateLabel(widget.state),
            texts: widget.bubbleTexts,
          ),
        ],
      );
    }

    return Semantics(
      image: true,
      excludeSemantics: true,
      label: widget.semanticLabel ?? 'Robot, ${widget.state.name}',
      child: SizedBox.square(dimension: widget.size, child: child),
    );
  }
}
