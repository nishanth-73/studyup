import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/seed/starter_data.dart';
import '../data/subjects_models.dart';

int _n = 0;
String _uid(String prefix) =>
    '$prefix${DateTime.now().microsecondsSinceEpoch}_${_n++}';

class SubjectsController extends StateNotifier<List<Subject>> {
  SubjectsController() : super(const []) {
    unawaited(_load());
  }

  static const _storageKey = 'studyup.subjects.v1';

  /// Set once the starter library has been considered (seeded or skipped).
  /// Never reset: deleting the examples must not bring them back, and
  /// upgrades must never overwrite real academic data.
  static const _starterFlagKey = 'studyup.subjects.starterSeeded.v1';
  final Completer<void> _loaded = Completer<void>();
  Future<void> _writeQueue = Future<void>.value();

  Future<void> _load() async {
    try {
      final preferences = await SharedPreferences.getInstance();
      if (!mounted) return;
      final raw = preferences.getString(_storageKey);
      final seeded = preferences.getBool(_starterFlagKey) ?? false;
      if (raw == null) {
        // Genuinely new user (no stored subjects at all): seed the
        // Mathematics + Physics starter library once. Fully editable and
        // deletable like any user-created subject. Subjects added before
        // loading finished are kept first, never overwritten.
        if (!seeded) {
          final knownIds = state.map((subject) => subject.id).toSet();
          final fresh = [
            for (final subject in StarterData.defaultSubjects())
              if (!knownIds.contains(subject.id)) subject,
          ];
          if (fresh.isNotEmpty) {
            state = List.unmodifiable([...state, ...fresh]);
          }
          await preferences.setBool(_starterFlagKey, true);
          if (!mounted) return;
          if (fresh.isNotEmpty) unawaited(_persist());
        }
        return;
      }
      final stored = (jsonDecode(raw) as List<Object?>)
          .map(
            (entry) =>
                _subjectFromJson(Map<String, Object?>.from(entry! as Map)),
          )
          .toList();
      final knownIds = stored.map((subject) => subject.id).toSet();
      final pending = state.where((subject) => !knownIds.contains(subject.id));
      if (!mounted) return;
      state = List.unmodifiable([...stored, ...pending]);
      // Existing users keep their data untouched; record the starter
      // decision so the examples are never seeded on top of real data.
      if (!seeded) await preferences.setBool(_starterFlagKey, true);
      if (pending.isNotEmpty) unawaited(_persist());
    } catch (error, stackTrace) {
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stackTrace,
          library: 'subjects',
          context: ErrorDescription('while loading persisted subjects'),
        ),
      );
    } finally {
      if (!_loaded.isCompleted) _loaded.complete();
    }
  }

  void _commit(List<Subject> subjects) {
    state = List.unmodifiable(subjects);
    unawaited(_persist());
  }

  Future<void> _persist() async {
    // Snapshot synchronously: the writes below may outlive the controller
    // when a test disposes it mid-flight, and must never touch `state` then.
    final encoded = jsonEncode(state.map(_subjectToJson).toList());
    try {
      await _loaded.future;
      final preferences = await SharedPreferences.getInstance();
      final write = _writeQueue.catchError((Object _) {}).then((_) async {
        final saved = await preferences.setString(_storageKey, encoded);
        if (!saved) throw StateError('Could not persist subjects.');
      });
      _writeQueue = write;
      await write;
    } catch (error, stackTrace) {
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stackTrace,
          library: 'subjects',
          context: ErrorDescription('while saving subject changes'),
        ),
      );
    }
  }

  Subject _withChapters(Subject subject, List<Chapter> chapters) =>
      subject.copyWith(chapters: chapters);

  void addChapter({required String subjectId, required String title}) {
    final value = title.trim().isEmpty ? 'New Chapter' : title.trim();
    _commit([
      for (final subject in state)
        if (subject.id != subjectId)
          subject
        else
          _withChapters(subject, [
            ...subject.chapters,
            Chapter(id: _uid('chapter'), title: value, topics: const []),
          ]),
    ]);
  }

  void renameChapter({
    required String subjectId,
    required String chapterId,
    required String title,
  }) {
    final value = title.trim();
    if (value.isEmpty) return;
    _commit([
      for (final subject in state)
        if (subject.id != subjectId)
          subject
        else
          _withChapters(subject, [
            for (final chapter in subject.chapters)
              if (chapter.id != chapterId)
                chapter
              else
                chapter.copyWith(title: value),
          ]),
    ]);
  }

  void deleteChapter({required String subjectId, required String chapterId}) {
    _commit([
      for (final subject in state)
        if (subject.id != subjectId)
          subject
        else
          _withChapters(subject, [
            for (final chapter in subject.chapters)
              if (chapter.id != chapterId) chapter,
          ]),
    ]);
  }

  void addTopic({
    required String subjectId,
    required String chapterId,
    required String name,
  }) {
    final value = name.trim();
    if (value.isEmpty) return;
    _commit([
      for (final subject in state)
        if (subject.id != subjectId)
          subject
        else
          _withChapters(subject, [
            for (final chapter in subject.chapters)
              if (chapter.id != chapterId)
                chapter
              else
                chapter.copyWith(
                  topics: [
                    ...chapter.topics,
                    Topic(id: _uid('topic'), name: value),
                  ],
                ),
          ]),
    ]);
  }

  void toggleTopic({
    required String subjectId,
    required String chapterId,
    required String topicId,
  }) {
    _commit([
      for (final subject in state)
        if (subject.id != subjectId)
          subject
        else
          _withChapters(subject, [
            for (final chapter in subject.chapters)
              if (chapter.id != chapterId)
                chapter
              else
                chapter.copyWith(
                  topics: [
                    for (final topic in chapter.topics)
                      if (topic.id != topicId)
                        topic
                      else
                        topic.copyWith(done: !topic.done),
                  ],
                ),
          ]),
    ]);
  }

  void editTopic({
    required String subjectId,
    required String chapterId,
    required String topicId,
    required String name,
  }) {
    final value = name.trim();
    if (value.isEmpty) return;
    _commit([
      for (final subject in state)
        if (subject.id != subjectId)
          subject
        else
          _withChapters(subject, [
            for (final chapter in subject.chapters)
              if (chapter.id != chapterId)
                chapter
              else
                chapter.copyWith(
                  topics: [
                    for (final topic in chapter.topics)
                      if (topic.id != topicId)
                        topic
                      else
                        topic.copyWith(name: value),
                  ],
                ),
          ]),
    ]);
  }

  void deleteTopic({
    required String subjectId,
    required String chapterId,
    required String topicId,
  }) {
    _commit([
      for (final subject in state)
        if (subject.id != subjectId)
          subject
        else
          _withChapters(subject, [
            for (final chapter in subject.chapters)
              if (chapter.id != chapterId)
                chapter
              else
                chapter.copyWith(
                  topics: [
                    for (final topic in chapter.topics)
                      if (topic.id != topicId) topic,
                  ],
                ),
          ]),
    ]);
  }

  void addSource({
    required String subjectId,
    required String chapterId,
    required String name,
    required StudySourceKind kind,
    required String url,
  }) {
    final title = name.trim().isEmpty ? 'Untitled source' : name.trim();
    final link = url.trim();
    if (link.isEmpty) return;
    _commit([
      for (final subject in state)
        if (subject.id != subjectId)
          subject
        else
          _withChapters(subject, [
            for (final chapter in subject.chapters)
              if (chapter.id != chapterId)
                chapter
              else
                chapter.copyWith(
                  sources: [
                    ...chapter.sources,
                    StudySource(
                      id: _uid('source'),
                      name: title,
                      kind: kind,
                      url: link,
                    ),
                  ],
                ),
          ]),
    ]);
  }

  void deleteSource({
    required String subjectId,
    required String chapterId,
    required String sourceId,
  }) {
    _commit([
      for (final subject in state)
        if (subject.id != subjectId)
          subject
        else
          _withChapters(subject, [
            for (final chapter in subject.chapters)
              if (chapter.id != chapterId)
                chapter
              else
                chapter.copyWith(
                  sources: [
                    for (final source in chapter.sources)
                      if (source.id != sourceId) source,
                  ],
                ),
          ]),
    ]);
  }

  void addSubject({required String name, required String meta}) {
    final value = name.trim().isEmpty ? 'New Subject' : name.trim();
    final description = meta.trim().isEmpty ? 'Custom subject' : meta.trim();
    const palette = [
      AppColors.cta,
      AppColors.green,
      AppColors.blue,
      AppColors.pink,
      AppColors.primary,
    ];
    final visibleCount = state.where((subject) => !subject.archived).length;
    _commit([
      ...state,
      Subject(
        id: _uid('subject'),
        name: value,
        meta: description,
        weekHours: '',
        totalHours: '',
        color: palette[visibleCount % palette.length],
        icon: Icons.book,
        chapters: [
          Chapter(id: _uid('chapter'), title: 'Chapter 1', topics: const []),
        ],
      ),
    ]);
  }

  void editSubject({
    required String subjectId,
    required String name,
    required String meta,
  }) {
    _commit([
      for (final subject in state)
        if (subject.id != subjectId)
          subject
        else
          subject.copyWith(
            name: name.trim().isEmpty ? subject.name : name.trim(),
            meta: meta.trim().isEmpty ? subject.meta : meta.trim(),
          ),
    ]);
    _sortPinned();
  }

  void deleteSubject(String subjectId) {
    _commit([
      for (final subject in state)
        if (subject.id == subjectId)
          subject.copyWith(archived: true)
        else
          subject,
    ]);
  }

  void togglePin(String subjectId) {
    _commit([
      for (final subject in state)
        if (subject.id == subjectId)
          subject.copyWith(pinned: !subject.pinned)
        else
          subject,
    ]);
    _sortPinned();
  }

  void _sortPinned() {
    final pinned = [
      for (final subject in state)
        if (subject.pinned) subject,
    ];
    final rest = [
      for (final subject in state)
        if (!subject.pinned) subject,
    ];
    _commit([...pinned, ...rest]);
  }
}

Map<String, Object?> _subjectToJson(Subject subject) => {
  'id': subject.id,
  'name': subject.name,
  'meta': subject.meta,
  'color': subject.color.toARGB32(),
  'pinned': subject.pinned,
  'archived': subject.archived,
  'studyGoalMinutes': subject.studyGoalMinutes,
  'chapters': [
    for (final chapter in subject.chapters)
      {
        'id': chapter.id,
        'title': chapter.title,
        'topics': [
          for (final topic in chapter.topics)
            {'id': topic.id, 'name': topic.name, 'done': topic.done},
        ],
        'sources': [
          for (final source in chapter.sources)
            {
              'id': source.id,
              'name': source.name,
              'kind': source.kind.name,
              'url': source.url,
            },
        ],
      },
  ],
};

Subject _subjectFromJson(Map<String, Object?> json) => Subject(
  id: json['id']! as String,
  name: json['name']! as String,
  meta: json['meta']! as String,
  weekHours: '',
  totalHours: '',
  color: Color(json['color']! as int),
  icon: Icons.book,
  pinned: json['pinned'] as bool? ?? false,
  archived: json['archived'] as bool? ?? false,
  studyGoalMinutes: json['studyGoalMinutes'] as int? ?? 200,
  chapters: [
    for (final entry in (json['chapters'] as List<Object?>? ?? const []))
      Chapter(
        id: (entry as Map)['id']! as String,
        title: entry['title']! as String,
        topics: [
          for (final topicEntry
              in (entry['topics'] as List<Object?>? ?? const []))
            Topic(
              id: (topicEntry as Map)['id']! as String,
              name: topicEntry['name']! as String,
              done: topicEntry['done'] as bool? ?? false,
            ),
        ],
        sources: [
          for (final sourceEntry
              in (entry['sources'] as List<Object?>? ?? const []))
            StudySource(
              id: (sourceEntry as Map)['id']! as String,
              name: sourceEntry['name'] as String? ?? 'Untitled source',
              kind:
                  StudySourceKind.values.asNameMap()[sourceEntry['kind']
                      as String?] ??
                  StudySourceKind.link,
              url: sourceEntry['url'] as String? ?? '',
            ),
        ],
      ),
  ],
);

final subjectsProvider =
    StateNotifierProvider<SubjectsController, List<Subject>>(
      (ref) => SubjectsController(),
    );

Subject? subjectById(List<Subject> subjects, String id) {
  for (final subject in subjects) {
    if (subject.id == id && !subject.archived) return subject;
  }
  return null;
}
