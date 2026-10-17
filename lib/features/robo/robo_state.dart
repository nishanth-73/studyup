import 'robo_types.dart';

// NOTE: the mascot's live behavior is resolved centrally by
// [resolveRoboMood] in robo_mood.dart (progress phases, paused reminder,
// task states, idle). The helpers below are shape-label utilities kept
// for the customisation UI.

/// Display name for the shape picker. The enum identifiers already match
/// the required Square / Circle / Hexagon naming.
String roboShapeName(RoboShape shape) {
  switch (shape) {
    case RoboShape.square:
      return 'Square';
    case RoboShape.circle:
      return 'Circle';
    case RoboShape.hexagon:
      return 'Hexagon';
  }
}
