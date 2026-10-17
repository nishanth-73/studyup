import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'dart:async';

import '../../../core/notifications/notification_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/ui_kit.dart';
import '../../../core/widgets/app_shell.dart';
import '../../../core/widgets/date_picker_sheet.dart';
import '../data/home_models.dart';
import '../../avatar/data/user_profile.dart';
import '../../avatar/presentation/avatar_widgets.dart';
import '../../avatar/presentation/user_profile_controller.dart';
import '../../progress/presentation/study_progress_controller.dart';
import '../../robo/study_robo.dart';
import 'home_controller.dart';
import 'widgets/home_sliding_cards.dart';

/// Time-of-day greeting aligned with the four fixed study periods
/// (Night 0–6, Morning 6–12, Afternoon 12–18, Evening 18–24).
String homeGreeting(DateTime now, String? displayName) {
  final hour = now.hour;
  final part = hour >= 6 && hour < 12
      ? 'Good morning'
      : hour >= 12 && hour < 18
      ? 'Good afternoon'
      : hour >= 18
      ? 'Good evening'
      : 'Good night';
  if (displayName == null || displayName.isEmpty) return '$part 👋';
  return '$part, $displayName 👋';
}

/// "Wed, 14 Oct 2026" style label for any locally-selected calendar date.
/// Handles month/year boundaries and leap days via DateTime arithmetic.
String selectedDateLabel(DateTime date) {
  const shortMonths = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  final day = DateTime(date.year, date.month, date.day);
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final diff = day.difference(today).inDays;
  final base =
      '${weekdayShort[day.weekday - 1]}, ${day.day} ${shortMonths[day.month - 1]} ${day.year}';
  if (diff == 0) return '$base · Today';
  if (diff == 1) return '$base · Tomorrow';
  if (diff == -1) return '$base · Yesterday';
  return base;
}

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  bool _permissionCheckQueued = false;

  @override
  void initState() {
    super.initState();
    // First entry into the app (post-onboarding/auth): explain the three
    // notification types, then ask for system permission exactly once.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _maybeAskNotificationPermission();
    });
    // Refresh the bell's red-dot count from storage on every open.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        unawaited(NotificationService.instance.reloadUnreadCount());
      }
    });
  }

  Future<void> _maybeAskNotificationPermission() async {
    if (_permissionCheckQueued || !mounted) return;
    _permissionCheckQueued = true;
    try {
      final service = NotificationService.instance;
      if (await service.permissionPrompted()) return;
      // "After entering the app" = past onboarding/auth with demo access.
      // Widget-test pumps (no signed-in profile) never see the dialog.
      final signedIn =
          ref.read(userProfileProvider).valueOrNull?.demoSignedIn ?? false;
      if (!signedIn) return;
      if (!mounted) return;
      final enable = await showDialog<bool>(
        context: context,
        barrierDismissible: true,
        builder: (ctx) => AlertDialog(
          backgroundColor: AppColors.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: Text('Stay on track?', style: AppTextStyles.section18),
          content: Text(
            'StudyUp can notify you:\n'
            '• 5 minutes before a scheduled task\n'
            '• When a focus session starts\n'
            '• When you reach your daily study goal\n\n'
            'You can change each of these anytime in Profile → Notifications.',
            style: AppTextStyles.secondary14,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(
                'Not now',
                style: AppTextStyles.body14Bold.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(
                'Enable',
                style: AppTextStyles.body14Bold.copyWith(color: AppColors.cta),
              ),
            ),
          ],
        ),
      );
      await service.markPermissionPrompted();
      if (enable == true && mounted) {
        final granted = await service.requestPermission();
        if ((granted == false || granted == null) && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Notifications are off. You can enable them anytime in '
                'Profile → Notifications.',
              ),
            ),
          );
        }
      }
    } catch (_) {
      // Permission flow must never break entering the app.
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(homeControllerProvider);
    final profile = ref.watch(userProfileProvider).valueOrNull;

    return AppShell(
      currentIndex: 0,
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Top-left avatar: the selected PNG portrait, opens Profile.
                Semantics(
                  button: true,
                  label: 'Open Profile',
                  child: Material(
                    color: Colors.transparent,
                    shape: const CircleBorder(),
                    child: InkWell(
                      customBorder: const CircleBorder(),
                      splashColor: Colors.white24,
                      onTap: () {
                        SystemSound.play(SystemSoundType.click);
                        HapticFeedback.selectionClick();
                        context.push('/profile');
                      },
                      child: UserAvatar(
                        avatarId:
                            profile != null && isValidAvatarId(profile.avatarId)
                            ? profile.avatarId
                            : defaultAvatarId,
                        size: 52,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    (profile?.displayName.isEmpty ?? true)
                        ? 'StudyUp user'
                        : profile!.displayName,
                    textAlign: TextAlign.center,
                    style: AppTextStyles.title26.copyWith(fontSize: 26),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                // Top-right notification center entry with the unread dot.
                Semantics(
                  button: true,
                  label: 'Open notifications',
                  child: Material(
                    color: AppColors.surface,
                    shape: const CircleBorder(),
                    child: InkWell(
                      customBorder: const CircleBorder(),
                      splashColor: AppColors.primary.withValues(alpha: 0.3),
                      onTap: () {
                        SystemSound.play(SystemSoundType.click);
                        HapticFeedback.selectionClick();
                        context.push('/notifications');
                      },
                      child: Padding(
                        padding: const EdgeInsets.all(10),
                        child: Stack(
                          clipBehavior: Clip.none,
                          children: [
                            const Icon(
                              Icons.notifications_outlined,
                              size: 22,
                              color: AppColors.textPrimary,
                            ),
                            ValueListenableBuilder<int>(
                              valueListenable:
                                  NotificationService.instance.unreadCount,
                              builder: (_, count, _) {
                                if (count <= 0) {
                                  return const SizedBox.shrink();
                                }
                                return Positioned(
                                  right: -1,
                                  top: -1,
                                  child: Container(
                                    width: 9,
                                    height: 9,
                                    decoration: BoxDecoration(
                                      color: Colors.red,
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                        color: AppColors.surface,
                                        width: 1.5,
                                      ),
                                    ),
                                  ),
                                );
                              },
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            _DateStrip(
              weekDates: state.weekDates,
              selected: state.selectedDate,
              onTap: (date) => selectTaskDate(context, ref, date),
            ),
            const SizedBox(height: 14),
            // Live sliding cards pinned left; Robo keeps its own fixed box
            // on the right so the two never overlap.
            // (The Home date strip above has no calendar icon; its
            // functionality is unchanged.)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Expanded(child: _HomeSlidingCards()),
                const SizedBox(width: 12),
                const _HomeRobo(),
              ],
            ),
            const SizedBox(height: 16),
            // Tasks header: title + calendar picker + Add Task.
            Row(
              children: [
                Expanded(
                  child: Text(
                    state.dayTitle,
                    style: AppTextStyles.section18,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                Material(
                  color: AppColors.surface,
                  shape: const CircleBorder(),
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    splashColor: AppColors.primary.withValues(alpha: 0.3),
                    onTap: () {
                      SystemSound.play(SystemSoundType.click);
                      HapticFeedback.selectionClick();
                      pickTaskDate(context, ref, state.selectedDate);
                    },
                    child: Tooltip(
                      message: 'Choose a date',
                      child: const Padding(
                        padding: EdgeInsets.all(10),
                        child: Icon(
                          Icons.calendar_month_outlined,
                          size: 20,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Material(
                  color: AppColors.cta,
                  borderRadius: BorderRadius.circular(100),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(100),
                    splashColor: Colors.black26,
                    onTap: () {
                      SystemSound.play(SystemSoundType.click);
                      HapticFeedback.selectionClick();
                      TaskEditorSheet.showAdd(context, ref);
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 10,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.add,
                            size: 16,
                            color: AppColors.onCta,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            'Add Task',
                            style: AppTextStyles.caption12Bold.copyWith(
                              color: AppColors.onCta,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _TimedTaskList(state: state),
            // Scroll clearance above the floating nav (AppShell math).
            SizedBox(height: AppShell.scrollClearance(context)),
          ],
        ),
      ),
    );
  }
}

/// Live sliding cards filling the row next to Robo's box.
class _HomeSlidingCards extends ConsumerWidget {
  const _HomeSlidingCards();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedDate = ref.watch(
      homeControllerProvider.select((s) => s.selectedDate),
    );
    return HomeSlidingCards(selectedDate: selectedDate);
  }
}

/// Home Robo in its own fixed box on the right of the sliding cards.
/// The box (and every surrounding widget) keeps its exact size and
/// position; only Robo's painting is enlarged with a bounded
/// [Transform.scale] so it reads slightly larger without moving anything.
/// The 20px screen padding absorbs the right overflow; nothing in the
/// layout shifts apart.
class _HomeRobo extends StatelessWidget {
  /// Fixed box height matching the sliding-card total height.
  static const double cardHeight = 176;

  /// Visual scale applied to Robo only (layout size is unchanged).
  static const double roboScale = 1.5;

  const _HomeRobo();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 112,
      height: cardHeight,
      child: Center(
        child: Transform.scale(
          scale: roboScale,
          alignment: Alignment.center,
          child: const StudyRobo(size: 100, seed: 0.15),
        ),
      ),
    );
  }
}

/// Whether picking [date] should immediately offer the Add Task sheet:
/// only future dates (planning ahead). Pure and unit-tested.
bool shouldAutoOpenAddSheet(DateTime date, DateTime now) {
  final day = DateTime(date.year, date.month, date.day);
  final today = DateTime(now.year, now.month, now.day);
  return day.isAfter(today);
}

/// Selects a task date from a tap: always navigates, and immediately
/// opens the Add Task sheet when the date is in the future.
void selectTaskDate(BuildContext context, WidgetRef ref, DateTime date) {
  ref.read(homeControllerProvider.notifier).selectDate(date);
  if (shouldAutoOpenAddSheet(date, DateTime.now())) {
    TaskEditorSheet.showAdd(context, ref);
  }
}

/// Full calendar date picker for the Tasks section: any past date back to
/// the year 2000, today, or any future date through 2100. Uses the shared
/// bottom-sheet calendar. Picking a future date opens the Add Task sheet
/// immediately.
Future<void> pickTaskDate(
  BuildContext context,
  WidgetRef ref,
  DateTime selectedDate,
) async {
  final initial = DateTime(
    selectedDate.year,
    selectedDate.month,
    selectedDate.day,
  );
  final picked = await showCalendarPickerSheet(
    context,
    initialDate: initial,
    firstDate: DateTime(2000),
    lastDate: DateTime(2100, 12, 31),
    title: 'Choose a date',
  );
  if (picked == null || !context.mounted) return;
  SystemSound.play(SystemSoundType.click);
  HapticFeedback.selectionClick();
  selectTaskDate(context, ref, picked);
}

class _DateStrip extends ConsumerWidget {
  final List<DateTime> weekDates;
  final DateTime selected;
  final ValueChanged<DateTime> onTap;
  const _DateStrip({
    required this.weekDates,
    required this.selected,
    required this.onTap,
  });

  bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final progress = ref.watch(studyProgressProvider);
    return Row(
      children: weekDates.map((d) {
        final isSel = _sameDay(d, selected);
        final isToday = _sameDay(d, today);
        final bg = isSel
            ? AppColors.cta
            : isToday
            ? AppColors.primary
            : AppColors.surface;
        final fg = (isSel || isToday) ? Colors.white : AppColors.textPrimary;
        final sub = isSel
            ? AppColors.onCta
            : isToday
            ? Colors.white70
            : AppColors.textSecondary;
        return Expanded(
          child: Container(
            margin: const EdgeInsets.only(right: 6),
            child: Material(
              color: bg,
              borderRadius: BorderRadius.circular(18),
              child: InkWell(
                borderRadius: BorderRadius.circular(18),
                splashColor: Colors.white24,
                onTap: () {
                  SystemSound.play(SystemSoundType.click);
                  HapticFeedback.selectionClick();
                  onTap(d);
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        weekdayShort[d.weekday - 1],
                        style: AppTextStyles.label10.copyWith(
                          color: isSel ? AppColors.onCta : sub,
                        ),
                        maxLines: 1,
                      ),
                      const SizedBox(height: 2),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          '${d.day}',
                          style: AppTextStyles.body16Bold.copyWith(
                            color: isSel ? AppColors.onCta : fg,
                          ),
                        ),
                      ),
                      if (progress.minutesForDate(d) > 0) ...[
                        const SizedBox(height: 3),
                        Container(
                          width: 5,
                          height: 5,
                          decoration: BoxDecoration(
                            color: isSel ? AppColors.onCta : AppColors.green,
                            shape: BoxShape.circle,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}

String _formatStudyDuration(int minutes) {
  final hours = minutes ~/ 60;
  final remainder = minutes % 60;
  return hours == 0 ? '${remainder}m' : '${hours}h ${remainder}m';
}

/// Task tile:
/// start | checkbox title + desc   duration ...
/// end   |
class _TimedTaskList extends ConsumerWidget {
  final HomeDayState state;
  const _TimedTaskList({required this.state});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tasks = state.selectedTasks;
    if (tasks.isEmpty) {
      final msg = state.selectedKind == DateKind.past
          ? 'No tasks done for that day'
          : state.selectedKind == DateKind.future
          ? 'Nothing scheduled yet — tap + Add Task.'
          : 'No tasks for today — tap + Add Task.';
      return Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Center(
          child: Text(
            msg,
            style: AppTextStyles.secondary14,
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    final ctrl = ref.read(homeControllerProvider.notifier);
    return Column(
      children: tasks.map((t) {
        return Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(18),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Left: start / end times.
              SizedBox(
                width: 72,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      t.startLabel,
                      style: AppTextStyles.caption12Bold.copyWith(fontSize: 11),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      t.endLabel,
                      style: AppTextStyles.caption12.copyWith(fontSize: 11),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              Container(
                width: 1,
                height: 44,
                color: AppColors.track,
                margin: const EdgeInsets.symmetric(horizontal: 10),
              ),
              // Middle: checkbox + title/desc.
              Material(
                color: Colors.transparent,
                shape: const CircleBorder(),
                child: InkWell(
                  customBorder: const CircleBorder(),
                  splashColor: AppColors.green.withValues(alpha: 0.4),
                  onTap: () {
                    SystemSound.play(SystemSoundType.click);
                    HapticFeedback.selectionClick();
                    ctrl.toggleTask(t.id);
                  },
                  child: Container(
                    width: 26,
                    height: 26,
                    decoration: BoxDecoration(
                      color: t.isDone ? AppColors.green : Colors.transparent,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: t.isDone
                            ? AppColors.green
                            : AppColors.textSecondary,
                      ),
                    ),
                    child: t.isDone
                        ? const Icon(
                            Icons.check,
                            size: 16,
                            color: AppColors.onCta,
                          )
                        : null,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      t.title,
                      style: AppTextStyles.body15.copyWith(
                        decoration: t.isDone
                            ? TextDecoration.lineThrough
                            : null,
                        color: t.isDone
                            ? AppColors.textSecondary
                            : AppColors.textPrimary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      t.description,
                      style: AppTextStyles.caption12,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              // Right: duration + 3-dot menu.
              Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Pill(t.durationLabel),
                  PopupMenuButton<String>(
                    icon: const Icon(
                      Icons.more_vert,
                      size: 18,
                      color: AppColors.textSecondary,
                    ),
                    padding: EdgeInsets.zero,
                    onSelected: (v) {
                      if (v == 'edit') {
                        TaskEditorSheet.showEdit(context, ref, t);
                      } else if (v == 'delete') {
                        ctrl.deleteTask(t.id);
                      }
                    },
                    itemBuilder: (_) => const [
                      PopupMenuItem(value: 'edit', child: Text('Edit')),
                      PopupMenuItem(value: 'delete', child: Text('Delete')),
                    ],
                  ),
                ],
              ),
            ],
          ),
        );
      }).toList(),
    );
  }
}

/// Add/Edit sheet with Android Material time pickers.
class TaskEditorSheet extends ConsumerStatefulWidget {
  final WidgetRef parentRef;
  final StudyTask? existing;
  const TaskEditorSheet({super.key, required this.parentRef, this.existing});

  static void showAdd(BuildContext context, WidgetRef ref) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: TaskEditorSheet(parentRef: ref),
      ),
    );
  }

  static void showEdit(BuildContext context, WidgetRef ref, StudyTask task) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: TaskEditorSheet(parentRef: ref, existing: task),
      ),
    );
  }

  @override
  ConsumerState<TaskEditorSheet> createState() => _TaskEditorSheetState();
}

class _TaskEditorSheetState extends ConsumerState<TaskEditorSheet> {
  late final TextEditingController _title;
  late final TextEditingController _desc;
  late int _start;
  late int _end;
  String? _titleError;

  @override
  void initState() {
    super.initState();
    _title = TextEditingController(text: widget.existing?.title ?? '');
    _desc = TextEditingController(text: widget.existing?.description ?? '');
    _start = widget.existing?.startMinutes ?? (9 * 60);
    _end = widget.existing?.endMinutes ?? (10 * 60);
  }

  @override
  void dispose() {
    _title.dispose();
    _desc.dispose();
    super.dispose();
  }

  TimeOfDay _tod(int mins) =>
      TimeOfDay(hour: (mins ~/ 60) % 24, minute: mins % 60);

  Future<void> _pick(bool isStart) async {
    // Native Android Material time picker.
    final picked = await showTimePicker(
      context: context,
      initialTime: _tod(isStart ? _start : _end),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          timePickerTheme: const TimePickerThemeData(
            dayPeriodShape: RoundedRectangleBorder(),
          ),
        ),
        child: child!,
      ),
    );
    if (picked == null) return;
    setState(() {
      final mins = picked.hour * 60 + picked.minute;
      if (isStart) {
        _start = mins;
        if (_end <= _start) _end = (_start + 60).clamp(0, 1440);
      } else {
        _end = mins;
        if (_end <= _start) _start = (_end - 60).clamp(0, 1439);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.existing != null;
    final state = widget.parentRef.watch(homeControllerProvider);
    final dur = (_end - _start).clamp(5, 1440);
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${isEdit ? 'Edit' : 'Add'} task — ${selectedDateLabel(state.selectedDate).split(' · ').first}',
              style: AppTextStyles.section18,
            ),
            const SizedBox(height: 12),
            AppTextField(
              controller: _title,
              label: 'Task title',
              hintText: 'Task title (e.g. Binary Search)',
              textInputAction: TextInputAction.next,
              textCapitalization: TextCapitalization.sentences,
              errorText: _titleError,
              onChanged: (_) {
                if (_titleError != null) setState(() => _titleError = null);
              },
            ),
            const SizedBox(height: 8),
            AppTextField(
              controller: _desc,
              label: 'Description',
              hintText: 'Description (e.g. BST revisions ch.3)',
              maxLines: 2,
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: Material(
                    color: AppColors.background,
                    borderRadius: BorderRadius.circular(14),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(14),
                      splashColor: AppColors.primary.withValues(alpha: 0.3),
                      onTap: () {
                        SystemSound.play(SystemSoundType.click);
                        HapticFeedback.selectionClick();
                        _pick(true);
                      },
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Start time', style: AppTextStyles.label10),
                            const SizedBox(height: 2),
                            Text(
                              StudyTask.formatTime(_start),
                              style: AppTextStyles.body16Bold,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Material(
                    color: AppColors.background,
                    borderRadius: BorderRadius.circular(14),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(14),
                      splashColor: AppColors.primary.withValues(alpha: 0.3),
                      onTap: () {
                        SystemSound.play(SystemSoundType.click);
                        HapticFeedback.selectionClick();
                        _pick(false);
                      },
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('End time', style: AppTextStyles.label10),
                            const SizedBox(height: 2),
                            Text(
                              StudyTask.formatTime(_end),
                              style: AppTextStyles.body16Bold,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Pill(_formatStudyDuration(dur)),
              ],
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: PrimaryButton(
                label: isEdit ? 'Save Changes' : 'Schedule Task',
                onPressed: () {
                  if (_title.text.trim().isEmpty) {
                    HapticFeedback.selectionClick();
                    setState(
                      () => _titleError = 'Give your task a title first.',
                    );
                    return;
                  }
                  final ctrl = widget.parentRef.read(
                    homeControllerProvider.notifier,
                  );
                  if (isEdit) {
                    ctrl.editTask(
                      taskId: widget.existing!.id,
                      title: _title.text,
                      description: _desc.text,
                      startMinutes: _start,
                      endMinutes: _end,
                    );
                  } else {
                    ctrl.addTask(
                      title: _title.text,
                      description: _desc.text,
                      startMinutes: _start,
                      endMinutes: _end,
                    );
                  }
                  Navigator.pop(context);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
