import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../../features/notifications/data/app_notification.dart';
import 'study_timer_bridge.dart';

/// Local-day key shared by the goal notification bookkeeping.
String notifDateKey(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// Pure, unit-testable notification decisions (no plugin touches here).
class NotifRules {
  /// Deterministic, collision-safe id for a task reminder.
  /// Range kept positive and below 2^31.
  static int taskReminderId(String taskId) => taskId.hashCode & 0x3fffffff;

  /// Fire time = task start minus five minutes, or null when the reminder
  /// would already be stale (fire time at/past [now]).
  static DateTime? taskReminderFireTime({
    required DateTime date,
    required int startMinutes,
    required DateTime now,
  }) {
    final start = DateTime(
      date.year,
      date.month,
      date.day,
    ).add(Duration(minutes: startMinutes));
    final fire = start.subtract(const Duration(minutes: 5));
    if (!fire.isAfter(now)) return null;
    return fire;
  }

  static String taskReminderBody(String title) => '$title starts in 5 minutes.';

  /// Once-per-local-day goal gate.
  static bool shouldNotifyGoal({
    required int minutesToday,
    required int goalMinutes,
    required String notifiedDateKey,
    required String todayKey,
  }) {
    if (goalMinutes <= 0) return false;
    if (minutesToday < goalMinutes) return false;
    return notifiedDateKey != todayKey;
  }
}

/// Central local-notification service. Initialized once from [main].
/// All public methods are safe to call from controllers: they never throw
/// (failures are reported via [FlutterError] and swallowed so study logic
/// keeps working even when notifications are unavailable).
class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  static const taskChannelId = 'studyup_task_reminders';
  static const goalChannelId = 'studyup_goal';
  static const communityChannelId = 'studyup_community';

  /// Stable id shared by the Live Progress tray entry on every platform:
  /// updates replace it, nothing ever stacks a second one.
  static const liveNotificationId = 0x5e5510;

  static const goalNotificationId = 0x6091;

  static const prefTaskReminders = 'studyup.notif.taskReminders.v1';
  static const prefSessionStarted = 'studyup.notif.sessionStarted.v1';
  static const prefGoalReached = 'studyup.notif.goalReached.v1';
  static const prefLiveProgress = 'studyup.notif.liveProgress.v1';
  static const prefPermissionPrompted = 'studyup.notif.permissionPrompted.v1';
  static const prefGoalNotifiedDate = 'studyup.notif.goalNotifiedDate.v1';

  /// Persisted in-app notification-center rows.
  static const prefCenterItems = 'studyup.notif.centerItems.v1';

  /// Live unread count for the Home red dot. Loaded from storage at
  /// [init] and updated on every center mutation; the dot rebuilds from
  /// this notifier so nobody polls SharedPreferences.
  final ValueNotifier<int> unreadCount = ValueNotifier<int>(0);

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  bool _initialized = false;

  /// Becomes true when the native plugin is unreachable (widget tests,
  /// unsupported platforms). Plugin calls then silently no-op so study
  /// logic and tests keep working; preferences still apply on devices.
  bool _pluginUnavailable = false;

  bool _tzReady = false;

  /// Runs a plugin call, swallowing expected unavailability without
  /// polluting the error channel (test frameworks treat reported
  /// FlutterErrors as failures). Genuine runtime errors are still
  /// reported in production.
  Future<T?> _withPlugin<T>(
    Future<T> Function() call, {
    required String context,
  }) async {
    if (_pluginUnavailable) return null;
    try {
      return await call();
    } on MissingPluginException catch (_) {
      _pluginUnavailable = true;
      return null;
    } catch (error, stackTrace) {
      // The platform interface throws when it was never registered
      // (flutter_test / unsupported platforms). The concrete late-error
      // type is private in current Dart SDKs, so match by name and stay
      // silent: study logic must keep working without a plugin.
      final name = error.runtimeType.toString();
      if (name.contains('LateInitialization') ||
          error.toString().startsWith('LateInitializationError')) {
        _pluginUnavailable = true;
        return null;
      }
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stackTrace,
          library: 'notifications',
          context: ErrorDescription(context),
        ),
      );
      return null;
    }
  }

  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;
    _ensureTimeZones();
    // Status-bar small icon: the StudyUp mark vector
    // (res/drawable/ic_stat_studyup.xml). Android renders small icons
    // as an alpha mask, so only its white silhouette appears — never a
    // full-color image.
    const androidInit = AndroidInitializationSettings(
      '@drawable/ic_stat_studyup',
    );
    const darwinInit = DarwinInitializationSettings();
    final android = AndroidFlutterLocalNotificationsPlugin();
    await _withPlugin(
      () => _plugin.initialize(
        settings: const InitializationSettings(
          android: androidInit,
          iOS: darwinInit,
          macOS: darwinInit,
        ),
      ),
      context: 'while initializing notifications',
    );
    for (final channel in _channels) {
      await _withPlugin(
        () => android.createNotificationChannel(channel),
        context: 'while creating notification channels',
      );
    }
    await _reloadUnreadCount();
  }

  void _ensureTimeZones() {
    if (_tzReady) return;
    try {
      tzdata.initializeTimeZones();
      _tzReady = true;
    } catch (_) {
      // Time-zone data stays unavailable; scheduling degrades to a no-op.
    }
  }

  static List<AndroidNotificationChannel> get _channels => const [
    AndroidNotificationChannel(
      taskChannelId,
      'Task reminders',
      description: 'Reminders five minutes before scheduled tasks.',
      importance: Importance.high,
    ),
    AndroidNotificationChannel(
      goalChannelId,
      'Daily goal',
      description: 'Shown once per day when the study goal is reached.',
      importance: Importance.high,
    ),
    AndroidNotificationChannel(
      communityChannelId,
      'Community',
      description:
          'Friend requests, accepted invitations, and challenge updates.',
      importance: Importance.defaultImportance,
    ),
  ];

  // ---------- preferences ----------

  Future<bool> taskRemindersEnabled() async =>
      (await SharedPreferences.getInstance()).getBool(prefTaskReminders) ??
      true;

  Future<bool> sessionStartedEnabled() async =>
      (await SharedPreferences.getInstance()).getBool(prefSessionStarted) ??
      true;

  Future<bool> goalReachedEnabled() async =>
      (await SharedPreferences.getInstance()).getBool(prefGoalReached) ?? true;

  Future<void> setTaskReminders(bool value) async =>
      (await SharedPreferences.getInstance()).setBool(prefTaskReminders, value);

  Future<void> setSessionStarted(bool value) async =>
      (await SharedPreferences.getInstance()).setBool(
        prefSessionStarted,
        value,
      );

  Future<void> setGoalReached(bool value) async =>
      (await SharedPreferences.getInstance()).setBool(prefGoalReached, value);

  Future<bool> liveProgressEnabled() async =>
      (await SharedPreferences.getInstance()).getBool(prefLiveProgress) ?? true;

  Future<void> setLiveProgress(bool value) async {
    await (await SharedPreferences.getInstance()).setBool(
      prefLiveProgress,
      value,
    );
    if (!value) {
      // Switched off mid-session: stop the timer service and clear the
      // tray entry; study tracking itself is untouched.
      await StudyTimerBridge.cancel();
    }
  }

  Future<bool> permissionPrompted() async =>
      (await SharedPreferences.getInstance()).getBool(prefPermissionPrompted) ??
      false;

  Future<void> markPermissionPrompted() async =>
      (await SharedPreferences.getInstance()).setBool(
        prefPermissionPrompted,
        true,
      );

  // ---------- permission ----------

  /// Returns the platform-confirmed grant state, or null when unknown.
  Future<bool?> requestPermission() {
    if (defaultTargetPlatform == TargetPlatform.android) {
      return _withPlugin<bool?>(() async {
        final android = _plugin
            .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin
            >();
        if (android == null) return null;
        return android.requestNotificationsPermission();
      }, context: 'while requesting permission');
    }
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      return _withPlugin<bool?>(() async {
        final ios = _plugin
            .resolvePlatformSpecificImplementation<
              IOSFlutterLocalNotificationsPlugin
            >();
        if (ios == null) return null;
        return ios.requestPermissions(alert: true, badge: true, sound: true);
      }, context: 'while requesting permission');
    }
    if (defaultTargetPlatform == TargetPlatform.macOS) {
      return _withPlugin<bool?>(() async {
        final macos = _plugin
            .resolvePlatformSpecificImplementation<
              MacOSFlutterLocalNotificationsPlugin
            >();
        if (macos == null) return null;
        return macos.requestPermissions(alert: true, badge: true, sound: true);
      }, context: 'while requesting permission');
    }
    return Future.value(true);
  }

  Future<bool?> systemNotificationsEnabled() {
    if (defaultTargetPlatform == TargetPlatform.android) {
      return _withPlugin<bool?>(() async {
        final android = _plugin
            .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin
            >();
        if (android == null) return null;
        return android.areNotificationsEnabled();
      }, context: 'while checking notification permission');
    }
    return Future.value(true);
  }

  // ---------- task reminders ----------

  NotificationDetails _taskDetails() => const NotificationDetails(
    android: AndroidNotificationDetails(
      taskChannelId,
      'Task reminders',
      channelDescription: 'Reminders five minutes before scheduled tasks.',
      importance: Importance.high,
      priority: Priority.high,
      // Supplied artwork: active.png is bundled as a drawable
      // (res/drawable/notif_task.png) and shown as the large icon.
      // Small icon is the white notification.svg silhouette
      // (ic_stat_studyup), set explicitly per notification.
      icon: 'ic_stat_studyup',
      largeIcon: DrawableResourceAndroidBitmap('notif_task'),
    ),
    iOS: DarwinNotificationDetails(),
    macOS: DarwinNotificationDetails(),
  );

  /// Schedules (or refreshes — same deterministic id, so no duplicates)
  /// the five-minutes-before reminder for one task. No-op for done tasks,
  /// disabled preferences, or stale fire times.
  Future<void> scheduleTaskReminder({
    required String taskId,
    required String title,
    required DateTime date,
    required int startMinutes,
    required bool isDone,
  }) async {
    if (isDone) {
      await cancelTaskReminder(taskId);
      return;
    }
    if (!await taskRemindersEnabled()) return;
    final now = DateTime.now();
    final fire = NotifRules.taskReminderFireTime(
      date: date,
      startMinutes: startMinutes,
      now: now,
    );
    if (fire == null) {
      await cancelTaskReminder(taskId);
      return;
    }
    _ensureTimeZones();
    tz.TZDateTime scheduled;
    try {
      // Timezone-aware scheduling; local wall-clock time survives DST via tz.
      scheduled = tz.TZDateTime.from(fire, tz.local);
    } catch (_) {
      return;
    }
    await _withPlugin(
      () => _plugin.zonedSchedule(
        id: NotifRules.taskReminderId(taskId),
        scheduledDate: scheduled,
        notificationDetails: _taskDetails(),
        // Inexact on purpose: avoids the SCHEDULE_EXACT_ALARM / USE_EXACT_ALARM
        // special permissions while still firing near the reminder time.
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        title: 'Task coming up',
        body: NotifRules.taskReminderBody(title),
        payload: taskId,
      ),
      context: 'while scheduling a task reminder',
    );
    // Mirror into the in-app center (upsert: edits never duplicate rows
    // and never re-light an already-read row).
    await recordCenterTask(
      taskId: taskId,
      title: title,
      date: date,
      startMinutes: startMinutes,
      now: now,
    );
  }

  Future<void> cancelTaskReminder(String taskId) async {
    await _withPlugin(
      () => _plugin.cancel(id: NotifRules.taskReminderId(taskId)),
      context: 'while cancelling a task reminder',
    );
    // No OS reminder left behind: the upcoming row goes away too.
    await removeCenterTaskItem(taskId);
  }

  /// Cancels every pending reminder id we own. Immediate session/goal
  /// notifications use different ids and are untouched.
  Future<void> cancelAllTaskReminders(Iterable<String> taskIds) async {
    for (final id in taskIds) {
      await cancelTaskReminder(id);
    }
  }

  /// Cancels everything still scheduled with the OS. Task reminders are
  /// the only type this app ever schedules (session/goal use immediate
  /// show()), so this can only ever clear task reminders — it exists for
  /// the disable-switch path when the task list itself hasn't loaded yet.
  Future<void> cancelAllScheduled() {
    return _withPlugin(
      () => _plugin.cancelAllPendingNotifications(),
      context: 'while cancelling scheduled reminders',
    ).then((_) {});
  }

  // ---------- immediate notifications ----------

  NotificationDetails _goalDetails() => const NotificationDetails(
    android: AndroidNotificationDetails(
      goalChannelId,
      'Daily goal',
      channelDescription: 'Shown once per day when the study goal is reached.',
      importance: Importance.high,
      priority: Priority.high,
      // Supplied artwork: focus.png -> res/drawable/notif_goal.png.
      // Small icon is the white notification.svg silhouette.
      icon: 'ic_stat_studyup',
      largeIcon: DrawableResourceAndroidBitmap('notif_goal'),
    ),
    iOS: DarwinNotificationDetails(),
    macOS: DarwinNotificationDetails(),
  );

  static String formatStartTime(DateTime start) {
    final h24 = start.hour;
    final m = start.minute.toString().padLeft(2, '0');
    final period = h24 >= 12 ? 'PM' : 'AM';
    var h = h24 % 12;
    if (h == 0) h = 12;
    return '$h:$m $period';
  }

  // ---------- live study timer (foreground service on Android) ----------

  NotificationDetails _liveFallbackDetails({required bool ongoing}) =>
      NotificationDetails(
        android: AndroidNotificationDetails(
          taskChannelId,
          'Task reminders',
          channelDescription: 'Reminders five minutes before scheduled tasks.',
          importance: Importance.defaultImportance,
          priority: Priority.defaultPriority,
          icon: 'ic_stat_studyup',
          ongoing: ongoing,
          autoCancel: false,
          onlyAlertOnce: true,
        ),
        iOS: const DarwinNotificationDetails(),
        macOS: const DarwinNotificationDetails(),
      );

  /// Starts (or adopts) the persistent Live Progress notification for a
  /// freshly checked-in session. Android routes to the foreground service
  /// (exact 4-line RemoteViews card, 1s ticks, survives recents removal);
  /// other platforms get the closest plain ongoing equivalent. Same
  /// [liveNotificationId] everywhere. Gated on the Live progress switch;
  /// never throws (timer logic must keep working regardless).
  Future<void> startLiveTimer({
    required int bankedTodaySec,
    required DateTime anchorUtc,
    required int goalMinutes,
    required String dayKey,
  }) async {
    if (!await liveProgressEnabled()) return;
    if (defaultTargetPlatform == TargetPlatform.android) {
      await StudyTimerBridge.checkIn(
        bankedSec: bankedTodaySec,
        anchorUtcMs: anchorUtc.millisecondsSinceEpoch,
        goalMin: goalMinutes,
        dayKey: dayKey,
      );
      return;
    }
    await _withPlugin(
      () => _plugin.show(
        id: liveNotificationId,
        title: 'Live Progress',
        body: 'Studying now',
        notificationDetails: _liveFallbackDetails(ongoing: true),
      ),
      context: 'while starting live progress fallback',
    );
  }

  /// Pushes fresh anchor/goal parameters to the running live timer
  /// (resume, goal change, app-restart adopt). Never creates a second
  /// timer, worker, or notification id.
  Future<void> updateLiveTimer({
    required int bankedTodaySec,
    required DateTime anchorUtc,
    required int goalMinutes,
    required String dayKey,
  }) async {
    if (!await liveProgressEnabled()) return;
    if (defaultTargetPlatform == TargetPlatform.android) {
      await StudyTimerBridge.update(
        bankedSec: bankedTodaySec,
        anchorUtcMs: anchorUtc.millisecondsSinceEpoch,
        goalMin: goalMinutes,
        dayKey: dayKey,
      );
    }
  }

  /// Pauses everything: the foreground service stops its ticks (no
  /// resource use while checked out) and the same tray entry flips to a
  /// dismissible frozen-time status. Accumulated duration is preserved —
  /// check-in resumes it.
  Future<void> pauseLiveTimer({
    required int elapsedSec,
    required int goalMinutes,
    required String dayKey,
  }) async {
    if (!await liveProgressEnabled()) {
      // Feature off: stop any ticking and clear the entry instead of
      // maintaining a paused card against the user's choice.
      await StudyTimerBridge.cancel();
      return;
    }
    if (defaultTargetPlatform == TargetPlatform.android) {
      await StudyTimerBridge.checkOut(
        elapsedSec: elapsedSec,
        goalMin: goalMinutes,
        dayKey: dayKey,
      );
      return;
    }
    await _withPlugin(
      () => _plugin.show(
        id: liveNotificationId,
        title: 'Live Progress',
        body: 'Checked out',
        notificationDetails: _liveFallbackDetails(ongoing: false),
      ),
      context: 'while pausing live progress fallback',
    );
  }

  /// Removes the Live Progress tray entry without touching task reminders
  /// or the goal alert.
  Future<void> cancelLiveTimer() async {
    if (defaultTargetPlatform == TargetPlatform.android) {
      await StudyTimerBridge.cancel();
      return;
    }
    await _withPlugin(
      () => _plugin.cancel(id: liveNotificationId),
      context: 'while cancelling live progress',
    );
  }

  /// Shows the daily-goal notification at most once per local day.
  /// Returns true when a notification was shown.
  Future<bool> maybeNotifyGoalReached({
    required int minutesToday,
    required int goalMinutes,
    required DateTime now,
  }) async {
    if (!await goalReachedEnabled()) return false;
    final prefs = await SharedPreferences.getInstance();
    final todayKey = notifDateKey(now);
    final notified = prefs.getString(prefGoalNotifiedDate) ?? '';
    if (!NotifRules.shouldNotifyGoal(
      minutesToday: minutesToday,
      goalMinutes: goalMinutes,
      notifiedDateKey: notified,
      todayKey: todayKey,
    )) {
      return false;
    }
    await _withPlugin(
      () => _plugin.show(
        id: goalNotificationId,
        title: 'Daily goal reached!',
        body: "Amazing! You've completed your daily study goal.",
        notificationDetails: _goalDetails(),
      ),
      context: 'while showing goal-reached',
    );
    // Record the day only when the plugin is reachable: on a real device
    // the attempt counts (the OS owns delivery from there); in test
    // environments without a plugin the gate stays open harmlessly.
    if (_pluginUnavailable) return false;
    await prefs.setString(prefGoalNotifiedDate, todayKey);
    return true;
  }

  /// Records a community event (friend request accepted, challenge
  /// invitation, milestone) in the in-app center and — when system
  /// notifications are enabled — as a best-effort OS notification.
  /// Stable [id] upserts: re-deliveries never duplicate rows or re-alert.
  Future<void> recordCommunityEvent({
    required String id,
    required String title,
    required String body,
  }) async {
    final now = DateTime.now();
    final items = (await loadCenterItems()).toList();
    upsertCenterItem(
      items,
      CenterItem(
        id: 'community:$id',
        kind: CenterItemKind.community,
        title: title,
        body: body,
        at: now,
        dayKey: notifDateKey(now),
      ),
    );
    await _persistCenterItems(items);
    final enabled = await systemNotificationsEnabled() ?? true;
    if (!enabled) return;
    await _withPlugin(
      () => _plugin.show(
        id: id.hashCode & 0x3fffffff,
        title: title,
        body: body,
        notificationDetails: const NotificationDetails(
          android: AndroidNotificationDetails(
            communityChannelId,
            'Community',
            channelDescription:
                'Friend requests, accepted invitations, and challenge updates.',
            importance: Importance.defaultImportance,
            priority: Priority.defaultPriority,
            icon: 'ic_stat_studyup',
            onlyAlertOnce: true,
          ),
          iOS: DarwinNotificationDetails(),
          macOS: DarwinNotificationDetails(),
        ),
      ),
      context: 'while showing community event',
    );
  }

  // ---------- in-app notification center (SharedPreferences rows) ----------

  Future<List<CenterItem>> loadCenterItems() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(prefCenterItems);
      if (raw == null || raw.isEmpty) return const [];
      final decoded = jsonDecode(raw) as List<Object?>;
      final items = [
        for (final entry in decoded)
          CenterItem.fromJson(Map<String, Object?>.from(entry! as Map)),
      ];
      final todayKey = notifDateKey(DateTime.now());
      final before = items.length;
      prunePastTaskItems(items, todayKey);
      if (items.length != before) {
        await _persistCenterItems(items);
      }
      return List.unmodifiable(items);
    } catch (error, stackTrace) {
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stackTrace,
          library: 'notifications',
          context: ErrorDescription('while loading notification center'),
        ),
      );
      return const [];
    }
  }

  Future<void> _persistCenterItems(List<CenterItem> items) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      prefCenterItems,
      jsonEncode(items.map((i) => i.toJson()).toList()),
    );
    await _reloadUnreadCount(items);
  }

  Future<void> _reloadUnreadCount([List<CenterItem>? items]) async {
    final list = items ?? await loadCenterItems();
    unreadCount.value = list.where((i) => !i.read).length;
  }

  /// Recomputes the red-dot count from storage. Home calls this on open
  /// (and tests call it directly); safe to call repeatedly, never throws.
  Future<void> reloadUnreadCount() async {
    await _reloadUnreadCount();
  }

  /// Upserts the upcoming-reminder row for one scheduled task. Edits keep
  /// the same stable id (no duplicates) and preserve an already-read row;
  /// only a genuinely new row lights the red dot.
  Future<void> recordCenterTask({
    required String taskId,
    required String title,
    required DateTime date,
    required int startMinutes,
    required DateTime now,
  }) async {
    final day = DateTime(date.year, date.month, date.day);
    final items = (await loadCenterItems()).toList();
    final isNew = upsertCenterItem(
      items,
      CenterItem(
        id: 'task:$taskId',
        kind: CenterItemKind.taskReminder,
        title: title,
        body: '${_centerDayLabel(day, now)} · ${centerTimeLabel(startMinutes)}',
        at: now,
        dayKey: notifDateKey(day),
        taskDate: day,
        taskStartMinutes: startMinutes,
      ),
    );
    await _persistCenterItems(items);
    if (!isNew) return;
  }

  String _centerDayLabel(DateTime day, DateTime now) {
    final today = DateTime(now.year, now.month, now.day);
    final diff = day.difference(today).inDays;
    if (diff <= 0) return 'Today';
    if (diff == 1) return 'Tomorrow';
    return '${day.month}/${day.day}';
  }

  /// Drops one upcoming-reminder row (task done, deleted, or stale).
  Future<void> removeCenterTaskItem(String taskId) async {
    final items = (await loadCenterItems()).toList();
    final before = items.length;
    items.removeWhere((i) => i.id == 'task:$taskId');
    if (items.length != before) await _persistCenterItems(items);
  }

  /// Drops every upcoming-reminder row (reminders switch turned off).
  Future<void> clearCenterTaskItems() async {
    final items = (await loadCenterItems()).toList();
    final before = items.length;
    items.removeWhere((i) => i.kind == CenterItemKind.taskReminder);
    if (items.length != before) await _persistCenterItems(items);
  }

  /// Records the once-per-day goal-reached event. The existing gate in
  /// [maybeNotifyGoalReached] guarantees at most one row per local day.
  Future<void> recordGoalReached({
    required int minutesToday,
    required int goalMinutes,
    required DateTime now,
  }) async {
    final day = DateTime(now.year, now.month, now.day);
    final items = (await loadCenterItems()).toList();
    upsertCenterItem(
      items,
      CenterItem(
        id: 'goal:${notifDateKey(day)}',
        kind: CenterItemKind.goalReached,
        title: 'Daily goal reached',
        body: '$minutesToday of $goalMinutes min studied today.',
        at: now,
        dayKey: notifDateKey(day),
      ),
    );
    await _persistCenterItems(items);
  }

  /// Opening-the-screen policy: every visible row becomes read, which
  /// clears the red dot. Persisted, so restarts stay read.
  Future<void> markCenterAllRead() async {
    final items = (await loadCenterItems())
        .map((i) => i.read ? i : i.copyWith(read: true))
        .toList();
    await _persistCenterItems(items);
  }
}
