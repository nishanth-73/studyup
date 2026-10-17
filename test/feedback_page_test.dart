import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:functions_client/functions_client.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:studyup/core/backend/feedback_config.dart';
import 'package:studyup/features/profile/data/feedback_submitter.dart';
import 'package:studyup/features/profile/data/supabase_feedback_service.dart';
import 'package:studyup/features/profile/presentation/profile_detail_pages.dart';

Widget _harness({List<Override> overrides = const []}) {
  return ProviderScope(
    overrides: overrides,
    child: const MaterialApp(home: FeedbackPage()),
  );
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FeedbackConfig.debugResetForTest();
  });

  testWidgets('renders category, subject, message, contact and send button', (
    tester,
  ) async {
    await tester.pumpWidget(_harness());
    await tester.pumpAndSettle();
    expect(find.text('Category'), findsOneWidget);
    expect(find.text('Subject'), findsOneWidget);
    expect(find.text('Message'), findsOneWidget);
    expect(find.text('Contact email (optional)'), findsOneWidget);
    expect(find.text('Send feedback'), findsOneWidget);
  });

  testWidgets('empty submit shows validation errors and keeps form', (
    tester,
  ) async {
    await tester.pumpWidget(_harness());
    await tester.pumpAndSettle();
    await tester.tap(find.text('Send feedback'));
    await tester.pumpAndSettle();
    expect(find.textContaining('min 3'), findsOneWidget);
    expect(find.textContaining('min 10'), findsOneWidget);
  });

  testWidgets('invalid contact email is rejected before network', (
    tester,
  ) async {
    await tester.pumpWidget(_harness());
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'e.g. Timer kept running').hitTestable(),
      'Timer kept running',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'What happened, step by step…').hitTestable(),
      'A sufficiently long message body here.',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'you@example.com — only for replies').hitTestable(),
      'not-an-email',
    );
    await tester.tap(find.text('Send feedback'));
    await tester.pumpAndSettle();
    expect(find.textContaining('valid email'), findsOneWidget);
  });

  testWidgets('failed submit preserves draft and surfaces a message', (
    tester,
  ) async {
    // Deterministic failure: a deployed transport that answers 503.
    final submitter = FeedbackSubmitter(
      supabaseLive: true,
      httpEndpoint: '',
      edgeFactory: () => SupabaseFeedbackService(
        invoker: (_) async =>
            throw const FunctionsHttpException(status: 503, details: null),
      ),
    );
    await tester.pumpWidget(
      _harness(overrides: [
        feedbackSubmitterProvider.overrideWithValue(submitter),
      ]),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'e.g. Timer kept running').hitTestable(),
      'My subject here',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'What happened, step by step…').hitTestable(),
      'A sufficiently long message body here.',
    );
    await tester.tap(find.text('Send feedback'));
    await tester.pump(); // start async submit
    await tester.pumpAndSettle();
    // Draft preserved (fields NOT cleared) and a message shown.
    expect(
      find.widgetWithText(TextField, 'My subject here').hitTestable(),
      findsOneWidget,
    );
    expect(find.byType(SnackBar), findsOneWidget);
  });
}
