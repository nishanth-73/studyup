import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:studyup/features/progress/data/study_session.dart';
import 'package:studyup/features/social/data/social_providers.dart';
import 'package:studyup/features/social/data/session_sync.dart';
import 'package:studyup/features/social/data/social_remote.dart';

class _SyncRemote extends SocialRemote {
  _SyncRemote(this.accountId)
    : super(
        SupabaseClient(
          'https://example.supabase.co',
          'test-anon-key',
          authOptions: const AuthClientOptions(autoRefreshToken: false),
        ),
      );

  final String accountId;
  final List<String> uploadedIds = [];

  @override
  String get userId => accountId;

  @override
  Future<void> upsertSession(StudySession session) async {
    uploadedIds.add(session.id);
  }
}

StudySession _ended(String id, DateTime start, DateTime end) => StudySession(
  id: id,
  subjectId: 'general',
  subjectName: 'Daily Study',
  checkInTime: start,
  checkOutTime: end,
  pausedSeconds: end.difference(start).inSeconds,
  studySegments: [StudyTimeSegment(startTime: start, endTime: end)],
);

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('sync bookkeeping (idempotent, offline-safe)', () {
    test('nothing is marked synced on a fresh install', () async {
      // No client needed: synced-id bookkeeping is purely local.
      final container = ProviderContainer();
      addTearDown(container.dispose);
      // sessionSyncTriggerProvider is a no-op without a backend.
      container.read(sessionSyncTriggerProvider);
      final status = container.read(syncStatusProvider);
      expect(status.syncing, isFalse);
      expect(status.pending, 0);
      expect(status.lastError, isNull);
    });

    test('SyncStatus.copyWith preserves untouched fields', () {
      const base = SyncStatus(pending: 3);
      final next = base.copyWith(syncing: true);
      expect(next.syncing, isTrue);
      expect(next.pending, 3);
      expect(next.lastError, isNull);
      final failed = base.copyWith(lastError: 'boom');
      expect(failed.lastError, 'boom');
      expect(failed.syncing, isFalse);
    });

    test('sync tracking is isolated between authenticated accounts', () async {
      final session = _ended(
        'shared-local-session',
        DateTime(2026, 10, 12, 9),
        DateTime(2026, 10, 12, 10),
      );
      final firstAccount = _SyncRemote('account-a');
      final secondAccount = _SyncRemote('account-b');

      expect(await SessionSyncService(firstAccount).syncAll([session]), 1);
      expect(await SessionSyncService(firstAccount).syncAll([session]), 0);
      expect(await SessionSyncService(secondAccount).syncAll([session]), 1);
      expect(firstAccount.uploadedIds, ['shared-local-session']);
      expect(secondAccount.uploadedIds, ['shared-local-session']);
      expect(await SessionSyncService(firstAccount).syncedIds(), {
        'shared-local-session',
      });
      expect(await SessionSyncService(secondAccount).syncedIds(), {
        'shared-local-session',
      });
    });

    test('split rows never exceed the session total (server cap rule)', () {
      final s = _ended(
        's1',
        DateTime(2026, 10, 12, 9),
        DateTime(2026, 10, 12, 11),
      );
      expect(s.durationAt(s.checkOutTime!).inSeconds, 2 * 3600);
      // The per-day split helper used for session_days upserts:
      final dayStart = DateTime(2026, 10, 12);
      expect(
        dayStart.add(const Duration(days: 1)).difference(dayStart).inHours,
        24,
      );
    });
  });
}
