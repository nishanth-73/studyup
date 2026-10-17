import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/app_shell.dart';
import 'quiz_controller.dart';

/// Quiz tab: choose a curated quiz. Content, counts, and best scores come
/// from the bundled bank; tapping a row starts that quiz in the runner.
class QuizScreen extends ConsumerWidget {
  const QuizScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bank = ref.watch(quizBankProvider);
    final best = ref.watch(quizBestScoresProvider);

    return AppShell(
      currentIndex: 3,
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
          children: [
            Text('Quiz', style: AppTextStyles.title26.copyWith(fontSize: 26)),
            const SizedBox(height: 4),
            Text(
              'Pick a quiz to practise',
              style: AppTextStyles.secondary14,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 14),
            bank.when(
              loading: () => const Padding(
                padding: EdgeInsets.symmetric(vertical: 48),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (error, _) => Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Text(
                  'Could not load quizzes: $error',
                  style: AppTextStyles.secondary14,
                ),
              ),
              data: (data) {
                if (data.quizzes.isEmpty) {
                  return Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: Text(
                      'No quizzes are available right now.',
                      style: AppTextStyles.secondary14,
                    ),
                  );
                }
                final bestMap = best.valueOrNull ?? const <String, int>{};
                return Column(
                  children: [
                    for (final quiz in data.quizzes)
                      Container(
                        margin: const EdgeInsets.only(bottom: 10),
                        child: Material(
                          color: AppColors.surface,
                          borderRadius: BorderRadius.circular(18),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(18),
                            onTap: () {
                              SystemSound.play(SystemSoundType.click);
                              HapticFeedback.selectionClick();
                              context.push('/quiz/run/${quiz.id}');
                            },
                            child: Padding(
                              padding: const EdgeInsets.all(14),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          quiz.title,
                                          style: AppTextStyles.body15,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          '${quiz.questions.length} questions'
                                          '${bestMap[quiz.id] == null ? '' : ' · Best ${bestMap[quiz.id]}%'}',
                                          style: AppTextStyles.caption12,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ],
                                    ),
                                  ),
                                  const Icon(
                                    Icons.chevron_right,
                                    color: AppColors.textSecondary,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
            SizedBox(height: AppShell.scrollClearance(context)),
          ],
        ),
      ),
    );
  }
}
