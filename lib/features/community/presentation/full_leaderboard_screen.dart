import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../avatar/data/user_profile.dart';
import '../../avatar/presentation/avatar_widgets.dart';
import '../data/community_models.dart';

/// Full leaderboard screen displayed when the user taps "See all" on the main Community screen.
class FullLeaderboardScreen extends StatelessWidget {
  final List<CommunityMember> members;
  final String weekLabel;
  final void Function(CommunityMember member)? onMemberTap;

  const FullLeaderboardScreen({
    super.key,
    required this.members,
    required this.weekLabel,
    this.onMemberTap,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: AppColors.textPrimary),
          onPressed: () {
            HapticFeedback.selectionClick();
            Navigator.of(context).pop();
          },
        ),
        title: Text('Leaderboard', style: AppTextStyles.title26),
        centerTitle: false,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: AppColors.surface2,
                  borderRadius: BorderRadius.circular(100),
                  border: Border.all(color: AppColors.track.withValues(alpha: 0.5)),
                ),
                child: Text(
                  weekLabel,
                  style: AppTextStyles.caption12Bold.copyWith(color: AppColors.textSecondary),
                ),
              ),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView.separated(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          itemCount: members.length,
          separatorBuilder: (_, _) => const SizedBox(height: 8),
          itemBuilder: (context, index) {
            final member = members[index];
            final rank = index + 1;
            final isTop3 = rank <= 3;

            final rankColor = switch (rank) {
              1 => AppColors.green,
              2 => AppColors.blue,
              3 => AppColors.pink,
              _ => AppColors.textSecondary,
            };

            final hasCustomAvatar = member.avatarUrl != null && isValidAvatarId(member.avatarUrl!);

            return Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: onMemberTap != null ? () => onMemberTap!(member) : null,
                borderRadius: BorderRadius.circular(16),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: member.isCurrentUser
                        ? AppColors.cta.withValues(alpha: 0.12)
                        : AppColors.surface,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: member.isCurrentUser
                          ? AppColors.cta.withValues(alpha: 0.45)
                          : AppColors.track.withValues(alpha: 0.25),
                      width: member.isCurrentUser ? 1.5 : 1,
                    ),
                  ),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 32,
                        child: Text(
                          '#$rank',
                          style: AppTextStyles.body14Bold.copyWith(
                            color: rankColor,
                            fontWeight: isTop3 || member.isCurrentUser
                                ? FontWeight.w800
                                : FontWeight.w600,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      hasCustomAvatar
                          ? UserAvatar(avatarId: member.avatarUrl!, size: 40)
                          : CircleAvatar(
                              radius: 20,
                              backgroundColor: member.avatarColor.withValues(alpha: 0.2),
                              child: Text(
                                member.initials,
                                style: AppTextStyles.caption12Bold.copyWith(
                                  color: member.avatarColor,
                                ),
                              ),
                            ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Flexible(
                                  child: Text(
                                    member.name,
                                    style: AppTextStyles.body14Bold.copyWith(
                                      color: member.isCurrentUser
                                          ? AppColors.cta
                                          : AppColors.textPrimary,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                if (member.isCurrentUser) ...[
                                  const SizedBox(width: 6),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 6,
                                      vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      color: AppColors.cta.withValues(alpha: 0.2),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      'YOU',
                                      style: AppTextStyles.caption12Bold.copyWith(
                                        fontSize: 10,
                                        color: AppColors.cta,
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                            if (member.streakDays > 0)
                              Padding(
                                padding: const EdgeInsets.only(top: 2),
                                child: Row(
                                  children: [
                                    const Icon(
                                      Icons.local_fire_department_rounded,
                                      size: 13,
                                      color: AppColors.orange,
                                    ),
                                    const SizedBox(width: 3),
                                    Text(
                                      '${member.streakDays} day streak',
                                      style: AppTextStyles.caption12.copyWith(
                                        fontSize: 11,
                                        color: AppColors.textSecondary,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                          ],
                        ),
                      ),
                      Text(
                        member.formattedStudyTime,
                        style: AppTextStyles.body14Bold.copyWith(
                          color: member.isCurrentUser
                              ? AppColors.cta
                              : (isTop3 ? AppColors.textPrimary : AppColors.textSecondary),
                        ),
                      ),
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
}

