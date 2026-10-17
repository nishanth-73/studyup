import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:studyup/features/quiz/data/quiz_bank.dart';
import 'package:studyup/features/quiz/data/quiz_models.dart';
import 'package:studyup/features/quiz/presentation/quiz_controller.dart';
import 'package:studyup/features/quiz/presentation/quiz_runner_screen.dart';
import 'package:studyup/features/quiz/presentation/quiz_screen.dart';

QuizBank testBank() => const QuizBank(
  quizzes: [
    Quiz(
      id: 't',
      title: 'Test Quiz',
      questions: [
        QuizQuestion(
          id: 'q-mcq',
          type: QuestionType.mcq,
          prompt: 'Pick A.',
          options: ['A', 'B'],
          correctIndex: 0,
        ),
        QuizQuestion(
          id: 'q-fill',
          type: QuestionType.fillBlank,
          prompt: 'Say ____ loudly.',
          acceptedAnswers: ['hi'],
        ),
      ],
    ),
  ],
);

Future<void> pumpRunner(WidgetTester tester) async {
  SharedPreferences.setMockInitialValues({});
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        quizBankProvider.overrideWith(
          (ref) async => const QuizBank(quizzes: []),
        ),
      ],
      child: const MaterialApp(
        home: Scaffold(body: QuizRunnerScreen(quizId: 't')),
      ),
    ),
  );
  await tester.pump();
}

/// Same as [pumpRunner] but with a usable two-question bank.
Future<void> pumpRunnerWithBank(WidgetTester tester) async {
  SharedPreferences.setMockInitialValues({});
  await tester.pumpWidget(
    ProviderScope(
      overrides: [quizBankProvider.overrideWith((ref) async => testBank())],
      child: const MaterialApp(
        home: Scaffold(body: QuizRunnerScreen(quizId: 't')),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

void main() {
  group('QuizRunner flow', () {
    testWidgets('unknown quiz id shows an error state', (tester) async {
      await pumpRunner(tester);
      expect(find.text('This quiz no longer exists.'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('answers survive back navigation and score on finish', (
      tester,
    ) async {
      await pumpRunnerWithBank(tester);
      // Q1: answer the MCQ, then move on.
      expect(find.text('Pick A.'), findsOneWidget);
      await tester.tap(find.text('A'));
      await tester.pump();
      await tester.tap(find.text('Next'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      // Q2: fill blank, then go back and confirm Q1 kept its answer.
      expect(find.text('Say _____ loudly.'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'hi');
      await tester.pump();
      await tester.tap(find.text('Back'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Pick A.'), findsOneWidget);
      // Finish from Q1 is disabled-safe: go forward and finish.
      await tester.tap(find.text('Next'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Say _____ loudly.'), findsOneWidget);
      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.controller!.text, 'hi');
      await tester.tap(find.text('Finish'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      // Both correct: 100%, counts shown, review lists both answers.
      expect(find.text('100%'), findsOneWidget);
      expect(find.textContaining('2 correct'), findsOneWidget);
      expect(find.textContaining('Your answer:'), findsWidgets);
      expect(tester.takeException(), isNull);
    });

    testWidgets('retry clears answers and restarts', (tester) async {
      await pumpRunnerWithBank(tester);
      await tester.tap(find.text('A'));
      await tester.pump();
      await tester.tap(find.text('Next'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('Finish'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('50%'), findsOneWidget);
      await tester.tap(find.text('Retry'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Pick A.'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('QuizScreen list', () {
    QuizBank twoQuizBank() => const QuizBank(
      quizzes: [
        Quiz(id: 'a', title: 'Alpha', questions: []),
        Quiz(id: 'b', title: 'Beta', questions: []),
      ],
    );

    testWidgets('shows titles, counts, and recorded best scores', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({'studyup.quizBest.a': 80});
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            quizBankProvider.overrideWith((ref) async => twoQuizBank()),
          ],
          child: const MaterialApp(home: Scaffold(body: QuizScreen())),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Alpha'), findsOneWidget);
      expect(find.text('Beta'), findsOneWidget);
      expect(find.textContaining('Best 80%'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
