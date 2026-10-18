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

  // The session sync service keys its "already uploaded" ledger by the
  // authenticated user id, which the fake SupabaseClient cannot provide.
  @override
  String get userId => 'me';

  @override
  Future<void> upsertSession(StudySession session) async {
    uploaded.add(session.id);
  }

  @override
  Future<List<RemoteFriend>> myFriends() async => const [];

  @override
  Future<List<RemoteBoardRow>> leaderboard({
    required DateTime weekStart,
  }) async => const [];

  @override
  RealtimeChannel subscribeFriendships(void Function() onChange) =>
      client.channel('friendships');
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
      {
        'startTime': start.toIso8601String(),
        'endTime': now.toIso8601String(),
      },
    ],
  };
}

void main() {
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