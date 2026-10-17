/// StudyUp integration point for the Robo mascot (see NOTICE.md for
/// attribution). The renderer itself lives in `robo_*.dart` (copied
/// verbatim from the supplied implementation); this barrel re-exports the
/// public pieces StudyUp screens use.
library;

export 'robo_avatar.dart' show RoboAvatar;
export 'robo_bubble.dart' show RoboBubble, roboStateLabel;
export 'robo_customize.dart'
    show RoboColorController, roboShellColorProvider, showRoboCustomizeSheet;
export 'robo_events.dart' show RoboEvents;
export 'robo_mood.dart'
    show
        RoboMood,
        resolveRoboMood,
        roboDaySeconds,
        roboMoodProvider,
        thinkingQuotes,
        searchingQuotes,
        listeningQuotes,
        speakingQuotes,
        phaseWorkingQuotes,
        phaseHappyQuotes,
        pausedQuotes,
        taskSleepingQuotes,
        taskWorkingQuotes,
        taskHappyQuotes;
export 'robo_palette.dart' show RoboPalette;
export 'robo_shape.dart' show RoboShapeController, roboShapeProvider;
export 'robo_shape_selector.dart' show RoboShapeSelector;
export 'robo_state.dart' show roboShapeName;
export 'robo_types.dart' show RoboShape, RoboState;
export 'study_robo.dart' show StudyRobo;
