import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

/// The colours a Robo is built from.
///
/// The default follows the reference: a dark glossy body, a bright face
/// panel with a teal inset edge, and dark "ink" eyes.
@immutable
class RoboPalette {
  const RoboPalette({
    required this.shell,
    required this.trim,
    required this.ink,
    required this.screen,
    required this.accent,
    this.outline = const Color(0xFF08090C),
    this.error = const Color(0xFFE5483F),
  });

  /// Builds a palette from a body colour, deriving [trim] (limbs).
  factory RoboPalette.fromShell(
    Color shell, {
    Color? trim,
    Color? ink,
    Color? screen,
    Color? accent,
  }) {
    return RoboPalette(
      shell: shell,
      trim: trim ?? Color.lerp(shell, const Color(0xFF000000), 0.22)!,
      ink: ink ?? defaultInk,
      screen: screen ?? defaultScreen,
      accent: accent ?? defaultAccent,
    );
  }

  /// Graphite body colour.
  static const Color defaultShell = Color(0xFF2B2E39);

  /// Eye / mouth colour.
  static const Color defaultInk = Color(0xFF15161B);

  /// Face panel colour.
  static const Color defaultScreen = Color(0xFFF5F8FA);

  /// Teal inset edge of the face panel, equaliser bars, scan beam.
  static const Color defaultAccent = Color(0xFF35D6C3);

  /// The default palette.
  static final RoboPalette standard = RoboPalette.fromShell(defaultShell);

  /// Head and torso colour.
  final Color shell;

  /// Arms, hands, legs, feet and antenna stem.
  final Color trim;

  /// Colour of the face drawn on the panel (eyes, mouth, effects).
  final Color ink;

  /// Colour of the face panel.
  final Color screen;

  /// Accent: panel edge, equaliser, scan beam.
  final Color accent;

  /// Colour of the cartoon outline around every part.
  final Color outline;

  /// Colour used by the error face.
  final Color error;

  @override
  bool operator ==(Object other) =>
      other is RoboPalette &&
      other.shell == shell &&
      other.trim == trim &&
      other.ink == ink &&
      other.screen == screen &&
      other.accent == accent &&
      other.outline == outline &&
      other.error == error;

  @override
  int get hashCode =>
      Object.hash(shell, trim, ink, screen, accent, outline, error);
}
