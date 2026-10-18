import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/deeplink/invite_links.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/ui_kit.dart';
import '../../avatar/presentation/user_profile_controller.dart';
import '../../progress/presentation/study_progress_controller.dart';
import '../../social/data/session_sync.dart';
import '../../social/data/social_remote.dart';
import '../data/auth_controller.dart';
import '../data/auth_repository.dart';

/// Login / Sign Up screen shown after setup on first launch (and whenever
/// access lapses). Card structure mirrors the shadcn CardDemo
/// reference; styling is StudyUp dark theme.
///
/// Two modes, chosen automatically:
/// - Backend connected: real Supabase email/password auth with email
///   verification, password reset, and session persistence. On success
///   the local profile links to the account and local study history
///   syncs (nothing local is deleted).
/// - Backend missing: explicit offline demo access via
///   [UserProfileController.demoSignIn] (no remote account, password
///   never stored). The banner says so — never faked as real auth.
class AuthScreen extends ConsumerStatefulWidget {
  const AuthScreen({super.key});

  /// Clears the "continue without account" choice (used on sign-out).
  static Future<void> clearOfflineMode() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_offlineKey);
  }

  static const _offlineKey = 'studyup.offlineMode.v1';

  @override
  ConsumerState<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends ConsumerState<AuthScreen> {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _signup = false;
  bool _obscure = true;
  bool _busy = false;
  String? _notice; // verification / info banner

  static final _emailPattern = RegExp(r'^[^@\s]+[^@\s]*@[^@\s]+\.[^@\s]+$');

  @override
  void dispose() {
    _email.dispose();
    // Never retain the password longer than this screen lives.
    _password.dispose();
    super.dispose();
  }

  void _say(String message) {
    HapticFeedback.selectionClick();
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  void _switchMode() {
    HapticFeedback.selectionClick();
    setState(() {
      _signup = !_signup;
      _notice = null;
    });
  }

  AuthRepository? get _repo => ref.read(authRepositoryProvider);

  Future<void> _submit() async {
    if (_busy) return;
    FocusScope.of(context).unfocus();
    if (!(_form.currentState?.validate() ?? false)) return;
    setState(() => _busy = true);
    try {
      final repo = _repo;
      if (repo == null) {
        await _demoAccess();
        return;
      }
      final result = _signup
          ? await repo.signUp(email: _email.text, password: _password.text)
          : await repo.signIn(email: _email.text, password: _password.text);
      if (!mounted) return;
      if (result.needsVerification) {
        setState(() {
          _notice =
              'Check your inbox to verify ${_email.text.trim()}, then log in. Didn\u2019t get it? Use Resend below.';
        });
        return;
      }
      if (!result.isOk) {
        _say(result.error!);
        return;
      }
      await _afterAuth(email: _email.text);
    } catch (error) {
      if (mounted) _say('Could not sign in: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Local demo access (offline / backend missing). Records only the
  /// email identifier; the password is never persisted.
  Future<void> _demoAccess() async {
    await Future<void>.delayed(const Duration(milliseconds: 400));
    var profile = ref.read(userProfileProvider);
    for (var i = 0; i < 100 && profile.isLoading; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
      if (!mounted) return;
      profile = ref.read(userProfileProvider);
    }
    try {
      await ref
          .read(userProfileProvider.notifier)
          .demoSignIn(email: _email.text);
    } catch (error) {
      if (mounted) _say('Could not sign in locally: $error');
      return;
    }
    if (mounted) context.go('/home');
  }

  /// Post-auth linking: attach the local profile to the account, sync
  /// local history (idempotent, nothing deleted), then resume a pending
  /// invitation if one is waiting.
  Future<void> _afterAuth({required String email}) async {
    final repo = _repo;
    final local = ref.read(userProfileProvider).valueOrNull;
    if (repo != null && local != null) {
      try {
        await repo.ensureProfileRow(
          displayName: local.displayName,
          avatarId: local.avatarId,
          blobVariant: local.blobVariant,
        );
      } catch (_) {}
      try {
        final sessions = ref.read(studyProgressProvider).sessions;
        await SessionSyncService(SocialRemote(repo.client)).syncAll(sessions);
      } catch (_) {}
    }
    try {
      await ref.read(userProfileProvider.notifier).demoSignIn(email: email);
    } catch (_) {}
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(AuthScreen._offlineKey);
    final pending = await InviteLinks.takePending();
    if (!mounted) return;
    if (pending != null && pending.isNotEmpty) {
      context.go('/invite/${Uri.encodeComponent(pending)}');
    } else {
      context.go('/home');
    }
  }

  Future<void> _forgotPassword() async {
    final repo = _repo;
    if (repo == null) {
      _say('Password recovery needs the connected backend.');
      return;
    }
    if (!_emailPattern.hasMatch(_email.text.trim())) {
      _say('Enter your account email first.');
      return;
    }
    setState(() => _busy = true);
    try {
      final error = await repo.sendPasswordReset(email: _email.text);
      if (!mounted) return;
      _say(error ?? 'Reset link sent — check your inbox (and spam folder).');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _resendVerification() async {
    final repo = _repo;
    if (repo == null) return;
    setState(() => _busy = true);
    try {
      final error = await repo.resendVerification(email: _email.text);
      if (!mounted) return;
      _say(error ?? 'Verification email re-sent.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _continueOffline() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(AuthScreen._offlineKey, true);
    if (!mounted) return;
    // Offline keeps every local feature; social shows a setup banner.
    context.go('/home');
  }

  /// Google OAuth: launches the system browser; Supabase redirects to
  /// the native auth callback and supabase_flutter completes sign-in
  /// automatically. Success is observed via auth state, which routes
  /// home (plus profile link + pending-invite resume) from there.
  Future<void> _googleSignIn() async {
    final repo = _repo;
    if (repo == null || _busy) return;
    setState(() => _busy = true);
    try {
      final error = await repo.signInWithGoogle();
      if (!mounted) return;
      if (error != null) _say(error);
      // Null error = browser launched; stay on this screen until the
      // auth callback arrives (or the user returns manually).
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  InputDecoration _field(String hint, {Widget? suffix}) {
    return InputDecoration(
      hintText: hint,
      hintStyle: AppTextStyles.body14.copyWith(color: AppColors.textMuted),
      filled: true,
      fillColor: AppColors.surface2,
      suffixIcon: suffix,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: const OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(14)),
        borderSide: BorderSide.none,
      ),
      errorStyle: AppTextStyles.caption12.copyWith(color: AppColors.error),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Instantiate the profile early so it is loaded by submit time.
    ref.watch(userProfileProvider);
    final backendLive = ref.watch(backendLiveProvider);
    final title = _signup ? 'Sign Up' : 'Login';
    final action = _signup ? 'Sign Up' : 'Login';
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(
              24,
              12,
              24,
              16 + MediaQuery.viewInsetsOf(context).bottom,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Form(
                    key: _form,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(title, style: AppTextStyles.title26),
                        const SizedBox(height: 6),
                        Text(
                          _signup
                              ? 'Create your StudyUp account.'
                              : 'Welcome back. Log in to continue studying.',
                          style: AppTextStyles.secondary14,
                        ),
                        if (!backendLive) ...[
                          const SizedBox(height: 10),
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: AppColors.surface2,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              'Backend not connected — demo access only. No account is created.',
                              style: AppTextStyles.caption12,
                            ),
                          ),
                        ],
                        if (_notice != null) ...[
                          const SizedBox(height: 10),
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: AppColors.cta.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              _notice!,
                              style: AppTextStyles.caption12,
                            ),
                          ),
                        ],
                        const SizedBox(height: 18),
                        Text('Email', style: AppTextStyles.caption13),
                        const SizedBox(height: 6),
                        TextFormField(
                          controller: _email,
                          keyboardType: TextInputType.emailAddress,
                          autocorrect: false,
                          enableSuggestions: false,
                          textInputAction: TextInputAction.next,
                          style: AppTextStyles.body14,
                          decoration: _field('you@example.com'),
                          validator: (value) {
                            if (value == null ||
                                !_emailPattern.hasMatch(value.trim())) {
                              return 'Enter a valid email address.';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 14),
                        Text('Password', style: AppTextStyles.caption13),
                        const SizedBox(height: 6),
                        TextFormField(
                          controller: _password,
                          obscureText: _obscure,
                          enableSuggestions: false,
                          autocorrect: false,
                          textInputAction: TextInputAction.done,
                          onFieldSubmitted: (_) => _submit(),
                          style: AppTextStyles.body14,
                          decoration: _field(
                            backendLive ? '6+ characters' : 'Your password',
                            suffix: IconButton(
                              tooltip: _obscure
                                  ? 'Show password'
                                  : 'Hide password',
                              onPressed: () =>
                                  setState(() => _obscure = !_obscure),
                              icon: Icon(
                                _obscure
                                    ? Icons.visibility_outlined
                                    : Icons.visibility_off_outlined,
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ),
                          validator: (value) {
                            if (value == null || value.isEmpty) {
                              return 'Enter your password.';
                            }
                            if (backendLive && value.length < 6) {
                              return 'Use at least 6 characters.';
                            }
                            return null;
                          },
                        ),
                        if (!_signup) ...[
                          const SizedBox(height: 4),
                          Align(
                            alignment: Alignment.centerRight,
                            child: TextButton(
                              onPressed: _busy ? null : _forgotPassword,
                              child: Text(
                                'Forgot Password?',
                                style: AppTextStyles.caption13.copyWith(
                                  color: AppColors.cta,
                                ),
                              ),
                            ),
                          ),
                        ],
                        const SizedBox(height: 10),
                        PrimaryButton(
                          label: action,
                          onPressed: _busy ? null : _submit,
                          icon: _busy
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: AppColors.onCta,
                                  ),
                                )
                              : const Icon(Icons.arrow_forward, size: 18),
                        ),
                        if (_notice != null && backendLive) ...[
                          const SizedBox(height: 8),
                          TextButton(
                            onPressed: _busy ? null : _resendVerification,
                            child: Text(
                              'Resend verification email',
                              style: AppTextStyles.body14Bold.copyWith(
                                color: AppColors.cta,
                              ),
                            ),
                          ),
                        ],
                        if (backendLive) ...[
                          const SizedBox(height: 12),
                          SizedBox(
                            width: double.infinity,
                            height: 56,
                            child: OutlinedButton(
                              onPressed: _busy ? null : _googleSignIn,
                              style: OutlinedButton.styleFrom(
                                foregroundColor: AppColors.textPrimary,
                                side: const BorderSide(color: AppColors.track),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(26),
                                ),
                              ),
                              child: _busy
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : Text(
                                      'Continue with Google',
                                      style: AppTextStyles.body16Bold,
                                    ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          TextButton(
                            onPressed: _busy ? null : _continueOffline,
                            child: Text(
                              'Continue without an account (offline)',
                              style: AppTextStyles.body14.copyWith(
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ),
                        ] else ...[
                          const SizedBox(height: 12),
                          SizedBox(
                            width: double.infinity,
                            height: 56,
                            child: OutlinedButton(
                              onPressed: () => _say(
                                'Google sign-in will be available later.',
                              ),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: AppColors.textPrimary,
                                side: const BorderSide(color: AppColors.track),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(26),
                                ),
                              ),
                              child: Text(
                                'Continue with Google',
                                style: AppTextStyles.body16Bold,
                              ),
                            ),
                          ),
                        ],
                        const SizedBox(height: 8),
                        TextButton(
                          onPressed: _busy ? null : _switchMode,
                          child: Text(
                            _signup
                                ? 'Already have an account? Log in'
                                : "Don't have an account? Sign up",
                            style: AppTextStyles.body14Bold.copyWith(
                              color: AppColors.cta,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
