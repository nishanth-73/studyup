import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/user_profile.dart';

/// Owns the persistent user identity: display name + onboarding state.
/// Null state = no profile yet (fresh install or skipped onboarding) —
//  callers must show the onboarding state, never a random avatar.
class UserProfileController extends StateNotifier<AsyncValue<UserProfile?>> {
  UserProfileController() : super(const AsyncValue.loading()) {
    unawaited(_load());
  }

  static const _storageKey = 'studyup.userProfile.v1';

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_storageKey);
      if (raw == null || raw.isEmpty) {
        state = const AsyncValue.data(null);
        return;
      }
      state = AsyncValue.data(
        UserProfile.fromJson(Map<String, Object?>.from(jsonDecode(raw) as Map)),
      );
    } catch (error, stackTrace) {
      state = AsyncValue.error(error, stackTrace);
    }
  }

  Future<void> _save(UserProfile profile) async {
    final prefs = await SharedPreferences.getInstance();
    final saved = await prefs.setString(
      _storageKey,
      jsonEncode(profile.toJson()),
    );
    if (!saved) throw StateError('Could not persist the user profile.');
    state = AsyncValue.data(profile);
  }

  /// First-time setup: stores the entered name and marks onboarding
  /// complete with the default avatar.
  ///
  /// Kept for backward compatibility (and old tests): completes the whole
  /// funnel at once with the default avatar and demo access granted.
  Future<void> completeOnboarding({required String displayName}) async {
    final name = displayName.trim();
    if (name.isEmpty) throw ArgumentError('Display name must not be empty.');
    await _save(
      UserProfile(
        displayName: name,
        blobName: name.toLowerCase(),
        onboardingComplete: true,
        slidesSeen: true,
        setupComplete: true,
        demoSignedIn: true,
      ),
    );
  }

  /// Intro slides finished (Skip or Get Started). Name/avatar/goal may
  /// still be missing — later stages collect them.
  Future<void> markSlidesSeen() async {
    final current = state.valueOrNull;
    if (current == null) {
      await _save(
        const UserProfile(
          displayName: '',
          blobName: '',
          onboardingComplete: false,
          slidesSeen: true,
          setupComplete: false,
          demoSignedIn: false,
        ),
      );
      return;
    }
    await _save(current.copyWith(slidesSeen: true));
  }

  /// Blob + name step finished (goal step still pending). Kept separate
  /// from [completeSetup] so an interrupted flow resumes at goal select.
  /// [avatarId] is optional for backward compatibility: when omitted, the
  /// stored (or default) avatar is preserved.
  Future<void> saveSetupProgress({
    required int blobVariant,
    required String displayName,
    String? avatarId,
  }) async {
    if (!isValidBlobVariant(blobVariant)) {
      throw ArgumentError('Unknown Blob variant: $blobVariant.');
    }
    final name = displayName.trim();
    if (name.isEmpty) throw ArgumentError('Display name must not be empty.');
    if (avatarId != null && !isValidAvatarId(avatarId)) {
      throw ArgumentError('Unknown avatar: $avatarId.');
    }
    final current = state.valueOrNull;
    final profile = current?.copyWith(
      displayName: name,
      blobName: current.blobName.isEmpty ? name.toLowerCase() : null,
      onboardingComplete: false,
      blobVariant: blobVariant,
      avatarId: avatarId,
      slidesSeen: true,
      setupComplete: false,
      demoSignedIn: false,
    );
    await _save(
      profile ??
          UserProfile(
            displayName: name,
            blobName: name.toLowerCase(),
            onboardingComplete: false,
            blobVariant: blobVariant,
            avatarId: avatarId ?? defaultAvatarId,
            slidesSeen: true,
            setupComplete: false,
            demoSignedIn: false,
          ),
    );
  }

  /// Goal step finished: the whole first-launch setup is done. The demo
  /// auth screen still follows (see [demoSignIn]).
  Future<void> completeSetup() async {
    final current = state.valueOrNull;
    if (current == null) throw StateError('No user profile exists yet.');
    if (current.displayName.trim().isEmpty) {
      throw StateError('Display name must be set before completing setup.');
    }
    await _save(
      current.copyWith(
        onboardingComplete: true,
        slidesSeen: true,
        setupComplete: true,
      ),
    );
  }

  /// Temporary local demo access (NO backend, NO password storage).
  /// Records only the email as an identifier; the password is never
  /// persisted. Replace with Supabase session handling later.
  Future<void> demoSignIn({required String email}) async {
    final current = state.valueOrNull;
    if (current == null) throw StateError('No user profile exists yet.');
    final address = email.trim();
    if (address.isEmpty) throw ArgumentError('Email must not be empty.');
    await _save(current.copyWith(demoSignedIn: true, demoEmail: address));
  }

  /// Drops local demo access (used by tests; no UI wired yet).
  Future<void> demoSignOut() async {
    final current = state.valueOrNull;
    if (current == null) throw StateError('No user profile exists yet.');
    await _save(current.copyWith(demoSignedIn: false));
  }

  /// Rename without touching anything else.
  Future<void> updateDisplayName(String displayName) async {
    final current = state.valueOrNull;
    if (current == null) throw StateError('No user profile exists yet.');
    final name = displayName.trim();
    if (name.isEmpty) throw ArgumentError('Display name must not be empty.');
    await _save(current.copyWith(displayName: name));
  }

  /// Change the PNG avatar portrait without touching anything else.
  /// Unknown ids are rejected; rendering falls back to the default.
  Future<void> updateAvatarId(String avatarId) async {
    final current = state.valueOrNull;
    if (current == null) throw StateError('No user profile exists yet.');
    if (!isValidAvatarId(avatarId)) {
      throw ArgumentError('Unknown avatar: $avatarId.');
    }
    await _save(current.copyWith(avatarId: avatarId));
  }

  /// Change Blob color without touching anything else.
  Future<void> updateBlobVariant(int blobVariant) async {
    final current = state.valueOrNull;
    if (current == null) throw StateError('No user profile exists yet.');
    if (!isValidBlobVariant(blobVariant)) {
      throw ArgumentError('Unknown Blob variant: $blobVariant.');
    }
    await _save(current.copyWith(blobVariant: blobVariant));
  }
}

final userProfileProvider =
    StateNotifierProvider<UserProfileController, AsyncValue<UserProfile?>>(
      (ref) => UserProfileController(),
    );
