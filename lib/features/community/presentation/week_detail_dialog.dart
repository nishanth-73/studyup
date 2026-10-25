import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/weekly_study_time_card.dart';
import '../../avatar/data/user_profile.dart';
import '../../avatar/presentation/avatar_widgets.dart';
import '../../avatar/presentation/user_profile_controller.dart';
import '../data/community_models.dart';
import 'community_providers.dart';

/// Opens the Community person-detail view as a bottom sheet.
void showWeekDetailSheet({
  required BuildContext context,
  required String userId,
  required String userName,
  String? avatarUrl,
  DateTime? monday,
}) {
  HapticFeedback.selectionClick();
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => WeekDetailSheet(
      userId: userId,
      userName: userName,
      avatarUrl: avatarUrl,
      initialMonday: monday,
    ),
  );
}

class WeekDetailSheet extends ConsumerStatefulWidget {
  final String userId;
  final String userName;
  final String? avatarUrl;
  final DateTime? initialMonday;

  const WeekDetailSheet({
    super.key,
    required this.userId,
    required this.userName,
    this.avatarUrl,
    this.initialMonday,
  });

  @override
  ConsumerState<WeekDetailSheet> createState() => _WeekDetailSheetState();
}

class _WeekDetailSheetState extends ConsumerState<WeekDetailSheet> {
  @override
  void initState() {
    super.initState();
    if (widget.initialMonday != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ref.read(selectedCommunityMondayProvider.notifier).state = widget.initialMonday!;
      });
    }
  }

  void _prevWeek(DateTime currentMonday) {
    HapticFeedback.selectionClick();
    ref.read(selectedCommunityMondayProvider.notifier).state =
        currentMonday.subtract(const Duration(days: 7));
  }

  void _nextWeek(DateTime currentMonday) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final thisMonday = today.subtract(Duration(days: today.weekday - DateTime.monday));
    if (currentMonday.isBefore(thisMonday)) {
      HapticFeedback.selectionClick();
      ref.read(selectedCommunityMondayProvider.notifier).state =
          currentMonday.add(const Duration(days: 7));
    }
  }

  String _formatWeekRange(DateTime monday) {
    final sunday = monday.add(const Duration(days: 6));
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    if (monday.month == sunday.month) {
      return '${months[monday.month - 1]} ${monday.day} – ${sunday.day}';
    }
    return '${months[monday.month - 1]} ${monday.day} – ${months[sunday.month - 1]} ${sunday.day}';
  }

  Widget _buildAvatar(String? avatarId, String userName, bool isMe) {
    if (avatarId != null && isValidAvatarId(avatarId)) {
      return UserAvatar(avatarId: avatarId, size: 44);
    }

    final initials = _getInitials(userName);
    final color = isMe ? AppColors.green : AppColors.blue;

    return CircleAvatar(
      radius: 22,
      backgroundColor: color.withValues(alpha: 0.25),
      child: Text(
        initials,
        style: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }

  String _getInitials(String name) {
    final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return 'U';
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return (parts[0][0] + parts[1][0]).toUpperCase();
  }

  Widget _buildHeader(WeekDetailSummary? detail) {
    final isMe = detail?.isMe ?? false;
    final avatarId = isMe
        ? (ref.watch(userProfileProvider).valueOrNull?.avatarId ?? detail?.avatarUrl ?? widget.avatarUrl)
        : (detail?.avatarUrl ?? widget.avatarUrl);
    final displayName = detail?.userName ?? widget.userName;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        children: [
          _buildAvatar(avatarId, displayName, isMe),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        displayName,
                        style: AppTextStyles.title26.copyWith(fontSize: 20),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (isMe) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                        decoration: BoxDecoration(
                          color: AppColors.green.withValues(alpha: 0.18),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          'YOU',
                          style: AppTextStyles.caption12Bold.copyWith(
                            fontSize: 8.5,
                            color: AppColors.green,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  isMe ? 'Your Study Performance' : 'Study Circle Member',
                  style: AppTextStyles.secondary12,
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close_rounded, color: AppColors.textSecondary),
            onPressed: () {
              HapticFeedback.selectionClick();
              Navigator.of(context).pop();
            },
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final selectedMonday = ref.watch(selectedCommunityMondayProvider);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final thisMonday = today.subtract(Duration(days: today.weekday - DateTime.monday));
    final canGoNext = selectedMonday.isBefore(thisMonday);

    final detailAsync = ref.watch(
      weekDetailProvider((userId: widget.userId, monday: selectedMonday)),
    );

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.85,
      ),
      decoration: const BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Handle bar
            const SizedBox(height: 12),
            Container(
              width: 38,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.track.withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 14),

            // Header with Person Avatar, Name & Close
            _buildHeader(detailAsync.valueOrNull),

            // Week Stepper Bar (Shared Selected-Week State)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.track.withValues(alpha: 0.4)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.chevron_left_rounded, size: 20),
                      onPressed: () => _prevWeek(selectedMonday),
                    ),
                    Text(
                      _formatWeekRange(selectedMonday),
                      style: AppTextStyles.body14Bold.copyWith(color: AppColors.textPrimary),
                    ),
                    IconButton(
                      icon: Icon(
                        Icons.chevron_right_rounded,
                        size: 20,
                        color: canGoNext
                            ? AppColors.textPrimary
                            : AppColors.textSecondary.withValues(alpha: 0.3),
                      ),
                      onPressed: canGoNext ? () => _nextWeek(selectedMonday) : null,
                    ),
                  ],
                ),
              ),
            ),

            // Body
            Flexible(
              child: detailAsync.when(
                loading: () => const Padding(
                  padding: EdgeInsets.all(40),
                  child: Center(
                    child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.cta),
                  ),
                ),
                error: (err, _) => Padding(
                  padding: const EdgeInsets.all(28),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.info_outline_rounded, color: AppColors.cta, size: 32),
                      const SizedBox(height: 10),
                      Text('Could not load weekly progress', style: AppTextStyles.body14Bold),
                      const SizedBox(height: 4),
                      Text(err.toString(), style: AppTextStyles.caption12, textAlign: TextAlign.center),
                      const SizedBox(height: 12),
                      FilledButton.tonal(
                        onPressed: () => ref.invalidate(
                          weekDetailProvider((userId: widget.userId, monday: selectedMonday)),
                        ),
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                ),
                data: (detail) => _buildDetailContent(detail, selectedMonday),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailContent(WeekDetailSummary detail, DateTime selectedMonday) {
    final weekly = detail.weeklyCard;
    final weekMinutes = detail.days.map((d) => d.minutes).toList();

    return ListView(
      shrinkWrap: true,
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      children: [
        // 1. Weekly Progress Card following Insights Weekly Progress visual style
        WeeklyStudyTimeCard(
          monday: selectedMonday,
          weekMinutes: weekMinutes,
          dailyGoalMinutes: weekly.goalMinutes > 0 ? (weekly.goalMinutes ~/ 7) : 480,
          title: '${detail.userName.toUpperCase()} WEEKLY PROGRESS',
          subtitle: '${detail.userName} · ${_formatWeekRange(selectedMonday)}',
          primaryBarColor: detail.isMe ? AppColors.green : AppColors.blue,
          primaryLabel: detail.isMe ? 'You' : detail.userName,
        ),
        const SizedBox(height: 16),

        // 2. Summary Metrics Card (Studied, Goal %, Sessions, Streak)
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.track.withValues(alpha: 0.3)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildMetric('Studied', weekly.formattedStudyTime),
              Container(width: 1, height: 32, color: AppColors.track.withValues(alpha: 0.5)),
              _buildMetric('Goal %', '${weekly.percent}%'),
              Container(width: 1, height: 32, color: AppColors.track.withValues(alpha: 0.5)),
              _buildMetric('Sessions', '${weekly.completedSessions}'),
              Container(width: 1, height: 32, color: AppColors.track.withValues(alpha: 0.5)),
              _buildMetric('Streak', '${weekly.streak}d'),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildMetric(String label, String value) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(value, style: AppTextStyles.title26.copyWith(fontSize: 18)),
        const SizedBox(height: 2),
        Text(label, style: AppTextStyles.secondary12),
      ],
    );
  }
}
