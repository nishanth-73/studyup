import 'dart:math' as math;

import 'package:flutter/painting.dart';

import 'robo_types.dart';

/// A smooth 0..1 pseudo-random signal built from a few incommensurate sines.
/// Deterministic, so animations are reproducible.
double roboNoise(double x) {
  return 0.5 +
      0.25 * math.sin(x * 1.7) +
      0.15 * math.sin(x * 3.1 + 1.3) +
      0.1 * math.sin(x * 5.3 + 4.1);
}

/// Per-state constants: antenna light colour, pulse pattern and the
/// canonical still-frame time.
class RoboStateStyle {
  RoboStateStyle._();

  /// The antenna light colour for [s].
  static Color bulbColor(RoboState s) {
    switch (s) {
      case RoboState.idle:
        return const Color(0xFFFFF4E0);
      case RoboState.thinking:
        return const Color(0xFFFFB840);
      case RoboState.searching:
        return const Color(0xFF5ADCFF);
      case RoboState.listening:
        return const Color(0xFF4DF0B4);
      case RoboState.speaking:
        return const Color(0xFFFFF4E0);
      case RoboState.working:
        return const Color(0xFF6EA0FF);
      case RoboState.happy:
        return const Color(0xFFFF82C8);
      case RoboState.error:
        return const Color(0xFFFF3C32);
      case RoboState.sleeping:
        return const Color(0xFFFFF4E0);
    }
  }

  /// Antenna light brightness (0 = off, 1 = full) at time [t] seconds.
  static double bulbPulse(RoboState s, double t) {
    switch (s) {
      case RoboState.idle:
        return 0.75 + 0.1 * math.sin(t * 1.4);
      case RoboState.thinking:
        return 0.45 + 0.55 * (0.5 + 0.5 * math.sin(t * 4.2));
      case RoboState.searching:
        final p = (t * 2.4) % 1.0;
        return 0.25 + 0.75 * math.exp(-p * 9.0);
      case RoboState.listening:
        return 0.8 + 0.2 * math.sin(t * 2.4);
      case RoboState.speaking:
        return 0.55 + 0.45 * roboNoise(t * 11.0);
      case RoboState.working:
        return 0.65 + 0.35 * math.sin(t * 5.0);
      case RoboState.happy:
        return 0.8 + 0.2 * math.sin(t * 8.0);
      case RoboState.error:
        return 0.15 + 0.85 * (0.5 + 0.5 * math.sin(t * 3.0 * 2 * math.pi));
      case RoboState.sleeping:
        return 0.0;
    }
  }

  /// A time (seconds) at which the state's face looks representative; used
  /// for still poses (animation disabled) so they show the best frame.
  static double stillTime(RoboState s) {
    switch (s) {
      case RoboState.idle:
        return 0.0;
      case RoboState.thinking:
        return 0.12;
      case RoboState.searching:
        return 1.71;
      case RoboState.listening:
        return 0.35;
      case RoboState.speaking:
        return 0.7;
      case RoboState.working:
        return 1.3;
      case RoboState.happy:
        return 0.0;
      case RoboState.error:
        return 1.2;
      case RoboState.sleeping:
        return 0.5;
    }
  }
}
