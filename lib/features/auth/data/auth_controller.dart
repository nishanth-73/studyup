import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/backend/supabase_client.dart';
import '../../../core/deeplink/invite_links.dart';
import '../../avatar/presentation/user_profile_controller.dart';
import '../../progress/presentation/study_progress_controller.dart';
import '../../social/data/session_sync.dart';
import '../../social/data/social_remote.dart';
import 'auth_repository.dart';

/// True when the app was built with Supabase credentials AND the client
/// initialized. All remote UI branches off this.
final backendLiveProvider = Provider<bool>((ref) {
  return ref.watch(backendReadyProvider);
});

final authRepositoryProvider = Provider<AuthRepository?>((ref) {
  if (!ref.watch(backendLiveProvider)) return null;
  return AuthRepository(Supabase.instance.client);
});

/// Raw Supabase auth events (sign in/out, token refresh, expiry).
/// Widgets showing account state watch this, never a cached user.
final supabaseAuthEventsProvider = StreamProvider<AuthState>((ref) {
  final repo = ref.watch(authRepositoryProvider);
  if (repo == null) return const Stream.empty();
  return repo.authChanges;
});

/// Authenticated user id, or null when signed out / backend missing.
/// This is the single source of truth for social actions.
final backendUserIdProvider = Provider<String?>((ref) {
  if (!ref.watch(backendLiveProvider)) return null;
  // Re-evaluate on every auth event (expiry, sign-out, refresh).
  ref.watch(supabaseAuthEventsProvider);
  try {
    return Supabase.instance.client.auth.currentUser?.id;
  } catch (_) {
    return null;
  }
});

final backendUserEmailProvider = Provider<String?>((ref) {
  final id = ref.watch(backendUserIdProvider);
  if (id == null) return null;
  try {
    return Supabase.instance.client.auth.currentUser?.email;
  } catch (_) {
    return null;
  }
});

/// Pending invitation token stashed before sign-in (peeked, not
/// consumed — the screen that handles it calls takePending). Auto-dispose
/// so a consumed/cancelled token is never replayed from the cache on a
/// later startup within the same process.
final pendingInviteProvider = FutureProvider.autoDispose<String?>((_) {
  return InviteLinks.peekPending();
});

/// One-shot post-sign-in linking, safe to watch from the startup gate:
/// ensures the public profile row, uploads local history once per
/// account (idempotent, nothing local deleted), then records the link.
/// Runs silently; offline and logged-out states are no-ops.
final postSignInLinkProvider = FutureProvider<void>((ref) async {
  final userId = ref.watch(backendUserIdProvider);
  if (userId == null) return;
  final prefs = await SharedPreferences.getInstance();
  if (prefs.getString('studyup.linkedUserId.v1') == userId) return;
  final repo = ref.watch(authRepositoryProvider);
  final profile = ref.watch(userProfileProvider).valueOrNull;
  if (repo != null && profile != null) {
    try {
      await repo.ensureProfileRow(
        displayName: profile.displayName,
        avatarId: profile.avatarId,
        blobVariant: profile.blobVariant,
      );
    } catch (_) {}
  }
  try {
    final sessions = ref.watch(studyProgressProvider).sessions;
    await SessionSyncService(SocialRemote(Supabase.instance.client))
        .syncAll(sessions);
  } catch (_) {}
  await prefs.setString('studyup.linkedUserId.v1', userId);
});

/// Clears the per-account link marker (called on sign-out so the next
/// account links and syncs fresh).
Future<void> clearPostSignInLink() async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.remove('studyup.linkedUserId.v1');
}
