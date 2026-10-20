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

  testWidgets('returning setup user must sign in before protected features', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'studyup.userProfile.v1': '{"ownerId":"local","displayName":"Alex","blobName":"alex","onboardingComplete":true,"avatarId":"avatar1","slidesSeen":true,"setupComplete":true,"demoSignedIn":true,"demoEmail":""}',
      'studyup.tasks.starterSeeded.v1': true,
    });

    await tester.pumpWidget(const ProviderScope(child: StudyUpApp()));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    // Setup remains saved, but a local legacy demo flag cannot bypass auth.
    expect(
      find.textContaining('Offline guest access is not available.'),
      findsOneWidget,
    );
    expect(find.text('Track Your Progress'), findsNothing);
    expect(find.text('Home'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
