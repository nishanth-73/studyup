import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/theme/app_colors.dart';
import 'robo_avatar.dart';
import 'robo_state.dart';
import 'robo_types.dart';

/// Persisted Robo shell color (the yellow/accent body). Stored as ARGB int
/// under the existing SharedPreferences settings storage. Null/absent
/// means the default StudyUp yellow.
class RoboColorController extends StateNotifier<Color> {
  // StudyUp default stays brand yellow even though the library's own
  // default shell is graphite: existing users keep their look.
  RoboColorController() : super(_studyUpYellow) {
    unawaited(_load());
  }

  static const Color _studyUpYellow = Color(0xFFFDD679);

  static const storageKey = 'studyup.roboShellColor.v1';

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (!mounted) return;
      final raw = prefs.getInt(storageKey);
      if (raw != null) state = Color(raw);
    } catch (error, stackTrace) {
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stackTrace,
          library: 'robo color',
          context: ErrorDescription('while loading the Robo shell color'),
        ),
      );
    }
  }

  Future<void> select(Color color) async {
    state = color;
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = await prefs.setInt(storageKey, color.toARGB32());
      if (!saved) throw StateError('Could not persist the Robo shell color.');
    } catch (error, stackTrace) {
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stackTrace,
          library: 'robo color',
          context: ErrorDescription('while saving the Robo shell color'),
        ),
      );
    }
  }
}

final roboShellColorProvider =
    StateNotifierProvider<RoboColorController, Color>(
      (ref) => RoboColorController(),
    );

/// Shell color choices offered in the customize sheet. First entry is the
/// default StudyUp yellow.
const List<Color> roboShellChoices = [
  Color(0xFFFDD679),
  Color(0xFF8BC48A),
  Color(0xFF7DD3E8),
  Color(0xFFFF8FA8),
  Color(0xFF7B68D9),
];

/// Opens the customize sheet for [shape]: a large live preview plus shell
/// color swatches. Selecting a color applies it everywhere immediately
/// and persists it.
Future<void> showRoboCustomizeSheet(BuildContext context, RoboShape shape) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    builder: (ctx) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
      child: _RoboCustomizeSheet(shape: shape),
    ),
  );
}

class _RoboCustomizeSheet extends ConsumerWidget {
  final RoboShape shape;
  const _RoboCustomizeSheet({required this.shape});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final shell = ref.watch(roboShellColorProvider);
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Customize Robo · ${roboShapeName(shape)}',
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 12),
            RoboAvatar(
              shape: shape,
              state: RoboState.happy,
              size: 140,
              color: shell,
              seed: 0.5,
            ),
            const SizedBox(height: 12),
            const Text(
              'Shell color',
              style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              alignment: WrapAlignment.center,
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
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () => Navigator.pop(context),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.cta,
                  foregroundColor: AppColors.onCta,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(26),
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                child: const Text(
                  'Done',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
