import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/backend/supabase_config.dart';

/// Result of an auth attempt: either signed in, or a user-facing error.
/// Email-confirmation flows return [needsVerification] instead of a user.
class AuthResult {
  final User? user;
  final String? error;
  final bool needsVerification;

  const AuthResult._({this.user, this.error, this.needsVerification = false});

  factory AuthResult.ok(User user) => AuthResult._(user: user);
  factory AuthResult.fail(String error) => AuthResult._(error: error);
  factory AuthResult.verify() => const AuthResult._(needsVerification: true);

  bool get isOk => user != null;
}

/// Supabase Auth for real accounts (email/password + verification).
///
/// Guest/local data is never touched here: sign-in only attaches an
/// identity; session/port history migration is handled explicitly by
/// [SessionSyncService.syncAfterSignIn]. Passwords are never stored —
/// Supabase Auth holds the credentials server-side.
class AuthRepository {
  AuthRepository(this._client);

  final SupabaseClient _client;

  User? get currentUser => _client.auth.currentUser;
  Session? get currentSession => _client.auth.currentSession;
  Stream<AuthState> get authChanges => _client.auth.onAuthStateChange;

  /// Raw client for sync/social layers (same singleton, RLS-enforced).
  SupabaseClient get client => _client;

  static String friendlyError(Object error) {
    final message = error.toString().toLowerCase();
    if (message.contains('invalid login credentials') ||
        message.contains('invalid_credentials')) {
      return 'Wrong email or password. Try again.';
    }
    if (message.contains('user already registered') ||
        message.contains('already exists')) {
      return 'This email already has an account. Log in instead.';
    }
    if (message.contains('email not confirmed') ||
        message.contains('not confirmed')) {
      return 'Please verify your email first — check your inbox.';
    }
    if (message.contains('user cancelled') ||
        message.contains('cancelled') ||
        message.contains('canceled') ||
        message.contains('access_denied')) {
      return 'Sign-in was cancelled before completing.';
    }
    if (message.contains('browser') || message.contains('launch')) {
      return 'Could not open the browser. Check your connection and retry.';
    }
    if (message.contains('network') ||
        message.contains('socketexception') ||
        message.contains('failed host')) {
      return 'No connection. Check your network and retry.';
    }
    if (message.contains('too many requests') ||
        message.contains('rate limit')) {
      return 'Too many attempts. Wait a minute and retry.';
    }
    if (message.contains('password')) {
      return 'Password must be at least 6 characters.';
    }
    return 'Authentication failed. Please retry.';
  }

  Future<AuthResult> signUp({
    required String email,
    required String password,
  }) async {
    try {
      final response = await _client.auth.signUp(
        email: email.trim(),
        password: password,
        // Tapping the verification email returns to the app via the
        // native auth callback (must be allowlisted in the dashboard).
        emailRedirectTo: SupabaseConfig.authCallbackUrl,
      );
      final user = response.user;
      if (user == null) return AuthResult.fail('Sign-up failed. Please retry.');
      // Email confirmation on: no session yet → verify first.
      if (response.session == null) return AuthResult.verify();
      return AuthResult.ok(user);
    } catch (error) {
      return AuthResult.fail(friendlyError(error));
    }
  }

  Future<AuthResult> signIn({
    required String email,
    required String password,
  }) async {
    try {
      final response = await _client.auth.signInWithPassword(
        email: email.trim(),
        password: password,
      );
      final user = response.user;
      if (user == null) return AuthResult.fail('Sign-in failed. Please retry.');
      return AuthResult.ok(user);
    } catch (error) {
      return AuthResult.fail(friendlyError(error));
    }
  }

  /// Google OAuth via the system browser (forced external on Android —
  /// Google blocks embedded webviews). Returns null on launch; the
  /// actual result arrives through [authChanges] after Supabase
  /// redirects to [SupabaseConfig.authCallbackUrl] and supabase_flutter
  /// exchanges the code for a session automatically.
  /// Returns a user-facing error only when the flow cannot start or the
  /// user cancels in a detectable way.
  Future<String?> signInWithGoogle() async {
    try {
      final launched = await _client.auth.signInWithOAuth(
        OAuthProvider.google,
        redirectTo: SupabaseConfig.authCallbackUrl,
      );
      if (!launched) return 'Could not open the browser. Try again.';
      return null;
    } catch (error) {
      return friendlyError(error);
    }
  }

  Future<String?> sendPasswordReset({required String email}) async {
    try {
      await _client.auth.resetPasswordForEmail(
        email.trim(),
        // Recovery link returns to the app instead of a dead web page.
        redirectTo: SupabaseConfig.authCallbackUrl,
      );
      return null;
    } catch (error) {
      return friendlyError(error);
    }
  }

  Future<String?> resendVerification({required String email}) async {
    try {
      await _client.auth.resend(
        type: OtpType.signup,
        email: email.trim(),
        emailRedirectTo: SupabaseConfig.authCallbackUrl,
      );
      return null;
    } catch (error) {
      return friendlyError(error);
    }
  }

  Future<void> signOut() async {
    try {
      await _client.auth.signOut();
    } catch (_) {
      // Local session cleared best-effort; offline sign-out still works
      // because supabase_flutter clears storage before the network call.
    }
  }

  /// Ensures a public profile row exists for the current user (the DB
  /// trigger normally creates it; this is a safe idempotent repair).
  Future<void> ensureProfileRow({
    required String displayName,
    required String avatarId,
    required int blobVariant,
  }) async {
    final user = currentUser;
    if (user == null) return;
    await _client.from('community_profiles').upsert({
      'id': user.id,
      'display_name': displayName.trim().isEmpty
          ? 'Student'
          : displayName.trim(),
      'avatar_id': avatarId,
      'blob_variant': blobVariant,
    }, onConflict: 'id');
  }
}
