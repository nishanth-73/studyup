import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import 'feedback_service.dart';

/// App version sent as diagnostic context with feedback.
/// Mirrors `pubspec.yaml`. Never a secret; safe to send.
const studyupAppVersion = '1.0.0+1';

/// Transport name of the Supabase Edge Function (see
/// `supabase/functions/send-feedback/index.ts`).
const sendFeedbackFunctionName = 'send-feedback';

/// Minimal result of one Edge Function invocation. Decouples the service
/// from `functions_client` so tests can inject a fake invoker.
class EdgeInvokeResult {
  final int status;
  final dynamic data;
  const EdgeInvokeResult({required this.status, this.data});
}

typedef EdgeInvoker =
    Future<EdgeInvokeResult> Function(Map<String, Object?> body);

Future<EdgeInvokeResult> _defaultInvoker(Map<String, Object?> body) async {
  final res = await Supabase.instance.client.functions.invoke(
    sendFeedbackFunctionName,
    body: body,
  );
  return EdgeInvokeResult(status: res.status, data: res.data);
}

/// Submits StudyUp feedback through the Supabase `send-feedback` Edge
/// Function using the existing Supabase client (anon key attached
/// automatically — never calls api.resend.com from the app).
///
/// Resend keys and inbox addresses stay in server-side function secrets.
/// [invoker] is injectable for tests; [timeout] guards hung requests.
class SupabaseFeedbackService {
  final EdgeInvoker _invoker;
  final Duration timeout;

  SupabaseFeedbackService({
    EdgeInvoker? invoker,
    this.timeout = const Duration(seconds: 15),
  }) : _invoker = invoker ?? _defaultInvoker;

  Future<FeedbackResult> submit({
    required String category,
    required String subject,
    required String message,
    String? contactEmail,
    String appVersion = studyupAppVersion,
    String? platform,
  }) async {
    final cat = category.trim().toLowerCase();
    if (!feedbackCategories.contains(cat)) {
      throw const FeedbackException(
        'Choose a valid category: bug, feature, improvement, or other.',
      );
    }
    final subjectError = validateFeedbackSubject(subject);
    if (subjectError != null) throw FeedbackException(subjectError);
    final messageError = validateFeedbackMessage(message);
    if (messageError != null) throw FeedbackException(messageError);
    final emailError = validateFeedbackContactEmail(contactEmail ?? '');
    if (emailError != null) throw FeedbackException(emailError);

    final contact = (contactEmail ?? '').trim();
    final body = <String, Object?>{
      'category': cat,
      'subject': subject.trim(),
      'message': message.trim(),
      if (contact.isNotEmpty) 'contactEmail': contact,
      if (appVersion.trim().isNotEmpty) 'appVersion': appVersion.trim(),
      if (platform != null && platform.trim().isNotEmpty)
        'platform': platform.trim(),
    };

    late final EdgeInvokeResult res;
    try {
      res = await _invoker(body).timeout(timeout);
    } on TimeoutException {
      throw const FeedbackException(
        'Request timed out. Check your connection and try again — your draft is kept.',
      );
    } on FunctionsFetchException {
      throw const FeedbackException(
        'Could not reach the feedback service. Check your connection and try again — your draft is kept.',
      );
    } on FunctionsRelayException {
      throw const FeedbackException(
        'Feedback service is unavailable. Your draft is kept — please retry later.',
      );
    } on FunctionsHttpException catch (e) {
      throw _httpError(e.status, e.details);
    } catch (_) {
      throw const FeedbackException(
        'Could not send feedback. Your draft is kept — please retry.',
      );
    }

    if (res.status == 200) {
      final data = res.data;
      if (data is Map) {
        if (data['ok'] == true) {
          final id = data['id'];
          return FeedbackResult(resendId: id is String ? id : null);
        }
        final err = data['error'];
        if (err is String && err.isNotEmpty) throw FeedbackException(err);
      }
      throw const FeedbackException(
        'Got an unexpected response. Your draft is kept — please retry.',
      );
    }
    throw _httpError(res.status, res.data);
  }

  FeedbackException _httpError(int status, dynamic details) {
    // Prefer the server's non-sensitive message when it sent one: a
    // deployed function always answers `{ok:false,error}`, even on 404.
    if (details is Map) {
      final err = details['error'];
      if (err is String && err.isNotEmpty) return FeedbackException(err);
      // Supabase gateway 404 for a function that is not deployed yet:
      // {"code":"NOT_FOUND","message":"Requested function was not found"}
      if (status == 404 && details['code'] == 'NOT_FOUND') {
        return const FeedbackException(
          'Feedback service is not deployed yet. '
          'Your draft is kept — please retry later.',
          edgeFunctionMissing: true,
        );
      }
    }
    if (status == 429) {
      return const FeedbackException(
        'Too many attempts. Wait a few minutes and try again — your draft is kept.',
      );
    }
    if (status >= 500 || status == 0) {
      return const FeedbackException(
        'Feedback service is unavailable. Your draft is kept — please retry later.',
      );
    }
    return const FeedbackException(
      'Could not send feedback. Your draft is kept — please retry.',
    );
  }
}
