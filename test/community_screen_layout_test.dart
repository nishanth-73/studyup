import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:studyup/core/theme/app_colors.dart';
import 'package:studyup/features/community/data/community_models.dart';
import 'package:studyup/features/community/data/community_repository.dart';
import 'package:studyup/features/community/presentation/community_providers.dart';
import 'package:studyup/features/community/presentation/community_screen.dart';
import 'package:studyup/features/community/presentation/full_leaderboard_screen.dart';

void main() {
  const testMe = CommunityMember(
    id: 'user-me',
    name: 'Alex',
    avatarColor: AppColors.cta,
    weeklyMinutes: 765,
    isCurrentUser: true,
    streakDays: 8,
  );
  const testFriend1 = CommunityMember(
    id: 'user-1',
    name: 'Aisha Rahman',
    avatarColor: AppColors.primary,
    weeklyMinutes: 920,
    streakDays: 14,
  );
  const testFriend2 = CommunityMember(
    id: 'user-2',
    name: 'Vikram Sharma',
    avatarColor: AppColors.blue,
    weeklyMinutes: 670,
    streakDays: 6,
  );
  const testFriend3 = CommunityMember(
    id: 'user-3',
    name: 'Sneha Patel',
    avatarColor: AppColors.pink,
    weeklyMinutes: 570,
    streakDays: 5,
  );
  const testFriend4 = CommunityMember(
    id: 'user-4',
    name: 'Rohan Gupta',
    avatarColor: AppColors.orange,
    weeklyMinutes: 465,
    streakDays: 4,
  );

  final testHomeData = CommunityHomeData(
    me: testMe,
    meWeekly: WeeklyCardSummary(
      weekStart: DateTime(2026, 10, 19),
      completedSessions: 8,
      totalMinutes: 765,
      goalMinutes: 600,
      percent: 128,
      streak: 8,
    ),
    meToday: TodayCardSummary(
      date: DateTime(2026, 10, 24),
      completedSessions: 2,
      totalMinutes: 90,
    ),
    friends: const [testFriend1, testFriend2, testFriend3, testFriend4],
    allRankedMembers: const [testFriend1, testMe, testFriend2, testFriend3, testFriend4],
  );

  Widget buildTestableCommunityScreen() {
    return ProviderScope(
      overrides: [
        communityHomeProvider.overrideWith((ref, monday) async => testHomeData),
      ],
      child: const MaterialApp(
        home: CommunityScreen(),
      ),
    );
  }

  group('Community Screen Layout & Hierarchy', () {
    testWidgets('1. Top bar displays Title and compact week picker button in top-right', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(buildTestableCommunityScreen());
      await tester.pumpAndSettle();

      // Top bar title
      expect(find.text('Community'), findsOneWidget);
      expect(find.text('Study circle rankings'), findsOneWidget);

      // Compact week picker button
      expect(find.text('This week'), findsOneWidget);
      expect(find.byIcon(Icons.calendar_today_rounded), findsOneWidget);
      expect(find.byIcon(Icons.keyboard_arrow_down_rounded), findsOneWidget);
    });

    testWidgets('2. Top 3 Podium Card displays #1, #2, #3 users with times and first place highlight', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(buildTestableCommunityScreen());
      await tester.pumpAndSettle();

      // Podium section title
      expect(find.text('TOP 3 THIS WEEK'), findsOneWidget);

      // Rank numerals 1, 2, 3
      expect(find.text('#1'), findsOneWidget);
      expect(find.text('#2'), findsOneWidget);
      expect(find.text('#3'), findsOneWidget);

      // First place star / crown icon
      expect(find.byIcon(Icons.star_rounded), findsOneWidget);
    });

    testWidgets('3. Weekly Comparison Card compares You vs Top Friend with progress bars and difference', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(buildTestableCommunityScreen());
      await tester.pumpAndSettle();

      // Comparison card header
      expect(find.text('Weekly Comparison'), findsOneWidget);
      expect(find.text('vs. Top Friend'), findsOneWidget);
      expect(find.byIcon(Icons.compare_arrows_rounded), findsOneWidget);

      // Shows 'You' and top friend name
      expect(find.text('You'), findsWidgets);
      expect(find.text('Aisha Rahman'), findsWidgets);

      // Shows progress difference or target/leader indicator
      expect(find.byIcon(Icons.trending_up_rounded), findsOneWidget);
    });

    testWidgets('4. Leaderboard Card displays Top 5 by default, highlights You, and has "See all"', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(buildTestableCommunityScreen());
      await tester.pumpAndSettle();

      // Leaderboard card header
      expect(find.text('Leaderboard'), findsOneWidget);
      expect(find.text('See all'), findsOneWidget);
      expect(find.byIcon(Icons.chevron_right_rounded), findsOneWidget);

      // "YOU" pill highlights current user
      expect(find.text('YOU'), findsWidgets);
    });

    testWidgets('5. Tapping "See all" opens the Full Leaderboard Screen', (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(buildTestableCommunityScreen());
      await tester.pumpAndSettle();

      final seeAllButton = find.text('See all');
      expect(seeAllButton, findsOneWidget);

      await tester.tap(seeAllButton);
      await tester.pumpAndSettle();

      expect(find.byType(FullLeaderboardScreen), findsOneWidget);
      expect(find.text('Leaderboard'), findsWidgets);
    });
  });
}
