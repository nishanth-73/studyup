import 'package:flutter_test/flutter_test.dart';
import 'package:functions_client/functions_client.dart';
import 'package:studyup/features/profile/data/feedback_service.dart';
import 'package:studyup/features/profile/data/supabase_feedback_service.dart';

void main() {
  const valid = {
    'category': 'bug',
    'subject': 'Timer kept running',
    'message': 'Step by step description here.',
  };

  group('SupabaseFeedbackService.submit', () {
    test('sends expected body and returns id on success', () async {
      Map<String, Object?>? sent;
      final service = SupabaseFeedbackService(
        invoker: (body) async {
          sent = body;
          return const EdgeInvokeResult(
            status: 200,
            data: {'ok': true, 'id': 'edge-id-1'},
          );
        },
      );
      final result = await service.submit(
        category: 'bug',
        subject: valid['subject']!,
        message: valid['message']!,
        contactEmail: 'user@example.com',
        platform: 'android',
      );
      expect(result.resendId, 'edge-id-1');
      expect(sent!['category'], 'bug');
      expect(sent!['subject'], 'Timer kept running');
      expect(sent!['contactEmail'], 'user@example.com');
      expect(sent!['appVersion'], studyupAppVersion);
      expect(sent!['platform'], 'android');
    });

    test('omits empty contact email and platform', () async {
      Map<String, Object?>? sent;
      final service = SupabaseFeedbackService(
        invoker: (body) async {
          sent = body;
          return const EdgeInvokeResult(status: 200, data: {'ok': true});
        },
      );
      await service.submit(
        category: 'feature',
        subject: 'A good subject',
        message: 'A long enough message body.',
      );
      expect(sent!.containsKey('contactEmail'), isFalse);
      expect(sent!.containsKey('platform'), isFalse);
      expect(sent!['appVersion'], studyupAppVersion);
    });

    test('validates locally without invoking', () async {
      var called = false;
      final service = SupabaseFeedbackService(
        invoker: (_) async {
          called = true;
          return const EdgeInvokeResult(status: 200, data: {'ok': true});
        },
      );
      await expectLater(
        service.submit(
          category: 'spam',
          subject: 'ok subject',
          message: 'long enough message',
        ),
        throwsA(isA<FeedbackException>()),
      );
      await expectLater(
        service.submit(
          category: 'bug',
          subject: 'hi',
          message: 'long enough message',
        ),
        throwsA(isA<FeedbackException>()),
      );
      expect(called, isFalse);
    });

    test('surfaces server error message from details', () async {
      final service = SupabaseFeedbackService(
        invoker: (_) async => const EdgeInvokeResult(
          status: 200,
          data: {'ok': false, 'error': 'Too many requests.'},
        ),
      );
      await expectLater(
        service.submit(
          category: 'bug',
          subject: 'ok subject',
          message: 'long enough message here',
        ),
        throwsA(
          predicate<FeedbackException>((e) => e.message.contains('Too many')),
        ),
      );
    });

    test('maps FunctionsHttpException 429/500 to draft-safe messages', () async {
      final tooMany = SupabaseFeedbackService(
        invoker: (_) async => throw const FunctionsHttpException(
          status: 429,
          details: {'ok': false, 'error': ''},
        ),
      );
      await expectLater(
        tooMany.submit(
          category: 'bug',
          subject: 'ok subject',
          message: 'long enough message here',
        ),
        throwsA(
          predicate<FeedbackException>((e) => e.message.contains('Too many')),
        ),
      );

      final broken = SupabaseFeedbackService(
        invoker: (_) async =>
            throw const FunctionsHttpException(status: 502, details: null),
      );
      await expectLater(
        broken.submit(
          category: 'bug',
          subject: 'ok subject',
          message: 'long enough message here',
        ),
        throwsA(
          predicate<FeedbackException>((e) => e.message.contains('unavailable')),
        ),
      );
    });

    test('marks the undeployed-function gateway 404 as edgeFunctionMissing', () async {
      for (final invoker in <Future<EdgeInvokeResult> Function()>[
        () async => throw const FunctionsHttpException(
              status: 404,
              details: {
                'code': 'NOT_FOUND',
                'message': 'Requested function was not found',
              },
            ),
        () async => const EdgeInvokeResult(
              status: 404,
              data: {
                'code': 'NOT_FOUND',
                'message': 'Requested function was not found',
              },
            ),
      ]) {
        final service = SupabaseFeedbackService(invoker: (_) => invoker());
        try {
          await service.submit(
            category: 'bug',
            subject: 'ok subject',
            message: 'long enough message here',
          );
          fail('expected throw');
        } on FeedbackException catch (e) {
          expect(e.edgeFunctionMissing, isTrue);
          expect(e.message, contains('draft is kept'));
        }
      }
    });

    test('a deployed function error on 404 is surfaced without the flag', () async {
      final service = SupabaseFeedbackService(
        invoker: (_) async => const EdgeInvokeResult(
          status: 404,
          data: {'ok': false, 'error': 'Unknown feedback category.'},
        ),
      );
      try {
        await service.submit(
          category: 'bug',
          subject: 'ok subject',
          message: 'long enough message here',
        );
        fail('expected throw');
      } on FeedbackException catch (e) {
        expect(e.edgeFunctionMissing, isFalse);
        expect(e.message, 'Unknown feedback category.');
      }
    });

    test('maps network failure and timeout to draft-safe messages', () async {
      final offline = SupabaseFeedbackService(
        invoker: (_) async => throw const FunctionsFetchException(),
      );
      await expectLater(
        offline.submit(
          category: 'bug',
          subject: 'ok subject',
          message: 'long enough message here',
        ),
        throwsA(
          predicate<FeedbackException>((e) => e.message.contains('connection')),
        ),
      );

      final slow = SupabaseFeedbackService(
        timeout: const Duration(milliseconds: 20),
        invoker: (_) async {
          await Future<void>.delayed(const Duration(milliseconds: 200));
          return const EdgeInvokeResult(status: 200, data: {'ok': true});
        },
      );
      await expectLater(
        slow.submit(
          category: 'bug',
          subject: 'ok subject',
          message: 'long enough message here',
        ),
        throwsA(
          predicate<FeedbackException>((e) => e.message.contains('timed out')),
        ),
      );
    });

    test('maps malformed 200 body to retry message', () async {
      final service = SupabaseFeedbackService(
        invoker: (_) async =>
            const EdgeInvokeResult(status: 200, data: 'not-a-map'),
      );
      await expectLater(
        service.submit(
          category: 'bug',
          subject: 'ok subject',
          message: 'long enough message here',
        ),
        throwsA(isA<FeedbackException>()),
      );
    });
  });
}
