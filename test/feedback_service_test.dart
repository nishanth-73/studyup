import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:studyup/core/backend/feedback_config.dart';
import 'package:studyup/features/profile/data/feedback_service.dart';

void main() {
  group('feedback validation', () {
    test('subject limits', () {
      expect(validateFeedbackSubject(''), isNotNull);
      expect(validateFeedbackSubject('ab'), isNotNull);
      expect(validateFeedbackSubject('ok subject'), isNull);
      expect(validateFeedbackSubject('x' * 121), isNotNull);
    });

    test('message limits', () {
      expect(validateFeedbackMessage('short'), isNotNull);
      expect(validateFeedbackMessage('long enough message'), isNull);
      expect(validateFeedbackMessage('x' * 2001), isNotNull);
    });

    test('contact email optional but validated', () {
      expect(validateFeedbackContactEmail(''), isNull);
      expect(validateFeedbackContactEmail('  '), isNull);
      expect(validateFeedbackContactEmail('user@example.com'), isNull);
      expect(validateFeedbackContactEmail('not-an-email'), isNotNull);
    });
  });

  group('FeedbackConfig', () {
    setUp(() => FeedbackConfig.debugResetForTest());
    tearDown(() => FeedbackConfig.debugResetForTest());

    test('empty when unconfigured', () {
      expect(FeedbackConfig.endpoint, isEmpty);
      expect(FeedbackConfig.isConfigured, isFalse);
    });

    test('appends /api/feedback to base URL', () {
      FeedbackConfig.debugSetFileBaseForTest('https://demo.vercel.app');
      expect(
        FeedbackConfig.endpoint,
        'https://demo.vercel.app/api/feedback',
      );
      expect(FeedbackConfig.isConfigured, isTrue);
    });

    test('keeps full endpoint as-is, rejects non-https', () {
      FeedbackConfig.debugSetFileBaseForTest(
        'https://demo.vercel.app/api/feedback',
      );
      expect(
        FeedbackConfig.endpoint,
        'https://demo.vercel.app/api/feedback',
      );
      FeedbackConfig.debugSetFileBaseForTest('http://demo.vercel.app');
      expect(FeedbackConfig.endpoint, isEmpty);
      expect(FeedbackConfig.isConfigured, isFalse);
    });
  });

  group('FeedbackService.submit', () {
    const endpoint = 'https://demo.vercel.app/api/feedback';

    test('sends expected JSON and returns id on success', () async {
      Map<String, dynamic>? sent;
      final client = MockClient((req) async {
        expect(req.url.toString(), endpoint);
        expect(req.headers['Content-Type'], contains('application/json'));
        sent = jsonDecode(req.body) as Map<String, dynamic>;
        return http.Response(jsonEncode({'ok': true, 'id': 'abc123'}), 200);
      });
      final service = FeedbackService(endpoint: endpoint, client: client);
      final result = await service.submit(
        category: 'bug',
        subject: 'Timer kept running',
        message: 'Step by step description here.',
        contactEmail: 'user@example.com',
      );
      expect(result.resendId, 'abc123');
      expect(sent!['category'], 'bug');
      expect(sent!['subject'], 'Timer kept running');
      expect(sent!['contactEmail'], 'user@example.com');
      service.close();
    });

    test('omits contactEmail when empty', () async {
      Map<String, dynamic>? sent;
      final client = MockClient((req) async {
        sent = jsonDecode(req.body) as Map<String, dynamic>;
        return http.Response(jsonEncode({'ok': true}), 200);
      });
      final service = FeedbackService(endpoint: endpoint, client: client);
      await service.submit(
        category: 'feature',
        subject: 'A good subject',
        message: 'A long enough message body.',
      );
      expect(sent!.containsKey('contactEmail'), isFalse);
      service.close();
    });

    test('validates locally without network call', () async {
      var called = false;
      final client = MockClient((_) async {
        called = true;
        return http.Response('{}', 200);
      });
      final service = FeedbackService(endpoint: endpoint, client: client);
      await expectLater(
        service.submit(category: 'spam', subject: 'ok subject', message: 'long enough message'),
        throwsA(isA<FeedbackException>()),
      );
      await expectLater(
        service.submit(category: 'bug', subject: 'hi', message: 'long enough message'),
        throwsA(isA<FeedbackException>()),
      );
      expect(called, isFalse);
      service.close();
    });

    test('rejects unconfigured endpoint', () async {
      final service = FeedbackService(
        endpoint: '',
        client: MockClient((_) async => http.Response('{}', 200)),
      );
      await expectLater(
        service.submit(category: 'bug', subject: 'ok subject', message: 'long enough message'),
        throwsA(isA<FeedbackException>()),
      );
      service.close();
    });

    test('surfaces server error message (failure keeps draft)', () async {
      final client = MockClient(
        (_) async => http.Response(jsonEncode({'ok': false, 'error': 'Too many requests.'}), 429),
      );
      final service = FeedbackService(endpoint: endpoint, client: client);
      try {
        await service.submit(category: 'bug', subject: 'ok subject', message: 'long enough message here');
        fail('expected throw');
      } on FeedbackException catch (e) {
        expect(e.message, contains('Too many'));
      }
      service.close();
    });

    test('maps 500 to unavailable message', () async {
      final client = MockClient((_) async => http.Response('oops', 500));
      final service = FeedbackService(endpoint: endpoint, client: client);
      await expectLater(
        service.submit(category: 'bug', subject: 'ok subject', message: 'long enough message here'),
        throwsA(
          predicate<FeedbackException>((e) => e.message.contains('unavailable')),
        ),
      );
      service.close();
    });

    test('maps network failure to connection message', () async {
      final client = MockClient((_) async => throw Exception('socket'));
      final service = FeedbackService(endpoint: endpoint, client: client);
      await expectLater(
        service.submit(category: 'bug', subject: 'ok subject', message: 'long enough message here'),
        throwsA(
          predicate<FeedbackException>((e) => e.message.contains('connection')),
        ),
      );
      service.close();
    });

    test('maps malformed success body to retry message', () async {
      final client = MockClient((_) async => http.Response('not-json', 200));
      final service = FeedbackService(endpoint: endpoint, client: client);
      await expectLater(
        service.submit(category: 'bug', subject: 'ok subject', message: 'long enough message here'),
        throwsA(isA<FeedbackException>()),
      );
      service.close();
    });

    test('timeout keeps draft-friendly message', () async {
      final client = MockClient((_) async {
        await Future<void>.delayed(const Duration(milliseconds: 200));
        return http.Response('{}', 200);
      });
      final service = FeedbackService(
        endpoint: endpoint,
        client: client,
        timeout: const Duration(milliseconds: 20),
      );
      await expectLater(
        service.submit(category: 'bug', subject: 'ok subject', message: 'long enough message here'),
        throwsA(
          predicate<FeedbackException>((e) => e.message.contains('timed out')),
        ),
      );
      service.close();
    });
  });
}
