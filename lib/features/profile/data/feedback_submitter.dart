import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/backend/feedback_config.dart';
import '../../auth/data/auth_controller.dart';
import 'feedback_service.dart';
import 'supabase_feedback_service.dart';

/// Public endpoint of the hosted Vercel feedback API (this repo's
/// `api/feedback.js`). No secrets: the app only posts to this URL; Resend
/// keys and inbox addresses stay in Vercel environment variables.
const String hostedFeedbackEndpoint =
    'https://studyup-feedback-api.vercel.app/api/feedback';

/// Factory seams so tests can inject fakes for both transports.
typedef SupabaseFeedbackFactory = SupabaseFeedbackService Function();
typedef HttpFeedbackFactory = FeedbackService Function(String endpoint);

/// Picks the feedback transport with a real fallback chain:
///
/// 1. Supabase `send-feedback` Edge Function (primary when the backend is
///    live — it allows unauthenticated callers with abuse protection);
/// 2. the hosted Vercel `/api/feedback` endpoint when the Edge Function is
///    not deployed yet ([FeedbackException.edgeFunctionMissing]).
///
/// Fallback only happens for the undeployed-function case: the function
/// never saw the body, so retrying cannot duplicate a submission. Real
/// errors a deployed transport answered (validation, rate limit, server
/// errors, timeouts) surface immediately and are never retried blindly.
class FeedbackSubmitter {
  final bool supabaseLive;
  final String _httpEndpoint;
  final SupabaseFeedbackFactory _edgeFactory;
  final HttpFeedbackFactory _httpFactory;

  FeedbackSubmitter({
    required this.supabaseLive,
    String? httpEndpoint,
    SupabaseFeedbackFactory? edgeFactory,
    HttpFeedbackFactory? httpFactory,
  })  : _httpEndpoint = httpEndpoint ?? hostedFeedbackEndpoint,
        _edgeFactory = edgeFactory ?? SupabaseFeedbackService.new,
        _httpFactory =
            httpFactory ?? ((endpoint) => FeedbackService(endpoint: endpoint));

  /// Visible for tests/diagnostics.
  String get httpEndpoint => _httpEndpoint;

  Future<FeedbackResult> submit({
    required String category,
    required String subject,
    required String message,
    String? contactEmail,
    String? platform,
  }) async {
    if (supabaseLive) {
      try {
        return await _edgeFactory().submit(
          category: category,
          subject: subject,
          message: message,
          contactEmail: contactEmail,
          platform: platform,
        );
      } on FeedbackException catch (e) {
        if (!e.edgeFunctionMissing) rethrow;
        // Edge Function not deployed: fall through to the HTTP endpoint.
        if (_httpEndpoint.isEmpty) rethrow;
      }
    }
    if (_httpEndpoint.isEmpty) {
      throw const FeedbackException(
        'Feedback sending is not set up in this build yet. '
        'Your draft is kept on this device.',
      );
    }
    final service = _httpFactory(_httpEndpoint);
    try {
      return await service.submit(
        category: category,
        subject: subject,
        message: message,
        contactEmail: contactEmail,
      );
    } finally {
      service.close();
    }
  }
}

/// App-wide transport selection: primary = Supabase Edge Function when the
/// backend is live, fallback = FEEDBACK_API_URL when set, else the hosted
/// Vercel endpoint above. Overridable in widget tests.
final feedbackSubmitterProvider = Provider<FeedbackSubmitter>((ref) {
  return FeedbackSubmitter(
    supabaseLive: ref.watch(backendLiveProvider),
    httpEndpoint: FeedbackConfig.isConfigured
        ? FeedbackConfig.endpoint
        : hostedFeedbackEndpoint,
  );
});
