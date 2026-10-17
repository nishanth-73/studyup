import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/app_colors.dart';
import '../data/user_profile.dart';

/// PNG avatar catalogue: the six bundled profile portraits.
const List<String> avatarIds = bundledAvatarIds;

/// Asset path for an avatar id, falling back to the default portrait for
/// unknown or legacy values so stored profiles never break rendering.
String avatarAssetForId(String avatarId) {
  final id = avatarIds.contains(avatarId) ? avatarId : avatarIds.first;
  return 'assets/images/avatars/$id.png';
}

/// Circular PNG user avatar used everywhere the profile picture appears
/// (Home header, Profile). The Robo mascot is never used here.
class UserAvatar extends StatelessWidget {
  final String avatarId;
  final double size;
  const UserAvatar({super.key, required this.avatarId, this.size = 52});

  @override
  Widget build(BuildContext context) {
    return ClipOval(
      child: Image.asset(
        avatarAssetForId(avatarId),
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => Container(
          width: size,
          height: size,
          color: AppColors.surface2,
          child: Icon(
            Icons.person,
            size: size * 0.55,
            color: AppColors.textSecondary,
          ),
        ),
      ),
    );
  }
}

/// PNG avatar picker grid: the six bundled portraits with a selection
/// ring. Persists through [onSelected]; callers own the storage.
class AvatarPickerGrid extends StatelessWidget {
  final String selectedId;
  final ValueChanged<String> onSelected;
  final double avatarSize;
  const AvatarPickerGrid({
    super.key,
    required this.selectedId,
    required this.onSelected,
    this.avatarSize = 64,
  });

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
      ),
      itemCount: avatarIds.length,
      itemBuilder: (context, i) {
        final id = avatarIds[i];
        final selected = id == selectedId;
        return Semantics(
          button: true,
          selected: selected,
          label: 'Avatar option ${i + 1}',
          child: Material(
            color: selected
                ? AppColors.cta.withValues(alpha: 0.16)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(18),
            child: InkWell(
              key: ValueKey('avatar-option-$id'),
              borderRadius: BorderRadius.circular(18),
              onTap: () {
                SystemSound.play(SystemSoundType.click);
                HapticFeedback.selectionClick();
                onSelected(id);
              },
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: selected ? AppColors.cta : Colors.transparent,
                    width: 2,
                  ),
                ),
                child: Center(
                  child: UserAvatar(avatarId: id, size: avatarSize),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
