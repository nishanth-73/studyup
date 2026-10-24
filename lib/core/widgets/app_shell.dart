import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import 'bottom_nav.dart';

/// App-wide page shell: ONE floating bottom navigation shared by every
/// main-app tab screen (Home, Subjects, Progress).
/// Profile is a pushed standalone page without the floating nav.
///
/// How the reference floating behavior works:
/// - [Scaffold.extendBody] is true, so the body extends behind the
///   navigation instead of being squeezed above an opaque bar.
/// - [CustomBottomNav] paints only the three circular buttons; the area
///   around them is fully transparent, so page content shows behind and
///   around the controls while scrolling.
/// - The navigation owns the bottom system inset itself (its own
///   SafeArea), so screen bodies use `SafeArea(bottom: false)` and only
///   add [scrollClearance] at the end of scrollable content. That keeps
///   the final item/button/card reachable above the buttons without
///   giant arbitrary padding.
///
/// Future main-app screens: return `AppShell(currentIndex: ...,
/// body: ...)` instead of building a Scaffold + bottomNavigationBar.
/// Do NOT use this shell for onboarding, login, avatar/goal setup,
/// dialogs, sheets, or detail screens pushed on top.
class AppShell extends StatelessWidget {
  /// Index into the nav destinations (0 home, 1 subjects, 2 progress, 3 community).
  /// Screens without their own destination keep the closest highlight
  /// (e.g. Plan highlights Home).
  final int currentIndex;

  /// Screen content. Must not include its own bottom navigation.
  /// Scrollable bodies end with `SizedBox(height:
  /// AppShell.scrollClearance(context))` instead of a magic number.
  final Widget body;

  final Color backgroundColor;

  const AppShell({
    super.key,
    required this.currentIndex,
    required this.body,
    this.backgroundColor = AppColors.background,
  });

  /// Diameter of one navigation circle. Mirrors [CustomBottomNav.diameter].
  static const double navButtonDiameter = CustomBottomNav.diameter;

  /// Gap between the buttons and the content / screen bottom.
  static const double navEdgeGap = 16;

  /// Bottom scroll clearance so the last item can scroll fully above
  /// the floating buttons: gap + buttons + offset + system inset.
  /// Derived from the real nav metrics — never a magic constant.
  static double scrollClearance(BuildContext context) {
    return MediaQuery.paddingOf(context).bottom +
        navEdgeGap +
        navButtonDiameter +
        navEdgeGap;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: backgroundColor,
      extendBody: true,
      body: body,
      bottomNavigationBar: CustomBottomNav(currentIndex: currentIndex),
    );
  }
}
