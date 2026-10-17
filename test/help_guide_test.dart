import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:studyup/features/profile/presentation/help_guide.dart';
import 'package:studyup/features/profile/presentation/profile_detail_pages.dart';

void main() {
  group('help guide content', () {
    test('every article belongs to a known category', () {
      final ids = helpCategories.map((c) => c.id).toSet();
      for (final a in helpArticles) {
        expect(ids, contains(a.categoryId), reason: a.id);
        expect(a.title.trim(), isNotEmpty);
        expect(a.body, isNotEmpty);
      }
    });

    test('covers all required areas', () {
      final titles = helpArticles.map((a) => a.title).join(' | ');
      for (final needle in [
        'Getting started',
        'Tasks',
        'Subjects',
        'Chapters',
        'Sources',
        'Focus sessions',
        'Daily goal',
        'Streaks',
        'Community',
        'Notifications',
        'Privacy',
        'Feedback',
      ]) {
        expect(titles, contains(needle), reason: 'missing: $needle');
      }
    });

    test('search is case-insensitive and empty query returns all', () {
      expect(searchHelpArticles(''), hasLength(helpArticles.length));
      expect(
        searchHelpArticles('REMINDER').map((a) => a.id),
        contains('tasks'),
      );
      expect(searchHelpArticles('midnight').map((a) => a.id), contains('focus-sessions'));
      expect(searchHelpArticles('zzz-no-such-topic'), isEmpty);
    });

    test('documents missing goal editor honestly', () {
      final goal = helpArticles.firstWhere((a) => a.id == 'daily-goal');
      expect(
        goal.body.join(' '),
        contains('no in-app editor'),
      );
    });
  });

  group('HelpPage widgets', () {
    Future<void> pumpHelp(WidgetTester tester) async {
      SharedPreferences.setMockInitialValues({});
      final router = GoRouter(
        initialLocation: '/help',
        routes: [
          GoRoute(path: '/help', builder: (_, _) => const HelpPage()),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(
        MaterialApp.router(
          routerConfig: router,
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('shows search, categories and articles, no shortcuts', (
      tester,
    ) async {
      await pumpHelp(tester);
      expect(find.byType(TextField), findsOneWidget);
      expect(find.text('Getting started'), findsWidgets);
      // Default category shows its articles.
      expect(find.text('Troubleshooting & empty states'), findsOneWidget);
      // Removed shortcuts must be gone.
      expect(find.text('Open Home'), findsNothing);
      expect(find.text('Open Progress'), findsNothing);
      expect(find.text('Open Profile'), findsNothing);
    });

    testWidgets('search filters articles and empty state shows', (
      tester,
    ) async {
      await pumpHelp(tester);
      await tester.enterText(find.byType(TextField), 'reminder');
      await tester.pumpAndSettle();
      expect(find.text('Tasks: create, edit & reminders'), findsOneWidget);
      expect(find.text('Focus sessions'), findsNothing);

      await tester.enterText(find.byType(TextField), 'zzz-no-such-topic');
      await tester.pumpAndSettle();
      expect(find.textContaining('No guide articles match'), findsOneWidget);
    });

    testWidgets('category chips switch the article list', (tester) async {
      await pumpHelp(tester);
      expect(find.text('Focus sessions'), findsNothing);
      await tester.ensureVisible(find.text('Focus & sessions'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Focus & sessions'));
      await tester.pumpAndSettle();
      expect(find.text('Focus sessions'), findsOneWidget);
    });

    testWidgets('article opens and back returns to the guide', (
      tester,
    ) async {
      await pumpHelp(tester);
      await tester.ensureVisible(find.text('Focus & sessions'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Focus & sessions'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Focus sessions'));
      await tester.pumpAndSettle();
      // Article page shows full paragraphs.
      expect(find.textContaining('banks the studied time'), findsOneWidget);
      await tester.tap(find.byIcon(Icons.arrow_back_rounded));
      await tester.pumpAndSettle();
      expect(find.text('Focus sessions'), findsOneWidget);
    });
  });
}
