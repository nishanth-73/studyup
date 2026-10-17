import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../home/data/home_models.dart';
import '../home/presentation/home_controller.dart';
import '../progress/presentation/study_progress_controller.dart';
import 'robo_types.dart';

/// One mood of the shared mascot: the resolved [RoboState], the short
/// label shown first, the contextual quotes shown after ~3 seconds, and
/// whether the error state should render as a calm paused rest.
@immutable
class RoboMood {
  final RoboState state;
  final String label;
  final List<String> quotes;
  final bool calmError;

  const RoboMood({
    required this.state,
    required this.label,
    required this.quotes,
    this.calmError = false,
  });

  /// Stable identity for change detection (quote timers restart only when
  /// the mood genuinely changes, never on timer-tick rebuilds).
  String get key =>
      '${state.name}|$label|${calmError ? 1 : 0}|${quotes.join('\u0000')}';
}

/// Study-phase quotes, exactly as specified (first entry is primary).
const List<String> thinkingQuotes = [
  "Let's begin!",
  'One step at a time.',
  'Ready to focus?',
];

const List<String> searchingQuotes = [
  'Finding my flow!',
  "Let's explore!",
  'Curiosity mode!',
];

const List<String> listeningQuotes = [
  "I'm all ears!",
  'Taking it in!',
  'Learning mode!',
];

const List<String> speakingQuotes = [
  "Let's explain it!",
  'Ideas in motion!',
  'Making connections!',
];

const List<String> phaseWorkingQuotes = [
  'Deep focus!',
  'Keep it going!',
  "We're on a roll!",
];

const List<String> phaseHappyQuotes = [
  'Almost there!',
  'Amazing progress!',
  'Goal in sight!',
];

const List<String> pausedQuotes = [
  'Ready to start again?',
  'Take a breath, then return!',
  'Your next session awaits!',
  "Let's get back to it!",
];

const List<String> taskSleepingQuotes = [
  'A task is waiting!',
  "Let's get started!",
  'Ready when you are!',
];

const List<String> taskWorkingQuotes = [
  'Busy day!',
  'One down, keep going!',
  "Let's finish the rest!",
  'Making progress!',
];

const List<String> taskHappyQuotes = [
  'All tasks done!',
  'You did it!',
  'Time to celebrate!',
];

/// Progress-phase boundaries as fractions of the configured daily goal.
/// Derived from the goal at call time — never a hardcoded minute count.
/// The central, deterministic mascot resolver shared by Home and Profile,
/// so both screens always agree for the same app situation. Pure and
/// unit-tested.
///
/// Precedence (first match wins):
/// 1. Actively running session -> one of the six study phases from the
///    actual daily-goal progress ratio (uncapped; >=95% is HAPPY).
/// 2. Paused session after Check Out -> ERROR (rendered calm) with a
///    gentle restart quote. Uses the persisted active/paused distinction,
///    never a zero timer.
/// 3. Today's scheduled tasks (selected date) -> SLEEPING (none done),
///    WORKING (some done), or HAPPY (all done, non-empty list).
/// 4. Otherwise -> IDLE with "Hii!" and the greeting wave.
///
/// An empty task list never counts as "all completed".
RoboMood resolveRoboMood({
  required bool sessionRunning,
  required bool sessionPaused,
  required double progressRatio,
  required int tasksTotal,
  required int tasksDone,
}) {
  if (sessionRunning) {
    final p = progressRatio;
    if (p < 0.20) {
      return const RoboMood(
        state: RoboState.thinking,
        label: 'Thinking...',
        quotes: thinkingQuotes,
      );
    }
    if (p < 0.40) {
      return const RoboMood(
        state: RoboState.searching,
        label: 'Searching...',
        quotes: searchingQuotes,
      );
    }
    if (p < 0.60) {
      return const RoboMood(
        state: RoboState.listening,
        label: 'Listening...',
        quotes: listeningQuotes,
      );
    }
    if (p < 0.80) {
      return const RoboMood(
        state: RoboState.speaking,
        label: 'Speaking...',
        quotes: speakingQuotes,
      );
    }
    if (p < 0.95) {
      return const RoboMood(
        state: RoboState.working,
        label: 'Working...',
        quotes: phaseWorkingQuotes,
      );
    }
    return const RoboMood(
      state: RoboState.happy,
      label: 'Happy!',
      quotes: phaseHappyQuotes,
    );
  }
  if (sessionPaused) {
    return const RoboMood(
      state: RoboState.error,
      label: 'Paused',
      quotes: pausedQuotes,
      calmError: true,
    );
  }
  if (tasksTotal > 0) {
    if (tasksDone >= tasksTotal) {
      return const RoboMood(
        state: RoboState.happy,
        label: 'Happy!',
        quotes: taskHappyQuotes,
      );
    }
    if (tasksDone > 0) {
      return const RoboMood(
        state: RoboState.working,
        label: 'Working...',
        quotes: taskWorkingQuotes,
      );
    }
    return const RoboMood(
      state: RoboState.sleeping,
      label: 'Sleeping...',
      quotes: taskSleepingQuotes,
    );
  }
  return const RoboMood(state: RoboState.idle, label: 'Hii!', quotes: ['Hii!']);
}

/// Seconds-accurate study total for one calendar date, shared with the
/// Home card math so the mascot phases and the card never disagree.
int roboDaySeconds(StudyProgressState progress, DateTime day, DateTime now) {
  final start = DateTime(day.year, day.month, day.day);
  final end = start.add(const Duration(days: 1));
  var seconds = 0;
  for (final session in progress.sessions) {
    seconds += session.secondsInRange(start, end, now);
  }
  return seconds;
}

/// The live mascot mood for the current app situation. Rebuilds on every
/// session tick, task change, goal change, and date selection — but the
/// resolved content only changes when the underlying situation does, so
/// animations and quote timers never restart spuriously.
final roboMoodProvider = Provider<RoboMood>((ref) {
  final progress = ref.watch(studyProgressProvider);
  final home = ref.watch(homeControllerProvider);
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final sel = home.selectedDate;
  final selDay = DateTime(sel.year, sel.month, sel.day);

  final active = progress.activeSession;
  final running = active?.isRunning ?? false;
  // A paused session counts only while its lifecycle is live (an ended
  // session is not active, so it correctly falls through to tasks).
  final paused = (active?.isPaused ?? false) && progress.isLoaded;

  double ratio = 0.0;
  final goalSeconds = progress.dailyStudyGoalMinutes * 60;
  if (goalSeconds > 0) {
    ratio = roboDaySeconds(progress, today, now) / goalSeconds;
  }

  final dayTasks = home.tasksByDate[dateKey(selDay)] ?? const <StudyTask>[];
  var done = 0;
  for (final task in dayTasks) {
    if (task.isDone) done++;
  }

  return resolveRoboMood(
    sessionRunning: running,
    sessionPaused: paused,
    progressRatio: ratio,
    tasksTotal: dayTasks.length,
    tasksDone: done,
  );
});
