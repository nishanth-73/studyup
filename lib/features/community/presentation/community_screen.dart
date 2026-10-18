import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/backend/supabase_client.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/app_shell.dart';
import '../../../core/widgets/ui_kit.dart';
import '../../../core/widgets/week_picker_dialog.dart';
import '../../progress/presentation/study_progress_controller.dart';
import '../../social/data/social_providers.dart';
import '../../social/data/social_remote.dart';
import '../data/community_demo.dart';
import '../data/community_models.dart';
import '../data/community_store.dart';
import 'community_controller.dart';
import 'community_widgets.dart';

// Exact podium accents (rank order must not be swapped).
const _podiumFirst = AppColors.green; // #8BC48A
const _podiumSecond = Color(0xFFFFA45B);
const _podiumThird = Color(0xFF72A7F7);

/// Community: a friendly study competition. Exactly five elements: week
/// selector (shared Progress-style picker), top-three podium, You vs.
/// Top Friend comparison, full friends leaderboard, and the Invite
/// button.
///
/// SIGNED IN: every row comes from the friends scope of the Supabase
/// [leaderboard_scope] RPC (server-computed from validated session
/// records) — no demo data, no snapshots, never mixed. OFFLINE: the local
/// path (own sessions + accepted-snapshot friends + clearly-flagged
/// [CommunityDemo] fixtures). Streaks/levels reuse the Progress-screen
/// math.
class CommunityScreen extends ConsumerWidget {
  const CommunityScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final community = ref.watch(communityControllerProvider);

    return AppShell(
      currentIndex: 3,
      body: SafeArea(
        bottom: false,
        child: community.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => _chrome(
            context,
            ref,
            CommunityError(
              error: e,
              onRetry: () =>
                  ref.read(communityControllerProvider.notifier).refresh(),
            ),
          ),
          data: (data) => _homeBody(context, ref, data),
        ),
      ),
    );
  }

  /// Header + body wrapper shared by content and error states.
  Widget _chrome(BuildContext context, WidgetRef ref, Widget body) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
      children: [
        _header(context, ref),
        const SizedBox(height: 14),
        body,
        SizedBox(height: AppShell.scrollClearance(context)),
      ],
    );
  }

  Widget _header(BuildContext context, WidgetRef ref) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Community',
              style: AppTextStyles.title26.copyWith(fontSize: 26),
            ),
            const SizedBox(height: 4),
            Text(
              'Compete & grow together with your study crew',
              style: AppTextStyles.secondary14,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
      const SizedBox(width: 12),
      _IconButton(
        icon: Icons.calendar_month,
        label: 'Pick a week',
        onTap: () => _openWeekPicker(context, ref),
      ),
    ],
  );

  Widget _homeBody(BuildContext context, WidgetRef ref, CommunityData data) {
    final weekStart = ref.watch(communityWeekProvider);
    final board = ref.watch(communityDisplayProvider(weekStart));
    return board.when(
      // Live self updates recompute the merged board on every session
      // event/tick: keep showing the last board while it recomputes
      // instead of flashing a spinner.
      skipLoadingOnReload: true,
      loading: () => ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
        children: [
          _header(context, ref),
          const SizedBox(height: 14),
          _weekCaption(weekStart),
          const SizedBox(height: 48),
          const Center(child: CircularProgressIndicator()),
          SizedBox(height: AppShell.scrollClearance(context)),
        ],
      ),
      error: (e, _) => _chrome(
        context,
        ref,
        CommunityError(
          error: e,
          onRetry: () {
            // Retry the actual server fetch (self is always local/live).
            ref.invalidate(remoteFriendsBoardProvider);
            ref.read(communityControllerProvider.notifier).refresh();
          },
        ),
      ),
      data: (entries) => _boardBody(context, ref, data, entries, weekStart),
    );
  }

  Widget _boardBody(
    BuildContext context,
    WidgetRef ref,
    CommunityData data,
    List<LeaderboardEntry> entries,
    DateTime weekStart,
  ) {
    final ranked = entries.where((e) => e.hasData).toList();
    final hasDemo = entries.any((e) => CommunityDemo.isDemoId(e.memberId));
    final live = ref.watch(socialLiveProvider);
    final backendOn = ref.watch(backendReadyProvider);
    final sync = ref.watch(syncStatusProvider);
    // Keep the leaderboard fresh: manual retry (errors above), week
    // changes (provider family), friend changes (realtime), and resume.
    return _ResumeRefresh(
      weekStart: weekStart,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
        children: [
          _header(context, ref),
          const SizedBox(height: 14),
          _weekCaption(weekStart),
          if (hasDemo) ...[
            const SizedBox(height: 10),
            CommunityCard(
              child: Text(
                'Preview with demo friends — marked DEMO. Real friends appear once the social backend connects; demo streaks/levels are illustrative.',
                style: AppTextStyles.secondary14,
              ),
            ),
          ],
          if (live) ...[
            if (sync.syncing || sync.pending > 0) ...[
              const SizedBox(height: 10),
              CommunityCard(
                child: Row(
                  children: [
                    const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Syncing ${sync.pending} session${sync.pending == 1 ? '' : 's'}… leaderboard updates when done.',
                        style: AppTextStyles.secondary14,
                      ),
                    ),
                  ],
                ),
              ),
            ] else if (sync.lastError != null) ...[
              const SizedBox(height: 10),
              CommunityCard(
                child: Text(
                  'Sync failed — your study data is safe on this device and will retry automatically.',
                  style: AppTextStyles.secondary14,
                ),
              ),
            ],
          ],
          if (!live && backendOn) ...[
            const SizedBox(height: 10),
            CommunityCard(
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'You\u2019re offline or signed out — showing local + demo data. Sign in to sync and compete for real.',
                      style: AppTextStyles.secondary14,
                    ),
                  ),
                  const SizedBox(width: 12),
                  TextButton(
                    onPressed: () => context.go('/auth'),
                    child: Text(
                      'Sign in',
                      style: AppTextStyles.caption13.copyWith(
                        color: AppColors.cta,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 16),
          Text('Top 3', style: AppTextStyles.section18),
          const SizedBox(height: 8),
          _podium(ranked),
          const SizedBox(height: 16),
          Text('You vs. Top Friend', style: AppTextStyles.section18),
          const SizedBox(height: 8),
          _comparison(entries),
          const SizedBox(height: 16),
          Text('Leaderboard', style: AppTextStyles.section18),
          const SizedBox(height: 8),
          _fullLeaderboard(entries, data),
          const SizedBox(height: 16),
          PrimaryButton(
            label: 'Invite Friends & Start Competing',
            onPressed: () => _invite(context, ref),
            icon: const Icon(Icons.person_add, size: 18),
          ),
          const SizedBox(height: 12),
          Text(
            ref.watch(socialLiveProvider)
                ? 'Friends open your link, sign in, and tap Accept — nobody is added without accepting.'
                : 'Friends join by entering your code — nobody is added without accepting.',
            style: AppTextStyles.secondary12,
            textAlign: TextAlign.center,
          ),
          SizedBox(height: AppShell.scrollClearance(context)),
        ],
      ),
    );
  }

  // ---------- 1. selected-week caption (picker lives in the header) ----------

  /// Static one-line label showing the selected week + date range. It is
  /// intentionally NOT tappable: week picking happens through the
  /// calendar button in the header, which opens the shared
  /// week-picker dialog (month stepper, per-week real totals, future
  /// weeks locked). The picked week refreshes podium, comparison, and
  /// every leaderboard row together.
  Widget _weekCaption(DateTime weekStart) {
    final now = DateTime.now();
    final currentMonday = mondayOf(now);
    String label;
    if (!weekStart.isBefore(currentMonday)) {
      label = 'This Week';
    } else if (weekStart == currentMonday.subtract(const Duration(days: 7))) {
      label = 'Last Week';
    } else {
      label = 'Week';
    }
    var range = weekRangeLabel(weekStart);
    if (weekStart.year != now.year) range = '$range, ${weekStart.year}';
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Text(
        '$label · $range',
        style: AppTextStyles.secondary12,
        textAlign: TextAlign.center,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }

  Future<void> _openWeekPicker(BuildContext context, WidgetRef ref) async {
    final sessions = ref.read(studyProgressProvider).sessions;
    final now = DateTime.now();
    final picked = await showWeekPickerDialog(
      context: context,
      title: 'Select week',
      initialMonday: ref.read(communityWeekProvider),
      minutesFor: (monday) =>
          studiedSecondsInRange(
            sessions,
            monday,
            monday.add(const Duration(days: 7)),
            now,
          ) ~/
          60,
    );
    if (picked == null) return;
    // The dialog only returns Monday 00:00 starts, never future weeks.
    ref.read(communityWeekProvider.notifier).state = mondayOf(picked);
  }

  // ---------- 2. podium ----------

  Widget _podium(List<LeaderboardEntry> ranked) {
    final top = ranked.take(3).toList();
    if (top.isEmpty) {
      return const CommunityEmpty(
        title: 'No rankings yet',
        body: 'Study to post your time, or invite friends to fill this podium with real totals.',
      );
    }
    // Visual order: #2 left, #1 center (tallest), #3 right — one
    // connected component with exact rank colors.
    final LeaderboardEntry? second = top.length > 1 ? top[1] : null;
    final LeaderboardEntry? third = top.length > 2 ? top[2] : null;
    return CommunityCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(child: _podiumSlot(second, 2, _podiumSecond, short: true)),
          Expanded(child: _podiumSlot(top[0], 1, _podiumFirst, short: false)),
          Expanded(child: _podiumSlot(third, 3, _podiumThird, short: true)),
        ],
      ),
    );
  }

  Widget _podiumSlot(
    LeaderboardEntry? entry,
    int place,
    Color accent, {
    required bool short,
  }) {
    if (entry == null) {
      return Column(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: AppColors.track, width: 2),
            ),
            child: const Icon(Icons.person_outline, color: AppColors.textMuted),
          ),
          const SizedBox(height: 6),
          Text('—', style: AppTextStyles.secondary14),
          const SizedBox(height: 4),
          Container(
            width: double.infinity,
            height: short ? 44 : 72,
            decoration: BoxDecoration(
              color: AppColors.surface2,
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ],
      );
    }
    final isDemo = CommunityDemo.isDemoId(entry.memberId);
    return Column(
      children: [
        if (place == 1)
          const Padding(
            padding: EdgeInsets.only(bottom: 2),
            child: Icon(Icons.emoji_events, color: _podiumFirst, size: 22),
          ),
        CommunityAvatar(
          displayName: entry.displayName,
          avatarId: entry.avatarId,
          blobVariant: entry.blobVariant,
          radius: place == 1 ? 30 : 24,
          highlighted: entry.isSelf,
        ),
        const SizedBox(height: 6),
        Text(
          entry.isSelf ? 'You' : entry.displayName,
          style: AppTextStyles.caption13,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
        ),
        Text(
          formatHoursMinutes(entry.weekSeconds),
          style: AppTextStyles.body14Bold.copyWith(
            color: place == 1 ? _podiumFirst : AppColors.textPrimary,
          ),
        ),
        Text(
          _streakLevelLine(entry),
          style: AppTextStyles.secondary12,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        if (isDemo) Text('DEMO', style: AppTextStyles.label10),
        const SizedBox(height: 6),
        Container(
          width: double.infinity,
          height: short ? 44 : 72,
          decoration: BoxDecoration(
            color: accent.withValues(alpha: place == 1 ? 0.28 : 0.18),
            borderRadius: BorderRadius.circular(12),
            border: place == 1 ? Border.all(color: accent) : null,
          ),
          child: Center(
            child: Text(
              '$place',
              style: AppTextStyles.title26.copyWith(color: accent),
            ),
          ),
        ),
      ],
    );
  }

  String _streakLevelLine(LeaderboardEntry e) {
    final streak = e.streakDays == null ? '–' : '${e.streakDays}d streak';
    final level = e.level == null ? '–' : 'Lv ${e.level}';
    return '$streak · $level';
  }

  // ---------- 3. comparison ----------

  Widget _comparison(List<LeaderboardEntry> entries) {
    final self = entries.where((e) => e.isSelf).firstOrNull;
    // The top FRIEND, whether or not they have shared totals this week: a
    // brand-new friend with zero progress is still a real friend, and the
    // comparison must show honest zeros rather than claim there is nobody.
    final friends = entries.where((e) => !e.isSelf).toList()
      ..sort((a, b) {
        if (a.hasData != b.hasData) return a.hasData ? -1 : 1;
        if (a.hasData && b.hasData) {
          final bySeconds = b.weekSeconds.compareTo(a.weekSeconds);
          if (bySeconds != 0) return bySeconds;
        }
        return a.displayName.toLowerCase().compareTo(
          b.displayName.toLowerCase(),
        );
      });
    final friend = friends.firstOrNull;
    if (self == null) {
      return const CommunityEmpty(
        title: 'Sharing is off',
        body: 'Turn on leaderboard sharing in Friends → Privacy to compare your progress.',
      );
    }
    if (friend == null) {
      return const CommunityEmpty(
        title: 'No friend to compare with',
        body: 'Invite a friend and ask them to share a fresh code — your comparison appears here, never fabricated.',
      );
    }
    final friendLabel = friend.displayName.length > 12
        ? '${friend.displayName.substring(0, 11)}…'
        : friend.displayName;
    return CommunityCard(
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: _versusHead(
                  'You',
                  self.avatarId,
                  self.blobVariant,
                  isSelf: true,
                  isDemo: false,
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Text('vs', style: AppTextStyles.secondary14),
              ),
              Expanded(
                child: _versusHead(
                  friendLabel,
                  friend.avatarId,
                  friend.blobVariant,
                  isSelf: false,
                  isDemo: CommunityDemo.isDemoId(friend.memberId),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _versusRow(
            'Study time',
            formatHoursMinutes(self.weekSeconds),
            formatHoursMinutes(friend.weekSeconds),
            self.weekSeconds >= friend.weekSeconds,
          ),
          _versusRow(
            'Streak',
            self.streakDays == null ? '–' : '${self.streakDays}d',
            friend.streakDays == null ? '–' : '${friend.streakDays}d',
            (self.streakDays ?? -1) >= (friend.streakDays ?? -1),
            comparable: self.streakDays != null && friend.streakDays != null,
          ),
          _versusRow(
            'Level',
            self.level == null ? '–' : 'Lv ${self.level}',
            friend.level == null ? '–' : 'Lv ${friend.level}',
            (self.level ?? -1) >= (friend.level ?? -1),
            comparable: self.level != null && friend.level != null,
          ),
          if (CommunityDemo.isDemoId(friend.memberId))
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                'Demo comparison — illustrative figures.',
                style: AppTextStyles.secondary12,
              ),
            ),
        ],
      ),
    );
  }

  Widget _versusHead(
    String name,
    String avatarId,
    int blobVariant, {
    required bool isSelf,
    required bool isDemo,
  }) {
    return Column(
      children: [
        CommunityAvatar(
          displayName: name,
          avatarId: avatarId,
          blobVariant: blobVariant,
          radius: 20,
          highlighted: isSelf,
        ),
        const SizedBox(height: 4),
        Text(
          name,
          style: AppTextStyles.caption13,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        if (isDemo) Text('DEMO', style: AppTextStyles.label10),
      ],
    );
  }

  Widget _versusRow(
    String label,
    String you,
    String friend,
    bool youLead, {
    bool comparable = true,
  }) {
    final youStyle = AppTextStyles.body14Bold.copyWith(
      color: comparable && youLead ? AppColors.cta : AppColors.textPrimary,
    );
    final friendStyle = AppTextStyles.body14Bold.copyWith(
      color: comparable && !youLead ? AppColors.cta : AppColors.textPrimary,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Expanded(
            child: Text(you, style: youStyle, textAlign: TextAlign.center),
          ),
          Expanded(
            child: Text(
              label,
              style: AppTextStyles.secondary12,
              textAlign: TextAlign.center,
            ),
          ),
          Expanded(
            child: Text(
              friend,
              style: friendStyle,
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }

  // ---------- 4. full leaderboard ----------

  Widget _fullLeaderboard(List<LeaderboardEntry> entries, CommunityData data) {
    final ranked = entries.where((e) => e.hasData).toList();
    final waiting = entries.where((e) => !e.hasData).toList();
    if (ranked.isEmpty && waiting.isEmpty) {
      return const CommunityEmpty(
        title: 'Nobody here yet',
        body: 'Invite friends to compete. Your totals appear automatically as you study.',
      );
    }
    return Column(
      children: [
        if (ranked.isNotEmpty)
          CommunityCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                for (var i = 0; i < ranked.length; i++) ...[
                  _leaderRow(ranked[i]),
                  if (i < ranked.length - 1)
                    const Divider(
                      height: 1,
                      indent: 16,
                      endIndent: 16,
                      color: AppColors.track,
                    ),
                ],
              ],
            ),
          ),
        if (waiting.isNotEmpty) ...[
          const SizedBox(height: 10),
          CommunityCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Waiting for shared data', style: AppTextStyles.body15),
                const SizedBox(height: 4),
                Text(
                  'These friends have not shared this week\u2019s totals yet — listed without ranks, never as zero.',
                  style: AppTextStyles.secondary14,
                ),
                const SizedBox(height: 8),
                for (final e in waiting)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 5),
                    child: Row(
                      children: [
                        CommunityAvatar(
                          displayName: e.displayName,
                          avatarId: e.avatarId,
                          blobVariant: e.blobVariant,
                          radius: 15,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            e.displayName,
                            style: AppTextStyles.body14,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (e.isSelf)
                          const Pill(
                            'You',
                            background: AppColors.cta,
                            foreground: AppColors.onCta,
                          ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _leaderRow(LeaderboardEntry e) {
    final isDemo = CommunityDemo.isDemoId(e.memberId);
    return Container(
      decoration: BoxDecoration(
        color: e.isSelf
            ? AppColors.cta.withValues(alpha: 0.08)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(20),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          RankBadge(rank: e.rank),
          const SizedBox(width: 12),
          CommunityAvatar(
            displayName: e.displayName,
            avatarId: e.avatarId,
            blobVariant: e.blobVariant,
            radius: 17,
            highlighted: e.isSelf,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        e.displayName,
                        style: AppTextStyles.body14Bold,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (e.isSelf) ...[
                      const SizedBox(width: 6),
                      const Pill(
                        'You',
                        background: AppColors.cta,
                        foreground: AppColors.onCta,
                      ),
                    ],
                    if (isDemo) ...[
                      const SizedBox(width: 6),
                      const Pill('DEMO'),
                    ],
                  ],
                ),
                Text(
                  _streakLevelLine(e),
                  style: AppTextStyles.secondary12,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          RankMovement(movement: e.rankMovement),
          const SizedBox(width: 8),
          Text(
            formatHoursMinutes(e.weekSeconds),
            style: AppTextStyles.body14.copyWith(color: AppColors.cta),
          ),
        ],
      ),
    );
  }

  // ---------- 5. invite ----------

  Future<void> _invite(BuildContext context, WidgetRef ref) async {
    if (!ref.read(socialLiveProvider)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Sign in to create a shareable invitation link. You can still share an invite code from Friends.',
          ),
        ),
      );
      return;
    }
    await _inviteServerLink(context, ref);
  }

  /// Server invitation flow. Creates a single-use token via RPC (only the
  /// hash is stored), builds the real App Link, and opens the native
  /// share sheet. Falls back to clipboard; never shares a fake URL.
  Future<void> _inviteServerLink(BuildContext context, WidgetRef ref) async {
    final remote = ref.read(socialRemoteProvider);
    if (remote == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Sign in to create an invitation link.')),
      );
      return;
    }
    String? raw;
    try {
      raw = await remote.createInvitation(validDays: 7);
    } catch (_) {
      raw = null;
    }
    if (raw == null) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not create an invite right now.')),
      );
      return;
    }
    late final String link;
    try {
      link = inviteLinkFor(raw);
    } on ArgumentError {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not create a valid invitation link. Try again.'),
        ),
      );
      return;
    } on FormatException {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not create a valid invitation link. Try again.'),
        ),
      );
      return;
    }
    final message = inviteShareMessage(link);
    if (!context.mounted) return;
    await _shareMessage(context, message);
  }

  Future<void> _shareMessage(BuildContext context, String message) async {
    try {
      await SharePlus.instance.share(
        ShareParams(text: message, subject: 'Join me on StudyUp'),
      );
    } catch (_) {
      await Clipboard.setData(ClipboardData(text: message));
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Invite copied — paste it to a friend to share.'),
        ),
      );
    }
  }
}

/// Revalidates the friends + leaderboard when the screen appears and when
/// the app returns to the foreground: a friend may have accepted an
/// invitation (or studied) while we were away. Refreshing MEMBERSHIP as
/// well as statistics is what makes a newly accepted friend appear without
/// an app restart. Cleanup on dispose.
class _ResumeRefresh extends ConsumerStatefulWidget {
  final DateTime weekStart;
  final Widget child;

  const _ResumeRefresh({required this.weekStart, required this.child});

  @override
  ConsumerState<_ResumeRefresh> createState() => _ResumeRefreshState();
}

class _ResumeRefreshState extends ConsumerState<_ResumeRefresh>
    with WidgetsBindingObserver {
  /// Both layers: the friendship list (membership, including friends with
  /// no shared data) and the server board rows (progress). Self is always
  /// computed locally and needs no refetch.
  void _refresh() {
    ref.invalidate(remoteFriendsProvider);
    ref.invalidate(remoteFriendsBoardProvider);
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Entering the Community tab always re-reads the accepted friends, so a
    // friend who accepted while the user was elsewhere shows up here.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _refresh();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // Refetch friend rows; the local self row is always live.
      _refresh();
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// Small circular icon button for the header.
class _IconButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  const _IconButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap == null
            ? null
            : () {
                HapticFeedback.selectionClick();
                onTap!();
              },
        child: Opacity(
          opacity: onTap == null ? 0.35 : 1,
          child: Container(
            width: 44,
            height: 44,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.surface,
            ),
            child: Icon(icon, color: AppColors.textPrimary, size: 22),
          ),
        ),
      ),
    );
  }
}
