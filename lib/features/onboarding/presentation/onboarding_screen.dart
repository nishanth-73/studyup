import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/ui_kit.dart';
import '../../avatar/presentation/user_profile_controller.dart';
import '../../svg_art/presentation/svg_art.dart';

/// First-launch intro: exactly three animated SVG slides with
/// Skip / Previous / Next / Get Started. Finishing (Skip or Get Started)
/// persists `slidesSeen` and moves to avatar + name setup. Swipe also
/// works; the system back button steps back a slide when past the first.
class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});
  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _SlideData {
  final String asset;
  final String title;
  final String description;
  const _SlideData({
    required this.asset,
    required this.title,
    required this.description,
  });
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final _page = PageController();
  int _index = 0;
  bool _leaving = false;

  static const _slides = [
    _SlideData(
      asset: 'assets/images/onboarding_1.svg',
      title: 'Track Your Progress',
      description: "Track your study time and daily goals to see how consistently you're learning.",
    ),
    _SlideData(
      asset: 'assets/images/onboarding_2.svg',
      title: 'Compare Day by Day',
      description: 'Compare your study progress across days and discover your study patterns.',
    ),
    _SlideData(
      asset: 'assets/images/onboarding_3.svg',
      title: 'Study Well, Every Day',
      description: 'Build a daily study habit and keep your learning on track.',
    ),
  ];

  @override
  void dispose() {
    _page.dispose();
    super.dispose();
  }

  void _goTo(int page) {
    HapticFeedback.selectionClick();
    setState(() => _index = page);
    _page.animateToPage(
      page,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
    );
  }

  Future<void> _finish() async {
    if (_leaving) return;
    setState(() => _leaving = true);
    HapticFeedback.selectionClick();
    try {
      await ref.read(userProfileProvider.notifier).markSlidesSeen();
      if (mounted) context.go('/setup-profile');
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not save onboarding: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _leaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final last = _index == _slides.length - 1;
    return PopScope(
      // Past the first slide, system back steps back a slide instead of
      // leaving the funnel.
      canPop: _index == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _index > 0) _goTo(_index - 1);
      },
      child: Scaffold(
        backgroundColor: AppColors.background,
        body: SafeArea(
          child: Column(
            children: [
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: _leaving ? null : _finish,
                  child: Text(
                    'Skip',
                    style: AppTextStyles.body14Bold.copyWith(
                      color: AppColors.cta,
                    ),
                  ),
                ),
              ),
              Expanded(
                child: PageView.builder(
                  controller: _page,
                  itemCount: _slides.length,
                  onPageChanged: (i) => setState(() => _index = i),
                  itemBuilder: (_, i) => _Slide(data: _slides[i]),
                ),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(
                  _slides.length,
                  (i) => Container(
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    width: i == _index ? 22 : 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: i == _index ? AppColors.cta : AppColors.track,
                      borderRadius: BorderRadius.circular(100),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Row(
                  children: [
                    _NavCircle(
                      icon: Icons.arrow_back_rounded,
                      label: 'Previous slide',
                      enabled: _index > 0 && !_leaving,
                      onTap: () => _goTo(_index - 1),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: last
                          ? PrimaryButton(
                              label: 'Get Started',
                              icon: const Icon(Icons.arrow_forward, size: 18),
                              onPressed: _leaving ? null : _finish,
                            )
                          : Align(
                              alignment: Alignment.centerRight,
                              child: _NavCircle(
                                icon: Icons.arrow_forward_rounded,
                                label: 'Next slide',
                                enabled: !_leaving,
                                accent: true,
                                onTap: () => _goTo(_index + 1),
                              ),
                            ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }
}

/// One slide: animated illustration centered, title + description below.
/// Scrolls internally on small screens so nothing overlaps the controls.
class _Slide extends StatelessWidget {
  final _SlideData data;
  const _Slide({required this.data});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final artSide = constraints.maxWidth < 340
            ? constraints.maxWidth * 0.72
            : 280.0;
        return SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 28),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox(
                    width: artSide,
                    height: artSide,
                    child: SvgArt(asset: data.asset),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    data.title,
                    style: AppTextStyles.title26,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 10),
                  Text(
                    data.description,
                    style: AppTextStyles.body16.copyWith(
                      color: AppColors.textSecondary,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// A standalone round icon button — never inside a shared pill.
/// Disabled state mutes the icon and ignores taps.
class _NavCircle extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool enabled;
  final bool accent;
  final VoidCallback onTap;
  const _NavCircle({
    required this.icon,
    required this.label,
    required this.enabled,
    required this.onTap,
    this.accent = false,
  });

  @override
  Widget build(BuildContext context) {
    final background = !enabled
        ? AppColors.surface
        : accent
        ? AppColors.cta
        : AppColors.surface;
    final foreground = !enabled
        ? AppColors.textMuted
        : accent
        ? AppColors.onCta
        : AppColors.textPrimary;
    return Semantics(
      button: true,
      label: label,
      child: Material(
        color: background,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: enabled
              ? () {
                  SystemSound.play(SystemSoundType.click);
                  onTap();
                }
              : null,
          child: SizedBox(
            width: 56,
            height: 56,
            child: Icon(icon, size: 24, color: foreground),
          ),
        ),
      ),
    );
  }
}
