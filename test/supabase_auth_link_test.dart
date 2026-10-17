import 'package:flutter_test/flutter_test.dart';
import 'package:studyup/core/backend/supabase_config.dart';
import 'package:studyup/features/auth/data/auth_repository.dart';
import 'package:studyup/features/social/data/social_remote.dart';

/// Redirect-callback contract tests. These pin the exact values the user
/// must enter in Supabase Dashboard → Authentication → URL Configuration,
/// and guard the coexistence of the Supabase auth observer with the
/// invite deep-link router.
void main() {
  group('auth callback URL', () {
    test('is the exact native callback to allowlist', () {
      // Add EXACTLY this string under Allowed Redirect URLs.
      expect(
        SupabaseConfig.authCallbackUrl,
        'com.studyup.studyup://login-callback/',
      );
    });

    test('scheme matches the Android applicationId', () {
      final uri = Uri.parse(SupabaseConfig.authCallbackUrl);
      expect(uri.scheme, 'com.studyup.studyup');
      expect(uri.host, 'login-callback');
      expect(uri.scheme, isNot('https'));
    });

    test('invite parser ignores auth callbacks (with code or tokens)', () {
      // PKCE code exchange.
      expect(
        parseInviteToken(
          Uri.parse(
            'com.studyup.studyup://login-callback?code=abc123XYZ-_~000000000000000000000000000000000000',
          ),
        ),
        isNull,
      );
      // Implicit-flow fragment tokens.
      expect(
        parseInviteToken(
          Uri.parse(
            'com.studyup.studyup://login-callback/#access_token=eyJhbGciOiJIUzI1NiJ9&refresh_token=xyz',
          ),
        ),
        isNull,
      );
      // Error callbacks stay with the auth observer too.
      expect(
        parseInviteToken(
          Uri.parse(
            'com.studyup.studyup://login-callback?error=access_denied&error_code=otp_expired',
          ),
        ),
        isNull,
      );
    });

    test('invite links still parse alongside the callback', () {
      const raw = 'abcdef1234567890abcdef1234567890abcdef1234567890abcdef12';
      expect(
        parseInviteToken(Uri.parse('https://invite.studyup.app/i/$raw')),
        raw,
      );
      expect(parseInviteToken(Uri.parse('studyup://invite/$raw')), raw);
    });
  });

  group('auth error mapping', () {
    test('user cancellation is friendly, not a crash dump', () {
      expect(
        AuthRepository.friendlyError(
          Exception('User cancelled the sign-in flow'),
        ),
        'Sign-in was cancelled before completing.',
      );
      expect(
        AuthRepository.friendlyError(Exception('access_denied: user denied')),
        'Sign-in was cancelled before completing.',
      );
    });

    test('browser launch failures are actionable', () {
      expect(
        AuthRepository.friendlyError(
          Exception('Could not launch browser intent'),
        ),
        contains('browser'),
      );
    });

    test('known auth failures keep their messages', () {
      expect(
        AuthRepository.friendlyError(Exception('Invalid login credentials')),
        'Wrong email or password. Try again.',
      );
      expect(
        AuthRepository.friendlyError(Exception('Email not confirmed')),
        contains('verify'),
      );
    });
  });
}
