import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:studyup/core/theme/app_colors.dart';
import 'package:studyup/core/widgets/ui_kit.dart';
import 'package:studyup/features/home/presentation/home_controller.dart';
import 'package:studyup/features/home/presentation/home_screen.dart';
import 'package:studyup/features/progress/data/study_day.dart';
import 'package:studyup/features/subjects/presentation/subject_detail_screen.dart'
    show storePickedSourceFile;

void main() {
  group('normalizeCompareDay', () {
    final today = DateTime(2026, 10, 10, 15, 30);
    test('past and today normalize, future rejects', () {
      expect(
        normalizeCompareDay(DateTime(2026, 10, 9, 23, 59), today),
        DateTime(2026, 10, 9),
      );
      expect(
        normalizeCompareDay(DateTime(2026, 10, 10, 0, 5), today),
        DateTime(2026, 10, 10),
      );
      expect(normalizeCompareDay(DateTime(2026, 10, 11), today), isNull);
      expect(normalizeCompareDay(DateTime(2027, 1, 1), today), isNull);
    });
  });

  group('AppTextField', () {
    testWidgets('label, muted hint, entered text, error', (tester) async {
      final controller = TextEditingController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AppTextField(
              controller: controller,
              label: 'Task title',
              hintText: 'Task title (e.g. Binary Search)',
              errorText: 'Give your task a title first.',
            ),
          ),
        ),
      );
      expect(find.text('Task title'), findsWidgets);
      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.decoration?.hintText, 'Task title (e.g. Binary Search)');
      // Placeholder uses the muted theme color, entered text does not.
      final hintStyle = field.decoration?.hintStyle;
      expect(hintStyle?.color, AppColors.textMuted.withValues(alpha: 0.75));
      expect(field.style?.color, isNot(AppColors.textMuted));
      // Focus ring + error are wired through the decoration.
      expect(field.decoration?.focusedBorder, isNotNull);
      expect(field.decoration?.errorText, 'Give your task a title first.');
      expect(find.text('Give your task a title first.'), findsOneWidget);
    });
  });

  group('TaskEditorSheet validation + save', () {
    Future<WidgetRef> pumpHome(WidgetTester tester) async {
      SharedPreferences.setMockInitialValues({});
      late WidgetRef captured;
      final router = GoRouter(
        initialLocation: '/home',
        routes: [
          GoRoute(
            path: '/home',
            builder: (context, _) => Consumer(
              builder: (context, ref, _) {
                captured = ref;
                return const HomeScreen();
              },
            ),
          ),
          GoRoute(
            path: '/subjects',
            builder: (_, _) => const Scaffold(body: Text('S')),
          ),
          GoRoute(
            path: '/subjects/:id',
            builder: (_, _) => const Scaffold(body: Text('D')),
          ),
          GoRoute(
            path: '/progress',
            builder: (_, _) => const Scaffold(body: Text('P')),
          ),
          GoRoute(
            path: '/profile',
            builder: (_, _) => const Scaffold(body: Text('R')),
          ),
          GoRoute(
            path: '/plan',
            builder: (_, _) => const Scaffold(body: Text('L')),
          ),
        ],
      );
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
      return captured;
    }

    testWidgets('empty title shows error, valid input saves', (tester) async {
      final ref = await pumpHome(tester);
      // Open the add-task sheet via the header action.
      await tester.tap(find.text('Add Task'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      await tester.tap(find.text('Schedule Task'));
      await tester.pump();
      expect(find.text('Give your task a title first.'), findsOneWidget);

      await tester.enterText(find.byType(TextField).first, 'Binary Search');
      await tester.pump();
      await tester.tap(find.text('Schedule Task'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      final tasks = ref
          .read(homeControllerProvider)
          .tasksByDate
          .values
          .expand((list) => list);
      expect(tasks.map((t) => t.title), contains('Binary Search'));
    });
  });

  group('storePickedSourceFile', () {
    test('copies into app storage and round-trips bytes', () async {
      final tmp = await Directory.systemTemp.createTemp('studyup_source');
      addTearDown(() => tmp.delete(recursive: true));
      final source = File('${tmp.path}/notes.pdf');
      await source.writeAsBytes([1, 2, 3, 4, 5]);
      final target = Directory('${tmp.path}/appdocs');
      final stored = await storePickedSourceFile(
        source.path,
        'notes.pdf',
        targetDir: target,
      );
      expect(stored.endsWith('_notes.pdf'), isTrue);
      expect(stored.startsWith(target.path), isTrue);
      expect(File(stored).existsSync(), isTrue);
      expect(await File(stored).readAsBytes(), [1, 2, 3, 4, 5]);
    });

    test('missing source file throws instead of storing junk', () async {
      final tmp = await Directory.systemTemp.createTemp('studyup_source');
      addTearDown(() => tmp.delete(recursive: true));
      await expectLater(
        storePickedSourceFile('/no/such/file.pdf', 'file.pdf', targetDir: tmp),
        throwsStateError,
      );
    });
  });
}
