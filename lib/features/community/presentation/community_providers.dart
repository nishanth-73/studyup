import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/theme/app_colors.dart';
import '../../auth/data/auth_controller.dart';
import '../../progress/presentation/study_progress_controller.dart';
import '../../social/data/session_sync.dart';
import '../../social/data/social_remote.dart';
import '../data/community_models.dart';
import '../data/community_repository.dart';

final communityRepositoryProvider = Provider<CommunityRepository?>((ref) {
  final isLive = ref.watch(backendLiveProvider);
  if (!isLive) return null;
  return CommunityRepository(Supabase.instance.client);
});

/// Holds the selected week Monday for Community screen.
final selectedCommunityMondayProvider = StateProvider<DateTime>((ref) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  return today.subtract(Duration(days: today.weekday - DateTime.monday));
});

/// Fetches real community home data from Supabase for a given Monday,
/// unified with the authoritative Insights weekly calculation.
final communityHomeProvider =
    FutureProvider.family<CommunityHomeData, DateTime>((ref, monday) async {
  final repo = ref.watch(communityRepositoryProvider);
  final userId = ref.watch(backendUserIdProvider);
  final studyProgress = ref.watch(studyProgressProvider);

  // Authoritative local weekly calculation matching Insights exactly
  final userWeekMinutes = studyProgress.minutesByWeekday(monday);
  final userTotalMinutes = userWeekMinutes.fold(0, (sum, m) => sum + m);
  final dailyGoal = studyProgress.dailyStudyGoalMinutes;
  final weeklyGoal = dailyGoal * 7;
  final userPercent = weeklyGoal > 0 ? (userTotalMinutes / weeklyGoal * 100).round() : 0;
  final todayNow = DateTime.now();
  final todayMinutes = studyProgress.minutesForDate(todayNow);
  final todaySessions = studyProgress.sessionCountForDate(todayNow);

  // If offline or not signed in, return genuine progress based on real local records
  if (repo == null || userId == null) {
    final localWeekly = WeeklyCardSummary(
      weekStart: monday,
      completedSessions: userTotalMinutes > 0 ? 1 : 0,
      totalMinutes: userTotalMinutes,
      goalMinutes: weeklyGoal > 0 ? weeklyGoal : 600,
      percent: userPercent,
      streak: 0,
    );
    final localToday = TodayCardSummary(
      date: todayNow,
      completedSessions: todaySessions,
      totalMinutes: todayMinutes,
    );
    final me = CommunityMember(
      id: userId ?? 'local-user',
      name: 'You',
      avatarColor: AppColors.cta,
      weeklyMinutes: userTotalMinutes,
      completedSessions: localWeekly.completedSessions,
      percent: userPercent,
      streakDays: 0,
      isCurrentUser: true,
    );

    return CommunityHomeData(
      me: me,
      meWeekly: localWeekly,
      meToday: localToday,
      friends: const [],
      allRankedMembers: [me],
    );
  }

  // 1. Sync local sessions to Supabase so friends receive the latest progress
  final client = Supabase.instance.client;
  if (studyProgress.sessions.isNotEmpty) {
    try {
      await SessionSyncService(SocialRemote(client)).syncAll(studyProgress.sessions);
    } catch (_) {
      // Best-effort sync
    }
  }

  // 2. Fetch backend community home data
  final rawHome = await repo.getCommunityHome(monday);

  // 3. Unify current user's weekly metrics with the authoritative local calculation
  final effectiveMyMinutes = userTotalMinutes > 0 ? userTotalMinutes : rawHome.meWeekly.totalMinutes;
  final effectiveGoalMinutes = weeklyGoal > 0 ? weeklyGoal : rawHome.meWeekly.goalMinutes;
  final effectivePercent = userTotalMinutes > 0 ? userPercent : rawHome.meWeekly.percent;

  final unifiedMeWeekly = WeeklyCardSummary(
    weekStart: rawHome.meWeekly.weekStart,
    completedSessions: rawHome.meWeekly.completedSessions > 0
        ? rawHome.meWeekly.completedSessions
        : (userTotalMinutes > 0 ? 1 : 0),
    totalMinutes: effectiveMyMinutes,
    goalMinutes: effectiveGoalMinutes,
    percent: effectivePercent,
    streak: rawHome.meWeekly.streak,
  );

  final unifiedMeMember = CommunityMember(
    id: rawHome.me.id,
    name: rawHome.me.name,
    avatarUrl: rawHome.me.avatarUrl,
    avatarColor: rawHome.me.avatarColor,
    weeklyMinutes: effectiveMyMinutes,
    completedSessions: unifiedMeWeekly.completedSessions,
    percent: effectivePercent,
    streakDays: rawHome.me.streakDays,
    isCurrentUser: true,
  );

  // Re-rank all members with the unified me member
  final updatedRanked = [unifiedMeMember, ...rawHome.friends];
  updatedRanked.sort((a, b) {
    final cmp = b.weeklyMinutes.compareTo(a.weeklyMinutes);
    if (cmp != 0) return cmp;
    return a.name.toLowerCase().compareTo(b.name.toLowerCase());
  });

  return CommunityHomeData(
    me: unifiedMeMember,
    meWeekly: unifiedMeWeekly,
    meToday: rawHome.meToday.totalMinutes > 0
        ? rawHome.meToday
        : TodayCardSummary(
            date: todayNow,
            completedSessions: todaySessions,
            totalMinutes: todayMinutes,
          ),
    friends: rawHome.friends,
    allRankedMembers: updatedRanked,
  );
});

/// Fetches 7-day week detail breakdown for a specific user and week.
final weekDetailProvider = FutureProvider.family<WeekDetailSummary, ({String userId, DateTime monday})>(
  (ref, args) async {
    final repo = ref.watch(communityRepositoryProvider);
    if (repo == null) {
      throw StateError('Backend is offline');
    }
    return repo.getWeekDetail(args.userId, args.monday);
  },
);
