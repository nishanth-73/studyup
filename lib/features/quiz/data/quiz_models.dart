import 'dart:math';

import 'package:flutter/foundation.dart';

/// Question engine ported from the reference contracts in
/// `C:\Users\medur\Downloads\quiz` (pytest suite for a Python generation
/// engine whose `app/` implementation is NOT shipped — only the tests).
///
/// What is faithfully reused here, per the reference test expectations:
/// - the five question types (MCQ, true/false, fill-in-the-blank,
///   matching, subjective),
/// - validation rules (unique/distinct options, exactly one blank that
///   rebuilds its source, 3–6 non-identity matching pairs, subjective
///   reference answers),
/// - grading semantics (tolerant-but-not-fuzzy normalization, partial
///   matching counts, subjective always self-review, blank as unanswered).
///
/// What is NOT ported (absent from the reference): the NLP generation
/// pipeline (PDF extraction, text cleaning, fact extraction, per-type
/// generators). Question content therefore ships as a curated,
/// pre-validated bank (see `assets/quiz/quiz_bank.json`). No AI, network,
/// or mock generation is involved.
///
/// Every question is worth exactly 1 mark: the reference defines no
/// per-question marks, so uniform scoring is the faithful choice.

/// Blank marker used inside fill-in-the-blank prompts (exactly one per
/// prompt, mirroring the reference BLANK constant).
const String blankMarker = '____';

/// The five question types genuinely specified by the reference tests.
enum QuestionType {
  mcq,
  trueFalse,
  fillBlank,
  matching,
  subjective;

  static QuestionType? fromJson(String? raw) {
    switch (raw) {
      case 'mcq':
        return QuestionType.mcq;
      case 'true_false':
        return QuestionType.trueFalse;
      case 'fill_blank':
        return QuestionType.fillBlank;
      case 'matching':
        return QuestionType.matching;
      case 'subjective':
        return QuestionType.subjective;
      default:
        return null;
    }
  }

  String get label {
    switch (this) {
      case QuestionType.mcq:
        return 'Multiple choice';
      case QuestionType.trueFalse:
        return 'True or false';
      case QuestionType.fillBlank:
        return 'Fill in the blank';
      case QuestionType.matching:
        return 'Match the following';
      case QuestionType.subjective:
        return 'Short answer';
    }
  }
}

@immutable
class QuizQuestion {
  final String id;
  final QuestionType type;
  final String prompt;

  /// MCQ: answer choices in display order.
  final List<String> options;

  /// MCQ: index into [options] of the correct answer.
  final int? correctIndex;

  /// True/false: the correct boolean value.
  final bool? boolAnswer;

  /// True/false (false variants): swapped fragments, mirroring the
  /// reference original_fragment / replacement_fragment fields
  /// (empty unless the variant needs them).
  final String originalFragment;
  final String replacementFragment;

  /// Fill-in-the-blank: accepted answers (first is primary).
  final List<String> acceptedAnswers;

  /// Matching: left terms and right definitions in canonical (aligned)
  /// order; [pairs] maps each left index to its match's DISPLAY position
  /// in [displayRight], and is never the identity order.
  final List<String> leftItems;
  final List<String> rightItems;

  /// Matching: display order of [rightItems] (canonical indices), shuffled
  /// deterministically from the question id.
  final List<int> displayRight;

  /// Matching: answer key mapping left index -> display position.
  final List<int> pairs;

  /// Subjective: reference answer shown at review time.
  final String referenceAnswer;

  /// Subjective: reference bullet items, if any.
  final List<String> referenceItems;

  /// Traceability note (e.g. source sentence), kept from the reference
  /// model where questions always carry their source.
  final String source;

  const QuizQuestion({
    required this.id,
    required this.type,
    required this.prompt,
    this.options = const [],
    this.correctIndex,
    this.boolAnswer,
    this.originalFragment = '',
    this.replacementFragment = '',
    this.acceptedAnswers = const [],
    this.leftItems = const [],
    this.rightItems = const [],
    this.displayRight = const [],
    this.pairs = const [],
    this.referenceAnswer = '',
    this.referenceItems = const [],
    this.source = '',
  });

  /// Parses one bank entry, throwing [FormatException] on malformed data
  /// so the loader can skip it with a reason instead of crashing.
  factory QuizQuestion.fromJson(Map<String, Object?> json) {
    final id = json['id'] as String?;
    final type = QuestionType.fromJson(json['type'] as String?);
    final prompt = json['prompt'] as String?;
    if (id == null || id.isEmpty) {
      throw const FormatException('question is missing id');
    }
    if (type == null) {
      throw FormatException('question $id has unknown type');
    }
    if (prompt == null || prompt.trim().isEmpty) {
      throw FormatException('question $id has an empty prompt');
    }
    String str(String key) => (json[key] as String? ?? '').trim();
    List<String> strList(String key) => [
      for (final v in (json[key] as List? ?? const [])) v.toString(),
    ];

    var options = const <String>[];
    int? correctIndex;
    bool? boolAnswer;
    var acceptedAnswers = const <String>[];
    var leftItems = const <String>[];
    var rightItems = const <String>[];
    var displayRight = const <int>[];
    var pairs = const <int>[];
    var originalFragment = '';
    var replacementFragment = '';
    var referenceAnswer = '';
    var referenceItems = const <String>[];

    switch (type) {
      case QuestionType.mcq:
        options = strList('options');
        final rawIndex = json['correctIndex'];
        correctIndex = rawIndex is int ? rawIndex : int.tryParse('$rawIndex');
      case QuestionType.trueFalse:
        final raw = json['answer'];
        if (raw is bool) {
          boolAnswer = raw;
        } else if (raw is String) {
          final lower = raw.toLowerCase();
          if (lower == 'true') boolAnswer = true;
          if (lower == 'false') boolAnswer = false;
        }
        originalFragment = str('originalFragment');
        replacementFragment = str('replacementFragment');
      case QuestionType.fillBlank:
        acceptedAnswers = strList('answers');
      case QuestionType.matching:
        leftItems = strList('left');
        rightItems = strList('right');
        final order = List<int>.generate(rightItems.length, (i) => i);
        order.shuffle(Random(id.hashCode));
        if (_isIdentity(order)) {
          // Guarantee the key is never presented in identity order.
          final last = order.removeLast();
          order.insert(0, last);
        }
        displayRight = List.unmodifiable(order);
        final key = List<int>.filled(leftItems.length, 0);
        for (var display = 0; display < order.length; display++) {
          if (order[display] < key.length) key[order[display]] = display;
        }
        pairs = List.unmodifiable(key);
      case QuestionType.subjective:
        referenceAnswer = str('reference');
        referenceItems = strList('referenceItems');
    }

    return QuizQuestion(
      id: id,
      type: type,
      prompt: prompt,
      options: List.unmodifiable(options),
      correctIndex: correctIndex,
      boolAnswer: boolAnswer,
      originalFragment: originalFragment,
      replacementFragment: replacementFragment,
      acceptedAnswers: List.unmodifiable(acceptedAnswers),
      leftItems: List.unmodifiable(leftItems),
      rightItems: List.unmodifiable(rightItems),
      displayRight: displayRight,
      pairs: pairs,
      referenceAnswer: referenceAnswer,
      referenceItems: List.unmodifiable(referenceItems),
      source: str('source'),
    );
  }

  /// Structural validation mirroring the reference validator: returns an
  /// empty list when the question is usable.
  List<String> validate() {
    final problems = <String>[];
    if (prompt.trim().isEmpty) problems.add('empty prompt');
    switch (type) {
      case QuestionType.mcq:
        if (options.length < 2) {
          problems.add('fewer than 2 options');
        }
        if (options.any((o) => o.trim().isEmpty)) {
          problems.add('empty option');
        }
        final normalized = options.map(normalizeAnswer).toList();
        if (normalized.toSet().length != normalized.length) {
          problems.add('duplicate options');
        }
        if (correctIndex == null ||
            correctIndex! < 0 ||
            correctIndex! >= options.length) {
          problems.add('missing or invalid answer key');
        }
      case QuestionType.trueFalse:
        final answer = boolAnswer;
        if (answer == null) problems.add('missing boolean answer');
        if (answer == false &&
            (originalFragment.isEmpty || replacementFragment.isEmpty)) {
          problems.add('false variant missing fragments');
        }
        // When a source sentence is recorded, true statements must match
        // it verbatim and false ones must restore it by swapping the
        // replacement fragment back (reference traceability rule).
        if (source.trim().isNotEmpty && answer != null) {
          if (answer) {
            if (normalizeAnswer(prompt) != normalizeAnswer(source)) {
              problems.add('true statement differs from source');
            }
          } else if (originalFragment.isNotEmpty &&
              replacementFragment.isNotEmpty) {
            final restored = normalizeAnswer(
              prompt.replaceFirst(replacementFragment, originalFragment),
            );
            if (restored != normalizeAnswer(source)) {
              problems.add('false variant does not map to source');
            }
          }
        }
      case QuestionType.fillBlank:
        if (prompt.split(blankMarker).length - 1 != 1) {
          problems.add('prompt must contain exactly one blank');
        }
        if (acceptedAnswers.isEmpty ||
            acceptedAnswers.any((a) => a.trim().isEmpty)) {
          problems.add('missing accepted answer');
        } else {
          // The answer must not already sit elsewhere in the prompt.
          final withoutBlank = normalizeAnswer(
            prompt.replaceFirst(blankMarker, ' '),
          ).split(' ');
          if (withoutBlank.contains(normalizeAnswer(acceptedAnswers.first))) {
            problems.add('answer leaked in prompt');
          }
          // When a source sentence is recorded, the blank must rebuild
          // it exactly (reference traceability rule).
          if (source.trim().isNotEmpty) {
            final rebuilt = normalizeAnswer(
              prompt.replaceFirst(blankMarker, acceptedAnswers.first),
            );
            if (rebuilt != normalizeAnswer(source)) {
              problems.add('blank does not rebuild its source');
            }
          }
        }
      case QuestionType.matching:
        if (leftItems.length < 3 || leftItems.length > 6) {
          problems.add('matching needs 3-6 pairs');
        }
        if (rightItems.length != leftItems.length) {
          problems.add('left/right length mismatch');
        }
        if ([...leftItems, ...rightItems].any((s) => s.trim().isEmpty)) {
          problems.add('empty matching item');
        }
        if (pairs.length != leftItems.length ||
            pairs.toSet().length != pairs.length ||
            pairs.any((p) => p < 0 || p >= leftItems.length)) {
          problems.add('invalid pairs key');
        }
        if (_isIdentity(pairs)) {
          problems.add('key presented in identity order');
        }
      case QuestionType.subjective:
        if (referenceAnswer.isEmpty) problems.add('missing reference answer');
        // Reference items must not leak into the prompt.
        final cleanPrompt = normalizeAnswer(prompt);
        for (final item in referenceItems) {
          final needle = normalizeAnswer(item.replaceAll(RegExp(r'[.]+$'), ''));
          if (needle.isNotEmpty && cleanPrompt.contains(needle)) {
            problems.add('reference leaked in prompt');
            break;
          }
        }
    }
    return problems;
  }
}

bool _isIdentity(List<int> order) {
  for (var i = 0; i < order.length; i++) {
    if (order[i] != i) return false;
  }
  return true;
}

@immutable
class Quiz {
  final String id;
  final String title;
  final String description;
  final List<QuizQuestion> questions;

  const Quiz({
    required this.id,
    required this.title,
    this.description = '',
    required this.questions,
  });
}

/// Answer grading, ported from the reference scorer semantics.
enum GradeStatus { correct, incorrect, unanswered, selfReview }

@immutable
class GradeResult {
  final GradeStatus status;

  /// Matching only: correctly linked pairs / total pairs.
  final int pairsCorrect;
  final int pairsTotal;

  const GradeResult(this.status, {this.pairsCorrect = 0, this.pairsTotal = 0});
}

/// Normalizes a free-text answer for comparison (reference
/// `normalize_answer` semantics): case/space/punctuation tolerant,
/// articles dropped unless the whole answer, numbers unformatted —
/// but never fuzzy (typos stay wrong).
String normalizeAnswer(String? raw) {
  if (raw == null) return '';
  var s = raw.toLowerCase().trim();
  s = s
      .replaceAll('\u201c', '"')
      .replaceAll('\u201d', '"')
      .replaceAll("'", '')
      .replaceAll('-', ' ');
  s = s.replaceAll(RegExp(r'[.,;:!?()"\[\]]'), '');
  s = s.replaceAll(',', '');
  s = s.replaceAll(RegExp(r'\s+'), ' ').trim();
  for (final article in ['the ', 'an ', 'a ']) {
    if (s.startsWith(article) && s.length > article.length) {
      s = s.substring(article.length);
      break;
    }
  }
  return s;
}

/// Grades one answer. Answer shapes per type:
/// - MCQ: `int?` option index.
/// - True/false: `bool?`.
/// - Fill-in-the-blank / subjective: `String?` raw text.
/// - Matching: `Map<int, int>?` left canonical index -> right DISPLAY
///   position (use [matchingSelection] to build it from UI taps).
GradeResult gradeQuestion(QuizQuestion q, Object? answer) {
  switch (q.type) {
    case QuestionType.mcq:
      if (answer == null) return const GradeResult(GradeStatus.unanswered);
      final index = answer is int ? answer : int.tryParse('$answer');
      if (index == null) return const GradeResult(GradeStatus.unanswered);
      if (index < 0 || index >= q.options.length) {
        return const GradeResult(GradeStatus.incorrect);
      }
      return GradeResult(
        index == q.correctIndex ? GradeStatus.correct : GradeStatus.incorrect,
      );
    case QuestionType.trueFalse:
      if (answer == null) return const GradeResult(GradeStatus.unanswered);
      final value = answer is bool
          ? answer
          : answer.toString().toLowerCase() == 'true';
      return GradeResult(
        value == q.boolAnswer ? GradeStatus.correct : GradeStatus.incorrect,
      );
    case QuestionType.fillBlank:
      final text = answer?.toString() ?? '';
      if (text.trim().isEmpty) {
        return const GradeResult(GradeStatus.unanswered);
      }
      final given = normalizeAnswer(text);
      final ok = q.acceptedAnswers.any((a) => normalizeAnswer(a) == given);
      return GradeResult(ok ? GradeStatus.correct : GradeStatus.incorrect);
    case QuestionType.matching:
      if (answer == null) return const GradeResult(GradeStatus.unanswered);
      final map = answer is Map
          ? Map<int, int>.fromEntries(
              answer.entries.map(
                (e) => MapEntry(int.parse('${e.key}'), int.parse('${e.value}')),
              ),
            )
          : <int, int>{};
      if (map.isEmpty) return const GradeResult(GradeStatus.unanswered);
      var correct = 0;
      for (var i = 0; i < q.pairs.length; i++) {
        if (map[i] == q.pairs[i]) correct++;
      }
      final complete =
          map.length == q.pairs.length && correct == q.pairs.length;
      return GradeResult(
        complete ? GradeStatus.correct : GradeStatus.incorrect,
        pairsCorrect: correct,
        pairsTotal: q.pairs.length,
      );
    case QuestionType.subjective:
      // Self-review by design: viewing the reference is the exercise,
      // never an auto-score — even for blank answers.
      return const GradeResult(GradeStatus.selfReview);
  }
}

/// Builds a matching answer map from UI taps: left canonical index ->
/// right display position.
Map<int, int> matchingSelection(Map<int, int> picks) =>
    Map<int, int>.from(picks);

/// Attempt scoring over auto-gradable questions. Subjective items are
/// reported separately and never dilute the percentage.
@immutable
class AttemptScore {
  final int correct;
  final int incorrect;
  final int unanswered;
  final int selfReview;
  final int scorableTotal;

  const AttemptScore({
    required this.correct,
    required this.incorrect,
    required this.unanswered,
    required this.selfReview,
    required this.scorableTotal,
  });

  double? get percent => scorableTotal == 0
      ? null
      : (correct / scorableTotal * 100).roundToDouble();

  static AttemptScore evaluate(
    List<QuizQuestion> questions,
    Map<String, Object?> answers,
  ) {
    var correct = 0;
    var incorrect = 0;
    var unanswered = 0;
    var selfReview = 0;
    var scorable = 0;
    for (final q in questions) {
      final result = gradeQuestion(q, answers[q.id]);
      switch (result.status) {
        case GradeStatus.correct:
          correct++;
          scorable++;
        case GradeStatus.incorrect:
          incorrect++;
          scorable++;
        case GradeStatus.unanswered:
          unanswered++;
          scorable++;
        case GradeStatus.selfReview:
          selfReview++;
      }
    }
    return AttemptScore(
      correct: correct,
      incorrect: incorrect,
      unanswered: unanswered,
      selfReview: selfReview,
      scorableTotal: scorable,
    );
  }
}
