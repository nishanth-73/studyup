import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:studyup/core/router/startup_gate.dart';

void main() {
  testWidgets('profile storage errors show a retry action, not Home', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'studyup.userProfile.v1': '{invalid json',
    });

    await tester.pumpWidget(
      ProviderScope(child: const MaterialApp(home: StartupGate())),
    );
    await tester.pump();
    await tester.pump();

    expect(
      find.text('Could not load your profile from this device.'),
      findsOneWidget,
    );
    expect(find.text('Retry'), findsOneWidget);
    expect(find.text('HOME'), findsNothing);

    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(
      find.text('Could not load your profile from this device.'),
      findsOneWidget,
    );
  });
}
