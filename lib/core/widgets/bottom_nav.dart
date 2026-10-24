import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';

import '../theme/app_colors.dart';

/// One navigation item: outline + filled SVG assets and its route.
class NavItemData {
  final String outlineAsset;
  final String filledAsset;
  final String route;
  final String label;
  final IconData? icon;

  const NavItemData({
    this.outlineAsset = '',
    this.filledAsset = '',
    this.icon,
    required this.route,
    required this.label,
  });
}

/// Four fully independent circular buttons — no labels, no shared pill,
/// no sliding layer. The selected circle gets the accent background with
/// the filled icon; the rest stay muted with outline icons.
class CustomBottomNav extends StatelessWidget {
  final int currentIndex;
  const CustomBottomNav({super.key, required this.currentIndex});

  static const _items = [
    NavItemData(
      outlineAsset: 'assets/icons/home_outline.svg',
      filledAsset: 'assets/icons/home_filled.svg',
      route: '/home',
      label: 'Home',
    ),
    NavItemData(
      outlineAsset: 'assets/icons/subjects_outline.svg',
      filledAsset: 'assets/icons/subjects_filled.svg',
      route: '/subjects',
      label: 'Subjects',
    ),
    NavItemData(
      outlineAsset: 'assets/icons/progress_outline.svg',
      filledAsset: 'assets/icons/progress_filled.svg',
      route: '/progress',
      label: 'Progress',
    ),
    NavItemData(
      outlineAsset: 'assets/icons/community_outline.svg',
      filledAsset: 'assets/icons/community_filled.svg',
      route: '/community',
      label: 'Community',
    ),
  ];

  static const diameter = 56.0;
  static const _iconSize = 26.0;

  void _go(BuildContext context, int i) {
    if (i == currentIndex) return;
    HapticFeedback.selectionClick();
    context.go(_items[i].route);
  }

  @override
  Widget build(BuildContext context) {
    // Transparent floating row: this widget lives in
    // Scaffold.bottomNavigationBar of an AppShell (extendBody: true), so
    // the page extends behind it. Only the circles paint anything —
    // the surrounding SafeArea + Padding stay fully transparent.
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 16, left: 16, right: 16),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            for (var i = 0; i < _items.length; i++) ...[
              if (i > 0) const SizedBox(width: 8),
              _CircleButton(
                item: _items[i],
                active: i == currentIndex,
                onTap: () => _go(context, i),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// A single independent circular navigation button.
class _CircleButton extends StatelessWidget {
  final NavItemData item;
  final bool active;
  final VoidCallback onTap;

  const _CircleButton({
    required this.item,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: active,
      label: item.label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
          width: CustomBottomNav.diameter,
          height: CustomBottomNav.diameter,
          decoration: BoxDecoration(
            color: active ? AppColors.cta : AppColors.surface,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.3),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Center(
            child: item.outlineAsset.isNotEmpty
                ? SvgPicture.asset(
                    active ? item.filledAsset : item.outlineAsset,
                    width: CustomBottomNav._iconSize,
                    height: CustomBottomNav._iconSize,
                    colorFilter: ColorFilter.mode(
                      active ? AppColors.onCta : AppColors.textSecondary,
                      BlendMode.srcIn,
                    ),
                  )
                : Icon(
                    active ? Icons.groups_rounded : (item.icon ?? Icons.groups_outlined),
                    size: CustomBottomNav._iconSize,
                    color: active ? AppColors.onCta : AppColors.textSecondary,
                  ),
          ),
        ),
      ),
    );
  }
}
