/// Supabase connection configuration.
///
/// Resolution order (first non-empty wins):
/// 1. build-time dart-defines (`--dart-define=SUPABASE_URL=...`), best for
///    release builds;
/// 2. a local untracked `.env` file (loaded at startup via flutter_dotenv),
///    convenient for `flutter run` during development.
///
/// Never hardcoded, never committed (`.env` is git-ignored; only
/// `.env.example` with placeholders is tracked):
///
///   flutter run --dart-define=SUPABASE_URL=https://xyz.supabase.co \
///               --dart-define=SUPABASE_ANON_KEY=eyJ...
///
/// The publishable/anon key is safe to embed (RLS enforces access).
/// The service-role key must NEVER be placed in this app.
class SupabaseConfig {
  const SupabaseConfig._();

  /// Compile-time values (dart-define). Empty when not supplied.
  static const String _defineUrl = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: '',
  );
  static const String _defineAnonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue: '',
  );

  static String _fileUrl = '';
  static String _fileAnonKey = '';

  /// Called once at startup after `dotenv.load()`; dart-defines still win.
  static void loadFileEnv(Map<String, String> env) {
    _fileUrl = (env['SUPABASE_URL'] ?? '').trim();
    _fileAnonKey = (env['SUPABASE_ANON_KEY'] ?? '').trim();
  }

  /// Project URL, e.g. https://xyzcompany.supabase.co
  static String get url => _first(_defineUrl, _fileUrl);

  /// Publishable (anon) key.
  static String get anonKey => _first(_defineAnonKey, _fileAnonKey);

  static String _first(String a, String b) => a.isNotEmpty ? a : b;

  /// Native auth callback for Google OAuth, email confirmation, and
  /// password recovery. Scheme is the Android package name
  /// (Supabase convention); supabase_flutter exchanges the returned
  /// `code` / tokens for a session automatically.
  ///
  /// Add EXACTLY this URL under Supabase Dashboard → Authentication →
  /// URL Configuration → Allowed Redirect URLs, otherwise Supabase
  /// refuses the redirect and sign-in cannot return to the app.
  static const String authCallbackUrl = 'com.studyup.studyup://login-callback/';

  /// True only when real credentials were supplied at build time.
  static bool get isConfigured =>
      url.isNotEmpty && anonKey.isNotEmpty && _looksLikeUrl(url);

  static bool _looksLikeUrl(String value) =>
      value.startsWith('https://') &&
      value.length > 'https://'.length + 3 &&
      !value.contains('YOUR_') &&
      !value.contains('example');
}
