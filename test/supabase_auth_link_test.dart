import 'package:flutter_test/flutter_test.dart';
import 'package:studyup/core/backend/supabase_config.dart';
import 'package:studyup/features/auth/data/auth_repository.dart';

/// Redirect-callback contract tests. These pin the exact values the user
/// must enter in Supabase Dashboard → Authentication → URL Configuration.
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
