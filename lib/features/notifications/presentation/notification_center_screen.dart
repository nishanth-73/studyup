import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../progress/presentation/study_progress_controller.dart';
import '../../profile/presentation/profile_detail_pages.dart';
import '../data/app_notification.dart';
import 'notification_center_controller.dart';

String _hms(int totalSeconds) {
  final h = (totalSeconds ~/ 3600).toString().padLeft(2, '0');
  final m = ((totalSeconds % 3600) ~/ 60).toString().padLeft(2, '0');
  final s = (totalSeconds % 60).toString().padLeft(2, '0');
  return '$h:$m:$s';
}

/// In-app notification center: the single place for StudyUp's
/// notifications — upcoming task reminders, the live study item, and
/// daily-goal completions. Real data only; opening the screen marks the
/// visible rows as read (the red-dot policy).
class NotificationCenterScreen extends ConsumerStatefulWidget {
  const NotificationCenterScreen({super.key});

  @override
  ConsumerState<NotificationCenterScreen> createState() =>
      _NotificationCenterScreenState();
}

class _NotificationCenterScreenState
    extends ConsumerState<NotificationCenterScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ref.read(notificationCenterProvider.notifier).markAllRead();
    });
  }

  @override
  Widget build(BuildContext context) {
    final progress = ref.watch(studyProgressProvider);

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final tomorrow = today.add(const Duration(days: 1));
    var todaySeconds = 0;
    for (final session in progress.sessions) {
      todaySeconds += session.secondsInRange(today, tomorrow, now);
    }
    final active = progress.activeSession;
    final showLive =
        progress.isLoaded &&
        (active != null || progress.minutesForDate(today, now: now) > 0);

    final items = ref.watch(notificationCenterProvider);
    final tasks =
        items.where((i) => i.kind == CenterItemKind.taskReminder).toList()
          ..sort((a, b) {
            final ad = a.taskDate ?? a.at;
            final bd = b.taskDate ?? b.at;
            final c = ad.compareTo(bd);
            if (c != 0) return c;
            return (a.taskStartMinutes ?? 0).compareTo(b.taskStartMinutes ?? 0);
          });
    final goals =
        items.where((i) => i.kind == CenterItemKind.goalReached).toList()
          ..sort((a, b) => b.at.compareTo(a.at));

    return DetailScaffold(
      title: 'Notifications',
      children: [
        if (showLive)
          DetailCard(
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: const BoxDecoration(
                    color: AppColors.cta,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    active != null && !active.isPaused
                        ? Icons.play_arrow
                        : Icons.pause,
                    color: AppColors.onCta,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Live Progress', style: AppTextStyles.body14Bold),
                      const SizedBox(height: 2),
                      Text(
                        active == null
                            ? '${_hms(todaySeconds)} studied today'
                            : active.isPaused
                            ? 'Checked out · ${_hms(todaySeconds)} today'
                            : 'Studying · ${_hms(todaySeconds)} today',
                        style: AppTextStyles.caption12,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        if (tasks.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.only(top: 8, bottom: 8),
            child: Text('Upcoming reminders', style: AppTextStyles.section18),
          ),
          for (final item in tasks)
            _Row(
              icon: Icons.alarm_outlined,
              title: item.title,
              body: item.body,
              unread: !item.read,
            ),
        ],
        if (goals.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.only(top: 8, bottom: 8),
            child: Text('Goal reached', style: AppTextStyles.section18),
          ),
          for (final item in goals)
            _Row(
              icon: Icons.emoji_events_outlined,
              title: item.title,
              body: item.body,
              unread: !item.read,
            ),
        ],
        if (!showLive && tasks.isEmpty && goals.isEmpty)
          DetailCard(
            child: Text(
              'Nothing here yet. Task reminders and daily-goal completions '
              'will show up here.',
              style: AppTextStyles.caption12,
            ),
          ),
      ],
    );
  }
}

class _Row extends StatelessWidget {
  final IconData icon;
  final String title;
  final String body;
  final bool unread;
  const _Row({
    required this.icon,
    required this.title,
    required this.body,
    required this.unread,
  });

  @override
  Widget build(BuildContext context) {
    return DetailCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: AppColors.textSecondary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(title, style: AppTextStyles.body14Bold),
                    ),
                    if (unread)
                      Container(
                        width: 8,
                        height: 8,
                        margin: const EdgeInsets.only(left: 8),
                        decoration: const BoxDecoration(
                          color: Colors.red,
                          shape: BoxShape.circle,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(body, style: AppTextStyles.caption12),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
