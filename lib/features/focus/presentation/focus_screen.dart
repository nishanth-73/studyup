import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/ui_kit.dart';
import '../../progress/data/study_day.dart';
import '../../progress/presentation/study_progress_controller.dart';

class FocusScreen extends ConsumerWidget {
  const FocusScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final progress = ref.watch(studyProgressProvider);
    final session = progress.activeSession;
    final minutesToday = progress.minutesForDate(DateTime.now());
    final elapsed = session?.durationAt(DateTime.now()) ?? Duration.zero;
    final hours = elapsed.inHours.toString().padLeft(2, '0');
    final minutes = (elapsed.inMinutes % 60).toString().padLeft(2, '0');
    final seconds = (elapsed.inSeconds % 60).toString().padLeft(2, '0');
    final goalMinutes = progress.dailyStudyGoalMinutes;
    final ratio = (minutesToday / goalMinutes).clamp(0.0, 1.0);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          children: [
            Row(
              children: [
                IconButton(
                  onPressed: () => context.pop(),
                  icon: const Icon(Icons.close),
                ),
                Expanded(
                  child: Text(
                    'Focus Session',
                    textAlign: TextAlign.center,
                    style: AppTextStyles.body16Bold,
                  ),
                ),
                const SizedBox(width: 48),
              ],
            ),
            const SizedBox(height: 16),
            Center(
              child: Pill(
                session == null
                    ? 'No active session'
                    : session.isPaused
                    ? 'Paused'
                    : 'Studying',
                background: session == null
                    ? AppColors.surface2
                    : session.isPaused
                    ? AppColors.cta
                    : AppColors.green,
                foreground: session == null
                    ? AppColors.textPrimary
                    : AppColors.onCta,
              ),
            ),
            const SizedBox(height: 8),
            Center(
              child: Text(
                session == null
                    ? 'Tap Check In to begin today\u2019s session'
                    : session.isPaused
                    ? 'Paused · daily session'
                    : 'Studying · daily session',
                style: AppTextStyles.secondary14,
              ),
            ),
            const SizedBox(height: 20),
            Center(
              child: Stack(
                alignment: Alignment.center,
                children: [
                  SizedBox(
                    width: 240,
                    height: 240,
                    child: CircularProgressIndicator(
                      value: ratio,
                      strokeWidth: 12,
                      backgroundColor: AppColors.track,
                      valueColor: const AlwaysStoppedAnimation(AppColors.cta),
                    ),
                  ),
                  Column(
                    children: [
                      Text(
                        '$hours:$minutes:$seconds',
                        style: AppTextStyles.timer68.copyWith(fontSize: 48),
                      ),
                      Text('elapsed', style: AppTextStyles.secondary14),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            Builder(
              builder: (context) {
                final ready = progress.isLoaded && progress.error == null;
                final running = session != null && !session.isPaused;
                Future<void> checkIn() async {
                  try {
                    await ref.read(studyProgressProvider.notifier).checkIn();
                  } catch (error) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Could not check in: $error')),
                      );
                    }
                  }
                }

                Future<void> checkOut() async {
                  try {
                    await ref.read(studyProgressProvider.notifier).checkOut();
                  } catch (error) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Could not check out: $error')),
                      );
                    }
                  }
                }

                return Row(
                  children: [
                    Expanded(
                      child: PrimaryButton(
                        label: 'Check In',
                        icon: const Icon(Icons.login, size: 18),
                        onPressed: ready && !running ? checkIn : null,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: PrimaryButton(
                        label: 'Check Out',
                        icon: const Icon(Icons.logout, size: 18),
                        onPressed: ready && running ? checkOut : null,
                      ),
                    ),
                  ],
                );
              },
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: StatTile(
                    label: "TODAY'S STUDY",
                    value: '${minutesToday}m',
                    sub:
                        '${formatAchievement(minutesToday, goalMinutes)} of daily goal',
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: StatTile(
                    label: 'DAILY GOAL',
                    value: '${goalMinutes}m',
                    sub: '',
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
