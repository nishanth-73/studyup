import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../theme/app_colors.dart';
import '../../features/auth/data/auth_controller.dart';
import '../../features/auth/presentation/auth_screen.dart';
import '../../features/home/presentation/home_screen.dart';
import '../../features/onboarding/presentation/onboarding_screen.dart';
import '../../features/avatar/presentation/user_profile_controller.dart';
import '../../features/profile/presentation/setup_profile_screen.dart';
import '../../features/social/data/social_providers.dart';

/// Neutral startup gate: no branding, no animation, no artificial delay.
/// Routes to the first incomplete first-launch stage (or Home) as soon as
/// the persisted profile loads. Replaces the removed branded splash.
class StartupGate extends ConsumerWidget {
  const StartupGate({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // One-shot profile link + history sync after each sign-in.
    ref.watch(postSignInLinkProvider);
    final profile = ref.watch(userProfileProvider);
    return profile.when(
      loading: _startupLoading,
      error: (_, _) => Scaffold(
        backgroundColor: AppColors.background,
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Could not load your profile from this device.'),
              const SizedBox(height: 12),
              TextButton(
                onPressed: () => ref.invalidate(userProfileProvider),
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      ),
      data: (user) {
        if (user == null || !user.slidesSeen) {
          return const OnboardingScreen();
        }
        if (!user.setupComplete) {
          return const SetupProfileScreen();
        }
        if (ref.watch(backendLiveProvider)) {
          final authSettled = ref.watch(authSettledProvider);
          if (authSettled.isLoading) return _startupLoading();
          final signedInUserId = ref.watch(backendUserIdProvider);
          if (signedInUserId == null) return const AuthScreen();
          final localAccess = ref.watch(
            localAccountDataAccessProvider(signedInUserId),
          );
          if (localAccess.isLoading) return _startupLoading();
          if (localAccess.hasError) {
            return _startupError(
              'Could not verify access to this device’s study data.',
              () => ref.invalidate(
                localAccountDataAccessProvider(signedInUserId),
              ),
            );
          }
          if (localAccess.valueOrNull != true) {
            return const LocalDataAccountMismatchScreen();
          }
          // Keep session sync alive after the startup gate leaves, but
          // never expose this device’s history to a different account.
          ref.watch(sessionSyncTriggerProvider);
          return const HomeScreen();
        }
        return const AuthScreen();
      },
    );
  }
}

/// Route-level auth and local-account guard for protected screens.
class AuthenticatedRoute extends ConsumerWidget {
  final String returnTo;
  final Widget child;

  const AuthenticatedRoute({
    required this.returnTo,
    required this.child,
    super.key,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authSettled = ref.watch(authSettledProvider);
    return authSettled.when(
      loading: _startupLoading,
      error: (_, _) => _startupError(
        'Could not restore your sign-in session.',
        () => ref.invalidate(authSettledProvider),
      ),
      data: (_) {
        final userId = ref.watch(backendUserIdProvider);
        if (userId == null) return AuthScreen(returnTo: returnTo);
        final access = ref.watch(localAccountDataAccessProvider(userId));
        return access.when(
          loading: _startupLoading,
          error: (_, _) => _startupError(
            'Could not verify access to this device’s study data.',
            () => ref.invalidate(localAccountDataAccessProvider(userId)),
          ),
          data: (allowed) =>
              allowed ? child : const LocalDataAccountMismatchScreen(),
        );
      },
    );
  }
}

Widget _startupError(String message, VoidCallback retry) => Scaffold(
  backgroundColor: AppColors.background,
  body: Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(message, textAlign: TextAlign.center),
        const SizedBox(height: 12),
        TextButton(onPressed: retry, child: const Text('Retry')),
      ],
    ),
  ),
);

Widget _startupLoading() => const Scaffold(
  backgroundColor: AppColors.background,
  body: Center(
    child: CircularProgressIndicator(semanticsLabel: 'Loading StudyUp'),
  ),
);

class LocalDataAccountMismatchScreen extends ConsumerWidget {
  const LocalDataAccountMismatchScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) => Scaffold(
    backgroundColor: AppColors.background,
    body: Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'This device’s local study data belongs to a different account. '
              'Nothing has been erased or uploaded to this account. Sign out '
              'and use the account that owns this data. To switch accounts, '
              'sign in to the owner account and erase local data first.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            TextButton(
              onPressed: () async {
                try {
                  final auth = ref.read(authRepositoryProvider);
                  if (auth == null) {
                    throw StateError('Authentication is unavailable.');
                  }
                  await auth.signOut();
                  await clearPostSignInLink();
                  if (context.mounted) context.go('/auth');
                } catch (_) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Could not sign out. Please try again.'),
                      ),
                    );
                  }
                }
              },
              child: const Text('Sign out'),
            ),
          ],
        ),
      ),
    ),
  );
}
