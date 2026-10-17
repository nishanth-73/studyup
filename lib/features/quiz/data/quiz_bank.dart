import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'quiz_models.dart';

/// Loads the curated question bank. Malformed entries are skipped with a
/// recorded reason (mirroring the reference "skipped" reporting) instead
/// of failing the whole bank; a bank that yields nothing usable surfaces
/// as an explicit empty state in the UI.
@immutable
class QuizBank {
  final List<Quiz> quizzes;
  final List<String> skipped;

  const QuizBank({required this.quizzes, this.skipped = const []});

  static Future<QuizBank> load({
    String asset = 'assets/quiz/quiz_bank.json',
  }) async {
    try {
      final raw = await rootBundle.loadString(asset);
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, Object?>) {
        return const QuizBank(
          quizzes: [],
          skipped: ['bank root is not an object'],
        );
      }
      final quizzes = <Quiz>[];
      final skipped = <String>[];
      final list = decoded['quizzes'];
      if (list is! List) {
        return const QuizBank(
          quizzes: [],
          skipped: ['bank has no quizzes list'],
        );
      }
      for (final entry in list) {
        try {
          quizzes.add(_parseQuiz(entry));
        } catch (error) {
          skipped.add('$error');
        }
      }
      return QuizBank(
        quizzes: List.unmodifiable(quizzes),
        skipped: List.unmodifiable(skipped),
      );
    } catch (error) {
      return QuizBank(
        quizzes: const [],
        skipped: ['could not load bank: $error'],
      );
    }
  }

  static Quiz _parseQuiz(Object? entry) {
    if (entry is! Map<String, Object?>) {
      throw const FormatException('quiz entry is not an object');
    }
    final id = entry['id'] as String?;
    final title = entry['title'] as String?;
    if (id == null || id.isEmpty) {
      throw const FormatException('quiz missing id');
    }
    if (title == null || title.isEmpty) {
      throw FormatException('quiz $id missing title');
    }
    final rawQuestions = entry['questions'];
    if (rawQuestions is! List || rawQuestions.isEmpty) {
      throw FormatException('quiz $id has no questions');
    }
    final questions = <QuizQuestion>[];
    final seenPrompts = <String>{};
    for (final raw in rawQuestions) {
      try {
        if (raw is! Map<String, Object?>) {
          throw const FormatException('bad entry');
        }
        final q = QuizQuestion.fromJson(raw);
        final problems = q.validate();
        if (problems.isNotEmpty) {
          throw FormatException(
            'question ${q.id} invalid: ${problems.join(', ')}',
          );
        }
        // No duplicate prompts within one quiz (reference rule).
        if (!seenPrompts.add(normalizeAnswer(q.prompt))) {
          throw FormatException('duplicate prompt in quiz $id: ${q.id}');
        }
        questions.add(q);
      } catch (error) {
        throw FormatException('quiz $id: $error');
      }
    }
    if (questions.isEmpty) {
      throw FormatException('quiz $id has no valid questions');
    }
    return Quiz(
      id: id,
      title: title,
      description: entry['description'] as String? ?? '',
      questions: List.unmodifiable(questions),
    );
  }
}

/// Best-score persistence (SharedPreferences, the app's existing
/// strategy): percent per quiz id. Never throws; failures degrade to
/// "not attempted".
class QuizBestScores {
  QuizBestScores._();
  static String _key(String quizId) => 'studyup.quizBest.$quizId';

  static Future<int?> read(String quizId) async {
    try {
      return (await SharedPreferences.getInstance()).getInt(_key(quizId));
    } catch (_) {
      return null;
    }
  }

  static Future<Map<String, int>> readAll(Iterable<String> quizIds) async {
    final out = <String, int>{};
    try {
      final prefs = await SharedPreferences.getInstance();
      for (final id in quizIds) {
        final v = prefs.getInt(_key(id));
        if (v != null) out[id] = v;
      }
    } catch (_) {}
    return out;
  }

  static Future<void> record(String quizId, int percent) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final best = prefs.getInt(_key(quizId)) ?? -1;
      if (percent > best) await prefs.setInt(_key(quizId), percent);
    } catch (_) {}
  }
}
