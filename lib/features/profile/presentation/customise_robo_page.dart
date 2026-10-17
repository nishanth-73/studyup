import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../robo/robo_avatar.dart';
import '../../robo/robo_customize.dart';
import '../../robo/robo_shape.dart';
import '../../robo/robo_state.dart';
import '../../robo/robo_types.dart';
import 'profile_detail_pages.dart';

/// Dedicated Robo customisation page, opened from Profile → Settings →
/// Customise Robo.
///
/// Uses the actual integrated [RoboAvatar] (speech bubble, limbs and
/// animations included). Shape selection persists through the existing
/// [roboShapeProvider] storage and applies everywhere Robo appears.
/// State selection is preview-only local state: it never touches the
/// live study-progress-to-Robo-state wiring, and leaving the page
/// discards it so live screens show the real live state again.
class CustomiseRoboPage extends ConsumerStatefulWidget {
  const CustomiseRoboPage({super.key});

  @override
  ConsumerState<CustomiseRoboPage> createState() => _CustomiseRoboPageState();
}

class _CustomiseRoboPageState extends ConsumerState<CustomiseRoboPage> {
  /// Preview-only state. Local to this page; never persisted and never fed
  /// back into [resolveRoboState] or [RoboEvents].
  RoboState _previewState = RoboState.idle;

  static const List<RoboShape> _shapes = RoboShape.values;
  static const List<RoboState> _states = RoboState.values;

  @override
  Widget build(BuildContext context) {
    final selectedShape = ref.watch(roboShapeProvider);
    final shell = ref.watch(roboShellColorProvider);

    return DetailScaffold(
      title: 'Customise Robo',
      children: [
        DetailCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Text('Preview', style: AppTextStyles.body14Bold),
              const SizedBox(height: 2),
              Text(
                'Preview only — Home and Profile keep using Robo’s live state.',
                style: AppTextStyles.caption12,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              // Bounded preview so it never overflows on small phones.
              FittedBox(
                fit: BoxFit.scaleDown,
                child: RoboAvatar(
                  shape: selectedShape,
                  state: _previewState,
                  size: 180,
                  color: shell,
                  seed: 0.5,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '${roboShapeName(selectedShape)} · ${_previewState.name}',
                style: AppTextStyles.caption12Bold,
              ),
            ],
          ),
        ),
        DetailCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Shape', style: AppTextStyles.body14Bold),
              const SizedBox(height: 2),
              Text(
                'Saved automatically and applied everywhere.',
                style: AppTextStyles.caption12,
              ),
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  for (var i = 0; i < _shapes.length; i++)
                    _ShapePreview(
                      shape: _shapes[i],
                      selected: _shapes[i] == selectedShape,
                      shell: shell,
                      seed: i / _shapes.length,
                      onSelected: () {
                        HapticFeedback.selectionClick();
                        ref.read(roboShapeProvider.notifier).select(_shapes[i]);
                      },
                    ),
                ],
              ),
            ],
          ),
        ),
        DetailCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Preview state', style: AppTextStyles.body14Bold),
              const SizedBox(height: 2),
              Text(
                'Try the animations here. Leaving this page restores the live state.',
                style: AppTextStyles.caption12,
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final s in _states)
                    ChoiceChip(
                      key: ValueKey('robo-preview-state-${s.name}'),
                      label: Text(s.name),
                      selected: s == _previewState,
                      selectedColor: AppColors.cta,
                      backgroundColor: AppColors.surface2,
                      labelStyle: AppTextStyles.caption12Bold.copyWith(
                        color: s == _previewState
                            ? AppColors.onCta
                            : AppColors.textSecondary,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(100),
                      ),
                      onSelected: (_) {
                        SystemSound.play(SystemSoundType.click);
                        HapticFeedback.selectionClick();
                        setState(() => _previewState = s);
                      },
                    ),
                ],
              ),
            ],
          ),
        ),
        DetailCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Shell colour', style: AppTextStyles.body14Bold),
              const SizedBox(height: 2),
              Text(
                'Saved automatically and applied everywhere.',
                style: AppTextStyles.caption12,
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                alignment: WrapAlignment.start,
                children: [
                  for (final choice in roboShellChoices)
                    Semantics(
                      button: true,
                      selected: choice == shell,
                      label: 'Robo shell color option',
                      child: Material(
                        color: choice,
                        shape: const CircleBorder(),
                        child: InkWell(
                          key: ValueKey(
                            'robo-color-${choice.toARGB32().toRadixString(16)}',
                          ),
                          customBorder: const CircleBorder(),
                          onTap: () {
                            SystemSound.play(SystemSoundType.click);
                            HapticFeedback.selectionClick();
                            ref
                                .read(roboShellColorProvider.notifier)
                                .select(choice);
                          },
                          child: SizedBox(
                            width: 44,
                            height: 44,
                            child: choice == shell
                                ? const Icon(
                                    Icons.check,
                                    size: 22,
                                    color: Color(0xFF17181D),
                                  )
                                : null,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ShapePreview extends StatelessWidget {
  final RoboShape shape;
  final bool selected;
  final Color shell;
  final double seed;
  final VoidCallback onSelected;

  const _ShapePreview({
    required this.shape,
    required this.selected,
    required this.shell,
    required this.seed,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    final label = 'Robo shape ${roboShapeName(shape)}';
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: Material(
        color: selected
            ? AppColors.cta.withValues(alpha: 0.16)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          key: ValueKey('robo-shape-${shape.name}'),
          borderRadius: BorderRadius.circular(18),
          onTap: () {
            SystemSound.play(SystemSoundType.click);
            onSelected();
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: selected ? AppColors.cta : Colors.transparent,
                width: 2,
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                RoboAvatar(
                  shape: shape,
                  state: RoboState.idle,
                  size: 56,
                  color: shell,
                  showBubble: false,
                  seed: seed,
                ),
                const SizedBox(height: 4),
                Text(
                  roboShapeName(shape),
                  style: TextStyle(
                    color: selected ? AppColors.cta : AppColors.textSecondary,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
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
