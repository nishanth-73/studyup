import 'package:flutter_test/flutter_test.dart';
import 'package:studyup/features/quiz/data/quiz_bank.dart';
import 'package:studyup/features/quiz/data/quiz_models.dart';

QuizQuestion mcqFixture() => const QuizQuestion(
  id: 'mcq-1',
  type: QuestionType.mcq,
  prompt: 'Gravity was formulated by ____.',
  options: ['Isaac Newton', 'Albert Einstein', 'Galileo', 'Tesla'],
  correctIndex: 0,
);

QuizQuestion matchingFixture() => const QuizQuestion(
  id: 'match-1',
  type: QuestionType.matching,
  prompt: 'Match each term.',
  leftItems: ['A', 'B', 'C'],
  rightItems: ['a-def', 'b-def', 'c-def'],
  displayRight: [2, 0, 1],
  pairs: [2, 0, 1],
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('normalizeAnswer (reference table)', () {
    const cases = {
      '  ALEXANDER   Fleming ': 'alexander fleming',
      'The Nucleus.': 'nucleus',
      'an organelle': 'organelle',
      '1,000': '1000',
      '\u201cRAM\u201d': 'ram',
      'Self-Study': 'self study',
      'the': 'the',
    };
    cases.forEach((given, expected) {
      test('"$given" -> "$expected"', () {
        expect(normalizeAnswer(given), expected);
      });
    });
  });

  group('gradeQuestion per type', () {
    test('mcq correct/incorrect/unanswered', () {
      expect(gradeQuestion(mcqFixture(), 0).status, GradeStatus.correct);
      expect(gradeQuestion(mcqFixture(), 2).status, GradeStatus.incorrect);
      expect(gradeQuestion(mcqFixture(), null).status, GradeStatus.unanswered);
      expect(gradeQuestion(mcqFixture(), 9).status, GradeStatus.incorrect);
    });

    test('fill-blank tolerant but not fuzzy', () {
      const q = QuizQuestion(
        id: 'fill-1',
        type: QuestionType.fillBlank,
        prompt: 'Penicillin was discovered by ____.',
        acceptedAnswers: ['Alexander Fleming'],
      );
      expect(
        gradeQuestion(q, '  alexander   FLEMING. ').status,
        GradeStatus.correct,
      );
      expect(gradeQuestion(q, 'Fleming').status, GradeStatus.incorrect);
      expect(
        gradeQuestion(q, 'Alexander Flemming').status,
        GradeStatus.incorrect,
      );
      expect(gradeQuestion(q, '   ').status, GradeStatus.unanswered);
      expect(gradeQuestion(q, null).status, GradeStatus.unanswered);
    });

    test('true/false with null as unanswered', () {
      const q = QuizQuestion(
        id: 'tf-1',
        type: QuestionType.trueFalse,
        prompt: 'Force is measured in newtons.',
        boolAnswer: true,
      );
      expect(gradeQuestion(q, true).status, GradeStatus.correct);
      expect(gradeQuestion(q, false).status, GradeStatus.incorrect);
      expect(gradeQuestion(q, null).status, GradeStatus.unanswered);
    });

    test('matching perfect/swap/partial/empty', () {
      final q = matchingFixture();
      final perfect = {0: 2, 1: 0, 2: 1};
      final graded = gradeQuestion(q, perfect);
      expect(graded.status, GradeStatus.correct);
      expect(graded.pairsCorrect, 3);

      final swapped = {0: 0, 1: 2, 2: 1};
      final wrong = gradeQuestion(q, swapped);
      expect(wrong.status, GradeStatus.incorrect);
      expect(wrong.pairsCorrect, 1);
      expect(wrong.pairsTotal, 3);

      expect(gradeQuestion(q, {0: 2}).status, GradeStatus.incorrect);
      expect(gradeQuestion(q, {}).status, GradeStatus.unanswered);
      expect(gradeQuestion(q, null).status, GradeStatus.unanswered);
    });

    test('subjective is always self-review', () {
      const q = QuizQuestion(
        id: 'sub-1',
        type: QuestionType.subjective,
        prompt: 'Define it.',
        referenceAnswer: 'It is defined.',
      );
      expect(gradeQuestion(q, 'my answer').status, GradeStatus.selfReview);
      expect(gradeQuestion(q, null).status, GradeStatus.selfReview);
      expect(gradeQuestion(q, '  ').status, GradeStatus.selfReview);
    });
  });

  group('validate mirrors the reference tamper checks', () {
    test('tampered questions are rejected', () {
      final dup = mcqFixture();
      final dupOptions = List<String>.from(dup.options)..[1] = dup.options[0];
      expect(
        QuizQuestion(
          id: dup.id,
          type: dup.type,
          prompt: dup.prompt,
          options: dupOptions,
          correctIndex: dup.correctIndex,
        ).validate(),
        contains('duplicate options'),
      );

      expect(
        const QuizQuestion(
          id: 'x',
          type: QuestionType.mcq,
          prompt: 'P?',
          options: ['A', 'B'],
        ).validate(),
        contains('missing or invalid answer key'),
      );

      const fill = QuizQuestion(
        id: 'fill-t',
        type: QuestionType.fillBlank,
        prompt: 'A ____ is here.',
        acceptedAnswers: ['cat'],
      );
      expect(fill.validate(), isEmpty);
      final leaked = QuizQuestion(
        id: fill.id,
        type: fill.type,
        prompt: fill.prompt.replaceFirst(blankMarker, 'cat'),
        acceptedAnswers: fill.acceptedAnswers,
      );
      expect(leaked.validate(), isNotEmpty);
    });

    test('matching key must not be identity', () {
      const identity = QuizQuestion(
        id: 'm-id',
        type: QuestionType.matching,
        prompt: 'Match.',
        leftItems: ['A', 'B', 'C'],
        rightItems: ['a', 'b', 'c'],
        displayRight: [0, 1, 2],
        pairs: [0, 1, 2],
      );
      expect(identity.validate(), contains('key presented in identity order'));
      expect(matchingFixture().validate(), isEmpty);
    });
  });

  group('bundled bank', () {
    test('loads with all types valid and traceable', () async {
      final bank = await QuizBank.load();
      expect(bank.skipped, isEmpty);
      expect(bank.quizzes.length, 2);
      final all = bank.quizzes.expand((q) => q.questions).toList();
      expect(all.length, 16);
      for (final q in all) {
        expect(q.validate(), isEmpty, reason: q.id);
      }
      final types = all.map((q) => q.type).toSet();
      expect(
        types,
        containsAll([
          QuestionType.mcq,
          QuestionType.trueFalse,
          QuestionType.fillBlank,
          QuestionType.matching,
          QuestionType.subjective,
        ]),
      );
      for (final q in all.where((q) => q.type == QuestionType.matching)) {
        expect(
          q.pairs,
          isNot(orderedEquals(List.generate(q.pairs.length, (i) => i))),
        );
      }
      for (final q in all.where((q) => q.type == QuestionType.fillBlank)) {
        expect(q.prompt.split(blankMarker).length - 1, 1);
      }
    });

    test('malformed bank degrades to empty instead of throwing', () async {
      final bank = await QuizBank.load(
        asset: 'assets/quiz/does-not-exist.json',
      );
      expect(bank.quizzes, isEmpty);
      expect(bank.skipped, isNotEmpty);
    });
  });

  group('AttemptScore', () {
    test('mixes statuses and excludes self-review from percent', () {
      const sub = QuizQuestion(
        id: 'sub-1',
        type: QuestionType.subjective,
        prompt: 'Define it.',
        referenceAnswer: 'It.',
      );
      final score = AttemptScore.evaluate(
        [mcqFixture(), matchingFixture(), sub],
        {
          'mcq-1': 0,
          'match-1': {0: 2, 1: 0, 2: 1},
          'sub-1': 'text',
        },
      );
      expect(score.correct, 2);
      expect(score.selfReview, 1);
      expect(score.scorableTotal, 2);
      expect(score.percent, 100.0);
    });

    test('all self-review yields no percentage', () {
      const sub = QuizQuestion(
        id: 'sub-1',
        type: QuestionType.subjective,
        prompt: 'Define it.',
        referenceAnswer: 'It.',
      );
      final score = AttemptScore.evaluate([sub], {'sub-1': 'text'});
      expect(score.percent, isNull);
      expect(score.selfReview, 1);
    });

    test('unanswered counts as scorable and wrong', () {
      final score = AttemptScore.evaluate([mcqFixture()], {});
      expect(score.unanswered, 1);
      expect(score.percent, 0.0);
    });
  });
}
