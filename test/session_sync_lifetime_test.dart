import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:studyup/features/auth/data/auth_controller.dart';
import 'package:studyup/features/progress/data/study_session.dart';
import 'package:studyup/features/social/data/social_providers.dart';
import 'package:studyup/features/social/data/social_remote.dart';
import 'package:studyup/features/social/data/session_sync.dart';
import 'package:studyup/main.dart';

/// Production bug: friends saw 0m / "waiting" for real study time.
///
/// The upload trigger was watched only by the startup gate ('/'), which
/// unmounts the moment the router navigates to /home or /community — so a
/// session that ended anywhere else in the app never reached Supabase and
/// every friend's weekly total read 0. These tests pin that a finished
/// session uploads while the app is running, whatever route is mounted.
class _RecordingRemote extends SocialRemote {
  _RecordingRemote()
    : client = SupabaseClient(
        'https://example.supabase.co',
        'test-anon-key',
        authOptions: const AuthClientOptions(autoRefreshToken: false),
      ),
      super(
        SupabaseClient(
          'https://example.supabase.co',
          'test-anon-key',
          authOptions: const AuthClientOptions(autoRefreshToken: false),
        ),
      );

  final SupabaseClient client;
  final uploaded = <String>[];
  final uploadedSessions = <StudySession>[];

  // The session sync service keys its "already uploaded" ledger by the
  // authenticated user id, which the fake SupabaseClient cannot provide.
  @override
  String get userId => 'me';

  @override
  Future<void> upsertSession(StudySession session) async {
    uploaded.add(session.id);
    uploadedSessions.add(session);
  }

  @override
  Future<List<RemoteFriend>> myFriends() async => const [];

  @override
  Future<List<RemoteBoardRow>> leaderboard({
    required DateTime weekStart,
  }) async => const [];

  @override
  RealtimeChannel subscribeFriendships(
    void Function() onChange, {
    void Function(RealtimeSubscribeStatus status, Object? error)? onStatus,
  }) => client.channel('friendships');
}

class _BlockingRemote extends _RecordingRemote {
  final firstUploadStarted = Completer<void>();
  final releaseFirstUpload = Completer<void>();

  @override
  Future<void> upsertSession(StudySession session) async {
    if (!firstUploadStarted.isCompleted) {
      firstUploadStarted.complete();
      await releaseFirstUpload.future;
    }
    uploaded.add(session.id);
    uploadedSessions.add(session);
  }
}

Map<String, Object?> endedSessionDoc() {
  final now = DateTime.now();
  final start = now.subtract(const Duration(hours: 2));
  return {
    'id': 's-upload-1',
    'subjectId': 'general',
    'subjectName': 'Daily Study',
    'checkInTime': start.toIso8601String(),
    'checkOutTime': now.toIso8601String(),
    'pausedSeconds': 7200,
    'studySegments': [
      {'startTime': start.toIso8601String(), 'endTime': now.toIso8601String()},
    ],
  };
}

Map<String, Object?> pausedSessionDoc() {
  final now = DateTime.now();
  final start = now.subtract(const Duration(hours: 2));
  final pause = now.subtract(const Duration(hours: 1));
  return {
    'id': 's-paused-upload',
    'subjectId': 'general',
    'subjectName': 'Daily Study',
    'checkInTime': start.toIso8601String(),
    'checkOutTime': null,
    'pausedSeconds': 3600,
    'studySegments': [
      {
        'startTime': start.toIso8601String(),
        'endTime': pause.toIso8601String(),
      },
    ],
    'resumedAt': null,
  };
}

void main() {
  test('paused study segments sync and newer snapshots replace them', () async {
    SharedPreferences.setMockInitialValues({});
    final remote = _RecordingRemote();
    final service = SessionSyncService(remote);
    final start = DateTime.now().subtract(const Duration(minutes: 10));
    final firstSegment = StudyTimeSegment(
      startTime: start,
      endTime: start.add(const Duration(minutes: 2)),
    );
    final firstPause = StudySession(
      id: 's-paused',
      subjectId: 'general',
      subjectName: 'Daily Study',
      checkInTime: start,
      pausedSeconds: 120,
      studySegments: [firstSegment],
    );

    expect(await service.syncAll([firstPause]), 1);
    expect(remote.uploadedSessions.single.checkOutTime, isNull);
    expect(await service.syncAll([firstPause]), 0);

    final secondSegment = StudyTimeSegment(
      startTime: start.add(const Duration(minutes: 3)),
      endTime: start.add(const Duration(minutes: 5)),
    );
    final resumedPause = StudySession(
      id: 's-paused',
      subjectId: 'general',
      subjectName: 'Daily Study',
      checkInTime: start,
      pausedSeconds: 240,
      studySegments: [firstSegment, secondSegment],
    );
    expect(await service.syncAll([resumedPause]), 1);
    expect(remote.uploadedSessions.last.studySegments, hasLength(2));

    final ended = StudySession(
      id: 's-paused',
      subjectId: 'general',
      subjectName: 'Daily Study',
      checkInTime: start,
      checkOutTime: secondSegment.endTime,
      pausedSeconds: 240,
      studySegments: [firstSegment, secondSegment],
    );
    expect(await service.syncAll([ended]), 1);
    expect(await service.syncAll([ended]), 0);
    expect(remote.uploaded, ['s-paused', 's-paused', 's-paused']);
  });
  test(
    'queued session sync uploads the newer snapshot after an in-flight save',
    () async {
      SharedPreferences.setMockInitialValues({});
      final remote = _BlockingRemote();
      final service = SessionSyncService(remote);
      final first = StudySession.fromJson(endedSessionDoc());
      final secondDoc = endedSessionDoc()..['id'] = 's-upload-2';
      final second = StudySession.fromJson(secondDoc);

      final firstSync = service.syncAll([first]);
      await remote.firstUploadStarted.future;
      final newerSync = service.syncAll([first, second]);
      remote.releaseFirstUpload.complete();

      expect(await firstSync, 1);
      expect(await newerSync, 1);
      expect(remote.uploaded, ['s-upload-1', 's-upload-2']);
    },
  );

  testWidgets(
    'a finished session uploads while the app runs on a non-gate route',
    (tester) async {
      SharedPreferences.setMockInitialValues({
        'studyup.studySessions.v1': jsonEncode([endedSessionDoc()]),
      });
      final remote = _RecordingRemote();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            socialLiveProvider.overrideWithValue(true),
            backendUserIdProvider.overrideWithValue('me'),
            socialRemoteProvider.overrideWithValue(remote),
          ],
          child: const StudyUpApp(),
        ),
      );
      await tester.pump();
      // The root widget owns the sync trigger for the whole app lifetime;
      // the old StartupGate-only watch is what stranded these uploads.
      for (var i = 0; i < 100 && remote.uploaded.isEmpty; i++) {
        await tester.pump(const Duration(milliseconds: 20));
      }

      expect(remote.uploaded, ['s-upload-1']);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('a paused saved segment uploads while the session is active', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'studyup.studySessions.v1': jsonEncode([pausedSessionDoc()]),
    });
    final remote = _RecordingRemote();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          socialLiveProvider.overrideWithValue(true),
          backendUserIdProvider.overrideWithValue('me'),
          socialRemoteProvider.overrideWithValue(remote),
        ],
        child: const StudyUpApp(),
      ),
    );
    await tester.pump();
    for (var i = 0; i < 100 && remote.uploaded.isEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }

    expect(remote.uploaded, ['s-paused-upload']);
    expect(remote.uploadedSessions.single.checkOutTime, isNull);
    expect(remote.uploadedSessions.single.pausedSeconds, 3600);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('uploading is idempotent: a synced session is never resent', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'studyup.studySessions.v1': jsonEncode([endedSessionDoc()]),
      // Marked as already uploaded for this account (StringList, not JSON).
      'studyup.syncedSessionIds.v1.me': <String>['s-upload-1'],
    });
    final remote = _RecordingRemote();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          socialLiveProvider.overrideWithValue(true),
          backendUserIdProvider.overrideWithValue('me'),
          socialRemoteProvider.overrideWithValue(remote),
        ],
        child: const StudyUpApp(),
      ),
    );
    await tester.pump();
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }

    expect(remote.uploaded, isEmpty);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('signed out or offline: no uploads, no crash', (tester) async {
    SharedPreferences.setMockInitialValues({
      'studyup.studySessions.v1': jsonEncode([endedSessionDoc()]),
    });
    final remote = _RecordingRemote();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          // No session: the trigger must no-op.
          socialLiveProvider.overrideWithValue(false),
          backendUserIdProvider.overrideWithValue(null),
          socialRemoteProvider.overrideWithValue(null),
        ],
        child: const StudyUpApp(),
      ),
    );
    await tester.pump();
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }

    expect(remote.uploaded, isEmpty);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
