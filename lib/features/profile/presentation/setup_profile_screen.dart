import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/ui_kit.dart';
import '../../avatar/data/user_profile.dart';
import '../../avatar/presentation/avatar_widgets.dart';
import '../../avatar/presentation/user_profile_controller.dart';

/// First-launch personalization: choose a PNG avatar portrait and
/// enter a display name. Persists via the existing profile storage and
/// continues to daily-goal selection. Shown once — never again after
/// setup completes.
class SetupProfileScreen extends ConsumerStatefulWidget {
  const SetupProfileScreen({super.key});
  @override
  ConsumerState<SetupProfileScreen> createState() => _SetupProfileScreenState();
}

class _SetupProfileScreenState extends ConsumerState<SetupProfileScreen> {
  final _name = TextEditingController();
  late String _avatarId;
  String? _error;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final existing = ref.read(userProfileProvider).valueOrNull;
    if (existing != null) {
      if (existing.displayName.trim().isNotEmpty) {
        _name.text = existing.displayName;
      }
      _avatarId = isValidAvatarId(existing.avatarId)
          ? existing.avatarId
          : defaultAvatarId;
    } else {
      _avatarId = defaultAvatarId;
    }
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _continue() async {
    if (_saving) return;
    FocusScope.of(context).unfocus();
    if (_name.text.trim().isEmpty) {
      HapticFeedback.selectionClick();
      setState(() => _error = 'Please enter your name to continue.');
      return;
    }
    setState(() {
      _error = null;
      _saving = true;
    });
    try {
      final existing = ref.read(userProfileProvider).valueOrNull;
      // The chosen PNG portrait persists in the profile record itself, so
      // the same avatar renders on Home and Profile. The legacy
      // blobVariant slot is carried over untouched so stored profiles
      // keep their data.
      await ref
          .read(userProfileProvider.notifier)
          .saveSetupProgress(
            blobVariant: existing?.blobVariant ?? defaultBlobVariant,
            displayName: _name.text,
            avatarId: _avatarId,
          );
      if (mounted) context.go('/setup-goal');
    } catch (error) {
      if (mounted) {
        setState(() => _error = 'Could not save your profile: $error');
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  return SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(24, 12, 24, 12),
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        minHeight: constraints.maxHeight - 24,
                      ),
                      child: SizedBox(
                        width: double.infinity,
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 480),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Text(
                                    'Make it yours',
                                    style: AppTextStyles.title30,
                                    textAlign: TextAlign.center,
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    'Choose your avatar and tell us what to call you.',
                                    style: AppTextStyles.secondary14,
                                    textAlign: TextAlign.center,
                                  ),
                                  const SizedBox(height: 20),
                                  Text(
                                    'Pick your avatar',
                                    style: AppTextStyles.caption13,
                                    textAlign: TextAlign.center,
                                  ),
                                  const SizedBox(height: 10),
                                  AvatarPickerGrid(
                                    selectedId: _avatarId,
                                    onSelected: (id) =>
                                        setState(() => _avatarId = id),
                                  ),
                                  const SizedBox(height: 20),
                                  AppTextField(
                                    controller: _name,
                                    label: 'Your name',
                                    hintText: 'Enter your name',
                                    textInputAction: TextInputAction.done,
                                    textCapitalization:
                                        TextCapitalization.words,
                                    onSubmitted: (_) => _continue(),
                                    errorText: _error,
                                    onChanged: (_) {
                                      if (_error != null) {
                                        setState(() => _error = null);
                                      }
                                    },
                                  ),
                                  const SizedBox(height: 8),
                                ],
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
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 480),
                child: PrimaryButton(
                  label: 'Continue',
                  icon: _saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: AppColors.onCta,
                          ),
                        )
                      : const Icon(Icons.arrow_forward, size: 18),
                  onPressed: _saving ? null : _continue,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
