import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:studyup/features/profile/presentation/customise_robo_page.dart';
import 'package:studyup/features/robo/robo_avatar.dart';
import 'package:studyup/features/robo/robo_shape.dart';
import 'package:studyup/features/robo/robo_types.dart';

void main() {
  group('Customise Robo page', () {
    Future<void> pumpPage(WidgetTester tester) async {
      SharedPreferences.setMockInitialValues({});
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(home: Scaffold(body: CustomiseRoboPage())),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
    }

    testWidgets('offers three shapes and nine preview states', (tester) async {
      await pumpPage(tester);
      // Exactly three persisted shape options.
      expect(find.byKey(const ValueKey('robo-shape-square')), findsOneWidget);
      expect(find.byKey(const ValueKey('robo-shape-circle')), findsOneWidget);
      expect(find.byKey(const ValueKey('robo-shape-hexagon')), findsOneWidget);
      // Exactly nine preview-only state chips.
      for (final s in RoboState.values) {
        expect(
          find.byKey(ValueKey('robo-preview-state-${s.name}')),
          findsOneWidget,
        );
      }
      expect(find.byType(RoboAvatar), findsWidgets);
      // Preview/live separation is labelled.
      expect(find.textContaining('Preview only'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('shape selection persists via existing storage', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({});
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: Scaffold(body: CustomiseRoboPage())),
        ),
      );
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('robo-shape-hexagon')));
      await tester.pump();
      expect(container.read(roboShapeProvider), RoboShape.hexagon);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(RoboShapeController.storageKey), 'hexagon');
      // Previewing a state does not change the persisted shape.
      final sleeping = find.byKey(
        const ValueKey('robo-preview-state-sleeping'),
      );
      await tester.scrollUntilVisible(sleeping, 300);
      await tester.pump();
      await tester.tap(sleeping);
      await tester.pump();
      expect(container.read(roboShapeProvider), RoboShape.hexagon);
      expect(tester.takeException(), isNull);
    });
  });
}
