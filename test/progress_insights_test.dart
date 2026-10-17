import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:studyup/core/widgets/date_picker_sheet.dart';
import 'package:studyup/features/progress/data/study_gamification.dart';
import 'package:studyup/features/progress/presentation/progress_screen.dart';

/// Sessions: Oct 10 23:00 -> Oct 11 01:00 (60/60 split) plus
/// Oct 11 11:30 -> 12:30 (30 morning + 30 afternoon).
Map<String, Object?> _row(String id, DateTime start, DateTime end) => {
  'id': id,
  'subjectId': 'general',
  'subjectName': 'Daily Study',
  'checkInTime': start.toIso8601String(),
  'checkOutTime': end.toIso8601String(),
  'pausedSeconds': end.difference(start).inSeconds,
  'studySegments': [
    {'startTime': start.toIso8601String(), 'endTime': end.toIso8601String()},
  ],
  'resumedAt': null,
};

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({
      'studyup.studySessions.v1': jsonEncode([
        _row(
          'overnight',
          DateTime(2026, 10, 10, 23),
          DateTime(2026, 10, 11, 1),
        ),
        _row(
          'midday',
          DateTime(2026, 10, 11, 11, 30),
          DateTime(2026, 10, 11, 12, 30),
        ),
      ]),
      'studyup.dailyStudyGoalMinutes.v1': 480,
    });
  });

  GoRouter testRouter() => GoRouter(
    initialLocation: '/progress',
    routes: [
      GoRoute(path: '/progress', builder: (_, _) => const ProgressScreen()),
      GoRoute(
        path: '/home',
        builder: (_, _) => const Scaffold(body: Center(child: Text('HOME'))),
      ),
      GoRoute(
        path: '/subjects',
        builder: (_, _) =>
            const Scaffold(body: Center(child: Text('SUBJECTS'))),
      ),
      GoRoute(
        path: '/profile',
        builder: (_, _) => const Scaffold(body: Center(child: Text('PROFILE'))),
      ),
      GoRoute(
        path: '/plan',
        builder: (_, _) => const Scaffold(body: Center(child: Text('PLAN'))),
      ),
    ],
  );

  Future<void> pumpProgress(WidgetTester tester) async {
    // Tall viewport: the monthly card sits below the fold on phones and
    // ListView lazily builds it only when scrolled into cache range.
    tester.view.physicalSize = const Size(800, 1800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final router = testRouter();
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp.router(
          debugShowCheckedModeBanner: false,
          routerConfig: router,
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  void expectNoErrors(WidgetTester tester) {
    final errors = <Object>[];
    Object? error = tester.takeException();
    while (error != null) {
      errors.add(error);
      error = tester.takeException();
    }
    expect(errors, isEmpty, reason: errors.join('\n---\n'));
  }

  Finder datePickerIcons(WidgetTester tester) {
    return find.byWidgetPredicate(
      (w) =>
          w is SvgPicture &&
          w.bytesLoader is SvgAssetLoader &&
          (w.bytesLoader as SvgAssetLoader).assetName ==
              'assets/icons/date_picker.svg',
    );
  }

  group('Progress Insights pickers + charts', () {
    testWidgets('proxy pie renders with period data', (tester) async {
      await pumpProgress(tester);
      expectNoErrors(tester);
      // Proxy tab: pie card with total + legend entries.
      expect(find.textContaining('Total Studied:'), findsOneWidget);
      expect(find.textContaining('Morning'), findsWidgets);
      expect(find.textContaining('Night'), findsWidgets);
      // Study Statistics tiles read midnight-split totals.
      expect(find.text('Today'), findsWidgets);
      // No always-visible calendar icon on the pie card; Compare is the
      // single entry point.
      expect(datePickerIcons(tester), findsNothing);
    });

    testWidgets('insights charts render without errors', (tester) async {
      await pumpProgress(tester);
      await tester.tap(find.text('Insights'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 800));
      expectNoErrors(tester);
      expect(find.text('WEEKLY STUDY TIME'), findsOneWidget);
      expect(find.text('MONTHLY STUDY TIME'), findsOneWidget);
      // No calendar icon anywhere on Insights: the month/year jump
      // button is gone (months change by swiping the grid) and chart
      // cards have none until Compare.
      expect(datePickerIcons(tester), findsNothing);
    });

    Finder weekRow(String label) => find.descendant(
      of: find.byType(PickerSheetFrame),
      matching: find.textContaining(label, findRichText: true),
    );

    testWidgets('weekly Compare opens weeks popup and sets compare week', (
      tester,
    ) async {
      await pumpProgress(tester);
      await tester.tap(find.text('Insights'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 800));
      expect(find.text('WEEKLY STUDY TIME'), findsOneWidget);

      // No popup visible before Compare; no compare chart either.
      expect(find.text('Compare with week'), findsNothing);
      expect(find.textContaining(' vs '), findsNothing);

      await tester.tap(find.byTooltip('Compare week'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      // Weeks-only popup for the viewed month (no date strip).
      expect(find.text('Compare with week'), findsOneWidget);
      expect(weekRow('W1'), findsOneWidget);
      expectNoErrors(tester);

      // W1 always holds past days (or today): picking it sets the
      // compare week and closes the popup.
      await tester.tap(weekRow('W1'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 800));
      expect(find.text('Compare with week'), findsNothing);
      // Compare chart data is driven by the picked week.
      expect(find.textContaining(' vs '), findsWidgets);
      expectNoErrors(tester);

      // Compare again clears the comparison.
      await tester.tap(find.byTooltip('Reset comparison'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.textContaining(' vs '), findsNothing);
      expectNoErrors(tester);
    });

    testWidgets('weeks popup steps through past months only', (tester) async {
      await pumpProgress(tester);
      await tester.tap(find.text('Insights'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 800));

      await tester.tap(find.byTooltip('Compare week'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('Compare with week'), findsOneWidget);

      final now = DateTime.now();
      const months = [
        'January',
        'February',
        'March',
        'April',
        'May',
        'June',
        'July',
        'August',
        'September',
        'October',
        'November',
        'December',
      ];
      final thisLabel = '${months[now.month - 1]} ${now.year}';
      final prev = DateTime(now.year, now.month - 1, 1);
      final prevLabel = '${months[prev.month - 1]} ${prev.year}';

      Finder dialogText(String value) => find.descendant(
        of: find.byType(PickerSheetFrame),
        matching: find.text(value),
      );

      // At the present month: back arrow exists, no forward arrow.
      expect(dialogText(thisLabel), findsOneWidget);
      expect(find.byTooltip('Previous month'), findsOneWidget);
      expect(find.byTooltip('Next month'), findsNothing);
      expect(find.text('This month'), findsOneWidget);

      // Step back: a past month with fully tappable weeks.
      await tester.tap(find.byTooltip('Previous month'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(dialogText(prevLabel), findsOneWidget);
      // Forward travel back to the present is offered again.
      expect(find.byTooltip('Next month'), findsOneWidget);
      await tester.tap(weekRow('W1'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 800));
      // A past month's week now drives the comparison.
      expect(find.text('Compare with week'), findsNothing);
      expect(find.textContaining(' vs '), findsWidgets);
      expectNoErrors(tester);
    });

    testWidgets('monthly Compare opens month dialog and sets compare', (
      tester,
    ) async {
      await pumpProgress(tester);
      await tester.tap(find.text('Insights'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 800));

      await tester.tap(find.byTooltip('Compare month'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      // Shared month-picker sheet is showing (same year as today, so the
      // initial previous month is in the grid).
      expect(find.text('Aug'), findsOneWidget);
      expectNoErrors(tester);

      // Pick August 2026 and confirm: card label, chart and averages
      // follow the selected month.
      await tester.tap(find.text('Aug'));
      await tester.pump();
      await tester.tap(find.text('Done'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 800));
      expect(find.textContaining('August 2026'), findsWidgets);
      expectNoErrors(tester);

      // Reset clears the comparison and restores Compare.
      await tester.tap(find.byTooltip('Reset comparison'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.textContaining('August 2026'), findsNothing);
      expectNoErrors(tester);
    });

    testWidgets('pie Compare opens date dialog and drives compare pie', (
      tester,
    ) async {
      await pumpProgress(tester);
      expect(find.text('Today'), findsWidgets);

      await tester.tap(find.byTooltip('Compare another day'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      // Shared bottom-sheet calendar.
      expect(find.byType(PickerSheetFrame), findsOneWidget);
      expectNoErrors(tester);

      // Pick Oct 9 (seeded sessions are Oct 10/11) and confirm.
      final dialog = find.byType(PickerSheetFrame);
      await tester.tap(
        find.descendant(of: dialog, matching: find.text('9')).first,
      );
      await tester.pump();
      await tester.tap(find.text('Done'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 800));
      // Compare pie labeled with the picked date.
      expect(find.text('10/9'), findsOneWidget);
      expectNoErrors(tester);

      // Reset clears the comparison and restores Compare.
      await tester.tap(find.byTooltip('Reset comparison'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('10/9'), findsNothing);
      expectNoErrors(tester);
    });

    testWidgets('cancel preserves the previous comparison state', (
      tester,
    ) async {
      await pumpProgress(tester);
      await tester.tap(find.byTooltip('Compare another day'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.byType(PickerSheetFrame), findsOneWidget);

      await tester.tap(find.text('Cancel'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.byType(PickerSheetFrame), findsNothing);
      // Still no comparison UI.
      expect(find.text('10/9'), findsNothing);
      expectNoErrors(tester);
    });

    testWidgets('weeks popup locks future weeks', (tester) async {
      await pumpProgress(tester);
      await tester.tap(find.text('Insights'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 800));

      await tester.tap(find.byTooltip('Compare week'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('Compare with week'), findsOneWidget);

      // Same rows the app lists: Monday rows of the viewed month.
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final rows = monthWeekRows(now.year, now.month);
      final future = [
        for (final row in rows)
          if (row.monday.isAfter(today)) row,
      ];
      if (future.isEmpty) {
        // Whole viewed month is past/present: every row is tappable.
        // Picking the last one still sets a comparison.
        await tester.tap(weekRow(rows.last.label));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 800));
        expect(find.textContaining(' vs '), findsWidgets);
      } else {
        // Future rows are shown but locked: tapping them sets nothing
        // and the popup stays open.
        for (final row in future) {
          await tester.tap(weekRow(row.label), warnIfMissed: false);
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 300));
        }
        expect(find.textContaining(' vs '), findsNothing);
        expect(find.text('Compare with week'), findsOneWidget);
      }
      expectNoErrors(tester);
    });

    testWidgets('how-it-works dialog lists periods and dismisses', (
      tester,
    ) async {
      await pumpProgress(tester);
      await tester.tap(find.byTooltip('About day parts'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('How it works'), findsOneWidget);
      expect(find.text('Morning'), findsWidgets);
      expect(find.text('Afternoon'), findsWidgets);
      expect(find.text('Evening'), findsWidgets);
      expect(find.text('Night'), findsWidgets);
      expect(find.textContaining('shared daily goal'), findsOneWidget);
      expectNoErrors(tester);

      await tester.tap(find.text('Got it'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('How it works'), findsNothing);
      expectNoErrors(tester);
    });
  });
}
