import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/app_shell.dart';
import '../../../core/widgets/week_picker_dialog.dart';
import '../../auth/data/auth_controller.dart';
import '../../avatar/data/user_profile.dart';
import '../../avatar/presentation/avatar_widgets.dart';
import '../../avatar/presentation/user_profile_controller.dart';
import '../../progress/presentation/study_progress_controller.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../social/data/session_sync.dart';
import '../../social/data/social_remote.dart';
import '../data/community_models.dart';
import '../data/invitation_link_service.dart';
import 'community_providers.dart';
import 'full_leaderboard_screen.dart';
import 'week_detail_dialog.dart';

/// Production StudyUP Community screen:
/// 1. Top bar with Title + compact week picker in top-right (no extra icon).
/// 2. Top 3 Leaderboard Podium Card (1st place GREEN, 2nd BLUE, 3rd PINK, real profile avatars).
/// 3. My Today's Session Card (today study time, completed sessions, streak).
/// 4. Weekly Progress/Comparison Card: Reuses the exact WeeklyStudyTimeCard from Insights.
/// 5. Leaderboard Card (Top 5 preview, "YOU" highlight, tap for week detail, "See all" action).
/// 6. Exactly ONE clear 'Invite Friends' button at the very bottom of the content.
/// 7. Smooth natural scrolling matching Home and Insights screens.
class CommunityScreen extends ConsumerStatefulWidget {
  const CommunityScreen({super.key});

  @override
  ConsumerState<CommunityScreen> createState() => _CommunityScreenState();
}

class _CommunityScreenState extends ConsumerState<CommunityScreen> {
  bool _acceptingInvite = false;

  static DateTime _currentWeekMonday() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    return today.subtract(Duration(days: today.weekday - DateTime.monday));
  }

  Future<void> _openWeekPicker(DateTime currentMonday, CommunityHomeData? homeData) async {
    HapticFeedback.selectionClick();
    final picked = await showWeekPickerDialog(
      context: context,
      title: 'Select week',
      initialMonday: currentMonday,
      minutesFor: (monday) {
        return ref.read(studyProgressProvider).minutesForWeek(monday);
      },
    );

    if (picked != null && mounted) {
      HapticFeedback.selectionClick();
      ref.read(selectedCommunityMondayProvider.notifier).state = picked;
    }
  }

  void _openFullLeaderboard(List<CommunityMember> members, String weekLabel) {
    HapticFeedback.selectionClick();
    final selectedMonday = ref.read(selectedCommunityMondayProvider);
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => FullLeaderboardScreen(
          members: members,
          weekLabel: weekLabel,
          onMemberTap: (member) {
            showWeekDetailSheet(
              context: context,
              userId: member.id,
              userName: member.name,
              avatarUrl: member.avatarUrl,
              monday: selectedMonday,
            );
          },
        ),
      ),
    );
  }

  /// Opens normal native device share sheet using share_plus, with clipboard fallback.
  Future<void> _shareInviteLink() async {
    HapticFeedback.selectionClick();
    final repo = ref.read(communityRepositoryProvider);
    if (repo == null || repo.currentUserId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Sign in to invite friends.')),
      );
      return;
    }

    try {
      final inviteUrl = await repo.createInviteLink();
      final shareText =
          'Join my calm study circle on StudyUp: Focus on your goals. Grow together.\n$inviteUrl';

      try {
        final result = await Share.share(shareText);
        if (result.status == ShareResultStatus.dismissed) return;
        if (result.status == ShareResultStatus.success) return;
      } catch (_) {
        await Clipboard.setData(ClipboardData(text: inviteUrl));
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Invitation link copied to clipboard!')),
        );
      }
    } catch (err) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not create invite: $err')),
      );
    }
  }

  String _formatWeekButtonLabel(DateTime monday) {
    final currentMon = _currentWeekMonday();
    if (monday.year == currentMon.year &&
        monday.month == currentMon.month &&
        monday.day == currentMon.day) {
      return 'This week';
    }
    final sunday = monday.add(const Duration(days: 6));
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    if (monday.month == sunday.month) {
      return '${months[monday.month - 1]} ${monday.day}–${sunday.day}';
    }
    return '${months[monday.month - 1]} ${monday.day} – ${months[sunday.month - 1]} ${sunday.day}';
  }

  Widget _buildAvatarWidget({
    required CommunityMember? member,
    required double radius,
    required Color fallbackColor,
  }) {
    if (member == null) {
      return Container(
        width: radius * 2,
        height: radius * 2,
        decoration: const BoxDecoration(
          color: AppColors.surface2,
          shape: BoxShape.circle,
        ),
        child: Icon(
          Icons.person_outline_rounded,
          size: radius,
          color: AppColors.textSecondary,
        ),
      );
    }

    String? avatarId = member.avatarUrl;
    if (member.isCurrentUser) {
      final userProfile = ref.watch(userProfileProvider).valueOrNull;
      if (userProfile != null && isValidAvatarId(userProfile.avatarId)) {
        avatarId = userProfile.avatarId;
      }
    }

    if (avatarId != null && isValidAvatarId(avatarId)) {
      return UserAvatar(avatarId: avatarId, size: radius * 2);
    }

    return CircleAvatar(
      radius: radius,
      backgroundColor: member.avatarColor.withValues(alpha: 0.25),
      child: Text(
        member.initials,
        style: TextStyle(
          fontSize: radius * 0.55,
          fontWeight: FontWeight.w700,
          color: member.avatarColor,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final selectedMonday = ref.watch(selectedCommunityMondayProvider);
    final weekLabel = _formatWeekButtonLabel(selectedMonday);
    final homeAsync = ref.watch(communityHomeProvider(selectedMonday));
    final pendingInviteToken = ref.watch(pendingInviteTokenProvider);

    return AppShell(
      currentIndex: 3,
      body: SafeArea(
        bottom: false,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final maxWidth = math.min(constraints.maxWidth, 600.0);
            return Align(
              alignment: Alignment.topCenter,
              child: SizedBox(
                width: maxWidth,
                child: RefreshIndicator(
                  color: AppColors.green,
                  backgroundColor: AppColors.surface,
                  onRefresh: () async {
                    HapticFeedback.mediumImpact();
                    final studyProgress = ref.read(studyProgressProvider);
                    try {
                      final client = Supabase.instance.client;
                      if (client.auth.currentUser != null && studyProgress.sessions.isNotEmpty) {
                        await SessionSyncService(SocialRemote(client)).syncAll(studyProgress.sessions);
                      }
                    } catch (_) {}
                    ref.invalidate(communityHomeProvider(selectedMonday));
                    await ref.read(communityHomeProvider(selectedMonday).future);
                  },
                  child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(
                      parent: BouncingScrollPhysics(),
                    ),
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                    children: [
                      // 1. TOP BAR (Title + Compact Week Picker, NO extra icon)
                      _buildTopBar(weekLabel, selectedMonday, homeAsync.valueOrNull),
                      const SizedBox(height: 14),

                      // Pending friend invitation banner
                      if (pendingInviteToken != null) ...[
                        _buildPendingInvitationCard(pendingInviteToken, selectedMonday),
                        const SizedBox(height: 14),
                      ],

                      // Async content branch
                      ...homeAsync.when(
                        loading: () => [
                          const SizedBox(height: 48),
                          const Center(
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: AppColors.green,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Center(
                            child: Text(
                              'Loading community...',
                              style: AppTextStyles.caption12.copyWith(
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ),
                        ],
                        error: (err, _) => [
                          Container(
                            padding: const EdgeInsets.all(20),
                            decoration: BoxDecoration(
                              color: AppColors.surface,
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: AppColors.track.withValues(alpha: 0.3),
                              ),
                            ),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.cloud_off_rounded, color: AppColors.cta, size: 32),
                                const SizedBox(height: 10),
                                Text('Could not load Community', style: AppTextStyles.body14Bold),
                                const SizedBox(height: 4),
                                Text(
                                  err.toString(),
                                  style: AppTextStyles.caption12,
                                  textAlign: TextAlign.center,
                                ),
                                const SizedBox(height: 12),
                                FilledButton.tonal(
                                  onPressed: () => ref.invalidate(communityHomeProvider(selectedMonday)),
                                  child: const Text('Retry'),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 16),
                          _buildInviteFriendsButton(),
                        ],
                        data: (homeData) => _buildCommunitySections(homeData, weekLabel, selectedMonday),
                      ),

                      // Scroll clearance above the floating navigation
                      SizedBox(height: AppShell.scrollClearance(context)),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  List<Widget> _buildCommunitySections(
    CommunityHomeData homeData,
    String weekLabel,
    DateTime selectedMonday,
  ) {
    final members = homeData.allRankedMembers;
    final currentUser = homeData.me;
    final topFriend = homeData.topFriend;

    final first = members.isNotEmpty ? members[0] : null;
    final second = members.length > 1 ? members[1] : null;
    final third = members.length > 2 ? members[2] : null;

    final top5Members = members.take(5).toList();

    return [
      // 2. TOP 3 LEADERBOARD PODIUM CARD
      _buildPodiumCard(first, second, third, homeData.hasFriends, selectedMonday),
      const SizedBox(height: 14),

      // 3. TODAY'S SESSION CARD (Real focus summary)
      _buildTodaySessionCard(homeData.meToday, homeData.meWeekly.streak),
      const SizedBox(height: 14),

      // 4. WEEKLY PROGRESS / COMPARISON CARD (Reuses WeeklyStudyTimeCard from Insights)
      _buildWeeklyComparisonCard(currentUser, topFriend, homeData.hasFriends, selectedMonday),
      const SizedBox(height: 14),

      // 5. LEADERBOARD CARD (Top 5 + "See all" action)
      _buildLeaderboardCard(top5Members, members, weekLabel, selectedMonday),
      const SizedBox(height: 16),

      // 6. EXACTLY ONE 'Invite Friends' BUTTON at the very bottom
      _buildInviteFriendsButton(),
      const SizedBox(height: 14),
    ];
  }

  // --------------------------------------------------------------------------
  // 1. TOP BAR (Clean title + Compact Week Picker, NO extra icon)
  // --------------------------------------------------------------------------
  Widget _buildTopBar(String weekLabel, DateTime selectedMonday, CommunityHomeData? homeData) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Community', style: AppTextStyles.title28),
            const SizedBox(height: 2),
            Text(
              'Study circle rankings',
              style: AppTextStyles.secondary12,
            ),
          ],
        ),
        Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () => _openWeekPicker(selectedMonday, homeData),
            borderRadius: BorderRadius.circular(100),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(100),
                border: Border.all(
                  color: AppColors.track.withValues(alpha: 0.6),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.15),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.calendar_today_rounded,
                    size: 13,
                    color: AppColors.cta,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    weekLabel,
                    style: AppTextStyles.caption12Bold.copyWith(
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(width: 3),
                  const Icon(
                    Icons.keyboard_arrow_down_rounded,
                    size: 15,
                    color: AppColors.textSecondary,
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  // --------------------------------------------------------------------------
  // 2. TOP 3 LEADERBOARD PODIUM CARD
  // 1st place GREEN, 2nd BLUE, 3rd PINK, real user profile avatars.
  // --------------------------------------------------------------------------
  Widget _buildPodiumCard(
    CommunityMember? first,
    CommunityMember? second,
    CommunityMember? third,
    bool hasFriends,
    DateTime selectedMonday,
  ) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: AppColors.track.withValues(alpha: 0.35),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.18),
            blurRadius: 14,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.workspace_premium_rounded,
                size: 16,
                color: AppColors.green,
              ),
              const SizedBox(width: 6),
              Text(
                'TOP 3 THIS WEEK',
                style: AppTextStyles.caption12Bold.copyWith(
                  color: AppColors.textSecondary,
                  letterSpacing: 1.0,
                  fontSize: 11,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // #2 Rank (Silver) - Left
              Expanded(
                child: _buildPodiumColumn(
                  member: second,
                  place: 2,
                  pedestalHeight: 64,
                  accentColor: AppColors.blue,
                  avatarRadius: 22,
                  selectedMonday: selectedMonday,
                ),
              ),
              const SizedBox(width: 8),

              // #1 Rank (FIRST PLACE GREEN) - Center
              Expanded(
                child: _buildPodiumColumn(
                  member: first,
                  place: 1,
                  pedestalHeight: 88,
                  accentColor: AppColors.green,
                  avatarRadius: 28,
                  isWinner: true,
                  selectedMonday: selectedMonday,
                ),
              ),
              const SizedBox(width: 8),

              // #3 Rank (Bronze) - Right
              Expanded(
                child: _buildPodiumColumn(
                  member: third,
                  place: 3,
                  pedestalHeight: 48,
                  accentColor: AppColors.pink,
                  avatarRadius: 22,
                  selectedMonday: selectedMonday,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPodiumColumn({
    required CommunityMember? member,
    required int place,
    required double pedestalHeight,
    required Color accentColor,
    required double avatarRadius,
    bool isWinner = false,
    required DateTime selectedMonday,
  }) {
    final name = member?.name ?? 'Open spot';
    final time = member?.formattedStudyTime ?? '0h 0m';

    return GestureDetector(
      onTap: member != null
          ? () {
              showWeekDetailSheet(
                context: context,
                userId: member.id,
                userName: member.name,
                avatarUrl: member.avatarUrl,
                monday: selectedMonday,
              );
            }
          : null,
      behavior: HitTestBehavior.opaque,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isWinner)
            const Padding(
              padding: EdgeInsets.only(bottom: 3),
              child: Icon(
                Icons.star_rounded,
                size: 20,
                color: AppColors.green,
              ),
            )
          else
            const SizedBox(height: 12),

          Stack(
            alignment: Alignment.center,
            children: [
              Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: accentColor.withValues(alpha: isWinner ? 0.9 : 0.6),
                    width: isWinner ? 2.5 : 2.0,
                  ),
                ),
                child: _buildAvatarWidget(
                  member: member,
                  radius: avatarRadius,
                  fallbackColor: accentColor,
                ),
              ),
              Positioned(
                bottom: 0,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                  decoration: BoxDecoration(
                    color: accentColor,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '#$place',
                    style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w900,
                      color: AppColors.onCta,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 7),

          Text(
            name,
            style: AppTextStyles.body14Bold.copyWith(
              fontSize: isWinner ? 13 : 12,
              color: isWinner ? AppColors.textPrimary : AppColors.textSecondary,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 1),

          Text(
            time,
            style: AppTextStyles.caption12.copyWith(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: accentColor,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 6),

          Container(
            height: pedestalHeight,
            width: double.infinity,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  accentColor.withValues(alpha: isWinner ? 0.35 : 0.20),
                  AppColors.surface2,
                ],
              ),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
              border: Border.all(
                color: accentColor.withValues(alpha: isWinner ? 0.6 : 0.35),
                width: 1.0,
              ),
            ),
            child: Center(
              child: Text(
                '$place',
                style: TextStyle(
                  fontSize: isWinner ? 24 : 18,
                  fontWeight: FontWeight.w900,
                  color: accentColor.withValues(alpha: 0.9),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // --------------------------------------------------------------------------
  // 3. TODAY'S SESSION CARD
  // --------------------------------------------------------------------------
  Widget _buildTodaySessionCard(TodayCardSummary today, int streak) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.track.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                  color: AppColors.orange.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.local_fire_department_rounded,
                  size: 16,
                  color: AppColors.orange,
                ),
              ),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('Today\'s Focus', style: AppTextStyles.body14Bold),
                  Text(
                    '${today.completedSessions} session${today.completedSessions == 1 ? '' : 's'} completed',
                    style: AppTextStyles.caption12.copyWith(fontSize: 11),
                  ),
                ],
              ),
            ],
          ),
          Row(
            children: [
              Text(
                today.formattedStudyTime,
                style: AppTextStyles.title26.copyWith(fontSize: 18, color: AppColors.green),
              ),
              if (streak > 0) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppColors.orange.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    '${streak}d',
                    style: AppTextStyles.caption12Bold.copyWith(
                      fontSize: 10,
                      color: AppColors.orange,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  // --------------------------------------------------------------------------
  // 4. WEEKLY PROGRESS / COMPARISON CARD
  // Community's own dedicated comparison card (inspired by Insights styling).
  // --------------------------------------------------------------------------
  Widget _buildWeeklyComparisonCard(
    CommunityMember me,
    CommunityMember? topFriend,
    bool hasFriends,
    DateTime selectedMonday,
  ) {
    if (!hasFriends || topFriend == null) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.track.withValues(alpha: 0.35)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.18),
              blurRadius: 14,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Column(
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.compare_arrows_rounded,
                    size: 16,
                    color: AppColors.primary,
                  ),
                ),
                const SizedBox(width: 8),
                Text('Weekly Comparison', style: AppTextStyles.section18),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppColors.surface2,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    'Your Progress',
                    style: AppTextStyles.caption12.copyWith(
                      color: AppColors.textSecondary,
                      fontSize: 10,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            _buildComparisonProgressRow(
              member: me,
              name: 'You',
              isYou: true,
              timeString: me.formattedStudyTime,
              progress: 1.0,
              barColor: AppColors.green,
            ),
            const SizedBox(height: 12),
            Text(
              'Connect with friends to compare weekly focus hours and grow together.',
              style: AppTextStyles.secondary12,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    final maxMinutes = math.max(
      math.max(me.weeklyMinutes, topFriend.weeklyMinutes),
      60,
    );
    final myProgress = (me.weeklyMinutes / maxMinutes).clamp(0.0, 1.0);
    final friendProgress = (topFriend.weeklyMinutes / maxMinutes).clamp(0.0, 1.0);

    final diffMinutes = (me.weeklyMinutes - topFriend.weeklyMinutes).abs();
    final diffHours = diffMinutes ~/ 60;
    final diffRemainder = diffMinutes % 60;
    final diffString = diffHours > 0
        ? '${diffHours}h ${diffRemainder}m'
        : '${diffRemainder}m';
    final isLeading = me.weeklyMinutes >= topFriend.weeklyMinutes;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: AppColors.track.withValues(alpha: 0.35),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.18),
            blurRadius: 14,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(5),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(
                        Icons.compare_arrows_rounded,
                        size: 16,
                        color: AppColors.primary,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        'Weekly Comparison',
                        style: AppTextStyles.section18,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.surface2,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  'vs. Top Friend',
                  style: AppTextStyles.caption12.copyWith(
                    color: AppColors.textSecondary,
                    fontSize: 10,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // User Row ("You")
          _buildComparisonProgressRow(
            member: me,
            name: 'You',
            isYou: true,
            timeString: me.formattedStudyTime,
            progress: myProgress,
            barColor: AppColors.green,
          ),
          const SizedBox(height: 10),

          // Top Friend Row
          _buildComparisonProgressRow(
            member: topFriend,
            name: topFriend.name,
            isYou: false,
            timeString: topFriend.formattedStudyTime,
            progress: friendProgress,
            barColor: AppColors.blue,
          ),
          const SizedBox(height: 12),

          // Progress gap highlight badge
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: AppColors.surface2,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: AppColors.track.withValues(alpha: 0.5),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  isLeading
                      ? Icons.emoji_events_rounded
                      : Icons.trending_up_rounded,
                  size: 16,
                  color: isLeading ? AppColors.green : AppColors.blue,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    isLeading
                        ? 'You are leading by $diffString this week!'
                        : '$diffString behind ${topFriend.name.split(' ').first}',
                    style: AppTextStyles.caption12Bold.copyWith(
                      color: AppColors.textPrimary,
                      fontSize: 11,
                    ),
                  ),
                ),
                Text(
                  isLeading ? 'Leader' : 'Target',
                  style: AppTextStyles.caption12.copyWith(
                    color: isLeading ? AppColors.green : AppColors.textSecondary,
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildComparisonProgressRow({
    required CommunityMember member,
    required String name,
    required bool isYou,
    required String timeString,
    required double progress,
    required Color barColor,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                _buildAvatarWidget(member: member, radius: 11, fallbackColor: barColor),
                const SizedBox(width: 7),
                Text(
                  name,
                  style: AppTextStyles.body14Bold.copyWith(
                    color: isYou ? AppColors.green : AppColors.textPrimary,
                    fontSize: 13,
                  ),
                ),
                if (isYou) ...[
                  const SizedBox(width: 5),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 5,
                      vertical: 1,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.green.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      'YOU',
                      style: AppTextStyles.caption12Bold.copyWith(
                        fontSize: 8.5,
                        color: AppColors.green,
                      ),
                    ),
                  ),
                ],
              ],
            ),
            Text(
              timeString,
              style: AppTextStyles.body14Bold.copyWith(
                color: isYou ? AppColors.green : AppColors.textSecondary,
                fontSize: 13,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Container(
            height: 8,
            width: double.infinity,
            color: AppColors.surface2,
            child: FractionallySizedBox(
              alignment: Alignment.centerLeft,
              widthFactor: progress,
              child: Container(
                decoration: BoxDecoration(
                  color: barColor,
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  // --------------------------------------------------------------------------
  // 5. LEADERBOARD CARD (Top 5 + "See all" action)
  // Duplicate invitation button removed; clean list of members.
  // --------------------------------------------------------------------------
  Widget _buildLeaderboardCard(
    List<CommunityMember> top5Members,
    List<CommunityMember> allMembers,
    String weekLabel,
    DateTime selectedMonday,
  ) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: AppColors.track.withValues(alpha: 0.35),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.18),
            blurRadius: 14,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 10, 10),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    const Icon(
                      Icons.leaderboard_rounded,
                      size: 18,
                      color: AppColors.cta,
                    ),
                    const SizedBox(width: 7),
                    Text('Leaderboard', style: AppTextStyles.section18),
                  ],
                ),
                Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: () => _openFullLeaderboard(allMembers, weekLabel),
                    borderRadius: BorderRadius.circular(8),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 5,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'See all',
                            style: AppTextStyles.body14Bold.copyWith(
                              color: AppColors.cta,
                              fontSize: 13,
                            ),
                          ),
                          const SizedBox(width: 2),
                          const Icon(
                            Icons.chevron_right_rounded,
                            size: 16,
                            color: AppColors.cta,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Divider(
            height: 1,
            color: AppColors.track.withValues(alpha: 0.35),
          ),

          if (top5Members.isEmpty)
            Padding(
              padding: const EdgeInsets.all(24),
              child: Center(
                child: Text(
                  'No study circle members this week.',
                  style: AppTextStyles.secondary12,
                ),
              ),
            )
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              padding: EdgeInsets.zero,
              itemCount: top5Members.length,
              separatorBuilder: (_, _) => Divider(
                height: 1,
                color: AppColors.track.withValues(alpha: 0.25),
              ),
              itemBuilder: (context, index) {
                final member = top5Members[index];
                final rank = index + 1;
                return _buildLeaderboardRow(member, rank, selectedMonday);
              },
            ),
        ],
      ),
    );
  }

  Widget _buildLeaderboardRow(CommunityMember member, int rank, DateTime selectedMonday) {
    final rankColor = switch (rank) {
      1 => AppColors.green,
      2 => AppColors.blue,
      3 => AppColors.pink,
      _ => AppColors.textSecondary,
    };

    return InkWell(
      onTap: () {
        showWeekDetailSheet(
          context: context,
          userId: member.id,
          userName: member.name,
          avatarUrl: member.avatarUrl,
          monday: selectedMonday,
        );
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        child: Row(
          children: [
            SizedBox(
              width: 22,
              child: Text(
                '$rank',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: rankColor,
                ),
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(width: 10),

            _buildAvatarWidget(
              member: member,
              radius: 17,
              fallbackColor: member.avatarColor,
            ),
            const SizedBox(width: 10),

            Expanded(
              child: Row(
                children: [
                  Flexible(
                    child: Text(
                      member.name,
                      style: AppTextStyles.body14Bold.copyWith(
                        color: member.isCurrentUser ? AppColors.cta : AppColors.textPrimary,
                        fontSize: 13,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (member.isCurrentUser) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                      decoration: BoxDecoration(
                        color: AppColors.cta.withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        'YOU',
                        style: TextStyle(
                          fontSize: 8.5,
                          fontWeight: FontWeight.w800,
                          color: AppColors.cta,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),

            Text(
              member.formattedStudyTime,
              style: AppTextStyles.body14Bold.copyWith(
                fontSize: 13,
                color: member.isCurrentUser ? AppColors.green : AppColors.textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // --------------------------------------------------------------------------
  // 6. EXACTLY ONE 'Invite Friends' BUTTON
  // Positioned at the very bottom of the Community content below all cards.
  // --------------------------------------------------------------------------
  Widget _buildInviteFriendsButton() {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: FilledButton.icon(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.cta,
          foregroundColor: AppColors.onCta,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          elevation: 0,
        ),
        onPressed: _shareInviteLink,
        icon: const Icon(Icons.person_add_alt_1_rounded, size: 20),
        label: Text(
          'Invite Friends',
          style: AppTextStyles.body16Bold.copyWith(color: AppColors.onCta),
        ),
      ),
    );
  }

  // --------------------------------------------------------------------------
  // INVITATION ACCEPTANCE INTERFACE
  // --------------------------------------------------------------------------
  Widget _buildPendingInvitationCard(String token, DateTime selectedMonday) {
    final previewAsync = ref.watch(invitePreviewProvider(token));
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: AppColors.green.withValues(alpha: 0.4),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.green.withValues(alpha: 0.08),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: previewAsync.when(
        loading: () => Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: AppColors.green,
                ),
              ),
              const SizedBox(width: 12),
              Text('Checking invitation…', style: AppTextStyles.body14),
            ],
          ),
        ),
        error: (e, _) => Row(
          children: [
            const Icon(Icons.info_outline_rounded, color: AppColors.cta, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Could not verify invitation link.',
                style: AppTextStyles.caption12.copyWith(color: AppColors.textSecondary),
              ),
            ),
            IconButton(
              tooltip: 'Dismiss',
              icon: const Icon(Icons.close_rounded, size: 18, color: AppColors.textSecondary),
              onPressed: () => ref.read(pendingInviteTokenProvider.notifier).clear(),
            ),
          ],
        ),
        data: (preview) {
          if (!preview.isValid) {
            final String message = preview.isExpired
                ? 'This invitation link has expired.'
                : preview.isAlreadyAccepted
                    ? 'This invitation link was already used.'
                    : 'This invitation link is not valid.';
            return Row(
              children: [
                const Icon(Icons.info_outline_rounded, color: AppColors.cta, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    message,
                    style: AppTextStyles.body14.copyWith(color: AppColors.textSecondary),
                  ),
                ),
                TextButton(
                  onPressed: () => ref.read(pendingInviteTokenProvider.notifier).clear(),
                  child: const Text('Dismiss'),
                ),
              ],
            );
          }

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    radius: 20,
                    backgroundColor: AppColors.green.withValues(alpha: 0.2),
                    child: Text(
                      preview.inviterName.isNotEmpty
                          ? preview.inviterName[0].toUpperCase()
                          : 'F',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        color: AppColors.green,
                        fontSize: 16,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'STUDY CIRCLE INVITATION',
                          style: AppTextStyles.caption12.copyWith(
                            color: AppColors.green,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.8,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          preview.inviterName,
                          style: AppTextStyles.body16Bold,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Decline',
                    icon: const Icon(Icons.close_rounded, size: 20, color: AppColors.textSecondary),
                    onPressed: () {
                      HapticFeedback.lightImpact();
                      ref.read(pendingInviteTokenProvider.notifier).clear();
                    },
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                '${preview.inviterName} wants to connect with you on StudyUP so you can compare study progress and keep each other going.',
                style: AppTextStyles.body14.copyWith(color: AppColors.textSecondary),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: SizedBox(
                      height: 44,
                      child: FilledButton(
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.green,
                          foregroundColor: AppColors.onCta,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          elevation: 0,
                        ),
                        onPressed: _acceptingInvite
                            ? null
                            : () => _handleAcceptInvitation(token, preview.inviterName, selectedMonday),
                        child: _acceptingInvite
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: AppColors.onCta,
                                ),
                              )
                            : const Text(
                                'Accept Invitation',
                                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                              ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  SizedBox(
                    height: 44,
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.textSecondary,
                        side: BorderSide(color: AppColors.track.withValues(alpha: 0.3)),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      onPressed: () {
                        HapticFeedback.lightImpact();
                        ref.read(pendingInviteTokenProvider.notifier).clear();
                      },
                      child: const Text('Decline'),
                    ),
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _handleAcceptInvitation(
    String token,
    String inviterName,
    DateTime selectedMonday,
  ) async {
    final currentUserId = ref.read(backendUserIdProvider);
    if (currentUserId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Please sign in to connect with $inviterName.'),
          action: SnackBarAction(
            label: 'Sign In',
            onPressed: () {
              try {
                context.push('/auth');
              } catch (_) {}
            },
          ),
        ),
      );
      try {
        context.push('/auth');
      } catch (_) {}
      return;
    }

    final messenger = ScaffoldMessenger.of(context);
    setState(() => _acceptingInvite = true);
    try {
      final repo = ref.read(communityRepositoryProvider);
      if (repo == null) throw StateError('Community repository unavailable');

      final status = await repo.acceptInvite(token);
      if (!mounted) return;

      if (status == 'ok') {
        HapticFeedback.mediumImpact();
        await ref.read(pendingInviteTokenProvider.notifier).clear();
        ref.invalidate(communityHomeProvider(selectedMonday));
        messenger.showSnackBar(
          SnackBar(
            content: Text('You and $inviterName are now study friends!'),
            backgroundColor: AppColors.green,
          ),
        );
      } else if (status == 'own') {
        await ref.read(pendingInviteTokenProvider.notifier).clear();
        messenger.showSnackBar(
          const SnackBar(content: Text('You cannot accept your own invitation link.')),
        );
      } else if (status == 'already_friends') {
        await ref.read(pendingInviteTokenProvider.notifier).clear();
        ref.invalidate(communityHomeProvider(selectedMonday));
        messenger.showSnackBar(
          SnackBar(content: Text('You and $inviterName are already study friends.')),
        );
      } else if (status == 'used') {
        await ref.read(pendingInviteTokenProvider.notifier).clear();
        messenger.showSnackBar(
          const SnackBar(content: Text('This invitation link has already been used.')),
        );
      } else if (status == 'expired') {
        await ref.read(pendingInviteTokenProvider.notifier).clear();
        messenger.showSnackBar(
          const SnackBar(content: Text('This invitation link has expired.')),
        );
      } else {
        await ref.read(pendingInviteTokenProvider.notifier).clear();
        messenger.showSnackBar(
          const SnackBar(content: Text('Invalid invitation link.')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text('Could not accept invitation: $e')),
      );
    } finally {
      if (mounted) {
        setState(() => _acceptingInvite = false);
      }
    }
  }
}
