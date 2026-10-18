import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import '../../features/onboarding/presentation/onboarding_screen.dart';
import '../../features/profile/presentation/setup_profile_screen.dart';
import '../../features/profile/presentation/setup_goal_screen.dart';
import '../../features/auth/presentation/auth_screen.dart';
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
import '../../features/community/presentation/friends_screen.dart';
import '../../features/community/presentation/invite_accept_screen.dart';
import '../../features/community/presentation/leaderboard_screen.dart';
import '../../features/community/presentation/recap_screen.dart';
import 'startup_gate.dart';

// Bottom-tab destinations use NoTransitionPage = instant switch, no sliding.
NoTransitionPage<T> _noSlide<T>(Widget child) =>
    NoTransitionPage<T>(child: child);

final GoRouter appRouter = GoRouter(
  // Invitation App Links arrive as FULL urls (e.g.
  // https://studyup-4x7z.vercel.app/i/<code>). By default GoRouter adopts
  // the platform's initial route verbatim, and no route matches a full
  // url — the first tap therefore failed with
  // "GoException: no routes for location: https://…/i/…" (rendered as a
  // raw error screen) while the second tap worked, because the app was
  // already running by then. Invitation intake is handled explicitly by
  // InviteLinks (cold start + warm links), so the platform location is
  // ignored here and every entry point starts at StartupGate.
  overridePlatformDefaultLocation: true,
  initialLocation: '/',
  routes: [
    GoRoute(path: '/', builder: (_, _) => const StartupGate()),
    GoRoute(path: '/onboarding', builder: (_, _) => const OnboardingScreen()),
    GoRoute(
      path: '/setup-profile',
      builder: (_, _) => const SetupProfileScreen(),
    ),
    GoRoute(path: '/setup-goal', builder: (_, _) => const SetupGoalScreen()),
    GoRoute(path: '/auth', builder: (_, _) => const AuthScreen()),
    // Invitation landing (deep link / manual). Works logged-out too —
    // the screen holds the token across sign-in.
    GoRoute(
      path: '/invite/:token',
      builder: (_, s) =>
          InviteAcceptScreen(token: s.pathParameters['token'] ?? ''),
    ),
    GoRoute(path: '/home', pageBuilder: (_, _) => _noSlide(const HomeScreen())),
    GoRoute(
      path: '/subjects',
      pageBuilder: (_, _) => _noSlide(const SubjectsScreen()),
    ),
    GoRoute(
      path: '/subject/:id',
      builder: (_, s) => SubjectDetailScreen(id: s.pathParameters['id'] ?? '0'),
    ),
    GoRoute(
      path: '/progress',
      pageBuilder: (_, _) => _noSlide(const ProgressScreen()),
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
    GoRoute(path: '/profile/feedback', builder: (_, _) => const FeedbackPage()),
    GoRoute(
      path: '/profile/customise-robo',
      builder: (_, _) => const CustomiseRoboPage(),
    ),
    GoRoute(
      path: '/notifications',
      builder: (_, _) => const NotificationCenterScreen(),
    ),
    GoRoute(path: '/plan', pageBuilder: (_, _) => _noSlide(const PlanScreen())),
    GoRoute(path: '/focus', builder: (_, _) => const FocusScreen()),
    // Community replaces the former Quiz tab. (The bundled quiz bank
    // files remain on disk, unreferenced; no shared code was removed.)
    GoRoute(
      path: '/community',
      pageBuilder: (_, _) => _noSlide(const CommunityScreen()),
    ),
    GoRoute(
      path: '/community/friends',
      builder: (_, _) => const FriendsScreen(),
    ),
    GoRoute(
      path: '/community/leaderboard',
      builder: (_, _) => const LeaderboardScreen(),
    ),
    GoRoute(path: '/community/recap', builder: (_, _) => const RecapScreen()),
  ],
);
