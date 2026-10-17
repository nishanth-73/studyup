import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/ui_kit.dart';
import '../data/subjects_models.dart';
import 'subjects_controller.dart';

class SubjectDetailScreen extends ConsumerWidget {
  final String id;
  const SubjectDetailScreen({super.key, required this.id});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final subjects = ref.watch(subjectsProvider);
    final s = subjectById(subjects, id);
    if (s == null) {
      return Scaffold(
        backgroundColor: AppColors.background,
        body: SafeArea(
          child: Center(
            child: TextButton(
              onPressed: () => context.pop(),
              child: const Text('Subject not found · Go back'),
            ),
          ),
        ),
      );
    }
    final subjectRatio = s.progressRatio.clamp(0.0, 1.0);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          children: [
            Row(
              children: [
                Material(
                  color: Colors.transparent,
                  shape: const CircleBorder(),
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    splashColor: AppColors.primary.withValues(alpha: 0.3),
                    onTap: () {
                      SystemSound.play(SystemSoundType.click);
                      HapticFeedback.selectionClick();
                      context.pop();
                    },
                    child: const Padding(
                      padding: EdgeInsets.all(8),
                      child: Icon(Icons.arrow_back),
                    ),
                  ),
                ),
                Expanded(
                  child: Text(
                    s.name,
                    textAlign: TextAlign.center,
                    style: AppTextStyles.body16Bold,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                PopupMenuButton<String>(
                  icon: const Icon(
                    Icons.more_vert,
                    color: AppColors.textPrimary,
                  ),
                  splashRadius: 20,
                  onSelected: (v) {
                    SystemSound.play(SystemSoundType.click);
                    HapticFeedback.selectionClick();
                    final ctrl = ref.read(subjectsProvider.notifier);
                    if (v == 'edit') {
                      _EditSubjectSheet.show(context, ref, s);
                    } else if (v == 'pin') {
                      ctrl.togglePin(s.id);
                    } else if (v == 'delete') {
                      _confirmDelete(context, ref, s);
                    }
                  },
                  itemBuilder: (_) => [
                    const PopupMenuItem(value: 'edit', child: Text('Edit')),
                    PopupMenuItem(
                      value: 'pin',
                      child: Text(s.pinned ? 'Unpin' : 'Pin'),
                    ),
                    const PopupMenuItem(value: 'delete', child: Text('Delete')),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 12),
            // Overview hero per subject.
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: s.color,
                borderRadius: BorderRadius.circular(28),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Icon(s.icon, color: AppColors.onCta),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              s.name,
                              style: AppTextStyles.title26.copyWith(
                                color: AppColors.onCta,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            Text(
                              s.meta,
                              style: AppTextStyles.caption12.copyWith(
                                color: AppColors.onCta,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Overall progress · chapters',
                    style: AppTextStyles.caption13.copyWith(
                      color: AppColors.onCta,
                    ),
                  ),
                  Text(
                    s.chapterPercent,
                    style: AppTextStyles.display34.copyWith(
                      color: AppColors.onCta,
                    ),
                  ),
                  const SizedBox(height: 8),
                  _HeroBar(value: subjectRatio),
                  const SizedBox(height: 6),
                  Text(
                    s.chapterLabel,
                    style: AppTextStyles.caption12.copyWith(
                      color: AppColors.onCta,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: _HeroStat('${s.totalChapters}', 'chapters'),
                      ),
                      Expanded(
                        child: _HeroStat('${s.completedChapters}', 'completed'),
                      ),
                      Expanded(child: _HeroStat('${s.topicTotal}', 'topics')),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                const Expanded(child: SectionHeader(title: 'Chapters')),
                TextButton.icon(
                  onPressed: () => _AddChapterSheet.show(context, ref, s.id),
                  icon: const Icon(Icons.add, size: 16),
                  label: const Text('Add'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            for (int i = 0; i < s.chapters.length; i++)
              _ChapterCard(subject: s, index: i, chapter: s.chapters[i]),
          ],
        ),
      ),
    );
  }
}

class _HeroBar extends StatelessWidget {
  final double value;
  const _HeroBar({required this.value});
  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(100),
      child: LinearProgressIndicator(
        value: value.clamp(0, 1),
        minHeight: 6,
        backgroundColor: Colors.black26,
        valueColor: const AlwaysStoppedAnimation(AppColors.onCta),
      ),
    );
  }
}

class _ChapterCard extends ConsumerStatefulWidget {
  final Subject subject;
  final int index;
  final Chapter chapter;
  const _ChapterCard({
    required this.subject,
    required this.index,
    required this.chapter,
  });

  @override
  ConsumerState<_ChapterCard> createState() => _ChapterCardState();
}

class _ChapterCardState extends ConsumerState<_ChapterCard> {
  bool _open = false;
  final _ctrl = TextEditingController();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.chapter;
    final ctrl = ref.read(subjectsProvider.notifier);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              splashColor: AppColors.primary.withValues(alpha: 0.3),
              onTap: () {
                SystemSound.play(SystemSoundType.click);
                HapticFeedback.selectionClick();
                setState(() => _open = !_open);
              },
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: AppColors.surface2,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Text(
                      '${widget.index + 1}',
                      style: AppTextStyles.body16Bold,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          c.title,
                          style: AppTextStyles.body15,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(c.label, style: AppTextStyles.label11),
                        const SizedBox(height: 6),
                        AppProgressBar(
                          value: c.ratio,
                          fill: widget.subject.color,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Pill(c.percent, background: AppColors.surface2),
                  PopupMenuButton<String>(
                    icon: const Icon(
                      Icons.more_vert,
                      size: 16,
                      color: AppColors.textSecondary,
                    ),
                    splashRadius: 18,
                    padding: EdgeInsets.zero,
                    onSelected: (v) {
                      SystemSound.play(SystemSoundType.click);
                      HapticFeedback.selectionClick();
                      if (v == 'rename') {
                        _RenameChapterSheet.show(
                          context,
                          ref,
                          widget.subject.id,
                          c.id,
                          c.title,
                        );
                      } else if (v == 'delete') {
                        ctrl.deleteChapter(
                          subjectId: widget.subject.id,
                          chapterId: c.id,
                        );
                      } else if (v == 'sources') {
                        _ChapterSourcesSheet.show(
                          context,
                          ref,
                          widget.subject.id,
                          c.id,
                          c.title,
                        );
                      }
                    },
                    itemBuilder: (_) => const [
                      PopupMenuItem(value: 'rename', child: Text('Rename')),
                      PopupMenuItem(
                        value: 'sources',
                        child: Text('Add sources'),
                      ),
                      PopupMenuItem(value: 'delete', child: Text('Delete')),
                    ],
                  ),
                  Icon(
                    _open ? Icons.expand_less : Icons.expand_more,
                    color: AppColors.textSecondary,
                  ),
                ],
              ),
            ),
          ),
          if (_open) ...[
            const SizedBox(height: 10),
            for (final t in c.topics)
              Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(10),
                  onTap: () {
                    SystemSound.play(SystemSoundType.click);
                    HapticFeedback.selectionClick();
                    ctrl.toggleTopic(
                      subjectId: widget.subject.id,
                      chapterId: c.id,
                      topicId: t.id,
                    );
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(
                      children: [
                        Container(
                          width: 22,
                          height: 22,
                          decoration: BoxDecoration(
                            color: t.done
                                ? AppColors.green
                                : Colors.transparent,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: t.done
                                  ? AppColors.green
                                  : AppColors.textSecondary,
                            ),
                          ),
                          child: t.done
                              ? const Icon(
                                  Icons.check,
                                  size: 14,
                                  color: AppColors.onCta,
                                )
                              : null,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            t.name,
                            style: AppTextStyles.body14.copyWith(
                              decoration: t.done
                                  ? TextDecoration.lineThrough
                                  : null,
                              color: t.done
                                  ? AppColors.textSecondary
                                  : AppColors.textPrimary,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        PopupMenuButton<String>(
                          icon: const Icon(
                            Icons.more_vert,
                            size: 16,
                            color: AppColors.textSecondary,
                          ),
                          splashRadius: 18,
                          padding: EdgeInsets.zero,
                          onSelected: (v) {
                            SystemSound.play(SystemSoundType.click);
                            HapticFeedback.selectionClick();
                            if (v == 'edit') {
                              _EditTopicSheet.show(
                                context,
                                ref,
                                widget.subject.id,
                                c.id,
                                t.id,
                                t.name,
                              );
                            } else if (v == 'delete') {
                              ctrl.deleteTopic(
                                subjectId: widget.subject.id,
                                chapterId: c.id,
                                topicId: t.id,
                              );
                            }
                          },
                          itemBuilder: (_) => const [
                            PopupMenuItem(value: 'edit', child: Text('Edit')),
                            PopupMenuItem(
                              value: 'delete',
                              child: Text('Delete'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            Row(
              children: [
                Expanded(
                  child: AppTextField(
                    controller: _ctrl,
                    hintText: 'Add a topic…',
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => _add(ctrl),
                  ),
                ),
                const SizedBox(width: 8),
                Material(
                  color: widget.subject.color,
                  shape: const CircleBorder(),
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    onTap: () => _add(ctrl),
                    child: const Padding(
                      padding: EdgeInsets.all(10),
                      child: Icon(Icons.add, size: 18, color: AppColors.onCta),
                    ),
                  ),
                ),
              ],
            ),
            if (c.sources.isNotEmpty) ...[
              const SizedBox(height: 10),
              for (final s in c.sources)
                _SourceRow(
                  subjectId: widget.subject.id,
                  chapterId: c.id,
                  source: s,
                ),
            ],
          ],
        ],
      ),
    );
  }

  void _add(SubjectsController ctrl) {
    ctrl.addTopic(
      subjectId: widget.subject.id,
      chapterId: widget.chapter.id,
      name: _ctrl.text,
    );
    _ctrl.clear();
  }
}

IconData _sourceIcon(StudySourceKind kind) {
  switch (kind) {
    case StudySourceKind.link:
      return Icons.link_rounded;
    case StudySourceKind.pdf:
      return Icons.picture_as_pdf_outlined;
    case StudySourceKind.image:
      return Icons.image_outlined;
  }
}

String _sourceKindLabel(StudySourceKind kind) {
  switch (kind) {
    case StudySourceKind.link:
      return 'Link';
    case StudySourceKind.pdf:
      return 'PDF';
    case StudySourceKind.image:
      return 'Image';
  }
}

/// Copies a picked file into durable app-private storage and returns
/// the stored path. Picker results may point at temporary caches or
/// content URIs, so the copy — not the raw path — is what gets saved.
/// [targetDir] overrides the documents directory (tests only).
Future<String> storePickedSourceFile(
  String sourcePath,
  String hint, {
  Directory? targetDir,
}) async {
  final source = File(sourcePath);
  if (!await source.exists()) {
    throw StateError('Picked file is no longer available.');
  }
  final dir = targetDir ?? await getApplicationDocumentsDirectory();
  final folder = Directory('${dir.path}/sources');
  if (!await folder.exists()) {
    await folder.create(recursive: true);
  }
  final safe = hint.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
  final stamped = '${DateTime.now().microsecondsSinceEpoch}_$safe';
  final stored = await source.copy('${folder.path}/$stamped');
  return stored.path;
}

Future<void> _openSource(BuildContext context, StudySource source) async {
  if (source.kind == StudySourceKind.image) {
    final file = File(source.url);
    if (!await file.exists()) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Image file is no longer available.')),
        );
      }
      return;
    }
    if (context.mounted) {
      await showDialog(
        context: context,
        builder: (ctx) => Dialog(
          backgroundColor: AppColors.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  source.name,
                  style: AppTextStyles.body14Bold,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 8),
                Flexible(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.file(file, fit: BoxFit.contain),
                  ),
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Close'),
                ),
              ],
            ),
          ),
        ),
      );
    }
    return;
  }
  if (source.kind == StudySourceKind.pdf) {
    final file = File(source.url);
    if (!await file.exists()) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('PDF file is no longer available.')),
        );
      }
      return;
    }
    final result = await OpenFilex.open(file.path);
    if (result.type != ResultType.done && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not open PDF: ${result.message}')),
      );
    }
    return;
  }
  final uri = Uri.tryParse(source.url);
  if (uri == null || (!uri.hasScheme && !source.url.contains('.'))) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('That link does not look valid.')),
      );
    }
    return;
  }
  final fixed = uri.hasScheme ? uri : Uri.parse('https://${source.url}');
  final ok = await launchUrl(fixed, mode: LaunchMode.externalApplication);
  if (!ok && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Could not open this source.')),
    );
  }
}

/// One saved source row inside an expanded chapter: tap to view.
class _SourceRow extends ConsumerWidget {
  final String subjectId;
  final String chapterId;
  final StudySource source;
  const _SourceRow({
    required this.subjectId,
    required this.chapterId,
    required this.source,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () {
          SystemSound.play(SystemSoundType.click);
          HapticFeedback.selectionClick();
          _openSource(context, source);
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            children: [
              Container(
                width: 30,
                height: 30,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppColors.surface2,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  _sourceIcon(source.kind),
                  size: 16,
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      source.name,
                      style: AppTextStyles.body14,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      _sourceKindLabel(source.kind),
                      style: AppTextStyles.label11,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
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
                    ref
                        .read(subjectsProvider.notifier)
                        .deleteSource(
                          subjectId: subjectId,
                          chapterId: chapterId,
                          sourceId: source.id,
                        );
                  },
                  child: const Padding(
                    padding: EdgeInsets.all(8),
                    child: Icon(
                      Icons.delete_outline,
                      size: 16,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Add-a-source sheet: name + link/URL + type picker. Saved sources open
/// externally when tapped.
///
/// Attachment picker tile for the PDF/Image kinds: shows the picked
/// filename (or a muted empty state) with Pick/Clear actions.
class _AttachmentTile extends StatelessWidget {
  final StudySourceKind kind;
  final String? fileName;
  final VoidCallback onPick;
  final VoidCallback? onClear;
  const _AttachmentTile({
    required this.kind,
    required this.fileName,
    required this.onPick,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          kind == StudySourceKind.pdf ? 'PDF file' : 'Image',
          style: AppTextStyles.caption13,
        ),
        const SizedBox(height: 6),
        Material(
          color: AppColors.surface2,
          borderRadius: BorderRadius.circular(14),
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: () {
              SystemSound.play(SystemSoundType.click);
              HapticFeedback.selectionClick();
              onPick();
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Row(
                children: [
                  Icon(
                    kind == StudySourceKind.pdf
                        ? Icons.picture_as_pdf_outlined
                        : Icons.image_outlined,
                    color: AppColors.textSecondary,
                    size: 20,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      fileName ??
                          (kind == StudySourceKind.pdf
                              ? 'No PDF chosen — tap to browse files'
                              : 'No image chosen — tap to open gallery'),
                      style: AppTextStyles.body14.copyWith(
                        color: fileName == null
                            ? AppColors.textMuted.withValues(alpha: 0.75)
                            : AppColors.textPrimary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (onClear != null)
                    InkWell(
                      customBorder: const CircleBorder(),
                      onTap: () {
                        SystemSound.play(SystemSoundType.click);
                        HapticFeedback.selectionClick();
                        onClear!();
                      },
                      child: const Padding(
                        padding: EdgeInsets.all(4),
                        child: Icon(
                          Icons.close_rounded,
                          size: 18,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _ChapterSourcesSheet extends ConsumerStatefulWidget {
  final WidgetRef parentRef;
  final String subjectId;
  final String chapterId;
  final String chapterTitle;
  const _ChapterSourcesSheet({
    required this.parentRef,
    required this.subjectId,
    required this.chapterId,
    required this.chapterTitle,
  });

  static void show(
    BuildContext context,
    WidgetRef ref,
    String subjectId,
    String chapterId,
    String chapterTitle,
  ) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: _ChapterSourcesSheet(
          parentRef: ref,
          subjectId: subjectId,
          chapterId: chapterId,
          chapterTitle: chapterTitle,
        ),
      ),
    );
  }

  @override
  ConsumerState<_ChapterSourcesSheet> createState() =>
      _ChapterSourcesSheetState();
}

class _ChapterSourcesSheetState extends ConsumerState<_ChapterSourcesSheet> {
  final _name = TextEditingController();
  final _url = TextEditingController();
  StudySourceKind _kind = StudySourceKind.link;
  String? _pickedPath;
  String? _pickedName;
  bool _saving = false;

  @override
  void dispose() {
    _name.dispose();
    _url.dispose();
    super.dispose();
  }

  void _fail(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  /// Native pickers: Android file picker (PDF filter) and gallery.
  /// Cancellation returns null and leaves the sheet untouched.
  Future<void> _pickAttachment() async {
    try {
      if (_kind == StudySourceKind.pdf) {
        final files = await FilePicker.pickFiles(
          type: FileType.custom,
          allowedExtensions: ['pdf'],
        );
        if (files.isEmpty) return;
        final picked = files.single;
        if (picked.path == null || picked.path!.isEmpty) {
          _fail('That file could not be read. Try another PDF.');
          return;
        }
        if (mounted) {
          setState(() {
            _pickedPath = picked.path;
            _pickedName = picked.name;
          });
        }
      } else {
        final picked = await ImagePicker().pickImage(
          source: ImageSource.gallery,
        );
        if (picked == null) return;
        if (mounted) {
          setState(() {
            _pickedPath = picked.path;
            _pickedName = picked.name.isEmpty ? 'image' : picked.name;
          });
        }
      }
    } catch (_) {
      _fail('Could not open the picker. Please try again.');
    }
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      if (_kind == StudySourceKind.link) {
        if (_url.text.trim().isEmpty) {
          _fail('Paste a link first.');
          return;
        }
        widget.parentRef
            .read(subjectsProvider.notifier)
            .addSource(
              subjectId: widget.subjectId,
              chapterId: widget.chapterId,
              name: _name.text,
              kind: _kind,
              url: _url.text,
            );
      } else {
        if (_pickedPath == null) {
          _fail(
            _kind == StudySourceKind.pdf
                ? 'Choose a PDF first.'
                : 'Choose an image first.',
          );
          return;
        }
        late final String stored;
        try {
          stored = await storePickedSourceFile(
            _pickedPath!,
            _pickedName ?? 'file',
          );
        } catch (_) {
          _fail('That file could not be saved. Try another one.');
          return;
        }
        widget.parentRef
            .read(subjectsProvider.notifier)
            .addSource(
              subjectId: widget.subjectId,
              chapterId: widget.chapterId,
              name: _name.text.trim().isEmpty
                  ? (_pickedName ?? 'Attachment')
                  : _name.text,
              kind: _kind,
              url: stored,
            );
      }
      if (mounted) Navigator.pop(context);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
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
            Text(
              'Add source — ${widget.chapterTitle}',
              style: AppTextStyles.section18,
            ),
            const SizedBox(height: 4),
            Text(
              'Name it, attach a file or paste its link, pick what it is.',
              style: AppTextStyles.secondary14,
            ),
            const SizedBox(height: 12),
            AppTextField(
              controller: _name,
              label: 'Name',
              hintText: 'Name (e.g. Chapter 3 notes PDF)',
              textInputAction: TextInputAction.next,
              textCapitalization: TextCapitalization.words,
            ),
            const SizedBox(height: 8),
            if (_kind == StudySourceKind.link)
              AppTextField(
                controller: _url,
                label: 'Link',
                hintText: 'Link (https://…)',
                textInputAction: TextInputAction.done,
                keyboardType: TextInputType.url,
              )
            else
              _AttachmentTile(
                kind: _kind,
                fileName: _pickedName,
                onPick: _pickAttachment,
                onClear: _pickedPath == null
                    ? null
                    : () => setState(() {
                        _pickedPath = null;
                        _pickedName = null;
                      }),
              ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              children: [
                for (final kind in StudySourceKind.values)
                  ChoiceChip(
                    label: Text(_sourceKindLabel(kind)),
                    selected: _kind == kind,
                    onSelected: (_) => setState(() => _kind = kind),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: PrimaryButton(
                label: _saving ? 'Saving…' : 'Save Source',
                onPressed: _saving ? null : _save,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AddChapterSheet extends ConsumerStatefulWidget {
  final WidgetRef parentRef;
  final String subjectId;
  const _AddChapterSheet({required this.parentRef, required this.subjectId});

  static void show(BuildContext context, WidgetRef ref, String subjectId) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: _AddChapterSheet(parentRef: ref, subjectId: subjectId),
      ),
    );
  }

  @override
  ConsumerState<_AddChapterSheet> createState() => _AddChapterSheetState();
}

class _AddChapterSheetState extends ConsumerState<_AddChapterSheet> {
  final _title = TextEditingController();

  @override
  void dispose() {
    _title.dispose();
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
            Text('Add chapter', style: AppTextStyles.section18),
            const SizedBox(height: 12),
            AppTextField(
              controller: _title,
              label: 'Chapter title',
              hintText: 'Chapter title (e.g. Chapter 2)',
              textCapitalization: TextCapitalization.words,
              autofocus: true,
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: PrimaryButton(
                label: 'Add Chapter',
                onPressed: () {
                  widget.parentRef
                      .read(subjectsProvider.notifier)
                      .addChapter(
                        subjectId: widget.subjectId,
                        title: _title.text,
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

class _RenameChapterSheet extends ConsumerStatefulWidget {
  final WidgetRef parentRef;
  final String subjectId;
  final String chapterId;
  final String initial;
  const _RenameChapterSheet({
    required this.parentRef,
    required this.subjectId,
    required this.chapterId,
    required this.initial,
  });

  static void show(
    BuildContext context,
    WidgetRef ref,
    String sid,
    String cid,
    String title,
  ) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: _RenameChapterSheet(
          parentRef: ref,
          subjectId: sid,
          chapterId: cid,
          initial: title,
        ),
      ),
    );
  }

  @override
  ConsumerState<_RenameChapterSheet> createState() =>
      _RenameChapterSheetState();
}

class _RenameChapterSheetState extends ConsumerState<_RenameChapterSheet> {
  late final TextEditingController _title;

  @override
  void initState() {
    super.initState();
    _title = TextEditingController(text: widget.initial);
  }

  @override
  void dispose() {
    _title.dispose();
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
            Text('Rename chapter', style: AppTextStyles.section18),
            const SizedBox(height: 12),
            AppTextField(
              controller: _title,
              label: 'Chapter title',
              hintText: 'Chapter title',
              textCapitalization: TextCapitalization.words,
              autofocus: true,
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: PrimaryButton(
                label: 'Save Changes',
                onPressed: () {
                  widget.parentRef
                      .read(subjectsProvider.notifier)
                      .renameChapter(
                        subjectId: widget.subjectId,
                        chapterId: widget.chapterId,
                        title: _title.text,
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

class _HeroStat extends StatelessWidget {
  final String v;
  final String l;
  const _HeroStat(this.v, this.l);
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          v,
          style: AppTextStyles.body16Bold.copyWith(color: AppColors.onCta),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        Text(l, style: AppTextStyles.label11.copyWith(color: AppColors.onCta)),
      ],
    );
  }
}

Future<void> _confirmDelete(
  BuildContext context,
  WidgetRef ref,
  Subject s,
) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: AppColors.surface,
      title: Text('Delete "${s.name}"?', style: AppTextStyles.section18),
      content: const Text(
        'Warning: this will permanently delete the subject with all its chapters and topics. This cannot be undone.',
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
          child: const Text('Delete everything'),
        ),
      ],
    ),
  );
  if (ok == true && context.mounted) {
    ref.read(subjectsProvider.notifier).deleteSubject(s.id);
    context.pop();
  }
}

class _EditSubjectSheet extends ConsumerStatefulWidget {
  final WidgetRef parentRef;
  final Subject subject;
  const _EditSubjectSheet({required this.parentRef, required this.subject});

  static void show(BuildContext context, WidgetRef ref, Subject s) {
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
    _name = TextEditingController(text: widget.subject.name);
    _desc = TextEditingController(text: widget.subject.meta);
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
                        subjectId: widget.subject.id,
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

class _EditTopicSheet extends ConsumerStatefulWidget {
  final WidgetRef parentRef;
  final String subjectId;
  final String chapterId;
  final String topicId;
  final String initial;
  const _EditTopicSheet({
    required this.parentRef,
    required this.subjectId,
    required this.chapterId,
    required this.topicId,
    required this.initial,
  });

  static void show(
    BuildContext context,
    WidgetRef ref,
    String sid,
    String cid,
    String tid,
    String name,
  ) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: _EditTopicSheet(
          parentRef: ref,
          subjectId: sid,
          chapterId: cid,
          topicId: tid,
          initial: name,
        ),
      ),
    );
  }

  @override
  ConsumerState<_EditTopicSheet> createState() => _EditTopicSheetState();
}

class _EditTopicSheetState extends ConsumerState<_EditTopicSheet> {
  late final TextEditingController _name;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.initial);
  }

  @override
  void dispose() {
    _name.dispose();
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
            Text('Edit topic', style: AppTextStyles.section18),
            const SizedBox(height: 12),
            AppTextField(
              controller: _name,
              label: 'Topic name',
              hintText: 'Topic name',
              textCapitalization: TextCapitalization.sentences,
              autofocus: true,
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: PrimaryButton(
                label: 'Save Changes',
                onPressed: () {
                  widget.parentRef
                      .read(subjectsProvider.notifier)
                      .editTopic(
                        subjectId: widget.subjectId,
                        chapterId: widget.chapterId,
                        topicId: widget.topicId,
                        name: _name.text,
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
