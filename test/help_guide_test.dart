import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:studyup/features/profile/presentation/help_guide.dart';
import 'package:studyup/features/profile/presentation/profile_detail_pages.dart';

void main() {
  group('help guide content', () {
    test('exactly the four essential topics, in order', () {
      expect(helpTopics.map((t) => t.id).toList(), [
        'home',
        'subjects',
        'focus',
        'progress',
      ]);
      expect(helpTopics.map((t) => t.title).toList(), [
        'Home',
        'Subjects',
        'Focus & sessions',
        'Progress',
      ]);
    });

    test('every topic is short and self-contained', () {
      for (final topic in helpTopics) {
        expect(topic.title.trim(), isNotEmpty, reason: topic.id);
        expect(topic.lines, isNotEmpty, reason: topic.id);
        for (final line in topic.lines) {
          expect(line.trim(), isNotEmpty, reason: topic.id);
          expect(
            line.length,
            lessThan(140),
            reason: 'keep help lines scannable: ${topic.id}',
          );
        }
      }
    });

    test('no removed or advanced topics are mentioned', () {
      final all = helpTopics.map((t) => t.title).join(' | ');
      for (final gone in [
        'Getting started',
        'Troubleshooting',
        'Community',
        'Notifications',
        'Chapters:',
      ]) {
        expect(all, isNot(contains(gone)), reason: 'should be removed: $gone');
      }
    });

    test('no technical service names appear in user copy', () {
      final copy = helpTopics.expand((t) => t.lines).join(' ').toLowerCase();
      for (final term in [
        'supabase',
        'backend',
        'api',
        'database',
        'vercel',
        'edge function',
      ]) {
        expect(
          copy,
          isNot(contains(term)),
          reason: 'user-facing help must stay non-technical: $term',
        );
      }
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
      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      await tester.pumpAndSettle();
    }

    testWidgets('shows the four compact topics collapsed', (tester) async {
      await pumpHelp(tester);
      for (final title in ['Home', 'Subjects', 'Focus & sessions', 'Progress']) {
        expect(find.text(title), findsOneWidget);
      }
      // No search box and no article list remain.
      expect(find.byType(TextField), findsNothing);
      expect(find.byIcon(Icons.expand_more), findsNWidgets(4));
      // Bullet lines stay hidden until a topic is opened.
      expect(find.textContaining('reminder fires'), findsNothing);
    });

    testWidgets('tapping a topic expands it, tapping again collapses', (
      tester,
    ) async {
      await pumpHelp(tester);
      await tester.tap(find.text('Home'));
      await tester.pumpAndSettle();
      expect(find.textContaining('reminder fires'), findsOneWidget);
      expect(find.byIcon(Icons.expand_less), findsOneWidget);

      await tester.tap(find.text('Home'));
      await tester.pumpAndSettle();
      expect(find.textContaining('reminder fires'), findsNothing);
    });

    testWidgets('opening another topic closes the previous one', (
      tester,
    ) async {
      await pumpHelp(tester);
      await tester.tap(find.text('Home'));
      await tester.pumpAndSettle();
      expect(find.textContaining('reminder fires'), findsOneWidget);

      await tester.ensureVisible(find.text('Progress'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Progress'));
      await tester.pumpAndSettle();
      expect(find.textContaining('reminder fires'), findsNothing);
      expect(find.textContaining('day-parts pie'), findsOneWidget);
      expect(find.byIcon(Icons.expand_less), findsOneWidget);
    });
  });
}
