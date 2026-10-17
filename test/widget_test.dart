import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:studyup/main.dart';

void main() {
  testWidgets('fresh install opens onboarding with no splash delay', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(const ProviderScope(child: StudyUpApp()));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    // No branded splash screen: first launch lands on onboarding.
    expect(find.text('Track Your Progress'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('returning user opens Home directly', (tester) async {
    SharedPreferences.setMockInitialValues({
      'studyup.userProfile.v1': '{"ownerId":"local","displayName":"Alex","blobName":"alex","onboardingComplete":true,"avatarId":"avatar1","slidesSeen":true,"setupComplete":true,"demoSignedIn":true,"demoEmail":""}',
      'studyup.tasks.starterSeeded.v1': true,
    });

    await tester.pumpWidget(const ProviderScope(child: StudyUpApp()));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    // Home header shows the saved name; no splash, no onboarding.
    expect(find.text('Alex'), findsOneWidget);
    expect(find.text('Track Your Progress'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
