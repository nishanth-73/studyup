import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import 'robo_avatar.dart';
import 'robo_customize.dart';
import 'robo_shape.dart';
import 'robo_state.dart';
import 'robo_types.dart';

/// Shape picker offering exactly the three Robo head shapes, each
/// previewed with the real animated RoboAvatar (idle, current shell
/// color). Tapping a shape selects it AND opens its customize sheet
/// (large preview + shell colors).
class RoboShapeSelector extends ConsumerWidget {
  /// Preview avatar size.
  final double size;
  const RoboShapeSelector({super.key, this.size = 56});

  static const List<RoboShape> options = RoboShape.values;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = ref.watch(roboShapeProvider);
    final shell = ref.watch(roboShellColorProvider);
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        for (var i = 0; i < options.length; i++)
          _ShapeOption(
            shape: options[i],
            selected: options[i] == selected,
            size: size,
            seed: i / options.length,
            shell: shell,
            onSelected: () {
              HapticFeedback.selectionClick();
              ref.read(roboShapeProvider.notifier).select(options[i]);
              showRoboCustomizeSheet(context, options[i]);
            },
          ),
      ],
    );
  }
}

class _ShapeOption extends StatelessWidget {
  final RoboShape shape;
  final bool selected;
  final double size;
  final double seed;
  final Color shell;
  final VoidCallback onSelected;

  const _ShapeOption({
    required this.shape,
    required this.selected,
    required this.size,
    required this.seed,
    required this.shell,
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
                  size: size,
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
