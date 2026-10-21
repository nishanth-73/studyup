import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../auth/data/auth_controller.dart';
import '../../progress/data/study_session.dart';
import '../../progress/presentation/study_progress_controller.dart';
import 'session_sync.dart';
import 'social_remote.dart';

/// Live when the backend is configured AND the user is signed in.
/// Only then may any server call run; otherwise the app stays on the
/// local path and says so in the UI.
final socialLiveProvider = Provider<bool>((ref) {
  return ref.watch(backendLiveProvider) &&
      ref.watch(backendUserIdProvider) != null;
});

final socialRemoteProvider = Provider<SocialRemote?>((ref) {
  if (!ref.watch(socialLiveProvider)) return null;
  return SocialRemote(Supabase.instance.client);
});

/// Background trigger: uploads newly saved closed intervals whenever the
/// study list changes while signed in (kept alive for the app lifetime).
/// Idempotent — retries and re-syncs never duplicate rows.
final sessionSyncTriggerProvider = Provider<void>((ref) {
  if (!ref.watch(socialLiveProvider)) return;
  final sessions = ref.watch(
    studyProgressProvider.select((state) => state.sessions),
  );
  final remote = ref.watch(socialRemoteProvider);
  if (remote == null) return;
  var disposed = false;
  var retryDelay = const Duration(seconds: 15);
  Timer? retryTimer;

  Future<void> sync() async {
    final succeeded = await _syncQuietly(ref, remote, sessions);
    if (disposed) return;
    retryTimer?.cancel();
    if (succeeded) {
      retryDelay = const Duration(seconds: 15);
      return;
    }
    retryTimer = Timer(retryDelay, sync);
    retryDelay = Duration(
      seconds: (retryDelay.inSeconds * 2).clamp(15, 120).toInt(),
    );
  }

  ref.onDispose(() {
    disposed = true;
    retryTimer?.cancel();
  });
  unawaited(sync());
});

/// Honest sync state for the UI: in-flight, unsynced backlog count, and
/// the last failure (cleared on the next success). Never claims server
/// data is present when it is not.
@immutable
class SyncStatus {
  final bool syncing;
  final int pending;
  final String? lastError;
  final DateTime? lastOk;

  const SyncStatus({
    this.syncing = false,
    this.pending = 0,
    this.lastError,
    this.lastOk,
  });

  SyncStatus copyWith({
    bool? syncing,
    int? pending,
    String? lastError,
    DateTime? lastOk,
  }) => SyncStatus(
    syncing: syncing ?? this.syncing,
    pending: pending ?? this.pending,
    lastError: lastError,
    lastOk: lastOk ?? this.lastOk,
  );
}

final syncStatusProvider = StateProvider<SyncStatus>((_) => const SyncStatus());

Future<bool> _syncQuietly(
  Ref ref,
  SocialRemote remote,
  List<StudySession> sessions,
) async {
  final notifier = ref.read(syncStatusProvider.notifier);
  try {
    final synced = await SessionSyncService(remote).syncedIds();
    final pending = sessions
        .where((s) => s.checkOutTime != null && !synced.contains(s.id))
        .length;
    final hasSavedIntervals = sessions.any(
      (session) =>
          session.studySegments.any((segment) => segment.endTime != null),
    );
    notifier.state = notifier.state.copyWith(
      syncing: pending > 0 || hasSavedIntervals,
      pending: pending,
      lastError: null,
    );
    final service = SessionSyncService(remote);
    final uploaded = await service.syncAll(sessions);
    final after = await service.syncedIds();
    final remaining = sessions
        .where((s) => s.checkOutTime != null && !after.contains(s.id))
        .length;
    notifier.state = SyncStatus(
      pending: remaining,
      lastOk: uploaded > 0 ? DateTime.now() : notifier.state.lastOk,
    );
    return true;
  } catch (error) {
    // Offline or server error: retain the backlog; the trigger retries with
    // bounded backoff. Never fake success.
    final current = notifier.state;
    notifier.state = current.copyWith(
      syncing: false,
      lastError: error.toString(),
    );
    return false;
  }
}
