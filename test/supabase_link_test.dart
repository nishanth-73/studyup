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

    test('.env values apply when dart-defines are absent', () {
      SupabaseConfig.loadFileEnv({
        'SUPABASE_URL': 'https://abc.supabase.co',
        'SUPABASE_ANON_KEY': 'anon-key',
      });
      addTearDown(() => SupabaseConfig.loadFileEnv(const {}));
      expect(SupabaseConfig.isConfigured, isTrue);
      expect(SupabaseConfig.url, 'https://abc.supabase.co');
      expect(SupabaseConfig.anonKey, 'anon-key');
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
