import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:studyup/main.dart';

/// THROWAWAY crash repro: pump the real app past the splash hold and
/// navigate, surfacing any startup exception.
void main() {
  testWidgets('app survives splash to home navigation', (tester) async {
    SharedPreferences.setMockInitialValues({
      'studyup.userProfile.v1': '{"ownerId":"local","displayName":"Alex","blobName":"alex","onboardingComplete":true,"avatarId":"avatar1","slidesSeen":true,"setupComplete":true,"demoSignedIn":true,"demoEmail":""}',
      'studyup.tasks.starterSeeded.v1': true,
    });
    await tester.pumpWidget(const ProviderScope(child: StudyUpApp()));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(seconds: 3));
    await tester.pump(const Duration(seconds: 1));
    expect(tester.takeException(), isNull);
  });
}
