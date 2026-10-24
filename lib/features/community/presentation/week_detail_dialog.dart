import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../data/community_models.dart';
import 'community_providers.dart';

/// 7-day week detail breakdown modal sheet.
void showWeekDetailSheet({
  required BuildContext context,
  required String userId,
  required String userName,
  required DateTime monday,
}) {
  HapticFeedback.selectionClick();
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => WeekDetailSheet(
      userId: userId,
      userName: userName,
      initialMonday: monday,
    ),
  );
}

class WeekDetailSheet extends ConsumerStatefulWidget {
  final String userId;
  final String userName;
  final DateTime initialMonday;

  const WeekDetailSheet({
    super.key,
    required this.userId,
    required this.userName,
    required this.initialMonday,
  });

  @override
  ConsumerState<WeekDetailSheet> createState() => _WeekDetailSheetState();
}

class _WeekDetailSheetState extends ConsumerState<WeekDetailSheet> {
  late DateTime _currentMonday;

  @override
  void initState() {
    super.initState();
    _currentMonday = widget.initialMonday;
  }

  void _prevWeek() {
    HapticFeedback.selectionClick();
    setState(() {
      _currentMonday = _currentMonday.subtract(const Duration(days: 7));
    });
  }

  void _nextWeek() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final thisMonday = today.subtract(Duration(days: today.weekday - DateTime.monday));
    if (_currentMonday.isBefore(thisMonday)) {
      HapticFeedback.selectionClick();
      setState(() {
        _currentMonday = _currentMonday.add(const Duration(days: 7));
      });
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

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final thisMonday = today.subtract(Duration(days: today.weekday - DateTime.monday));
    final canGoNext = _currentMonday.isBefore(thisMonday);

    final detailAsync = ref.watch(
      weekDetailProvider((userId: widget.userId, monday: _currentMonday)),
    );

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.82,
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

            // Header Row: User Info & Close
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(widget.userName, style: AppTextStyles.title26),
                        const SizedBox(height: 2),
                        Text('7-Day Study Breakdown', style: AppTextStyles.secondary12),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, color: AppColors.textSecondary),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),

            // Week Stepper Bar
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
                      onPressed: _prevWeek,
                    ),
                    Text(
                      _formatWeekRange(_currentMonday),
                      style: AppTextStyles.body14Bold.copyWith(color: AppColors.textPrimary),
                    ),
                    IconButton(
                      icon: Icon(
                        Icons.chevron_right_rounded,
                        size: 20,
                        color: canGoNext ? AppColors.textPrimary : AppColors.textSecondary.withValues(alpha: 0.3),
                      ),
                      onPressed: canGoNext ? _nextWeek : null,
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
                      Text('Could not load week detail', style: AppTextStyles.body14Bold),
                      const SizedBox(height: 4),
                      Text(err.toString(), style: AppTextStyles.caption12, textAlign: TextAlign.center),
                    ],
                  ),
                ),
                data: (detail) => _buildDetailContent(detail),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailContent(WeekDetailSummary detail) {
    final weekly = detail.weeklyCard;
    final maxDayMinutes = detail.days.fold<int>(
      60,
      (max, d) => math.max(max, d.minutes),
    );

    return ListView(
      shrinkWrap: true,
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      children: [
        // Summary Card
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
        const SizedBox(height: 18),

        Text('DAILY ACTIVITY', style: AppTextStyles.caption12Bold.copyWith(color: AppColors.textSecondary)),
        const SizedBox(height: 10),

        // 7-day breakdown rows
        ...detail.days.map((day) {
          final ratio = maxDayMinutes > 0 ? (day.minutes / maxDayMinutes).clamp(0.0, 1.0) : 0.0;
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              children: [
                SizedBox(
                  width: 44,
                  child: Text(day.shortDayName, style: AppTextStyles.body14Bold),
                ),
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(999),
                    child: Container(
                      height: 10,
                      color: AppColors.surface2,
                      child: FractionallySizedBox(
                        alignment: Alignment.centerLeft,
                        widthFactor: ratio,
                        child: Container(
                          decoration: BoxDecoration(
                            color: day.minutes > 0 ? AppColors.cta : Colors.transparent,
                            borderRadius: BorderRadius.circular(999),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                SizedBox(
                  width: 72,
                  child: Text(
                    day.formattedStudyTime,
                    textAlign: TextAlign.right,
                    style: AppTextStyles.caption12Bold.copyWith(
                      color: day.minutes > 0 ? AppColors.textPrimary : AppColors.textSecondary,
                    ),
                  ),
                ),
              ],
            ),
          );
        }),
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
