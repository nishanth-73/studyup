import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../avatar/data/user_profile.dart';

/// Shared Community chrome: avatar, cards, empty/loading/error states.
/// Follows the StudyUp dark theme (#17181D / #202128 / #FDD679 / #8E90A3).

const _avatarPalette = [
  AppColors.primary,
  AppColors.green,
  AppColors.blue,
  AppColors.pink,
  AppColors.cta,
  AppColors.pinkLight,
];

Color avatarColorFor(int blobVariant) =>
    _avatarPalette[blobVariant.abs() % _avatarPalette.length];

/// Profile avatar: the real bundled portrait when [avatarId] names one
/// (own profile or a friend's shared id), otherwise an initial-based
/// fallback. Only local bundled assets are used — Community never loads
/// remote images, so no private imagery can leak.
class CommunityAvatar extends StatelessWidget {
  final String displayName;
  final String avatarId;
  final int blobVariant;
  final double radius;
  final bool highlighted;

  const CommunityAvatar({
    super.key,
    required this.displayName,
    this.avatarId = 'robo-default',
    required this.blobVariant,
    this.radius = 20,
    this.highlighted = false,
  });

  @override
  Widget build(BuildContext context) {
    final decoration = BoxDecoration(
      shape: BoxShape.circle,
      border: highlighted ? Border.all(color: AppColors.cta, width: 2) : null,
    );
    if (isValidAvatarId(avatarId)) {
      return Container(
        width: radius * 2,
        height: radius * 2,
        decoration: decoration,
        child: ClipOval(
          child: Image.asset(
            'assets/images/avatars/$avatarId.png',
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) => _fallback(),
          ),
        ),
      );
    }
    return Container(
      width: radius * 2,
      height: radius * 2,
      decoration: decoration.copyWith(
        color: avatarColorFor(blobVariant).withValues(alpha: 0.22),
      ),
      child: Center(child: _fallbackLabel()),
    );
  }

  Widget _fallback() => Container(
    color: avatarColorFor(blobVariant).withValues(alpha: 0.22),
    child: Center(child: _fallbackLabel()),
  );

  Widget _fallbackLabel() {
    final initial = displayName.trim().isEmpty
        ? '?'
        : displayName.trim()[0].toUpperCase();
    return Text(
      initial,
      style: AppTextStyles.body16Bold.copyWith(
        color: avatarColorFor(blobVariant),
      ),
    );
  }
}

class CommunityCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;

  const CommunityCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final card = Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
      ),
      child: child,
    );
    if (onTap == null) return card;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () {
          HapticFeedback.selectionClick();
          onTap!();
        },
        child: card,
      ),
    );
  }
}

class CommunityEmpty extends StatelessWidget {
  final String title;
  final String body;
  final String? actionLabel;
  final VoidCallback? onAction;

  const CommunityEmpty({
    super.key,
    required this.title,
    required this.body,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return CommunityCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: AppTextStyles.body15),
          const SizedBox(height: 4),
          Text(body, style: AppTextStyles.secondary14),
          if (actionLabel != null && onAction != null) ...[
            const SizedBox(height: 12),
            GestureDetector(
              onTap: onAction,
              child: Text(
                actionLabel!,
                style: AppTextStyles.caption13.copyWith(color: AppColors.cta),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class CommunityError extends StatelessWidget {
  final Object error;
  final VoidCallback onRetry;

  const CommunityError({super.key, required this.error, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return CommunityCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Something went wrong', style: AppTextStyles.body15),
          const SizedBox(height: 4),
          Text(
            'Community data could not be loaded. Your study data is safe.',
            style: AppTextStyles.secondary14,
          ),
          const SizedBox(height: 12),
          GestureDetector(
            onTap: onRetry,
            child: Text(
              'Try again',
              style: AppTextStyles.caption13.copyWith(color: AppColors.cta),
            ),
          ),
        ],
      ),
    );
  }
}

/// Rank badge: gold/silver/bronze for 1-3, muted otherwise. Rank 0 =
/// unranked (no shared data).
class RankBadge extends StatelessWidget {
  final int rank;

  const RankBadge({super.key, required this.rank});

  @override
  Widget build(BuildContext context) {
    if (rank <= 0) {
      return Text('–', style: AppTextStyles.secondary14);
    }
    final color = switch (rank) {
      1 => AppColors.cta,
      2 => const Color(0xFFC9CCD6),
      3 => const Color(0xFFE0A173),
      _ => AppColors.textSecondary,
    };
    return Container(
      width: 30,
      height: 30,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color.withValues(alpha: 0.16),
      ),
      child: Center(
        child: Text(
          '$rank',
          style: AppTextStyles.body14Bold.copyWith(color: color),
        ),
      ),
    );
  }
}

/// Up/down/flat movement indicator. Shown only when both weeks have
/// reliable data (null = not enough history, rendered as nothing).
class RankMovement extends StatelessWidget {
  final int? movement;

  const RankMovement({super.key, required this.movement});

  @override
  Widget build(BuildContext context) {
    if (movement == null || movement == 0) return const SizedBox.shrink();
    final up = movement! > 0;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          up ? Icons.arrow_upward : Icons.arrow_downward,
          size: 12,
          color: up ? AppColors.green : AppColors.error,
        ),
        Text(
          '${movement!.abs()}',
          style: AppTextStyles.caption12.copyWith(
            color: up ? AppColors.green : AppColors.error,
          ),
        ),
      ],
    );
  }
}
