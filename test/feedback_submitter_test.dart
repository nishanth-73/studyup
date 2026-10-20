import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:functions_client/functions_client.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:studyup/features/profile/data/feedback_service.dart';
import 'package:studyup/features/profile/data/feedback_submitter.dart';
import 'package:studyup/features/profile/data/supabase_feedback_service.dart';

void main() {
  const endpoint = 'https://demo.vercel.app/api/feedback';

  SupabaseFeedbackService edge(EdgeInvokeResult Function() run) =>
      SupabaseFeedbackService(invoker: (_) async => run());

  Future<EdgeInvokeResult> missingEdge() async =>
      throw const FunctionsHttpException(
        status: 404,
        details: {
          'code': 'NOT_FOUND',
          'message': 'Requested function was not found',
        },
      );

  test('hosted fallback endpoint is a valid https feedback endpoint', () {
    expect(hostedFeedbackEndpoint, startsWith('https://'));
    expect(hostedFeedbackEndpoint, endsWith('/api/feedback'));
  });

  test('uses the Edge Function when it succeeds (no HTTP call)', () async {
    var httpCalls = 0;
    final submitter = FeedbackSubmitter(
      supabaseLive: true,
      httpEndpoint: endpoint,
      edgeFactory: () => edge(
        () => const EdgeInvokeResult(
          status: 200,
          data: {'ok': true, 'id': 'edge-id'},
        ),
      ),
      httpFactory: (e) {
        httpCalls++;
        return FeedbackService(
          endpoint: e,
          client: MockClient((_) async => http.Response('{}', 200)),
        );
      },
    );
    final result = await submitter.submit(
      category: 'bug',
      subject: 'ok subject',
      message: 'long enough message here',
      contactEmail: 'user@example.com',
    );
    expect(result.resendId, 'edge-id');
    expect(httpCalls, 0);
  });

  test('undeployed Edge Function falls back to the HTTP endpoint', () async {
    Map<String, dynamic>? sent;
    final submitter = FeedbackSubmitter(
      supabaseLive: true,
      httpEndpoint: endpoint,
      edgeFactory: () => SupabaseFeedbackService(invoker: (_) => missingEdge()),
      httpFactory: (e) => FeedbackService(
        endpoint: e,
        client: MockClient((req) async {
          expect(req.url.toString(), endpoint);
          sent = jsonDecode(req.body) as Map<String, dynamic>;
          return http.Response(jsonEncode({'ok': true, 'id': 'http-id'}), 200);
        }),
      ),
    );
    final result = await submitter.submit(
      category: 'bug',
      subject: 'ok subject',
      message: 'long enough message here',
      contactEmail: 'user@example.com',
    );
    expect(result.resendId, 'http-id');
    expect(sent!['subject'], 'ok subject');
    expect(sent!['contactEmail'], 'user@example.com');
  });

  test('does not fall back for real submission errors', () async {
    var httpCalls = 0;
    final submitter = FeedbackSubmitter(
      supabaseLive: true,
      httpEndpoint: endpoint,
      edgeFactory: () => edge(
        () => const EdgeInvokeResult(
          status: 500,
          data: {'ok': false, 'error': 'Server exploded.'},
        ),
      ),
      httpFactory: (e) {
        httpCalls++;
        return FeedbackService(
          endpoint: e,
          client: MockClient((_) async => http.Response('{}', 200)),
        );
      },
    );
    try {
      await submitter.submit(
        category: 'bug',
        subject: 'ok subject',
        message: 'long enough message here',
        contactEmail: 'user@example.com',
      );
      fail('expected throw');
    } on FeedbackException catch (e) {
      expect(e.edgeFunctionMissing, isFalse);
      expect(e.message, 'Server exploded.');
    }
    expect(httpCalls, 0);
  });

  test('rethrows edgeFunctionMissing when no HTTP endpoint exists', () async {
    final submitter = FeedbackSubmitter(
      supabaseLive: true,
      httpEndpoint: '',
      edgeFactory: () => SupabaseFeedbackService(invoker: (_) => missingEdge()),
    );
    try {
      await submitter.submit(
        category: 'bug',
        subject: 'ok subject',
        message: 'long enough message here',
        contactEmail: 'user@example.com',
      );
      fail('expected throw');
    } on FeedbackException catch (e) {
      expect(e.edgeFunctionMissing, isTrue);
      expect(e.message, contains('draft is kept'));
    }
  });

  test('uses HTTP directly when Supabase is not live', () async {
    final submitter = FeedbackSubmitter(
      supabaseLive: false,
      httpEndpoint: endpoint,
      httpFactory: (e) => FeedbackService(
        endpoint: e,
        client: MockClient(
          (_) async => http.Response(jsonEncode({'ok': true}), 200),
        ),
      ),
    );
    final result = await submitter.submit(
      category: 'bug',
      subject: 'ok subject',
      message: 'long enough message here',
      contactEmail: 'user@example.com',
    );
    expect(result.resendId, isNull);
  });

  test('throws a setup error when neither transport is available', () async {
    final submitter = FeedbackSubmitter(supabaseLive: false, httpEndpoint: '');
    await expectLater(
      submitter.submit(
        category: 'bug',
        subject: 'ok subject',
        message: 'long enough message here',
        contactEmail: 'user@example.com',
      ),
      throwsA(
        predicate<FeedbackException>((e) => e.message.contains('not set up')),
      ),
    );
  });
}
