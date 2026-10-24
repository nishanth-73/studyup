import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/backend/supabase_client.dart';
import '../../auth/data/auth_controller.dart';
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

/// Fetches real community home data from Supabase for a given Monday.
final communityHomeProvider =
    FutureProvider.family<CommunityHomeData, DateTime>((ref, monday) async {
  final repo = ref.watch(communityRepositoryProvider);
  final userId = ref.watch(backendUserIdProvider);

  // If offline or not signed in, return genuine zero/guest data (NEVER fake users)
  if (repo == null || userId == null) {
    final emptyWeekly = WeeklyCardSummary.empty(monday);
    final emptyToday = TodayCardSummary.empty(DateTime.now());
    final me = CommunityMember.fromMeJson({
      'id': userId ?? 'local-user',
      'name': 'You',
    }, emptyWeekly);

    return CommunityHomeData(
      me: me,
      meWeekly: emptyWeekly,
      meToday: emptyToday,
      friends: const [],
      allRankedMembers: [me],
    );
  }

  return repo.getCommunityHome(monday);
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

