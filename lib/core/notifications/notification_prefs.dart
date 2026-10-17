import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'notification_service.dart';

/// App-level (per-device, not per-account) notification switches.
/// Device permission itself stays platform-owned; these gates only decide
/// whether StudyUp attempts each notification type.
class NotificationPrefsState {
  final bool taskReminders;
  final bool sessionStarted;
  final bool liveProgress;
  final bool goalReached;
  final bool loaded;

  const NotificationPrefsState({
    this.taskReminders = true,
    this.sessionStarted = true,
    this.liveProgress = true,
    this.goalReached = true,
    this.loaded = false,
  });

  NotificationPrefsState copyWith({
    bool? taskReminders,
    bool? sessionStarted,
    bool? liveProgress,
    bool? goalReached,
    bool? loaded,
  }) => NotificationPrefsState(
    taskReminders: taskReminders ?? this.taskReminders,
    sessionStarted: sessionStarted ?? this.sessionStarted,
    liveProgress: liveProgress ?? this.liveProgress,
    goalReached: goalReached ?? this.goalReached,
    loaded: loaded ?? this.loaded,
  );
}

class NotificationPrefsController
    extends StateNotifier<NotificationPrefsState> {
  NotificationPrefsController() : super(const NotificationPrefsState()) {
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    state = NotificationPrefsState(
      taskReminders:
          prefs.getBool(NotificationService.prefTaskReminders) ?? true,
      sessionStarted:
          prefs.getBool(NotificationService.prefSessionStarted) ?? true,
      liveProgress: prefs.getBool(NotificationService.prefLiveProgress) ?? true,
      goalReached: prefs.getBool(NotificationService.prefGoalReached) ?? true,
      loaded: true,
    );
  }

  Future<void> setTaskReminders(bool value) async {
    state = state.copyWith(taskReminders: value);
    await NotificationService.instance.setTaskReminders(value);
  }

  Future<void> setSessionStarted(bool value) async {
    state = state.copyWith(sessionStarted: value);
    await NotificationService.instance.setSessionStarted(value);
  }

  Future<void> setLiveProgress(bool value) async {
    state = state.copyWith(liveProgress: value);
    await NotificationService.instance.setLiveProgress(value);
  }

  Future<void> setGoalReached(bool value) async {
    state = state.copyWith(goalReached: value);
    await NotificationService.instance.setGoalReached(value);
  }
}

final notificationPrefsProvider =
    StateNotifierProvider<NotificationPrefsController, NotificationPrefsState>(
      (ref) => NotificationPrefsController(),
    );

/// Current OS-level permission state (null = unknown / not applicable).
final systemNotificationStatusProvider = FutureProvider<bool?>((_) {
  return NotificationService.instance.systemNotificationsEnabled();
});
