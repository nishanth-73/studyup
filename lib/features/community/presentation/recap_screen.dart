import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/ui_kit.dart';
import '../../progress/presentation/study_progress_controller.dart';
import '../data/community_models.dart';
import 'community_controller.dart';
import 'community_widgets.dart';

/// Weekly recap: real totals, week-over-week change, study days,
/// consistency, and consistency-first badges. New users get an honest
/// empty state — never fabricated statistics.
class RecapScreen extends ConsumerWidget {
  const RecapScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final recap = ref.watch(weeklyRecapProvider);
    final bestWeek = ref.watch(bestWeekMinutesProvider);
    final community = ref.watch(communityControllerProvider);
    final progress = ref.watch(studyProgressProvider);

    final completedChallenge =
        community.valueOrNull?.challenges.any((c) {
          if (!c.isEnded) return false;
          final p = ref.watch(challengeProgressProvider(c.id));
          return p.isComplete(c);
        }) ??
        false;
    final badges = buildAchievements(
      recap: recap,
      completedChallenge: completedChallenge,
      bestWeekMinutes: bestWeek,
    );

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        title: Text('Weekly Recap', style: AppTextStyles.section18),
      ),
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
          children: [
            Text(
              weekRangeLabel(recap.weekStart),
              style: AppTextStyles.secondary14,
            ),
            const SizedBox(height: 12),
            if (!recap.hasData)
              const CommunityEmpty(
                title: 'No study data yet',
                body: 'Check in from Focus and your recap — totals, trends, and badges — builds itself from real sessions.',
              )
            else ...[
              _hero(recap),
              const SizedBox(height: 16),
              Text('Daily consistency', style: AppTextStyles.section18),
              const SizedBox(height: 8),
              _weekStrip(ref, recap),
              const SizedBox(height: 16),
              Text('Achievements', style: AppTextStyles.section18),
              const SizedBox(height: 8),
              _badges(badges),
              const SizedBox(height: 16),
              Text('Records', style: AppTextStyles.section18),
              const SizedBox(height: 8),
              _records(recap, bestWeek, progress),
            ],
          ],
        ),
      ),
    );
  }

  Widget _hero(WeeklyRecap recap) {
    final delta = recap.deltaMinutes;
    final deltaLabel = recap.previousMinutes <= 0
        ? 'first tracked week'
        : delta == 0
        ? 'same as last week'
        : delta > 0
        ? '+${formatHoursMinutes(delta * 60)} vs last week'
        : '${formatHoursMinutes(-delta * 60)} less than last week';
    final deltaColor = delta > 0
        ? AppColors.green
        : delta < 0
        ? AppColors.error
        : AppColors.textSecondary;
    return CommunityCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('STUDIED THIS WEEK', style: AppTextStyles.label11),
          const SizedBox(height: 6),
          Text(
            formatHoursMinutes(recap.totalMinutes * 60),
            style: AppTextStyles.display36,
          ),
          const SizedBox(height: 4),
          Text(
            deltaLabel,
            style: AppTextStyles.body14.copyWith(color: deltaColor),
          ),
          const SizedBox(height: 12),
          AppProgressBar(value: recap.consistency, fill: AppColors.cta),
          const SizedBox(height: 6),
          Text(
            '${recap.studyDays}/7 study days · best day ${formatHoursMinutes(recap.bestDayMinutes * 60)}',
            style: AppTextStyles.secondary12,
          ),
        ],
      ),
    );
  }

  Widget _weekStrip(WidgetRef ref, WeeklyRecap recap) {
    const labels = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
    final progress = ref.watch(studyProgressProvider);
    final now = DateTime.now();
    var peak = 1;
    final mins = <int>[];
    for (var i = 0; i < 7; i++) {
      final day = recap.weekStart.add(Duration(days: i));
      final m =
          studiedSecondsInRange(
            progress.sessions,
            day,
            day.add(const Duration(days: 1)),
            now,
          ) ~/
          60;
      mins.add(m);
      if (m > peak) peak = m;
    }
    return CommunityCard(
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          for (var i = 0; i < 7; i++)
            Column(
              children: [
                Container(
                  width: 26,
                  height: 72,
                  alignment: Alignment.bottomCenter,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 400),
                    width: 26,
                    height: (mins[i] / peak * 64).clamp(6.0, 64.0),
                    decoration: BoxDecoration(
                      color: mins[i] > 0 ? AppColors.cta : AppColors.track,
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Text(labels[i], style: AppTextStyles.secondary12),
                Text(
                  mins[i] > 0 ? '${mins[i]}m' : '–',
                  style: AppTextStyles.caption12,
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _badges(List<Achievement> badges) {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        for (final b in badges)
          Opacity(
            opacity: b.earned ? 1 : 0.55,
            child: Container(
              width: 160,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(18),
                border: b.earned
                    ? Border.all(color: AppColors.cta.withValues(alpha: 0.5))
                    : null,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    b.earned ? Icons.verified : Icons.lock_outline,
                    color: b.earned ? AppColors.cta : AppColors.textMuted,
                    size: 22,
                  ),
                  const SizedBox(height: 8),
                  Text(b.title, style: AppTextStyles.body14Bold),
                  const SizedBox(height: 2),
                  Text(b.description, style: AppTextStyles.secondary12),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _records(
    WeeklyRecap recap,
    int bestWeek,
    StudyProgressState progress,
  ) {
    return Column(
      children: [
        CommunityCard(
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Best week', style: AppTextStyles.body14Bold),
                    Text(
                      bestWeek > 0
                          ? formatHoursMinutes(bestWeek * 60)
                          : 'Not set yet — keep studying.',
                      style: AppTextStyles.secondary14,
                    ),
                  ],
                ),
              ),
              const Icon(Icons.emoji_events, color: AppColors.cta),
            ],
          ),
        ),
        const SizedBox(height: 10),
        CommunityCard(
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Total sessions', style: AppTextStyles.body14Bold),
                    Text(
                      '${progress.sessions.length} tracked',
                      style: AppTextStyles.secondary14,
                    ),
                  ],
                ),
              ),
              const Icon(Icons.history, color: AppColors.textSecondary),
            ],
          ),
        ),
      ],
    );
  }
}
