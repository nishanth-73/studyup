import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/quiz_bank.dart';
import '../data/quiz_models.dart';

/// The curated question bank (loaded once from the bundled asset).
final quizBankProvider = FutureProvider<QuizBank>((_) => QuizBank.load());

/// Best score percent per quiz id (empty until an attempt is recorded).
final quizBestScoresProvider = FutureProvider<Map<String, int>>((ref) async {
  final bank = await ref.watch(quizBankProvider.future);
  return QuizBestScores.readAll(bank.quizzes.map((q) => q.id));
});

/// Lookup helper for the runner route.
Quiz? quizById(QuizBank bank, String quizId) {
  for (final quiz in bank.quizzes) {
    if (quiz.id == quizId) return quiz;
  }
  return null;
}
