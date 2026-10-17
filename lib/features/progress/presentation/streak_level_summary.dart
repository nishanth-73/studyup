import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../data/study_gamification.dart';
import '../presentation/study_progress_controller.dart';

/// Shared Streak + Level summary row used identically on Profile and
/// Progress. Single source of truth: [studyProgressProvider] plus the
/// real calculation functions in study_gamification.dart — never separate
/// inconsistent values per screen.
///
/// Streak: current run of consecutive studied days (quiet today counts
/// through yesterday) + best run, from persisted sessions.
/// Level: 1 XP per study minute; Level N unlocks at
/// 60 × N × (N − 1) ÷ 2 cumulative XP (L1 0, L2 60, L3 180, …).
class StreakLevelRow extends ConsumerWidget {
  const StreakLevelRow({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final progress = ref.watch(studyProgressProvider);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    final streak = computeStudyStreak(
      minutesForDay: (d) => progress.minutesForDate(d, now: now),
      today: today,
      earliestDay: earliestStudyDay(progress.sessions, today),
    );

    final totalXp = totalStudyMinutes(progress.sessions, now);
    final levelData = computeStudyLevel(totalXp);

    return Row(
      children: [
        Expanded(
          child: _SummaryCard(
            icon: Icons.local_fire_department_rounded,
            iconColor: AppColors.orange,
            value: '${streak.current}',
            unit: streak.current == 1 ? 'day' : 'days',
            label: 'Current streak',
            footer: 'Best: ${streak.best} ${streak.best == 1 ? 'day' : 'days'}',
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _SummaryCard(
            icon: Icons.bolt_rounded,
            iconColor: AppColors.cta,
            value: '${levelData.level}',
            unit: 'Level',
            label: 'Study level',
            footer:
                '${levelData.xpIntoLevel} / ${levelData.xpForNextLevel} XP',
            progressFraction: levelData.progress,
          ),
        ),
      ],
    );
  }
}

/// A compact summary card used by the Streak and Level displays.
/// [progressFraction] draws a thin goal-bar beneath the footer when
/// non-null (used for the Level card only).
class _SummaryCard extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String value;
  final String unit;
  final String label;
  final String footer;
  final double? progressFraction;

  const _SummaryCard({
    required this.icon,
    required this.iconColor,
    required this.value,
    required this.unit,
    required this.label,
    required this.footer,
    this.progressFraction,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: iconColor),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  label,
                  style: AppTextStyles.label11,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(value, style: AppTextStyles.stat26),
              const SizedBox(width: 4),
              Padding(
                padding: const EdgeInsets.only(bottom: 3),
                child: Text(unit, style: AppTextStyles.caption13),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(footer, style: AppTextStyles.caption12),
          if (progressFraction != null) ...[
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: progressFraction,
                minHeight: 3,
                backgroundColor: AppColors.track,
                valueColor:
                    const AlwaysStoppedAnimation<Color>(AppColors.cta),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
