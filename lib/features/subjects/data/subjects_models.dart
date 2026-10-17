import 'package:flutter/material.dart';

@immutable
class Topic {
  final String id;
  final String name;
  final bool done;
  const Topic({required this.id, required this.name, this.done = false});

  Topic copyWith({String? name, bool? done}) =>
      Topic(id: id, name: name ?? this.name, done: done ?? this.done);

  /// Spec aliases: TopicModel.title / isCompleted.
  String get title => name;
  bool get isCompleted => done;
}

/// Spec alias for gateway naming.
typedef TopicModel = Topic;

/// A named study source attached to a chapter: a link, PDF, or image.
/// [value] holds the URL (web link or hosted file) to open when tapped.
@immutable
class StudySource {
  final String id;
  final String name;
  final StudySourceKind kind;
  final String url;
  const StudySource({
    required this.id,
    required this.name,
    required this.kind,
    required this.url,
  });

  StudySource copyWith({String? name, StudySourceKind? kind, String? url}) =>
      StudySource(
        id: id,
        name: name ?? this.name,
        kind: kind ?? this.kind,
        url: url ?? this.url,
      );
}

enum StudySourceKind { link, pdf, image }

/// Spec alias for gateway naming.
typedef StudySourceModel = StudySource;

@immutable
class Chapter {
  final String id;
  final String title;
  final List<Topic> topics;
  final List<StudySource> sources;
  const Chapter({
    required this.id,
    required this.title,
    required this.topics,
    this.sources = const [],
  });

  Chapter copyWith({
    String? title,
    List<Topic>? topics,
    List<StudySource>? sources,
  }) => Chapter(
    id: id,
    title: title ?? this.title,
    topics: topics ?? this.topics,
    sources: sources ?? this.sources,
  );

  int get total => topics.length;
  int get done => topics.where((t) => t.done).length;
  double get ratio => total == 0 ? 0 : done / total;
  String get label => total == 0 ? '0 / 0 topics' : '$done / $total topics';
  String get percent => '${(ratio * 100).round()}%';

  /// Spec: chapter is 100% complete only when it has topics and ALL are done.
  /// Empty chapters never count as complete.
  bool get isChapterCompleted =>
      topics.isNotEmpty && topics.every((t) => t.done);
}

/// Spec alias for gateway naming.
typedef ChapterModel = Chapter;

@immutable
class Subject {
  final String id;
  final String name;
  final String meta;
  final String weekHours;
  final Color color;
  final IconData icon;
  final String totalHours;
  final List<Chapter> chapters;
  final bool pinned;
  final int studyGoalMinutes;
  final bool archived;
  const Subject({
    required this.id,
    required this.name,
    required this.meta,
    required this.weekHours,
    required this.color,
    required this.icon,
    required this.totalHours,
    required this.chapters,
    this.pinned = false,
    this.studyGoalMinutes = 200,
    this.archived = false,
  });

  Subject copyWith({
    String? name,
    String? meta,
    String? weekHours,
    Color? color,
    IconData? icon,
    String? totalHours,
    List<Chapter>? chapters,
    bool? pinned,
    int? studyGoalMinutes,
    bool? archived,
  }) {
    return Subject(
      id: id,
      name: name ?? this.name,
      meta: meta ?? this.meta,
      weekHours: weekHours ?? this.weekHours,
      color: color ?? this.color,
      icon: icon ?? this.icon,
      totalHours: totalHours ?? this.totalHours,
      chapters: chapters ?? this.chapters,
      pinned: pinned ?? this.pinned,
      studyGoalMinutes: studyGoalMinutes ?? this.studyGoalMinutes,
      archived: archived ?? this.archived,
    );
  }

  int get topicTotal => chapters.fold(0, (s, c) => s + c.total);
  int get topicDone => chapters.fold(0, (s, c) => s + c.done);
  double get ratio => topicTotal == 0 ? 0 : topicDone / topicTotal;
  String get percent => '${(ratio * 100).round()}%';
  String get completeLabel => '$percent complete';

  /// Spec Chapter-based progress (replaces time-based metrics on cards).
  /// Subject Progress % = completedChapters / totalChapters * 100.
  int get totalChapters => chapters.length;
  int get completedChapters =>
      chapters.where((c) => c.isChapterCompleted).length;
  double get chapterRatio =>
      totalChapters == 0 ? 0 : completedChapters / totalChapters;
  double get progressPercentage => chapterRatio * 100;
  double get progressRatio => chapterRatio;
  String get chapterPercent => '${progressPercentage.round()}%';
  String get chapterLabel =>
      'Total Chapters: $totalChapters · Completed: $completedChapters';
}

/// Spec alias for gateway naming (persisted via existing Subject storage).
typedef SubjectModel = Subject;
