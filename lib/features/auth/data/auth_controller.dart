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

/// True once the backend knows whether a session exists.
///
/// `Supabase.initialize()` starts session recovery but does NOT await it
/// (see supabase_flutter/src/supabase.dart: recoverSession runs inside a
/// CancelableOperation). On a cold start `currentUser` is therefore null
/// for a short moment EVEN for a signed-in user — reading it too early
/// made the invitation screen ask an existing user to sign in again.
///
/// Resolution order: a restored session answers immediately; otherwise we
/// wait for the first auth event (gotrue emits `initialSession` once the
/// persisted session is restored, `signedOut` when there is none), bounded
/// so a silent/offline backend can never block the UI.
final authSettledProvider = FutureProvider<bool>((ref) async {
  if (!ref.watch(backendLiveProvider)) return true;
  String? currentUserId() {
    try {
      return Supabase.instance.client.auth.currentUser?.id;
    } catch (_) {
      return null;
    }
  }

  if (currentUserId() != null) return true;
  final repo = ref.watch(authRepositoryProvider);
  if (repo == null) return true;
  try {
    await repo.authChanges.first.timeout(const Duration(seconds: 6));
  } catch (_) {
    // No event (signed out, offline, or backend silent): whatever the
    // current state is, it is the settled state.
  }
  return true;
});

const localDataOwnerPreferenceKey = 'studyup.localDataOwnerUserId.v1';
const _linkedUserPreferenceKey = 'studyup.linkedUserId.v1';

/// Allows one Supabase account to use the local study data on this device.
/// The owner is permanent until the user explicitly erases local data.
/// The older one-shot link key is used as the owner during migration.
final localAccountDataAccessProvider = FutureProvider.family<bool, String>((
  _,
  userId,
) async {
  if (userId.isEmpty) {
    throw ArgumentError.value(userId, 'userId', 'Must not be empty.');
  }
  final prefs = await SharedPreferences.getInstance();
  final owner = prefs.getString(localDataOwnerPreferenceKey);
  final previousLink = prefs.getString(_linkedUserPreferenceKey);
  final knownOwner = owner?.isNotEmpty == true ? owner : previousLink;
  if (knownOwner != null && knownOwner != userId) return false;
  if (owner == null || owner.isEmpty) {
    final saved = await prefs.setString(localDataOwnerPreferenceKey, userId);
    if (!saved) {
      throw StateError('Could not protect this device’s local study data.');
    }
  }
  return true;
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
  if (!await ref.watch(localAccountDataAccessProvider(userId).future)) return;
  final prefs = await SharedPreferences.getInstance();
  if (prefs.getString(_linkedUserPreferenceKey) == userId) return;
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
  await prefs.setString(_linkedUserPreferenceKey, userId);
});

/// Clears the one-shot sync marker on sign-out. The separate local-data
/// owner marker intentionally survives sign-out to prevent account mixing.
Future<void> clearPostSignInLink() async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.remove(_linkedUserPreferenceKey);
}
