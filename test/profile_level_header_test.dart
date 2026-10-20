import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:studyup/features/profile/presentation/profile_screen.dart';

void main() {
  testWidgets('Profile shows the earned level name beneath the user name', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'studyup.userProfile.v1': jsonEncode({
        'ownerId': 'local',
        'displayName': 'Alex',
        'blobName': 'alex',
        'onboardingComplete': true,
        'blobVariant': 0,
        'avatarId': 'avatar1',
        'slidesSeen': true,
        'setupComplete': true,
        'demoSignedIn': false,
        'demoEmail': '',
      }),
      'studyup.studySessions.v1': jsonEncode([]),
      'studyup.xpLedger.v1': jsonEncode({
        'days': List.generate(50, (index) => '2020-01-${index + 1}'),
        'weeks': <String>[],
      }),
    });

    await tester.pumpWidget(
      const ProviderScope(child: MaterialApp(home: ProfileScreen())),
    );
    await tester.pumpAndSettle();

    expect(find.text('Alex'), findsOneWidget);
    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey('profile-level-name')))
          .data,
      'Apprentice',
    );
    expect(tester.takeException(), isNull);
  });
}
