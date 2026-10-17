import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../data/community_models.dart';
import 'community_controller.dart';
import 'community_widgets.dart';

/// Weekly leaderboard: This Week / Last Week over friends, ranked by real
/// studied time in the selected Monday–Sunday window. Friends without a
/// matching-week snapshot render as "no shared data" — never as zero.
class LeaderboardScreen extends ConsumerStatefulWidget {
  const LeaderboardScreen({super.key});

  @override
  ConsumerState<LeaderboardScreen> createState() => _LeaderboardScreenState();
}

class _LeaderboardScreenState extends ConsumerState<LeaderboardScreen> {
  int _weekOffset = 0;

  DateTime get _weekStart =>
      mondayOf(DateTime.now()).subtract(Duration(days: 7 * _weekOffset));

  @override
  Widget build(BuildContext context) {
    final entries = ref.watch(leaderboardProvider(_weekStart));
    final community = ref.watch(communityControllerProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        title: Text('Leaderboard', style: AppTextStyles.section18),
      ),
      body: SafeArea(
        bottom: false,
        child: community.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => ListView(
            padding: const EdgeInsets.all(20),
            children: [
              CommunityError(
                error: e,
                onRetry: () =>
                    ref.read(communityControllerProvider.notifier).refresh(),
              ),
            ],
          ),
          data: (data) => _body(entries, data.friendIds.length),
        ),
      ),
    );
  }

  Widget _body(List<LeaderboardEntry> entries, int friendCount) {
    final ranked = entries.where((e) => e.hasData).toList();
    final unranked = entries.where((e) => !e.hasData).toList();
    final self = entries.where((e) => e.isSelf).firstOrNull;

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
      children: [
        _weekTabs(),
        const SizedBox(height: 6),
        Text(
          '${weekRangeLabel(_weekStart)} · Friends',
          style: AppTextStyles.secondary14,
        ),
        const SizedBox(height: 12),
        if (ranked.isEmpty)
          const CommunityEmpty(
            title: 'No shared data this week',
            body: 'Study to post your total, or ask friends to share a fresh invite code — only real, week-matched totals are ranked.',
          )
        else
          CommunityCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                for (var i = 0; i < ranked.length; i++) ...[
                  _row(ranked[i]),
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
        if (self != null) ...[const SizedBox(height: 12), _selfNote(self)],
        if (unranked.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text('No shared data', style: AppTextStyles.section18),
          const SizedBox(height: 8),
          for (final e in unranked)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: CommunityCard(
                child: Row(
                  children: [
                    CommunityAvatar(
                      displayName: e.displayName,
                      blobVariant: e.blobVariant,
                      radius: 16,
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
                    Text('waiting for share', style: AppTextStyles.secondary12),
                  ],
                ),
              ),
            ),
        ],
        const SizedBox(height: 16),
        CommunityCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('How ranking works', style: AppTextStyles.body15),
              SizedBox(height: 4),
              Text(
                'Monday–Sunday local weeks. Ties share a rank. Rank arrows need both weeks\u2019 data. The broader StudyUp leaderboard unlocks with cloud sync.',
                style: AppTextStyles.secondary14,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _weekTabs() {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(100),
      ),
      child: Row(
        children: [
          for (var i = 0; i < 2; i++)
            Expanded(
              child: GestureDetector(
                onTap: () => setState(() => _weekOffset = i),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(
                    color: _weekOffset == i
                        ? AppColors.cta
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(100),
                  ),
                  child: Center(
                    child: Text(
                      i == 0 ? 'This Week' : 'Last Week',
                      style: AppTextStyles.caption13.copyWith(
                        color: _weekOffset == i
                            ? AppColors.onCta
                            : AppColors.textSecondary,
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _row(LeaderboardEntry e) {
    final highlight = e.isSelf;
    return Container(
      decoration: BoxDecoration(
        color: highlight
            ? AppColors.cta.withValues(alpha: 0.08)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(20),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          RankBadge(rank: e.rank),
          const SizedBox(width: 12),
          CommunityAvatar(
            displayName: e.displayName,
            blobVariant: e.blobVariant,
            highlighted: highlight,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  highlight ? '${e.displayName} (you)' : e.displayName,
                  style: AppTextStyles.body14Bold,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                RankMovement(movement: e.rankMovement),
              ],
            ),
          ),
          Text(
            formatHoursMinutes(e.weekSeconds),
            style: AppTextStyles.body14Bold.copyWith(color: AppColors.cta),
          ),
        ],
      ),
    );
  }

  Widget _selfNote(LeaderboardEntry self) {
    if (!self.hasData || self.rank <= 0) {
      return const CommunityEmpty(
        title: 'You are opted out or idle',
        body: 'Enable leaderboard sharing in Friends → Privacy, then study to appear here.',
      );
    }
    final suffix = switch (self.rank) {
      1 => 'st',
      2 => 'nd',
      3 => 'rd',
      _ => 'th',
    };
    return CommunityCard(
      child: Text(
        'You are ${self.rank}$suffix with ${formatHoursMinutes(self.weekSeconds)} this week. Nice.',
        style: AppTextStyles.body14,
      ),
    );
  }
}
