import 'dart:async';

import 'package:flutter/foundation.dart';

/// App-lifetime event source for momentary Robo celebrations.
///
/// [celebrate] shows HAPPY for a short, controlled period, then clears
/// exactly once through a single one-shot timer (never a repeating timer,
/// at most one pending — re-celebrating replaces it). The UI observes
/// [happyUntil] and resolves back to the base state on expiry, so Robo is
/// never stuck celebrating and no widget owns a timer.
class RoboEvents {
  RoboEvents._();
  static final RoboEvents instance = RoboEvents._();

  /// How long one celebration lasts.
  static const celebrationDuration = Duration(seconds: 30);

  /// Expiry instant of the current celebration, or null when none.
  final ValueNotifier<DateTime?> happyUntil = ValueNotifier<DateTime?>(null);

  Timer? _clearTimer;

  /// Clock override for tests.
  @visibleForTesting
  DateTime Function() now = DateTime.now;

  void celebrate({Duration duration = celebrationDuration}) {
    happyUntil.value = now().add(duration);
    _clearTimer?.cancel();
    _clearTimer = Timer(duration, () {
      happyUntil.value = null;
    });
  }

  bool isCelebrating(DateTime at) {
    final until = happyUntil.value;
    return until != null && at.isBefore(until);
  }

  @visibleForTesting
  void reset() {
    _clearTimer?.cancel();
    _clearTimer = null;
    happyUntil.value = null;
  }
}
