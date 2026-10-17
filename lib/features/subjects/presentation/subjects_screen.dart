import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/ui_kit.dart';
import '../../../core/widgets/app_shell.dart';
import '../../progress/presentation/study_progress_controller.dart';
import 'subjects_controller.dart';

class SubjectsScreen extends ConsumerWidget {
  const SubjectsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final subjects = ref.watch(subjectsProvider);
    final progress = ref.watch(studyProgressProvider);
    final visibleSubjects = subjects
        .where((subject) => !subject.archived)
        .toList();
    final totalChapters = visibleSubjects.fold(
      0,
      (sum, subject) => sum + subject.totalChapters,
    );
    final completedChapters = visibleSubjects.fold(
      0,
      (sum, subject) => sum + subject.completedChapters,
    );
    final totalTopics = visibleSubjects.fold(
      0,
      (sum, subject) => sum + subject.topicTotal,
    );

    return AppShell(
      currentIndex: 1,
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Subjects',
                        style: AppTextStyles.title30,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        "Keep track of what you're learning.",
                        style: AppTextStyles.secondary14,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                // Add subject at top right.
                Material(
                  color: AppColors.cta,
                  shape: const CircleBorder(),
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    splashColor: Colors.black26,
                    onTap: () {
                      SystemSound.play(SystemSoundType.click);
                      HapticFeedback.selectionClick();
                      _AddSubjectSheet.show(context, ref);
                    },
                    child: const Padding(
                      padding: EdgeInsets.all(12),
                      child: Icon(Icons.add, color: AppColors.onCta, size: 22),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(24),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: _MiniStat('${visibleSubjects.length}', 'subjects'),
                  ),
                  Expanded(
                    child: _MiniStat(
                      '$totalChapters',
                      'chapters',
                      highlight: true,
                    ),
                  ),
                  Expanded(child: _MiniStat('$completedChapters', 'done')),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Center(
              child: Text(
                '$totalTopics topics across all subjects',
                style: AppTextStyles.caption12,
              ),
            ),
            const SizedBox(height: 16),
            // Cards with proper spacing (Padding outside, no collapse).
            if (progress.error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                  'Study data unavailable: ${progress.error}',
                  style: const TextStyle(color: AppColors.error),
                ),
              ),
            for (final s in visibleSubjects)
              Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: Material(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(24),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(24),
                    splashColor: AppColors.primary.withValues(alpha: 0.3),
                    onTap: () {
                      SystemSound.play(SystemSoundType.click);
                      HapticFeedback.selectionClick();
                      context.push('/subject/${s.id}');
                    },
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: s.color.withValues(alpha: 0.2),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Icon(s.icon, size: 18, color: s.color),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        s.name,
                                        style: AppTextStyles.section18.copyWith(
                                          fontSize: 18,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    if (s.pinned)
                                      const Padding(
                                        padding: EdgeInsets.only(left: 6),
                                        child: Icon(
                                          Icons.push_pin,
                                          size: 14,
                                          color: AppColors.cta,
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                              Material(
                                color: Colors.transparent,
                                shape: const CircleBorder(),
                                child: InkWell(
                                  customBorder: const CircleBorder(),
                                  onTap: () {
                                    SystemSound.play(SystemSoundType.click);
                                    HapticFeedback.selectionClick();
                                    _EditSubjectSheet.show(context, ref, s);
                                  },
                                  child: const Padding(
                                    padding: EdgeInsets.all(8),
                                    child: Icon(
                                      Icons.edit_outlined,
                                      size: 18,
                                      color: AppColors.textSecondary,
                                    ),
                                  ),
                                ),
                              ),
                              Material(
                                color: Colors.transparent,
                                shape: const CircleBorder(),
                                child: InkWell(
                                  customBorder: const CircleBorder(),
                                  onTap: () {
                                    SystemSound.play(SystemSoundType.click);
                                    HapticFeedback.selectionClick();
                                    _confirmDeleteSubject(
                                      context,
                                      ref,
                                      s.id,
                                      s.name,
                                    );
                                  },
                                  child: const Padding(
                                    padding: EdgeInsets.all(8),
                                    child: Icon(
                                      Icons.delete_outline,
                                      size: 18,
                                      color: AppColors.textSecondary,
                                    ),
                                  ),
                                ),
                              ),
                              const Icon(
                                Icons.arrow_forward_ios,
                                size: 14,
                                color: AppColors.textSecondary,
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${s.chapterPercent} · Total Chapters: ${s.totalChapters} · Completed: ${s.completedChapters}',
                            style: AppTextStyles.caption12,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 10),
                          AppProgressBar(
                            value: s.progressRatio.clamp(0.0, 1.0),
                            fill: s.color,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            // Scroll clearance above the floating nav (AppShell math).
            SizedBox(height: AppShell.scrollClearance(context)),
          ],
        ),
      ),
    );
  }
}

Future<void> _confirmDeleteSubject(
  BuildContext context,
  WidgetRef ref,
  String subjectId,
  String name,
) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: AppColors.surface,
      title: Text('Delete "$name"?', style: AppTextStyles.section18),
      content: const Text(
        'This will permanently delete the subject with all its chapters and topics.',
        style: TextStyle(color: AppColors.textSecondary),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: Colors.red),
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('Delete'),
        ),
      ],
    ),
  );
  if (ok == true) {
    ref.read(subjectsProvider.notifier).deleteSubject(subjectId);
  }
}

class _EditSubjectSheet extends ConsumerStatefulWidget {
  final WidgetRef parentRef;
  final dynamic subject;
  const _EditSubjectSheet({required this.parentRef, required this.subject});

  static void show(BuildContext context, WidgetRef ref, dynamic s) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: _EditSubjectSheet(parentRef: ref, subject: s),
      ),
    );
  }

  @override
  ConsumerState<_EditSubjectSheet> createState() => _EditSubjectSheetState();
}

class _EditSubjectSheetState extends ConsumerState<_EditSubjectSheet> {
  late final TextEditingController _name;
  late final TextEditingController _desc;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.subject.name as String);
    _desc = TextEditingController(text: widget.subject.meta as String);
  }

  @override
  void dispose() {
    _name.dispose();
    _desc.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Edit subject', style: AppTextStyles.section18),
            const SizedBox(height: 12),
            AppTextField(
              controller: _name,
              label: "Subject's name",
              hintText: "Subject's name",
              textCapitalization: TextCapitalization.words,
            ),
            const SizedBox(height: 8),
            AppTextField(
              controller: _desc,
              label: 'Description',
              hintText: 'Description',
              maxLines: 2,
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: PrimaryButton(
                label: 'Save Changes',
                onPressed: () {
                  widget.parentRef
                      .read(subjectsProvider.notifier)
                      .editSubject(
                        subjectId: widget.subject.id as String,
                        name: _name.text,
                        meta: _desc.text,
                      );
                  Navigator.pop(context);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MiniStat extends StatelessWidget {
  final String v;
  final String l;
  final bool highlight;
  const _MiniStat(this.v, this.l, {this.highlight = false});
  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          v,
          style: AppTextStyles.section18.copyWith(
            fontSize: 20,
            color: highlight ? AppColors.cta : AppColors.textPrimary,
          ),
        ),
        Text(l, style: AppTextStyles.label11),
      ],
    );
  }
}

class _AddSubjectSheet extends ConsumerStatefulWidget {
  final WidgetRef parentRef;
  const _AddSubjectSheet({required this.parentRef});

  static void show(BuildContext context, WidgetRef ref) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: _AddSubjectSheet(parentRef: ref),
      ),
    );
  }

  @override
  ConsumerState<_AddSubjectSheet> createState() => _AddSubjectSheetState();
}

class _AddSubjectSheetState extends ConsumerState<_AddSubjectSheet> {
  final _name = TextEditingController();
  final _desc = TextEditingController();

  @override
  void dispose() {
    _name.dispose();
    _desc.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Add subject', style: AppTextStyles.section18),
            const SizedBox(height: 4),
            Text(
              "Name it and describe what you're learning.",
              style: AppTextStyles.secondary14,
            ),
            const SizedBox(height: 12),
            AppTextField(
              controller: _name,
              label: "Subject's name",
              hintText: "Subject's name (e.g. Physics)",
              textInputAction: TextInputAction.next,
              textCapitalization: TextCapitalization.words,
            ),
            const SizedBox(height: 8),
            AppTextField(
              controller: _desc,
              label: 'Description',
              hintText: "Description (e.g. Semester 5 · Mechanics)",
              maxLines: 2,
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: PrimaryButton(
                label: 'Add Subject',
                onPressed: () {
                  widget.parentRef
                      .read(subjectsProvider.notifier)
                      .addSubject(name: _name.text, meta: _desc.text);
                  Navigator.pop(context);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
