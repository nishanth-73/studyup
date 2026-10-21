import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../avatar/data/user_profile.dart';
import '../../avatar/presentation/avatar_widgets.dart';
import '../../avatar/presentation/user_profile_controller.dart';
import '../../progress/data/study_gamification.dart';
import '../../progress/presentation/study_progress_controller.dart';
import '../../progress/presentation/streak_level_summary.dart';
import 'profile_detail_pages.dart';

/// Profile is a pushed standalone page (no bottom navigation): it always
/// opens on top of a tab, so the floating nav hides exactly like the
/// subject-detail pages, and the header back arrow returns.
class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(userProfileProvider).valueOrNull;
    final progress = ref.watch(studyProgressProvider);
    final levelName = progress.error != null
        ? 'Level unavailable'
        : !progress.isLoaded
        ? 'Loading level…'
        : computeStudyLevel(progress.xp.totalXp).tier.name;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
          children: [
            Row(
              children: [
                Material(
                  color: AppColors.surface,
                  shape: const CircleBorder(),
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    onTap: () {
                      SystemSound.play(SystemSoundType.click);
                      HapticFeedback.selectionClick();
                      if (context.canPop()) {
                        context.pop();
                      } else {
                        context.go('/home');
                      }
                    },
                    child: const Padding(
                      padding: EdgeInsets.all(10),
                      child: Icon(
                        Icons.arrow_back_ios_new,
                        size: 20,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: Text(
                    'Profile',
                    textAlign: TextAlign.center,
                    style: AppTextStyles.section18,
                  ),
                ),
                // Balances the back button so the title stays centered.
                const SizedBox(width: 44),
              ],
            ),
            const SizedBox(height: 12),
            if (profile == null)
              _SetupProfileTile(onTap: () => context.go('/onboarding'))
            else
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  UserAvatar(
                    avatarId: isValidAvatarId(profile.avatarId)
                        ? profile.avatarId
                        : defaultAvatarId,
                    size: 84,
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          profile.displayName.isEmpty
                              ? 'StudyUp user'
                              : profile.displayName,
                          style: AppTextStyles.title30,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          levelName,
                          key: const ValueKey('profile-level-name'),
                          style: AppTextStyles.caption13,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            const SizedBox(height: 16),
            // Streak and Level summary cards — live data from studyProgressProvider.
            const StreakLevelRow(),
            const SizedBox(height: 16),
            Text('Settings', style: AppTextStyles.section18),
            const SizedBox(height: 8),
            DetailRow(
              icon: Icons.smart_toy_outlined,
              title: 'Customise Robo',
              subtitle: 'Shape, preview and shell colour',
              onTap: () => context.push('/profile/customise-robo'),
            ),
            DetailRow(
              icon: Icons.notifications_outlined,
              title: 'Notifications',
              subtitle: 'Reminders, session and goal alerts',
              onTap: () => context.push('/profile/notifications'),
            ),
            DetailRow(
              icon: Icons.lock_outline,
              title: 'Privacy & data',
              subtitle: 'What is stored, sign out, erase',
              onTap: () => context.push('/profile/privacy'),
            ),
            DetailRow(
              icon: Icons.help_outline,
              title: 'Help',
              subtitle: 'How StudyUp works',
              onTap: () => context.push('/profile/help'),
            ),
            DetailRow(
              icon: Icons.feedback_outlined,
              title: 'Feedback',
              subtitle: 'Tell us what is broken or missing',
              onTap: () => context.push('/profile/feedback'),
            ),
            // No bottom navigation on this page: modest end padding only.
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}

/// Honest empty state: no profile yet, so prompt setup instead of
/// showing a placeholder name or a random avatar.
class _SetupProfileTile extends StatelessWidget {
  final VoidCallback onTap;
  const _SetupProfileTile({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(22),
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: () {
          SystemSound.play(SystemSoundType.click);
          HapticFeedback.selectionClick();
          onTap();
        },
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Set up your profile',
                      style: AppTextStyles.title30.copyWith(fontSize: 22),
                    ),
                    Text(
                      'Pick a name and your avatar',
                      style: AppTextStyles.caption13,
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.arrow_forward_ios,
                size: 14,
                color: AppColors.textSecondary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
