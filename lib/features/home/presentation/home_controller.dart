import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/notifications/notification_service.dart';
import '../../../core/seed/starter_data.dart';
import '../../robo/robo_events.dart';
import '../data/home_models.dart';

@immutable
class HomeDayState {
  final List<DateTime> weekDates;
  final DateTime selectedDate;
  final Map<String, List<StudyTask>> tasksByDate;
  final bool isLoaded;

  const HomeDayState({
    required this.weekDates,
    required this.selectedDate,
    required this.tasksByDate,
    this.isLoaded = false,
  });

  DateTime get today => DateTime.now();
  DateTime get _todayDay => DateTime(today.year, today.month, today.day);
  DateTime get _selDay =>
      DateTime(selectedDate.year, selectedDate.month, selectedDate.day);

  DateKind get selectedKind {
    if (_selDay.isAtSameMomentAs(_todayDay)) return DateKind.today;
    return _selDay.isBefore(_todayDay) ? DateKind.past : DateKind.future;
  }

  List<StudyTask> get selectedTasks {
    final list = tasksByDate[dateKey(_selDay)] ?? const <StudyTask>[];
    final sorted = List<StudyTask>.from(list)
      ..sort((a, b) => a.startMinutes.compareTo(b.startMinutes));
    return sorted;
  }

  List<StudyTask> get allTasks =>
      tasksByDate.values.expand((list) => list).toList(growable: false);

  String get dayTitle {
    switch (selectedKind) {
      case DateKind.today:
        return "Today's Tasks";
      case DateKind.past:
        final idx = _selDay.weekday - 1;
        return '${weekdayFull[idx]} Tasks';
      case DateKind.future:
        final idx = _selDay.weekday - 1;
        return '${weekdayFull[idx]} Plan';
    }
  }

  HomeDayState copyWith({
    DateTime? selectedDate,
    Map<String, List<StudyTask>>? tasksByDate,
    bool? isLoaded,
  }) {
    return HomeDayState(
      weekDates: weekDates,
      selectedDate: selectedDate ?? this.selectedDate,
      tasksByDate: tasksByDate ?? this.tasksByDate,
      isLoaded: isLoaded ?? this.isLoaded,
    );
  }
}

class HomeController extends StateNotifier<HomeDayState> {
  HomeController() : super(_seed()) {
    unawaited(_load());
  }

  static const _storageKey = 'studyup.tasks.v1';

  /// Set once starter tasks have been considered (seeded or skipped).
  /// Never reset: deleting the starters must not bring them back.
  static const _starterFlagKey = 'studyup.tasks.starterSeeded.v1';
  Future<void> _writeQueue = Future<void>.value();

  static HomeDayState _seed() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final monday = mondayOfWeek(today);
    final week = List.generate(7, (i) => monday.add(Duration(days: i)));

    return HomeDayState(
      weekDates: week,
      selectedDate: today,
      tasksByDate: const {},
    );
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (!mounted) return;
      final raw = prefs.getString(_storageKey);
      final seeded = prefs.getBool(_starterFlagKey) ?? false;
      if (raw == null) {
        // Genuinely new user (no stored task data at all): seed the two
        // starter examples once, then persist + flag so upgrades, logouts,
        // and relaunches never recreate or duplicate them. In-flight tasks
        // added before loading finished are kept, never overwritten.
        if (!seeded && state.tasksByDate.isEmpty) {
          final today = DateTime.now();
          final day = DateTime(today.year, today.month, today.day);
          final starters = StarterData.defaultTasks(day);
          final map = <String, List<StudyTask>>{dateKey(day): starters};
          state = state.copyWith(tasksByDate: map, isLoaded: true);
          await _persist();
          if (!mounted) return;
          await prefs.setBool(_starterFlagKey, true);
          unawaited(_rescheduleAll());
          return;
        }
        if (!seeded) await prefs.setBool(_starterFlagKey, true);
        if (!mounted) return;
        state = state.copyWith(isLoaded: true);
        return;
      }
      final decoded = jsonDecode(raw) as Map<String, Object?>;
      final map = <String, List<StudyTask>>{};
      decoded.forEach((key, value) {
        map[key] = [
          for (final entry in (value as List<Object?>))
            StudyTask.fromJson(Map<String, Object?>.from(entry! as Map)),
        ];
      });
      var hasPendingTasks = false;
      for (final entry in state.tasksByDate.entries) {
        final saved = map.putIfAbsent(entry.key, () => []);
        final savedIds = saved.map((task) => task.id).toSet();
        final pending = entry.value.where(
          (task) => !savedIds.contains(task.id),
        );
        if (pending.isNotEmpty) {
          saved.addAll(pending);
          hasPendingTasks = true;
        }
      }
      // Existing users keep their data untouched; just mark the starter
      // decision done so nothing is ever seeded on top of real tasks.
      if (!seeded) await prefs.setBool(_starterFlagKey, true);
      if (!mounted) return;
      state = state.copyWith(tasksByDate: map, isLoaded: true);
      if (hasPendingTasks) await _persist();
      unawaited(_rescheduleAll());
    } catch (error, stackTrace) {
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stackTrace,
          library: 'tasks',
          context: ErrorDescription('while loading persisted tasks'),
        ),
      );
      if (!mounted) return;
      state = state.copyWith(isLoaded: true);
    }
  }

  Future<void> _persist() async {
    // Snapshot synchronously: the writes below outlive the controller when
    // a test disposes it mid-flight, and must never touch `state` then.
    final encoded = jsonEncode(
      state.tasksByDate.map(
        (key, list) => MapEntry(key, [for (final task in list) task.toJson()]),
      ),
    );
    try {
      final prefs = await SharedPreferences.getInstance();
      final write = _writeQueue.catchError((Object _) {}).then((_) async {
        final saved = await prefs.setString(_storageKey, encoded);
        if (!saved) throw StateError('Could not persist tasks.');
      });
      _writeQueue = write;
      await write;
    } catch (error, stackTrace) {
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stackTrace,
          library: 'tasks',
          context: ErrorDescription('while saving tasks'),
        ),
      );
    }
  }

  /// Refreshes every stored upcoming reminder from saved data.
  /// Used after load and when the task-reminder switch is re-enabled.
  Future<void> rescheduleAllReminders() => _rescheduleAll();

  Future<void> _rescheduleAll() async {
    for (final task in state.allTasks) {
      await NotificationService.instance.scheduleTaskReminder(
        taskId: task.id,
        title: task.title,
        date: task.date,
        startMinutes: task.startMinutes,
        isDone: task.isDone,
      );
    }
  }

  Future<void> _syncReminder(StudyTask task) {
    return NotificationService.instance.scheduleTaskReminder(
      taskId: task.id,
      title: task.title,
      date: task.date,
      startMinutes: task.startMinutes,
      isDone: task.isDone,
    );
  }

  void selectDate(DateTime d) {
    state = state.copyWith(selectedDate: DateTime(d.year, d.month, d.day));
  }

  void toggleTask(String taskId) {
    final day = DateTime(
      state.selectedDate.year,
      state.selectedDate.month,
      state.selectedDate.day,
    );
    final key = dateKey(day);
    final list = state.tasksByDate[key];
    if (list == null) return;
    final next = list
        .map((t) => t.id == taskId ? t.copyWith(isDone: !t.isDone) : t)
        .toList(growable: false);
    _commit(day, next);
    for (final task in next) {
      if (task.id == taskId) {
        unawaited(_syncReminder(task));
        // Real task-completion event: Robo celebrates briefly.
        if (task.isDone) RoboEvents.instance.celebrate();
      }
    }
  }

  void addTask({
    required String title,
    required String description,
    required int startMinutes,
    required int endMinutes,
  }) {
    final day = DateTime(
      state.selectedDate.year,
      state.selectedDate.month,
      state.selectedDate.day,
    );
    final s = startMinutes.clamp(0, 1439);
    var e = endMinutes.clamp(0, 1440);
    if (e <= s) e = (s + 60).clamp(0, 1440);
    final list = List<StudyTask>.from(
      state.tasksByDate[dateKey(day)] ?? const [],
    );
    final task = StudyTask(
      id: 'u${DateTime.now().microsecondsSinceEpoch}',
      title: title.trim().isEmpty ? 'Untitled task' : title.trim(),
      description: description.trim().isEmpty
          ? 'No description'
          : description.trim(),
      startMinutes: s,
      endMinutes: e,
      date: day,
    );
    list.add(task);
    _commit(day, list);
    unawaited(_syncReminder(task));
  }

  void editTask({
    required String taskId,
    required String title,
    required String description,
    required int startMinutes,
    required int endMinutes,
  }) {
    final day = DateTime(
      state.selectedDate.year,
      state.selectedDate.month,
      state.selectedDate.day,
    );
    final key = dateKey(day);
    final list = state.tasksByDate[key];
    if (list == null) return;
    final s = startMinutes.clamp(0, 1439);
    var e = endMinutes.clamp(0, 1440);
    if (e <= s) e = (s + 60).clamp(0, 1440);
    final next = list
        .map(
          (t) => t.id == taskId
              ? t.copyWith(
                  title: title.trim().isEmpty ? t.title : title.trim(),
                  description: description.trim().isEmpty
                      ? t.description
                      : description.trim(),
                  startMinutes: s,
                  endMinutes: e,
                )
              : t,
        )
        .toList(growable: false);
    _commit(day, next);
    // Same deterministic notification id: rescheduling overwrites the old
    // reminder instead of creating a duplicate.
    for (final task in next) {
      if (task.id == taskId) unawaited(_syncReminder(task));
    }
  }

  void deleteTask(String taskId) {
    final day = DateTime(
      state.selectedDate.year,
      state.selectedDate.month,
      state.selectedDate.day,
    );
    final key = dateKey(day);
    final list = state.tasksByDate[key];
    if (list == null) return;
    final next = list.where((t) => t.id != taskId).toList(growable: false);
    final map = Map<String, List<StudyTask>>.from(state.tasksByDate);
    map[key] = next;
    state = state.copyWith(tasksByDate: map);
    unawaited(_persist());
    unawaited(NotificationService.instance.cancelTaskReminder(taskId));
  }

  void _commit(DateTime day, List<StudyTask> tasks) {
    final key = dateKey(day);
    final map = Map<String, List<StudyTask>>.from(state.tasksByDate);
    map[key] = tasks;
    state = state.copyWith(tasksByDate: map);
    unawaited(_persist());
  }
}

final homeControllerProvider =
    StateNotifierProvider<HomeController, HomeDayState>((ref) {
      return HomeController();
    });
