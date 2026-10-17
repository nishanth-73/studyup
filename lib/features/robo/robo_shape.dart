import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'robo_types.dart';

/// The user's chosen Robo head shape, persisted with the existing
/// SharedPreferences settings storage. Only the three shapes the Robo
/// library implements are possible: square, circle, hexagon.
/// Fresh installs default to square; unknown stored values (including any
/// legacy avatar data) fall back to square rather than breaking.
class RoboShapeController extends StateNotifier<RoboShape> {
  RoboShapeController() : super(RoboShape.square) {
    unawaited(_load());
  }

  static const storageKey = 'studyup.roboShape.v1';

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (!mounted) return;
      state = decodeShape(prefs.getString(storageKey));
    } catch (error, stackTrace) {
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stackTrace,
          library: 'robo shape',
          context: ErrorDescription('while loading the saved Robo shape'),
        ),
      );
    }
  }

  Future<void> select(RoboShape shape) async {
    state = shape;
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = await prefs.setString(storageKey, encodeShape(shape));
      if (!saved) throw StateError('Could not persist the Robo shape.');
    } catch (error, stackTrace) {
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stackTrace,
          library: 'robo shape',
          context: ErrorDescription('while saving the Robo shape'),
        ),
      );
    }
  }
}

/// Maps stored text to a shape. Anything unrecognised (null, typos,
/// legacy avatar values) becomes the square default.
@visibleForTesting
RoboShape decodeShape(String? raw) {
  switch (raw) {
    case 'circle':
      return RoboShape.circle;
    case 'hexagon':
      return RoboShape.hexagon;
    case 'square':
    default:
      return RoboShape.square;
  }
}

/// Stable storage form: the enum identifier itself.
@visibleForTesting
String encodeShape(RoboShape shape) => shape.name;

final roboShapeProvider = StateNotifierProvider<RoboShapeController, RoboShape>(
  (ref) => RoboShapeController(),
);
