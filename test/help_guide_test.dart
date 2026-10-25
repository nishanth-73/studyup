import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:studyup/features/profile/presentation/help_guide.dart';
import 'package:studyup/features/profile/presentation/profile_detail_pages.dart';

void main() {
  group('help guide content', () {
    test('essential topics, in order, including Community', () {
      expect(helpTopics.map((t) => t.id).toList(), [
        'home',
        'subjects',
        'focus',
        'progress',
        'community',
      ]);
      expect(helpTopics.map((t) => t.title).toList(), [
        'Home',
        'Subjects',
        'Focus & sessions',
        'Progress',
        'Community',
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

    test('no obsolete or removed topics are in titles', () {
      final all = helpTopics.map((t) => t.title).join(' | ');
      for (final gone in [
        'Getting started',
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

    test('community topic covers invitations, podium, leaderboard, troubleshooting and download guidance', () {
      final communityTopic = helpTopics.firstWhere((t) => t.id == 'community');
      expect(communityTopic.sections, hasLength(3));

      final headings = communityTopic.sections.map((s) => s.heading).toList();
      expect(headings, [
        'Inviting friends & joining circles',
        'Podium, rankings & member progress',
        'Troubleshooting & FAQs',
      ]);

      final allLines = communityTopic.lines.join(' ');
      expect(allLines, contains('Invite Friends'));
      expect(allLines, contains('Accept Invitation'));
      expect(allLines, contains('Top 3 Podium'));
      expect(allLines, contains('See all'));
      expect(allLines, contains('Download button shows “Coming soon”'));
      expect(allLines, contains('Missing minutes?'));
      expect(allLines, contains('refresh Community'));
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

    testWidgets('shows the five compact topics collapsed', (tester) async {
      await pumpHelp(tester);
      for (final title in ['Home', 'Subjects', 'Focus & sessions', 'Progress', 'Community']) {
        expect(find.text(title), findsOneWidget);
      }
      expect(find.byType(TextField), findsNothing);
      expect(find.byIcon(Icons.expand_more), findsNWidgets(5));
      expect(find.textContaining('reminder fires'), findsNothing);
      expect(find.textContaining('Invite Friends'), findsNothing);
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

    testWidgets('tapping Community expands sections with headings and troubleshooting', (
      tester,
    ) async {
      await pumpHelp(tester);
      await tester.ensureVisible(find.text('Community'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Community'));
      await tester.pumpAndSettle();

      // Section Headings
      expect(find.text('Inviting friends & joining circles'), findsOneWidget);
      expect(find.text('Podium, rankings & member progress'), findsOneWidget);
      expect(find.text('Troubleshooting & FAQs'), findsOneWidget);

      // Section Lines
      expect(find.textContaining("Tap 'Invite Friends'"), findsOneWidget);
      expect(find.textContaining('Top 3 Podium'), findsOneWidget);
      expect(find.textContaining('Coming soon'), findsOneWidget);
      expect(find.textContaining('Missing minutes?'), findsOneWidget);

      // Collapse again
      await tester.tap(find.text('Community'));
      await tester.pumpAndSettle();
      expect(find.text('Inviting friends & joining circles'), findsNothing);
    });

    testWidgets('opening another topic closes the previous one', (
      tester,
    ) async {
      await pumpHelp(tester);
      await tester.tap(find.text('Home'));
      await tester.pumpAndSettle();
      expect(find.textContaining('reminder fires'), findsOneWidget);

      await tester.ensureVisible(find.text('Community'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Community'));
      await tester.pumpAndSettle();
      expect(find.textContaining('reminder fires'), findsNothing);
      expect(find.text('Inviting friends & joining circles'), findsOneWidget);
      expect(find.byIcon(Icons.expand_less), findsOneWidget);
    });
  });
}
