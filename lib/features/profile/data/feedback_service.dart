import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

/// Allowed feedback categories (must match `api/feedback.js`).
const feedbackCategories = ['bug', 'feature', 'improvement', 'other'];

/// Human labels for the category dropdown.
String feedbackCategoryLabel(String value) {
  switch (value) {
    case 'bug':
      return 'Bug report';
    case 'feature':
      return 'Feature request';
    case 'improvement':
      return 'Improvement';
    case 'other':
      return 'Other';
    default:
      return value;
  }
}

/// Client-side validation mirroring the server limits.
/// Returns an error string, or null when valid.
String? validateFeedbackSubject(String value) {
  final v = value.trim();
  if (v.length < 3) return 'Add a short subject (min 3 characters).';
  if (v.length > 120) return 'Keep the subject under 120 characters.';
  return null;
}

String? validateFeedbackMessage(String value) {
  final v = value.trim();
  if (v.length < 10) return 'Tell us a little more (min 10 characters).';
  if (v.length > 2000) return 'Keep the message under 2000 characters.';
  return null;
}

String? validateFeedbackContactEmail(String value) {
  final v = value.trim();
  if (v.isEmpty) return 'Enter your contact email.';
  if (v.length > 254 || !RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]{2,}$').hasMatch(v)) {
    return 'Enter a valid email address.';
  }
  return null;
}

/// Thrown for every feedback submission failure with a user-safe message.
/// The draft must be preserved by callers when this is thrown.
class FeedbackException implements Exception {
  final String message;

  /// True only when the failure is specifically the Supabase Edge
  /// Function being missing/undeployed (gateway 404 `NOT_FOUND`). The same
  /// submission can then be retried on the HTTP fallback transport, since
  /// no function ever saw the body (safe, no duplicate emails).
  final bool edgeFunctionMissing;

  const FeedbackException(this.message, {this.edgeFunctionMissing = false});
  @override
  String toString() => 'FeedbackException: $message';
}

/// Accepted-by-backend result. [resendId] is Resend's queued-message id —
/// acceptance only, NOT confirmed delivery.
class FeedbackResult {
  final String? resendId;
  const FeedbackResult({this.resendId});
}

/// Submits StudyUp feedback to the Vercel `/api/feedback` endpoint.
///
/// No secrets here: only the public endpoint URL. Resend keys stay server-side.
/// [client] is injectable for tests.
class FeedbackService {
  final String endpoint;
  final http.Client _client;
  final Duration timeout;

  FeedbackService({
    required this.endpoint,
    http.Client? client,
    this.timeout = const Duration(seconds: 15),
  }) : _client = client ?? http.Client();

  Future<FeedbackResult> submit({
    required String category,
    required String subject,
    required String message,
    required String contactEmail,
  }) async {
    if (endpoint.isEmpty || !endpoint.startsWith('https://')) {
      throw const FeedbackException(
        'Feedback service is not configured yet. '
        'Set FEEDBACK_API_URL and rebuild the app.',
      );
    }
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
    final emailError = validateFeedbackContactEmail(contactEmail);
    if (emailError != null) throw FeedbackException(emailError);

    final contact = contactEmail.trim();

    http.Response res;
    try {
      res = await _client
          .post(
            Uri.parse(endpoint),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'category': cat,
              'subject': subject.trim(),
              'message': message.trim(),
              'contactEmail': contact,
            }),
          )
          .timeout(timeout);
    } on TimeoutException {
      throw const FeedbackException(
        'Request timed out. Check your connection and try again — your draft is kept.',
      );
    } catch (_) {
      throw const FeedbackException(
        'Could not reach the feedback service. Check your connection and try again — your draft is kept.',
      );
    }

    if (res.statusCode == 200) {
      try {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        if (data['ok'] == true) {
          final id = data['id'];
          return FeedbackResult(resendId: id is String ? id : null);
        }
        final err = data['error'];
        throw FeedbackException(
          err is String && err.isNotEmpty
              ? err
              : 'The service rejected the feedback. Your draft is kept.',
        );
      } catch (e) {
        if (e is FeedbackException) rethrow;
        throw const FeedbackException(
          'Got an unexpected response. Your draft is kept — please retry.',
        );
      }
    }
    // Non-200: try to surface the server's non-sensitive error, else generic.
    try {
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final err = data['error'];
      if (err is String && err.isNotEmpty) throw FeedbackException(err);
    } catch (e) {
      if (e is FeedbackException) rethrow;
    }
    if (res.statusCode == 429) {
      throw const FeedbackException(
        'Too many attempts. Wait a few minutes and try again — your draft is kept.',
      );
    }
    if (res.statusCode >= 500) {
      throw const FeedbackException(
        'Feedback service is unavailable. Your draft is kept — please retry later.',
      );
    }
    throw const FeedbackException(
      'Could not send feedback. Your draft is kept — please retry.',
    );
  }

  void close() => _client.close();
}
