import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/ui_kit.dart';
import '../../avatar/presentation/user_profile_controller.dart';
import '../../progress/presentation/study_progress_controller.dart';
import '../../svg_art/presentation/svg_art.dart';

/// First-launch daily-goal selection: 4–10 hours, persisted in minutes
/// through the existing shared goal storage
/// ([StudyProgressController.setDailyStudyGoalMinutes]) — the same single
/// source of truth Home, Progress Insights, and all calculations use.
/// Shown once; later edits stay in Profile's existing goal editor.
class SetupGoalScreen extends ConsumerStatefulWidget {
  const SetupGoalScreen({super.key});
  @override
  ConsumerState<SetupGoalScreen> createState() => _SetupGoalScreenState();
}

class _SetupGoalScreenState extends ConsumerState<SetupGoalScreen> {
  static const _minHours = 4;
  static const _maxHours = 10;
  static const _defaultHours = 8;

  int _hours = _defaultHours;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final stored = ref.read(studyProgressProvider).dailyStudyGoalMinutes ~/ 60;
    _hours = stored >= _minHours && stored <= _maxHours
        ? stored
        : _defaultHours;
  }

  Future<void> _continue() async {
    if (_saving) return;
    setState(() => _saving = true);
    HapticFeedback.selectionClick();
    try {
      // The profile loads asynchronously; wait for it instead of failing
      // when this screen is reached before the load finishes.
      var profile = ref.read(userProfileProvider);
      for (var i = 0; i < 100 && profile.isLoading; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
        if (!mounted) return;
        profile = ref.read(userProfileProvider);
      }
      // One shared goal in minutes — general study and every subject.
      // History is untouched; only the target changes.
      await ref
          .read(studyProgressProvider.notifier)
          .setDailyStudyGoalMinutes(_hours * 60);
      await ref.read(userProfileProvider.notifier).completeSetup();
      if (mounted) context.go('/auth');
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not save your goal: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Instantiate the profile early so it is loaded by Continue time.
    ref.watch(userProfileProvider);
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 12, 24, 12),
                child: Column(
                  children: [
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final side = (constraints.maxWidth * 0.66).clamp(
                          0,
                          240,
                        );
                        return SizedBox(
                          width: side.toDouble(),
                          height: side.toDouble(),
                          child: const SvgArt(
                            asset: 'assets/images/team_goals.svg',
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Pick Your Daily Goal',
                      style: AppTextStyles.title26,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Pick your daily goal to get on track.',
                      style: AppTextStyles.secondary14,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 20),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      alignment: WrapAlignment.center,
                      children: [
                        for (var h = _minHours; h <= _maxHours; h++)
                          _GoalOption(
                            label: '${h}h',
                            selected: h == _hours,
                            onTap: () => setState(() => _hours = h),
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
              child: PrimaryButton(
                label: 'Continue',
                icon: _saving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppColors.onCta,
                        ),
                      )
                    : const Icon(Icons.arrow_forward, size: 18),
                onPressed: _saving ? null : _continue,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GoalOption extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _GoalOption({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: 'Daily goal $label',
      child: Material(
        color: selected ? AppColors.cta : AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () {
            SystemSound.play(SystemSoundType.click);
            onTap();
          },
          child: SizedBox(
            width: 72,
            height: 56,
            child: Center(
              child: Text(
                label,
                style: AppTextStyles.body16Bold.copyWith(
                  color: selected ? AppColors.onCta : AppColors.textPrimary,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
