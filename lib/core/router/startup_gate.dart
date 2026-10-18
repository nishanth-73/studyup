import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../features/auth/data/auth_controller.dart';
import '../../features/auth/presentation/auth_screen.dart';
import '../../features/community/presentation/invite_accept_screen.dart';
import '../../features/home/presentation/home_screen.dart';
import '../../features/onboarding/presentation/onboarding_screen.dart';
import '../../features/avatar/presentation/user_profile_controller.dart';
import '../../features/profile/presentation/setup_profile_screen.dart';
import '../../features/social/data/social_providers.dart';

/// Set by "Continue without an account" on the auth screen: lets a user
/// with local data keep using the app when the backend is configured
/// but they choose not to sign in. Cleared on sign-in/sign-out.
final offlineModeProvider = FutureProvider<bool>((_) async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.getBool('studyup.offlineMode.v1') ?? false;
});

/// Neutral startup gate: no branding, no animation, no artificial delay.
/// Routes to the first incomplete first-launch stage (or Home) as soon as
/// the persisted profile loads. Replaces the removed branded splash.
///
/// With the backend configured, an authenticated Supabase session is
/// additionally required (unless offline mode was explicitly chosen);
/// without the backend, the original local demo flow applies unchanged.
class StartupGate extends ConsumerWidget {
  const StartupGate({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Background session sync while signed in (no-op offline).
    ref.watch(sessionSyncTriggerProvider);
    // One-shot profile link + history sync after each sign-in.
    ref.watch(postSignInLinkProvider);
    final profile = ref.watch(userProfileProvider);
    return profile.when(
      loading: () => const SizedBox.shrink(),
      error: (_, _) => const HomeScreen(),
      data: (user) {
        if (user == null || !user.slidesSeen) {
          return const OnboardingScreen();
        }
        if (!user.setupComplete) {
          return const SetupProfileScreen();
        }
        if (ref.watch(backendLiveProvider)) {
          final signedIn = ref.watch(backendUserIdProvider) != null;
          final offline = ref.watch(offlineModeProvider).valueOrNull ?? false;
          if (!signedIn && !offline) {
            return const AuthScreen();
          }
          if (signedIn) {
            // A pending invitation survives sign-in (including the OAuth
            // browser round-trip) and survives a cold start from an App
            // Link: resume it instead of Home. The pending lookup is
            // awaited first so a valid invitation is never flashed away
            // to Home (or lost) while SharedPreferences is read.
            final pending = ref.watch(pendingInviteProvider);
            return pending.when(
              data: (token) =>
                  token != null && token.isNotEmpty
                      ? InviteAcceptScreen(token: token)
                      : const HomeScreen(),
              loading: () => const SizedBox.shrink(),
              error: (_, _) => const HomeScreen(),
            );
          }
          return const HomeScreen();
        }
        if (!user.demoSignedIn) {
          return const AuthScreen();
        }
        return const HomeScreen();
      },
    );
  }
}
