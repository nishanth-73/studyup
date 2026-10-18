import 'package:flutter_test/flutter_test.dart';
import 'package:studyup/core/backend/supabase_config.dart';
import 'package:studyup/features/progress/data/study_session.dart';
import 'package:studyup/features/social/data/social_remote.dart';

StudySession _session(DateTime start, DateTime end) => StudySession(
  id: 's-${start.millisecondsSinceEpoch}',
  subjectId: 'general',
  subjectName: 'Daily Study',
  checkInTime: start,
  checkOutTime: end,
  pausedSeconds: end.difference(start).inSeconds,
  studySegments: [StudyTimeSegment(startTime: start, endTime: end)],
);

void main() {
  group('supabase config (no credentials in tests)', () {
    test('backend reports unconfigured without dart-defines', () {
      expect(SupabaseConfig.isConfigured, isFalse);
      expect(SupabaseConfig.url, isEmpty);
      expect(SupabaseConfig.anonKey, isEmpty);
    });

    test('invite host defaults are sane placeholders', () {
      expect(SupabaseConfig.inviteHost, isNotEmpty);
      expect(SupabaseConfig.inviteScheme, isNotEmpty);
    });

    test('.env values apply when dart-defines are absent', () {
      SupabaseConfig.loadFileEnv({
        'SUPABASE_URL': 'https://abc.supabase.co',
        'SUPABASE_ANON_KEY': 'anon-key',
        'INVITE_HOST': 'invite.example.com',
      });
      addTearDown(() => SupabaseConfig.loadFileEnv(const {}));
      expect(SupabaseConfig.isConfigured, isTrue);
      expect(SupabaseConfig.url, 'https://abc.supabase.co');
      expect(SupabaseConfig.anonKey, 'anon-key');
      expect(SupabaseConfig.inviteHost, 'invite.example.com');
    });

    test('placeholder and example values never count as configured', () {
      SupabaseConfig.loadFileEnv({
        'SUPABASE_URL': 'https://example.supabase.co',
        'SUPABASE_ANON_KEY': 'YOUR_KEY',
      });
      addTearDown(() => SupabaseConfig.loadFileEnv(const {}));
      expect(SupabaseConfig.isConfigured, isFalse);
    });
  });

  group('invitation tokens', () {
    test('generated tokens are 128-bit hex and unique', () {
      final a = newInviteToken();
      final b = newInviteToken();
      expect(a.length, 32);
      expect(RegExp(r'^[0-9a-f]{32}$').hasMatch(a), isTrue);
      expect(a, isNot(equals(b)));
    });

    test('hash is deterministic SHA-256 hex', () {
      expect(hashInviteToken('abc'), hashInviteToken('abc'));
      expect(hashInviteToken('abc').length, 64);
      expect(hashInviteToken('abc'), isNot(equals(hashInviteToken('abd'))));
    });

    test('links embed the token under /i/', () {
      const raw = 'abcdef1234567890abcdef1234567890abcdef1234567890abcdef12';
      expect(
        inviteLinkFor(raw, host: 'invite.example.com'),
        'https://invite.example.com/i/$raw',
      );
      expect(() => inviteLinkFor('SUP1-encoded-payload'), throwsArgumentError);
    });

    test('share message contains only the friendly text and invite URL', () {
      const link =
          'https://invite.example.com/i/abcdef1234567890abcdef1234567890';
      final message = inviteShareMessage(link);
      expect(
        message,
        "Join me on StudyUp! Let's track our study progress and compete together: $link",
      );
      expect(message, isNot(contains('SUP1-')));
      expect(message, isNot(contains('"uid"')));
    });

    test('parses App Links and custom-scheme URLs', () {
      const raw = 'abcdef1234567890abcdef1234567890';
      expect(
        parseInviteToken(Uri.parse('https://invite.studyup.app/i/$raw')),
        raw,
      );
      expect(
        parseInviteToken(Uri.parse('https://invite.studyup.app/invite/$raw/')),
        raw,
      );
      expect(
        parseInviteToken(Uri.parse('https://other.example/i/$raw')),
        raw, // host never matters; the token + server validation do
      );
      expect(parseInviteToken(Uri.parse('studyup://invite/$raw')), raw);
      expect(parseInviteToken(Uri.parse('studyup:///i/$raw')), raw);
    });

    test('routes malformed short tokens to app validation', () {
      expect(parseInviteToken(Uri.parse('https://x.test/i/')), isNull);
      expect(parseInviteToken(Uri.parse('https://x.test/x/abc')), isNull);
      expect(parseInviteToken(Uri.parse('https://x.test/i/short')), 'short');
      expect(parseInviteToken(Uri.parse('studyup://invite/')), isNull);
      expect(parseInviteToken(Uri.parse('mailto:a@b.c')), isNull);
      expect(
        parseInviteToken(Uri.parse('https://x.test/i/NOT-HEX!!')),
        'NOT-HEX!!',
      );
    });
  });

  group('session day splits (client-computed, server-validated)', () {
    test('single-day session yields one row matching segments', () {
      final s = _session(DateTime(2026, 10, 12, 9), DateTime(2026, 10, 12, 11));
      final rows = splitSessionDays(s);
      expect(rows, hasLength(1));
      expect(rows.single['day'], '2026-10-12');
      expect(rows.single['seconds'], 2 * 3600);
      expect(rows.single['day_start_utc'], isNotNull);
    });

    test('overnight session splits at local midnight', () {
      final s = _session(
        DateTime(2026, 10, 12, 23),
        DateTime(2026, 10, 13, 1, 30),
      );
      final rows = splitSessionDays(s);
      expect(rows, hasLength(2));
      final first = rows.firstWhere((r) => r['day'] == '2026-10-12');
      final second = rows.firstWhere((r) => r['day'] == '2026-10-13');
      expect(first['seconds'], 3600);
      expect(second['seconds'], 5400);
    });

    test('open (running) segments are excluded — sync on checkout only', () {
      final s = StudySession(
        id: 'live',
        subjectId: 'general',
        subjectName: 'Daily Study',
        checkInTime: DateTime(2026, 10, 12, 9),
        pausedSeconds: 0,
        studySegments: [StudyTimeSegment(startTime: DateTime(2026, 10, 12, 9))],
      );
      expect(splitSessionDays(s), isEmpty);
    });
  });
}
