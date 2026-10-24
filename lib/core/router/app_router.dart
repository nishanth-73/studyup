import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import '../../features/onboarding/presentation/onboarding_screen.dart';
import '../../features/profile/presentation/setup_profile_screen.dart';
import '../../features/profile/presentation/setup_goal_screen.dart';
import '../../features/home/presentation/home_screen.dart';
import '../../features/subjects/presentation/subjects_screen.dart';
import '../../features/subjects/presentation/subject_detail_screen.dart';
import '../../features/progress/presentation/progress_screen.dart';
import '../../features/profile/presentation/profile_screen.dart';
import '../../features/profile/presentation/profile_detail_pages.dart';
import '../../features/profile/presentation/customise_robo_page.dart';
import '../../features/notifications/presentation/notification_center_screen.dart';
import '../../features/plan/presentation/plan_screen.dart';
import '../../features/focus/presentation/focus_screen.dart';
import '../../features/community/presentation/community_screen.dart';
import '../../features/community/presentation/full_leaderboard_screen.dart';
import 'startup_gate.dart';

// Bottom-tab destinations use NoTransitionPage = instant switch, no sliding.
NoTransitionPage<T> _noSlide<T>(Widget child) =>
    NoTransitionPage<T>(child: child);

final GoRouter appRouter = GoRouter(
  // Legacy App Links arrive as FULL urls. Ignoring the platform location
  // starts every entry point at StartupGate instead of surfacing a raw
  // "no routes for location" error for links that are no longer handled.
  overridePlatformDefaultLocation: true,
  initialLocation: '/',
  onException: (_, _, router) => router.go('/'),
  routes: [
    GoRoute(path: '/', builder: (_, _) => const StartupGate()),
    GoRoute(path: '/onboarding', builder: (_, _) => const OnboardingScreen()),
    GoRoute(
      path: '/setup-profile',
      builder: (_, _) => const SetupProfileScreen(),
    ),
    GoRoute(path: '/setup-goal', builder: (_, _) => const SetupGoalScreen()),
    GoRoute(path: '/auth', builder: (_, _) => const StartupGate()),
    ShellRoute(
      builder: (_, state, child) =>
          AuthenticatedRoute(returnTo: state.uri.toString(), child: child),
      routes: [
        GoRoute(
          path: '/home',
          pageBuilder: (_, _) => _noSlide(const HomeScreen()),
        ),
        GoRoute(
          path: '/subjects',
          pageBuilder: (_, _) => _noSlide(const SubjectsScreen()),
        ),
        GoRoute(
          path: '/subject/:id',
          builder: (_, s) =>
              SubjectDetailScreen(id: s.pathParameters['id'] ?? '0'),
        ),
        GoRoute(
          path: '/progress',
          pageBuilder: (_, _) => _noSlide(const ProgressScreen()),
        ),
        GoRoute(
          path: '/community',
          pageBuilder: (_, _) => _noSlide(const CommunityScreen()),
        ),
        GoRoute(
          path: '/community/leaderboard',
          builder: (_, _) {
            final now = DateTime.now();
            final today = DateTime(now.year, now.month, now.day);
            return FullLeaderboardScreen(
              members: const [],
              weekLabel: 'This week',
            );
          },
        ),
        GoRoute(
          path: '/community/friends',
          redirect: (_, _) => '/community',
        ),
        GoRoute(
          path: '/profile',
          pageBuilder: (_, _) => _noSlide(const ProfileScreen()),
        ),
        GoRoute(
          path: '/profile/notifications',
          builder: (_, _) => const NotificationsPage(),
        ),
        GoRoute(
          path: '/profile/privacy',
          builder: (_, _) => const PrivacyDataPage(),
        ),
        GoRoute(path: '/profile/help', builder: (_, _) => const HelpPage()),
        GoRoute(
          path: '/profile/feedback',
          builder: (_, _) => const FeedbackPage(),
        ),
        GoRoute(
          path: '/profile/customise-robo',
          builder: (_, _) => const CustomiseRoboPage(),
        ),
        GoRoute(
          path: '/notifications',
          builder: (_, _) => const NotificationCenterScreen(),
        ),
        GoRoute(
          path: '/plan',
          pageBuilder: (_, _) => _noSlide(const PlanScreen()),
        ),
        GoRoute(path: '/focus', builder: (_, _) => const FocusScreen()),
      ],
    ),
  ],
);
