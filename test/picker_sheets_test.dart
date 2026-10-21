import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:studyup/core/widgets/date_picker_sheet.dart';

/// Contract tests for the shared bottom-sheet pickers used across Home
/// and Progress:
/// - calendar sheet: in-range days selectable, out-of-range days and
///   month navigation locked at the bounds, Done/Cancel semantics,
///   TODAY marker driven by the real current date;
/// - month sheet: month chips locked at the bounds, year stepping
///   crosses years only within bounds, Done returns the first day of
///   the picked month.
void main() {
  Future<void> pumpOpener(
    WidgetTester tester,
    Future<DateTime?> Function(BuildContext context) open,
    void Function(DateTime?) onResult,
  ) {
    // Tall phone viewport: the calendar sheet (month grid + Done) must be
    // fully visible, like on a real device.
    tester.view.physicalSize = const Size(900, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    return tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: ElevatedButton(
                onPressed: () async => onResult(await open(context)),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> openSheet(WidgetTester tester) async {
    await tester.tap(find.text('open'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
  }

  Finder inSheet(Finder matching) =>
      find.descendant(of: find.byType(PickerSheetFrame), matching: matching);

  Future<void> tapAndSettle(WidgetTester tester, Finder finder) async {
    await tester.tap(finder);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
  }

  group('shared calendar picker sheet', () {
    testWidgets('renders heading + weekday header and picks an in-range day', (
      tester,
    ) async {
      DateTime? result;
      await pumpOpener(
        tester,
        (context) => showCalendarPickerSheet(
          context,
          initialDate: DateTime(2026, 6, 15),
          firstDate: DateTime(2026, 6, 1),
          lastDate: DateTime(2026, 6, 30),
          title: 'Pick a day',
        ),
        (picked) => result = picked,
      );
      await openSheet(tester);

      expect(find.text('Pick a day'), findsOneWidget);
      expect(inSheet(find.text('June 2026')), findsOneWidget);
      // Monday-first weekday header (two T's and two S's).
      expect(inSheet(find.text('M')), findsOneWidget);
      expect(inSheet(find.text('T')), findsNWidgets(2));
      expect(inSheet(find.text('S')), findsNWidgets(2));

      await tapAndSettle(tester, inSheet(find.text('20')));
      await tapAndSettle(tester, inSheet(find.text('Done')));

      expect(find.byType(PickerSheetFrame), findsNothing);
      expect(result, DateTime(2026, 6, 20));
    });

    testWidgets('locks out-of-range days and the upper month bound', (
      tester,
    ) async {
      DateTime? result;
      await pumpOpener(
        tester,
        (context) => showCalendarPickerSheet(
          context,
          initialDate: DateTime(2026, 6, 10),
          firstDate: DateTime(2000),
          lastDate: DateTime(2026, 6, 15),
          title: 'Pick a day',
        ),
        (picked) => result = picked,
      );
      await openSheet(tester);

      // At the upper bound: forward stepping is disabled.
      await tapAndSettle(tester, find.byTooltip('Next month'));
      expect(inSheet(find.text('June 2026')), findsOneWidget);

      // June 16 is outside the range: tapping it changes nothing.
      await tapAndSettle(tester, inSheet(find.text('16')));
      await tapAndSettle(tester, inSheet(find.text('Done')));

      expect(result, DateTime(2026, 6, 10));
    });

    testWidgets('Home-style range allows future days and month stepping', (
      tester,
    ) async {
      DateTime? result;
      await pumpOpener(
        tester,
        (context) => showCalendarPickerSheet(
          context,
          initialDate: DateTime(2026, 6, 15),
          firstDate: DateTime(2000),
          lastDate: DateTime(2100, 12, 31),
          title: 'Choose a date',
        ),
        (picked) => result = picked,
      );
      await openSheet(tester);

      await tapAndSettle(tester, find.byTooltip('Next month'));
      expect(inSheet(find.text('July 2026')), findsOneWidget);
      await tapAndSettle(tester, inSheet(find.text('20')));
      await tapAndSettle(tester, inSheet(find.text('Done')));

      expect(result, DateTime(2026, 7, 20));
    });

    testWidgets('marks the real today and returns it on Done', (tester) async {
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      DateTime? result;
      await pumpOpener(
        tester,
        (context) => showCalendarPickerSheet(
          context,
          initialDate: today,
          firstDate: DateTime(2000),
          lastDate: today,
          title: 'Compare with day',
        ),
        (picked) => result = picked,
      );
      await openSheet(tester);

      expect(inSheet(find.text('TODAY')), findsOneWidget);
      await tapAndSettle(tester, inSheet(find.text('Done')));

      expect(result, today);
    });

    testWidgets('Cancel and barrier dismiss both return null', (tester) async {
      DateTime? result;
      await pumpOpener(
        tester,
        (context) => showCalendarPickerSheet(
          context,
          initialDate: DateTime(2026, 6, 15),
          firstDate: DateTime(2000),
          lastDate: DateTime(2100),
        ),
        (picked) => result = picked,
      );

      await openSheet(tester);
      await tapAndSettle(tester, inSheet(find.text('Cancel')));
      expect(find.byType(PickerSheetFrame), findsNothing);
      expect(result, isNull);

      // Barrier (tap above the sheet) also dismisses with null.
      await openSheet(tester);
      await tester.tapAt(const Offset(10, 10));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.byType(PickerSheetFrame), findsNothing);
      expect(result, isNull);
    });
  });

  group('shared month picker sheet', () {
    testWidgets('locks months past the ceiling and returns picked month', (
      tester,
    ) async {
      DateTime? result;
      await pumpOpener(
        tester,
        (context) => showMonthPickerSheet(
          context,
          initialMonth: DateTime(2026, 6, 1),
          firstMonth: DateTime(2000),
          lastMonth: DateTime(2026, 6, 1),
          title: 'Compare with month',
        ),
        (picked) => result = picked,
      );
      await openSheet(tester);

      expect(find.text('Compare with month'), findsOneWidget);
      expect(inSheet(find.text('2026')), findsOneWidget);
      // At the year ceiling: forward year stepping is disabled.
      await tapAndSettle(tester, find.byTooltip('Next year'));
      expect(inSheet(find.text('2026')), findsOneWidget);

      // September 2026 is past the ceiling: tapping it changes nothing.
      await tapAndSettle(tester, inSheet(find.text('Sep')));
      await tapAndSettle(tester, inSheet(find.text('Done')));
      expect(result, DateTime(2026, 6, 1));

      // Reopen and pick an in-range month: March 2026.
      await openSheet(tester);
      await tapAndSettle(tester, inSheet(find.text('Mar')));
      await tapAndSettle(tester, inSheet(find.text('Done')));
      expect(result, DateTime(2026, 3, 1));
    });

    testWidgets('year stepping crosses years within the bounds', (
      tester,
    ) async {
      DateTime? result;
      await pumpOpener(
        tester,
        (context) => showMonthPickerSheet(
          context,
          initialMonth: DateTime(2026, 6, 1),
          firstMonth: DateTime(2000),
          lastMonth: DateTime(2026, 6, 1),
          title: 'Compare with month',
        ),
        (picked) => result = picked,
      );
      await openSheet(tester);

      await tapAndSettle(tester, find.byTooltip('Previous year'));
      expect(inSheet(find.text('2025')), findsOneWidget);
      await tapAndSettle(tester, inSheet(find.text('Dec')));
      await tapAndSettle(tester, inSheet(find.text('Done')));

      expect(result, DateTime(2025, 12, 1));
    });
  });
}
