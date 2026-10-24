import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/app_shell.dart';
import '../../../core/widgets/week_picker_dialog.dart';
import '../../avatar/data/user_profile.dart';
import '../../avatar/presentation/avatar_widgets.dart';
import '../../avatar/presentation/user_profile_controller.dart';
import '../data/community_models.dart';
import 'community_providers.dart';
import 'full_leaderboard_screen.dart';
import 'week_detail_dialog.dart';

/// Production-ready StudyUP Community screen:
/// 1. Top bar with Title + compact week picker in top-right (no extra icon).
/// 2. Top 3 Leaderboard Podium Card (1st place GREEN, 2nd BLUE, 3rd PINK, real profile avatars).
/// 3. My Today's Session Card (today study time, completed sessions, streak).
/// 4. Weekly Comparison Card (You vs Top Friend).
/// 5. Leaderboard Card (Top 5 preview, "YOU" highlight, tap for week detail, "See all" action).
/// 6. Native device sharing for invitations with Web Share API and Clipboard fallback.
class CommunityScreen extends ConsumerStatefulWidget {
  const CommunityScreen({super.key});

  @override
  ConsumerState<CommunityScreen> createState() => _CommunityScreenState();
}

class _CommunityScreenState extends ConsumerState<CommunityScreen> {
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
        if (monday.year == currentMonday.year &&
            monday.month == currentMonday.month &&
            monday.day == currentMonday.day &&
            homeData != null) {
          return homeData.meWeekly.totalMinutes;
        }
        return 0;
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
        final result = await Share.share(
          shareText,
        );
        // If user cancelled or dismissed, do nothing (no false error)
        if (result.status == ShareResultStatus.dismissed) return;
        if (result.status == ShareResultStatus.success) return;
      } catch (_) {
        // Native share sheet failed or unsupported: fallback to clipboard
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

  /// Resolves actual selected avatar portrait from user profile, or falls back to initials.
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

    // Current user's selected profile avatar has priority
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

    // Graceful fallback: circle avatar with initials
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
                    ref.invalidate(communityHomeProvider(selectedMonday));
                    await ref.read(communityHomeProvider(selectedMonday).future);
                  },
                  child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(
                      parent: BouncingScrollPhysics(),
                    ),
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
                    children: [
                      // ========================================================
                      // 1. TOP BAR (Title + Compact Week Picker, NO extra icon)
                      // ========================================================
                      _buildTopBar(weekLabel, selectedMonday, homeAsync.valueOrNull),
                      const SizedBox(height: 12),

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
                              style: AppTextStyles.caption12.copyWith(color: AppColors.textSecondary),
                            ),
                          ),
                        ],
                        error: (err, _) => [
                          Container(
                            padding: const EdgeInsets.all(20),
                            decoration: BoxDecoration(
                              color: AppColors.surface,
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: AppColors.track.withValues(alpha: 0.3)),
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
                        ],
                        data: (homeData) => _buildCommunitySections(homeData, weekLabel, selectedMonday),
                      ),

                      // Scroll clearance for the floating navigation
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

    // Top 3 for podium
    final first = members.isNotEmpty ? members[0] : null;
    final second = members.length > 1 ? members[1] : null;
    final third = members.length > 2 ? members[2] : null;

    // Top 5 for leaderboard preview
    final top5Members = members.take(5).toList();

    return [
      // ========================================================
      // 2. TOP 3 LEADERBOARD PODIUM CARD
      // ========================================================
      _buildPodiumCard(first, second, third, homeData.hasFriends, selectedMonday),
      const SizedBox(height: 12),

      // ========================================================
      // 3. TODAY'S SESSION CARD (Real focus summary)
      // ========================================================
      _buildTodaySessionCard(homeData.meToday, homeData.meWeekly.streak),
      const SizedBox(height: 12),

      // ========================================================
      // 4. WEEKLY COMPARISON CARD (You vs Top Friend)
      // ========================================================
      _buildWeeklyComparisonCard(currentUser, topFriend, homeData.hasFriends),
      const SizedBox(height: 12),

      // ========================================================
      // 5. LEADERBOARD CARD (Top 5 + "See all" action)
      // ========================================================
      _buildLeaderboardCard(top5Members, members, weekLabel, selectedMonday),
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
        // Compact week picker button ONLY (extra icon removed)
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
                monday: selectedMonday,
              );
            }
          : null,
      behavior: HitTestBehavior.opaque,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Crown / star icon for 1st place (GREEN)
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

          // User-selected avatar with place ring
          Stack(
            alignment: Alignment.center,
            children: [
              Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: accentColor,
                    width: isWinner ? 2.5 : 2.0,
                  ),
                  boxShadow: isWinner
                      ? [
                          BoxShadow(
                            color: accentColor.withValues(alpha: 0.35),
                            blurRadius: 10,
                            spreadRadius: 1,
                          ),
                        ]
                      : null,
                ),
                child: _buildAvatarWidget(
                  member: member,
                  radius: avatarRadius,
                  fallbackColor: accentColor,
                ),
              ),
              // Place badge pill
              Positioned(
                bottom: -2,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                  decoration: BoxDecoration(
                    color: accentColor,
                    borderRadius: BorderRadius.circular(10),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.3),
                        blurRadius: 4,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Text(
                    '#$place',
                    style: const TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w800,
                      color: AppColors.onCta,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),

          // Display Name
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Flexible(
                child: Text(
                  member?.isCurrentUser == true ? 'You' : name,
                  style: AppTextStyles.caption12Bold.copyWith(
                    color: member?.isCurrentUser == true
                        ? (isWinner ? AppColors.green : AppColors.cta)
                        : AppColors.textPrimary,
                    fontWeight: isWinner ? FontWeight.w800 : FontWeight.w700,
                    fontSize: 11,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                ),
              ),
            ],
          ),
          const SizedBox(height: 1),

          // Study Time
          Text(
            time,
            style: AppTextStyles.caption12.copyWith(
              fontSize: 10,
              color: isWinner ? AppColors.green : AppColors.textSecondary,
              fontWeight: isWinner ? FontWeight.w700 : FontWeight.w500,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 8),

          // Pedestal block
          Container(
            height: pedestalHeight,
            width: double.infinity,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  accentColor.withValues(alpha: isWinner ? 0.35 : 0.20),
                  accentColor.withValues(alpha: 0.04),
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
  // 4. WEEKLY COMPARISON CARD (You vs Top Friend)
  // --------------------------------------------------------------------------
  Widget _buildWeeklyComparisonCard(
    CommunityMember me,
    CommunityMember? topFriend,
    bool hasFriends,
  ) {
    if (!hasFriends || topFriend == null) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.track.withValues(alpha: 0.35)),
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
              ],
            ),
            const SizedBox(height: 12),
            Text(
              'Invite a friend to compare weekly focus hours and cheer each other on!',
              style: AppTextStyles.secondary12,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 10),
            FilledButton.tonalIcon(
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.surface2,
                foregroundColor: AppColors.green,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              ),
              onPressed: _shareInviteLink,
              icon: const Icon(Icons.share_rounded, size: 15),
              label: const Text('Invite a friend', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
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
      padding: const EdgeInsets.all(14),
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
  // 5. LEADERBOARD CARD (Top 5 + "See all" action + native Share action)
  // --------------------------------------------------------------------------
  Widget _buildLeaderboardCard(
    List<CommunityMember> top5,
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
          // Header with Title and "See all"
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
                // "See all" Action
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
            color: AppColors.track.withValues(alpha: 0.4),
          ),

          // Top 5 Rows
          for (var i = 0; i < top5.length; i++) ...[
            _buildLeaderboardRow(top5[i], i + 1, selectedMonday),
            if (i < top5.length - 1)
              Divider(
                height: 1,
                indent: 52,
                endIndent: 14,
                color: AppColors.track.withValues(alpha: 0.25),
              ),
          ],

          // Footer action: Native share sheet button
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 8, 14, 12),
            child: SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.green,
                  side: BorderSide(color: AppColors.green.withValues(alpha: 0.4)),
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: _shareInviteLink,
                icon: const Icon(Icons.share_rounded, size: 14),
                label: const Text('Share invitation link', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLeaderboardRow(CommunityMember member, int rank, DateTime selectedMonday) {
    final isTop3 = rank <= 3;
    final rankColor = switch (rank) {
      1 => AppColors.green, // 1st place GREEN
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
          monday: selectedMonday,
        );
      },
      child: Container(
        color: member.isCurrentUser
            ? AppColors.green.withValues(alpha: 0.08)
            : Colors.transparent,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          children: [
            // Rank Numeral
            SizedBox(
              width: 24,
              child: Text(
                '$rank',
                style: AppTextStyles.body14Bold.copyWith(
                  color: rankColor,
                  fontSize: 13,
                  fontWeight: isTop3 || member.isCurrentUser
                      ? FontWeight.w800
                      : FontWeight.w600,
                ),
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(width: 8),

            // Profile Avatar (Actual selected avatar portrait or initials fallback)
            _buildAvatarWidget(member: member, radius: 15, fallbackColor: rankColor),
            const SizedBox(width: 10),

            // Name and (YOU) badge
            Expanded(
              child: Row(
                children: [
                  Flexible(
                    child: Text(
                      member.name,
                      style: AppTextStyles.body14Bold.copyWith(
                        color: member.isCurrentUser
                            ? (rank == 1 ? AppColors.green : AppColors.cta)
                            : AppColors.textPrimary,
                        fontSize: 13,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (member.isCurrentUser) ...[
                    const SizedBox(width: 5),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 5,
                        vertical: 1,
                      ),
                      decoration: BoxDecoration(
                        color: (rank == 1 ? AppColors.green : AppColors.cta).withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        'YOU',
                        style: AppTextStyles.caption12Bold.copyWith(
                          fontSize: 8.5,
                          color: rank == 1 ? AppColors.green : AppColors.cta,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),

            // Study Time
            Text(
              member.formattedStudyTime,
              style: AppTextStyles.body14Bold.copyWith(
                fontSize: 13,
                color: member.isCurrentUser
                    ? (rank == 1 ? AppColors.green : AppColors.cta)
                    : (isTop3 ? AppColors.textPrimary : AppColors.textSecondary),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
