import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/app_shell.dart';
import '../../../core/widgets/ui_kit.dart';
import '../data/quiz_bank.dart';
import '../data/quiz_models.dart';
import 'quiz_controller.dart';

/// Quiz runner: one question at a time with type-appropriate inputs,
/// backward/forward navigation that preserves answers, and a results
/// phase with per-question review. Pushed from the quiz list; popping
/// returns there (no separate result route, so attempts never leak).
class QuizRunnerScreen extends ConsumerStatefulWidget {
  final String quizId;
  const QuizRunnerScreen({super.key, required this.quizId});

  @override
  ConsumerState<QuizRunnerScreen> createState() => _QuizRunnerScreenState();
}

class _QuizRunnerScreenState extends ConsumerState<QuizRunnerScreen> {
  String? _loadedQuizId;
  Quiz? _quiz;
  int _index = 0;
  bool _finished = false;
  AttemptScore? _score;
  final Map<String, Object?> _answers = {};
  final Map<String, TextEditingController> _textControllers = {};
  int? _selectedLeft;

  @override
  void dispose() {
    for (final c in _textControllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _ensureAttempt(Quiz quiz) {
    if (_loadedQuizId == quiz.id) return;
    for (final c in _textControllers.values) {
      c.dispose();
    }
    _textControllers.clear();
    for (final q in quiz.questions) {
      if (q.type == QuestionType.fillBlank ||
          q.type == QuestionType.subjective) {
        _textControllers[q.id] = TextEditingController();
      }
    }
    _loadedQuizId = quiz.id;
    _quiz = quiz;
    _index = 0;
    _finished = false;
    _score = null;
    _answers.clear();
    _selectedLeft = null;
  }

  void _retry() {
    for (final c in _textControllers.values) {
      c.clear();
    }
    setState(() {
      _answers.clear();
      _index = 0;
      _finished = false;
      _score = null;
      _selectedLeft = null;
    });
  }

  Future<void> _finish() async {
    final quiz = _quiz;
    if (quiz == null) return;
    final score = AttemptScore.evaluate(quiz.questions, _answers);
    setState(() {
      _score = score;
      _finished = true;
    });
    if (score.percent != null) {
      await QuizBestScores.record(quiz.id, score.percent!.toInt());
      if (mounted) ref.invalidate(quizBestScoresProvider);
    }
  }

  void _goTo(int index) {
    setState(() {
      _index = index.clamp(0, (_quiz?.questions.length ?? 1) - 1);
      _selectedLeft = null;
    });
  }

  void _setAnswer(String id, Object? value) {
    setState(() {
      if (value == null) {
        _answers.remove(id);
      } else {
        _answers[id] = value;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final bank = ref.watch(quizBankProvider);
    return bank.when(
      loading: () => const Scaffold(
        backgroundColor: AppColors.background,
        body: Center(child: CircularProgressIndicator()),
      ),
      error: (error, _) => DetailLikeScaffold(
        title: 'Quiz',
        child: Text('Could not load quizzes: $error'),
      ),
      data: (data) {
        final quiz = quizById(data, widget.quizId);
        if (quiz == null) {
          return DetailLikeScaffold(
            title: 'Quiz',
            child: Text(
              'This quiz no longer exists.',
              style: AppTextStyles.secondary14,
            ),
          );
        }
        _ensureAttempt(quiz);
        if (_finished && _score != null) {
          return _ResultsBody(
            quiz: quiz,
            answers: Map.unmodifiable(_answers),
            score: _score!,
            onRetry: _retry,
            onExit: () => context.pop(),
          );
        }
        final question = quiz.questions[_index];
        return AppShell(
          currentIndex: 3,
          body: SafeArea(
            bottom: false,
            child: Column(
              children: [
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                    children: [
                      Row(
                        children: [
                          Material(
                            color: AppColors.surface,
                            shape: const CircleBorder(),
                            child: InkWell(
                              customBorder: const CircleBorder(),
                              onTap: () {
                                SystemSound.play(SystemSoundType.click);
                                HapticFeedback.selectionClick();
                                context.pop();
                              },
                              child: const Padding(
                                padding: EdgeInsets.all(10),
                                child: Icon(
                                  Icons.arrow_back_rounded,
                                  size: 20,
                                  color: AppColors.textPrimary,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  quiz.title,
                                  style: AppTextStyles.section18,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                Text(
                                  'Question ${_index + 1} of ${quiz.questions.length} · ${question.type.label}',
                                  style: AppTextStyles.caption12,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      AppProgressBar(
                        value: (_index + 1) / quiz.questions.length,
                        fill: AppColors.cta,
                      ),
                      const SizedBox(height: 14),
                      Container(
                        padding: const EdgeInsets.all(18),
                        decoration: BoxDecoration(
                          color: AppColors.surface,
                          borderRadius: BorderRadius.circular(18),
                        ),
                        child: Text(
                          question.type == QuestionType.fillBlank
                              ? question.prompt.replaceAll(blankMarker, '_____')
                              : question.prompt,
                          style: AppTextStyles.body15.copyWith(fontSize: 17),
                        ),
                      ),
                      const SizedBox(height: 12),
                      _AnswerInput(
                        question: question,
                        answer: _answers[question.id],
                        controller: _textControllers[question.id],
                        selectedLeft: _selectedLeft,
                        onSelectedLeft: (v) =>
                            setState(() => _selectedLeft = v),
                        onChanged: (v) => _setAnswer(question.id, v),
                      ),
                      SizedBox(
                        height: MediaQuery.of(context).viewInsets.bottom,
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                  child: Row(
                    children: [
                      Expanded(
                        child: PrimaryButton(
                          label: 'Back',
                          background: AppColors.surface2,
                          foreground: AppColors.textPrimary,
                          onPressed: _index == 0
                              ? null
                              : () => _goTo(_index - 1),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: PrimaryButton(
                          label: _index == quiz.questions.length - 1
                              ? 'Finish'
                              : 'Next',
                          onPressed: () {
                            if (_index == quiz.questions.length - 1) {
                              _finish();
                            } else {
                              _goTo(_index + 1);
                            }
                          },
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(height: AppShell.scrollClearance(context)),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Minimal scaffold for runner error states (shares the app background
/// without duplicating the detail-page frame).
class DetailLikeScaffold extends StatelessWidget {
  final String title;
  final Widget child;
  const DetailLikeScaffold({
    super.key,
    required this.title,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
          children: [
            Row(
              children: [
                Material(
                  color: AppColors.surface,
                  shape: const CircleBorder(),
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    onTap: () => context.pop(),
                    child: const Padding(
                      padding: EdgeInsets.all(10),
                      child: Icon(
                        Icons.arrow_back_rounded,
                        size: 20,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(child: Text(title, style: AppTextStyles.section18)),
              ],
            ),
            const SizedBox(height: 16),
            child,
          ],
        ),
      ),
    );
  }
}

/// Type-appropriate answer input. Stateless: all values live in the
/// runner state so backward/forward navigation preserves them.
class _AnswerInput extends StatelessWidget {
  final QuizQuestion question;
  final Object? answer;
  final TextEditingController? controller;
  final int? selectedLeft;
  final ValueChanged<int?> onSelectedLeft;
  final ValueChanged<Object?> onChanged;

  const _AnswerInput({
    required this.question,
    required this.answer,
    required this.controller,
    required this.selectedLeft,
    required this.onSelectedLeft,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    switch (question.type) {
      case QuestionType.mcq:
        final selected = answer is int ? answer as int : null;
        return Column(
          children: [
            for (var i = 0; i < question.options.length; i++)
              _OptionTile(
                key: ValueKey('mcq-$i'),
                text: question.options[i],
                selected: selected == i,
                onTap: () => onChanged(selected == i ? null : i),
              ),
          ],
        );
      case QuestionType.trueFalse:
        final value = answer is bool ? answer as bool : null;
        return Row(
          children: [
            Expanded(
              child: _OptionTile(
                text: 'True',
                selected: value == true,
                onTap: () => onChanged(value == true ? null : true),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _OptionTile(
                text: 'False',
                selected: value == false,
                onTap: () => onChanged(value == false ? null : false),
              ),
            ),
          ],
        );
      case QuestionType.fillBlank:
        return AppTextField(
          controller: controller!,
          label: 'Your answer',
          hintText: 'Type the missing word…',
          textInputAction: TextInputAction.done,
          textCapitalization: TextCapitalization.none,
          onChanged: (v) => onChanged(v.isEmpty ? null : v),
        );
      case QuestionType.matching:
        return _MatchingInput(
          question: question,
          picks: answer is Map
              ? Map<int, int>.fromEntries(
                  (answer as Map).entries.map(
                    (e) => MapEntry(
                      int.parse('${e.key}'),
                      int.parse('${e.value}'),
                    ),
                  ),
                )
              : const {},
          selectedLeft: selectedLeft,
          onSelectedLeft: onSelectedLeft,
          onPicks: (picks) =>
              onChanged(picks.isEmpty ? null : Map<int, int>.from(picks)),
        );
      case QuestionType.subjective:
        return AppTextField(
          controller: controller!,
          label: 'Your answer',
          hintText: 'Write in your own words…',
          maxLines: 4,
          textInputAction: TextInputAction.newline,
          textCapitalization: TextCapitalization.sentences,
          onChanged: (v) => onChanged(v.isEmpty ? null : v),
        );
    }
  }
}

class _OptionTile extends StatelessWidget {
  final String text;
  final bool selected;
  final VoidCallback onTap;
  const _OptionTile({
    super.key,
    required this.text,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: selected
            ? AppColors.cta.withValues(alpha: 0.16)
            : AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          splashColor: AppColors.primary.withValues(alpha: 0.3),
          onTap: () {
            SystemSound.play(SystemSoundType.click);
            HapticFeedback.selectionClick();
            onTap();
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: selected ? AppColors.cta : Colors.transparent,
                width: 2,
              ),
            ),
            child: Row(
              children: [
                Expanded(child: Text(text, style: AppTextStyles.body14)),
                if (selected)
                  const Icon(Icons.check_circle, color: AppColors.cta),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Matching interaction: tap a left term, then tap a right definition to
/// link them. Tapping a linked definition clears that link.
class _MatchingInput extends StatelessWidget {
  final QuizQuestion question;
  final Map<int, int> picks;
  final int? selectedLeft;
  final ValueChanged<int?> onSelectedLeft;
  final ValueChanged<Map<int, int>> onPicks;

  const _MatchingInput({
    required this.question,
    required this.picks,
    required this.selectedLeft,
    required this.onSelectedLeft,
    required this.onPicks,
  });

  String _letter(int i) => String.fromCharCode('A'.codeUnitAt(0) + i);

  @override
  Widget build(BuildContext context) {
    final rightByDisplay = question.displayRight;
    // Reverse lookup: display position -> left index using it.
    final usedBy = <int, int>{};
    picks.forEach((left, display) => usedBy[display] = left);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          selectedLeft == null
              ? 'Tap a term, then its match.'
              : 'Now tap its match.',
          style: AppTextStyles.caption12,
        ),
        const SizedBox(height: 8),
        for (var i = 0; i < question.leftItems.length; i++)
          _MatchRow(
            key: ValueKey('match-left-$i'),
            label: question.leftItems[i],
            chip: picks.containsKey(i)
                ? _letter(rightByDisplay.indexOf(picks[i]!))
                : null,
            selected: selectedLeft == i,
            assigned: picks.containsKey(i),
            onTap: () => onSelectedLeft(selectedLeft == i ? null : i),
          ),
        const SizedBox(height: 4),
        for (var j = 0; j < rightByDisplay.length; j++)
          _MatchRow(
            key: ValueKey('match-right-$j'),
            label: question.rightItems[rightByDisplay[j]],
            chip: _letter(j),
            selected: false,
            assigned: usedBy.containsKey(j),
            dimmed: usedBy.containsKey(j),
            onTap: () {
              final already = usedBy[j];
              final next = Map<int, int>.from(picks);
              if (already != null && selectedLeft == null) {
                next.remove(already);
                onPicks(next);
                return;
              }
              if (selectedLeft == null) return;
              next.removeWhere((_, display) => display == j);
              next[selectedLeft!] = j;
              onSelectedLeft(null);
              onPicks(next);
            },
          ),
      ],
    );
  }
}

class _MatchRow extends StatelessWidget {
  final String label;
  final String? chip;
  final bool selected;
  final bool assigned;
  final bool dimmed;
  final VoidCallback onTap;
  const _MatchRow({
    super.key,
    required this.label,
    this.chip,
    required this.selected,
    required this.assigned,
    this.dimmed = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: selected
            ? AppColors.cta.withValues(alpha: 0.16)
            : assigned
            ? AppColors.cta.withValues(alpha: 0.08)
            : AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () {
            SystemSound.play(SystemSoundType.click);
            HapticFeedback.selectionClick();
            onTap();
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: selected ? AppColors.cta : Colors.transparent,
                width: 2,
              ),
            ),
            child: Row(
              children: [
                if (chip != null)
                  Container(
                    width: 26,
                    height: 26,
                    alignment: Alignment.center,
                    margin: const EdgeInsets.only(right: 10),
                    decoration: BoxDecoration(
                      color: assigned ? AppColors.cta : AppColors.surface2,
                      shape: BoxShape.circle,
                    ),
                    child: Text(
                      chip!,
                      style: AppTextStyles.caption12Bold.copyWith(
                        color: assigned
                            ? AppColors.onCta
                            : AppColors.textSecondary,
                      ),
                    ),
                  ),
                Expanded(
                  child: Text(
                    label,
                    style: AppTextStyles.body14.copyWith(
                      color: dimmed && !selected
                          ? AppColors.textSecondary
                          : AppColors.textPrimary,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Results phase: score, counts, per-question review, retry/exit.
class _ResultsBody extends StatelessWidget {
  final Quiz quiz;
  final Map<String, Object?> answers;
  final AttemptScore score;
  final VoidCallback onRetry;
  final VoidCallback onExit;

  const _ResultsBody({
    required this.quiz,
    required this.answers,
    required this.score,
    required this.onRetry,
    required this.onExit,
  });

  @override
  Widget build(BuildContext context) {
    return AppShell(
      currentIndex: 3,
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
          children: [
            Text(
              'Results · ${quiz.title}',
              style: AppTextStyles.section18,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(18),
              ),
              child: Column(
                children: [
                  Text(
                    score.percent == null
                        ? 'Self-review complete'
                        : '${score.percent!.toInt()}%',
                    style: AppTextStyles.display40,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${score.correct} correct · ${score.incorrect} incorrect'
                    '${score.unanswered == 0 ? '' : ' · ${score.unanswered} unanswered'}'
                    '${score.selfReview == 0 ? '' : ' · ${score.selfReview} self-review'}',
                    style: AppTextStyles.caption12,
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            for (final q in quiz.questions)
              _ReviewCard(question: q, answer: answers[q.id]),
            Row(
              children: [
                Expanded(
                  child: PrimaryButton(
                    label: 'Retry',
                    background: AppColors.surface2,
                    foreground: AppColors.textPrimary,
                    onPressed: onRetry,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: PrimaryButton(label: 'Quizzes', onPressed: onExit),
                ),
              ],
            ),
            SizedBox(height: AppShell.scrollClearance(context)),
          ],
        ),
      ),
    );
  }
}

class _ReviewCard extends StatelessWidget {
  final QuizQuestion question;
  final Object? answer;
  const _ReviewCard({required this.question, required this.answer});

  @override
  Widget build(BuildContext context) {
    final result = gradeQuestion(question, answer);
    final Color statusColor = switch (result.status) {
      GradeStatus.correct => AppColors.green,
      GradeStatus.incorrect => AppColors.error,
      GradeStatus.unanswered => AppColors.textSecondary,
      GradeStatus.selfReview => AppColors.cta,
    };
    final String statusLabel = switch (result.status) {
      GradeStatus.correct => 'Correct',
      GradeStatus.incorrect =>
        result.pairsTotal > 0
            ? 'Incorrect · ${result.pairsCorrect}/${result.pairsTotal} pairs'
            : 'Incorrect',
      GradeStatus.unanswered => 'Unanswered',
      GradeStatus.selfReview => 'Self-review',
    };
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: statusColor.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: statusColor,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(statusLabel, style: AppTextStyles.caption12Bold),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(question.prompt, style: AppTextStyles.body14Bold),
          const SizedBox(height: 6),
          ..._reviewLines(),
        ],
      ),
    );
  }

  List<Widget> _reviewLines() {
    Widget line(String label, String value) => Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Text.rich(
        TextSpan(
          children: [
            TextSpan(text: '$label ', style: AppTextStyles.caption12),
            TextSpan(text: value, style: AppTextStyles.body14),
          ],
        ),
      ),
    );
    switch (question.type) {
      case QuestionType.mcq:
        final picked = answer is int ? answer as int : null;
        return [
          line(
            'Your answer:',
            picked == null
                ? '—'
                : (picked >= 0 && picked < question.options.length
                      ? question.options[picked]
                      : 'Invalid choice'),
          ),
          line(
            'Correct:',
            question.correctIndex != null &&
                    question.correctIndex! >= 0 &&
                    question.correctIndex! < question.options.length
                ? question.options[question.correctIndex!]
                : '—',
          ),
        ];
      case QuestionType.trueFalse:
        String shown(Object? v) => v == null
            ? '—'
            : (v is bool ? (v ? 'True' : 'False') : v.toString());
        return [
          line('Your answer:', shown(answer)),
          line(
            'Correct:',
            question.boolAnswer == null
                ? '—'
                : (question.boolAnswer! ? 'True' : 'False'),
          ),
        ];
      case QuestionType.fillBlank:
        return [
          line(
            'Your answer:',
            answer?.toString().trim().isEmpty ?? true ? '—' : answer.toString(),
          ),
          line(
            'Accepted:',
            question.acceptedAnswers.isEmpty
                ? '—'
                : question.acceptedAnswers.join(' / '),
          ),
        ];
      case QuestionType.matching:
        final map = answer is Map
            ? Map<int, int>.fromEntries(
                (answer as Map).entries.map(
                  (e) =>
                      MapEntry(int.parse('${e.key}'), int.parse('${e.value}')),
                ),
              )
            : <int, int>{};
        return [
          for (var i = 0; i < question.leftItems.length; i++)
            Builder(
              builder: (_) {
                final chosen = map[i];
                final ok = chosen != null && chosen == question.pairs[i];
                final correctDef = question.rightItems[i];
                return line(
                  '${question.leftItems[i]}:',
                  chosen == null
                      ? '—  (correct: $correctDef)'
                      : '${question.rightItems[question.displayRight[chosen]]}'
                            '${ok ? ' ✓' : ' ✗ (correct: $correctDef)'}',
                );
              },
            ),
        ];
      case QuestionType.subjective:
        final text = answer?.toString().trim() ?? '';
        return [
          line('Your answer:', text.isEmpty ? '—' : text),
          line(
            'Reference:',
            question.referenceAnswer.isEmpty ? '—' : question.referenceAnswer,
          ),
          if (question.referenceItems.isNotEmpty)
            line('Key points:', question.referenceItems.join(' · ')),
        ];
    }
  }
}
