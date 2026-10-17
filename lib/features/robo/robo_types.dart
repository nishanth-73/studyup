/// The three selectable Robo head outlines.
///
/// Every shape shares the same screen, side knobs, antenna, screws and
/// animation rig; only the silhouette (and the matching screen outline)
/// differs.
enum RoboShape {
  /// A rounded-square, TV-style head.
  square,

  /// A circular, porthole-style head.
  circle,

  /// A geometric, flat-topped hexagonal head.
  hexagon,
}

/// The nine things Robo can be doing. This list is the complete public set.
enum RoboState {
  /// Neutral face, natural blinks, small glances, gentle floating.
  idle,

  /// Heavy-lidded eyes looking up, pulsing dots, head tilt, amber antenna.
  thinking,

  /// Eyes glance side to side, a scan beam sweeps the screen.
  searching,

  /// Wide attentive eyes, an equaliser, small nods, green/teal antenna.
  listening,

  /// An animated mouth that opens and closes, subtle head bobbing.
  speaking,

  /// Focused eyes and a progress bar, energetic but controlled motion.
  working,

  /// Smiling `^ ^` eyes and a smile, bouncy hops.
  happy,

  /// `X X` eyes, red tint and antenna, a short head shake.
  error,

  /// Closed eyes, slow breathing, lowered pose, antenna light off.
  sleeping,
}
