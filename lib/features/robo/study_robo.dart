import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'robo_avatar.dart';
import 'robo_customize.dart';
import 'robo_mood.dart';
import 'robo_shape.dart';
import 'robo_types.dart';

/// The one shared StudyUp Robo, used by Home and Profile so both screens
/// always show the same shape and the same mood for the same situation.
///
/// Shape comes from the persisted [roboShapeProvider]. Mood comes from
/// the central [roboMoodProvider]: progress phases while running, a calm
/// paused reminder while checked out, task states otherwise, idle + wave
/// when nothing applies.
///
/// Quote timing: the state label shows first, then a contextual quote
/// after ~3 seconds, rotating every ~9 seconds. Timers restart only when
/// the mood genuinely changes (tracked by [RoboMood.key]) — never on
/// per-second timer ticks — and changing the bubble text never touches
/// the rig, so body animations keep running undisturbed. All timers are
/// cancelled on mood change and dispose.
class StudyRobo extends ConsumerStatefulWidget {
  final double size;
  final double seed;
  const StudyRobo({super.key, this.size = 96, this.seed = 0.0});

  @override
  ConsumerState<StudyRobo> createState() => _StudyRoboState();
}

class _StudyRoboState extends ConsumerState<StudyRobo> {
  String? _moodKey;
  bool _showQuote = false;
  int _quoteIndex = 0;
  Timer? _labelTimer;
  Timer? _quoteTimer;

  @override
  void dispose() {
    _labelTimer?.cancel();
    _quoteTimer?.cancel();
    super.dispose();
  }

  void _cancelTimers() {
    _labelTimer?.cancel();
    _labelTimer = null;
    _quoteTimer?.cancel();
    _quoteTimer = null;
  }

  void _observeMood(RoboMood mood) {
    if (mood.key == _moodKey) return;
    _moodKey = mood.key;
    _showQuote = false;
    _quoteIndex = 0;
    _cancelTimers();
    if (mood.state == RoboState.idle) {
      // "Hii!" shows immediately; no label phase for the greeting.
      _showQuote = true;
      return;
    }
    _labelTimer = Timer(const Duration(seconds: 3), () {
      if (!mounted || mood.key != _moodKey) return;
      setState(() => _showQuote = true);
      _quoteTimer = Timer.periodic(const Duration(seconds: 9), (_) {
        if (!mounted || mood.key != _moodKey) return;
        setState(() => _quoteIndex = _quoteIndex + 1);
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final mood = ref.watch(roboMoodProvider);
    final shape = ref.watch(roboShapeProvider);
    final shell = ref.watch(roboShellColorProvider);
    _observeMood(mood);

    final quotes = mood.quotes;
    final text = !_showQuote || quotes.isEmpty
        ? (mood.state == RoboState.idle ? 'Hii!' : mood.label)
        : quotes[_quoteIndex % quotes.length];
    return RoboAvatar(
      shape: shape,
      state: mood.state,
      size: widget.size,
      color: shell,
      seed: widget.seed,
      calmError: mood.calmError,
      bubbleText: text,
      bubbleTexts: [mood.label, ...quotes],
    );
  }
}
