/// Feedback backend configuration.
///
/// Resolution order (first non-empty wins):
/// 1. build-time dart-define (`--dart-define=FEEDBACK_API_URL=https://xxx.vercel.app`);
/// 2. local untracked `.env` file (`FEEDBACK_API_URL=...`, loaded at startup).
///
/// The value may be either the Vercel project base URL
/// (`https://studyup-xyz.vercel.app`) or the full endpoint URL
/// (`https://studyup-xyz.vercel.app/api/feedback`).
/// [endpoint] normalises to the full HTTPS endpoint, or '' when unconfigured.
///
/// No secrets live here: the browser/app only needs the public endpoint URL.
/// RESEND_API_KEY and inbox addresses stay server-side in Vercel.
class FeedbackConfig {
  const FeedbackConfig._();

  static const String _defineBase = String.fromEnvironment(
    'FEEDBACK_API_URL',
    defaultValue: '',
  );

  static String _fileBase = '';

  /// Called once at startup after `dotenv.load()`; dart-defines still win.
  static void loadFileEnv(Map<String, String> env) {
    _fileBase = (env['FEEDBACK_API_URL'] ?? '').trim();
  }

  /// Raw configured value (base or full endpoint), '' when unset.
  static String get raw => _first(_defineBase.trim(), _fileBase);

  /// Full HTTPS endpoint URL, or '' when not configured / invalid.
  static String get endpoint {
    final v = raw;
    if (v.isEmpty) return '';
    if (v.endsWith('/api/feedback')) return _httpsOnly(v);
    final base = v.endsWith('/') ? v.substring(0, v.length - 1) : v;
    return _httpsOnly('$base/api/feedback');
  }

  /// True when [endpoint] is a usable HTTPS URL.
  static bool get isConfigured =>
      endpoint.startsWith('https://') && endpoint.length > 'https://'.length + 8;

  static String _httpsOnly(String v) => v.startsWith('https://') ? v : '';

  static String _first(String a, String b) => a.isNotEmpty ? a : b;

  // Test-only reset.
  static void debugResetForTest() {
    _fileBase = '';
  }

  static void debugSetFileBaseForTest(String v) {
    _fileBase = v;
  }
}
