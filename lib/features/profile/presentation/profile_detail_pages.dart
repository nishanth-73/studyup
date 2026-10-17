import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:app_settings/app_settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/notifications/notification_prefs.dart';
import '../../../core/notifications/notification_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/app_shell.dart';
import '../../../core/widgets/ui_kit.dart';
import '../../avatar/presentation/user_profile_controller.dart';
import '../../auth/data/auth_controller.dart';
import '../../auth/presentation/auth_screen.dart';
import '../../community/presentation/community_controller.dart';
import '../../home/presentation/home_controller.dart';
import '../../profile/data/feedback_service.dart';
import '../../profile/data/feedback_submitter.dart';
import 'help_guide.dart';
import '../../progress/presentation/study_progress_controller.dart';
import '../../robo/robo_customize.dart';
import '../../robo/robo_shape.dart';
import '../../social/data/social_providers.dart';
import '../../subjects/presentation/subjects_controller.dart';

/// Shared detail-page frame: dark theme, back button that pops to the
/// previous page, no bottom nav (these are pushed sub-pages).
class DetailScaffold extends StatelessWidget {
  final String title;
  final List<Widget> children;
  const DetailScaffold({
    super.key,
    required this.title,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
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
                      context.pop();
                    },
                    child: const Padding(
                      padding: EdgeInsets.all(10),
                      child: Icon(
                        Icons.arrow_back_rounded,
                        size: 20,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    title,
                    style: AppTextStyles.section18,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            ...children,
            SizedBox(height: AppShell.scrollClearance(context)),
          ],
        ),
      ),
    );
  }
}

/// Reusable settings row card used by the detail pages.
class DetailCard extends StatelessWidget {
  final Widget child;
  const DetailCard({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
      ),
      child: child,
    );
  }
}

/// Tappable settings row (icon + title + subtitle + chevron).
class DetailRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback onTap;
  const DetailRow({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return DetailCard(
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () {
            SystemSound.play(SystemSoundType.click);
            HapticFeedback.selectionClick();
            onTap();
          },
          child: Row(
            children: [
              Icon(icon, color: Colors.white, size: 20),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: AppTextStyles.body14),
                    if (subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(subtitle!, style: AppTextStyles.caption12),
                    ],
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: AppColors.textSecondary),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------- NOTIFICATIONS ----------------

/// Dedicated Notifications settings page. Same switches, persistence,
/// and system-permission handling as the previous inline card.
class NotificationsPage extends ConsumerWidget {
  const NotificationsPage({super.key});

  Future<void> _applyTaskToggle(WidgetRef ref, bool value) async {
    HapticFeedback.selectionClick();
    await ref.read(notificationPrefsProvider.notifier).setTaskReminders(value);
    if (value) {
      // Re-enabled: reschedule every valid upcoming reminder from the
      // existing saved task data.
      await ref.read(homeControllerProvider.notifier).rescheduleAllReminders();
    } else {
      // Disabled: cancel pending task reminders immediately without
      // touching the goal alert. The id-based cancel
      // covers loaded tasks; the scheduled-clear covers reminders from a
      // previous run when the list hasn't loaded yet (task reminders are
      // the only type this app ever schedules).
      final ids = ref.read(homeControllerProvider).allTasks.map((t) => t.id);
      await NotificationService.instance.cancelAllTaskReminders(ids);
      await NotificationService.instance.cancelAllScheduled();
      await NotificationService.instance.clearCenterTaskItems();
    }
    ref.invalidate(systemNotificationStatusProvider);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final prefs = ref.watch(notificationPrefsProvider);
    final systemStatus = ref.watch(systemNotificationStatusProvider);
    final systemEnabled = systemStatus.valueOrNull;

    Widget switchRow({
      required String title,
      required String sub,
      required bool value,
      required ValueChanged<bool> onChanged,
    }) {
      return Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: AppTextStyles.body14),
                const SizedBox(height: 2),
                Text(sub, style: AppTextStyles.caption12),
              ],
            ),
          ),
          Switch(
            value: value,
            activeThumbColor: AppColors.cta,
            onChanged: prefs.loaded ? onChanged : null,
          ),
        ],
      );
    }

    return DetailScaffold(
      title: 'Notifications',
      children: [
        DetailCard(
          child: Column(
            children: [
              switchRow(
                title: 'Task reminders',
                sub: '5 minutes before scheduled tasks',
                value: prefs.taskReminders,
                onChanged: (v) => _applyTaskToggle(ref, v),
              ),
              const Divider(color: AppColors.track, height: 20),
              switchRow(
                title: 'Live progress',
                sub: 'Ongoing timer while you study',
                value: prefs.liveProgress,
                onChanged: (v) {
                  HapticFeedback.selectionClick();
                  ref
                      .read(notificationPrefsProvider.notifier)
                      .setLiveProgress(v);
                },
              ),
              const Divider(color: AppColors.track, height: 20),
              switchRow(
                title: 'Daily goal reached',
                sub: 'Once per day when the goal is met',
                value: prefs.goalReached,
                onChanged: (v) {
                  HapticFeedback.selectionClick();
                  ref
                      .read(notificationPrefsProvider.notifier)
                      .setGoalReached(v);
                },
              ),
            ],
          ),
        ),
        DetailCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(
                    Icons.notifications_outlined,
                    size: 18,
                    color: AppColors.textSecondary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      systemStatus.isLoading
                          ? 'Checking system permission…'
                          : systemEnabled == true
                          ? 'System notifications: on'
                          : systemEnabled == false
                          ? 'System notifications: off'
                          : 'System notifications: unknown',
                      style: AppTextStyles.caption12,
                    ),
                  ),
                  if (systemEnabled == false)
                    TextButton(
                      onPressed: () {
                        HapticFeedback.selectionClick();
                        AppSettings.openAppSettings(
                          type: AppSettingsType.notification,
                        );
                      },
                      child: Text(
                        'Open settings',
                        style: AppTextStyles.body14Bold.copyWith(
                          color: AppColors.cta,
                        ),
                      ),
                    )
                  else
                    IconButton(
                      tooltip: 'Notification settings',
                      onPressed: () {
                        HapticFeedback.selectionClick();
                        AppSettings.openAppSettings(
                          type: AppSettingsType.notification,
                        );
                      },
                      icon: const Icon(
                        Icons.settings_outlined,
                        size: 18,
                        color: AppColors.textSecondary,
                      ),
                    ),
                ],
              ),
              if (systemEnabled == false)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    'System permission is off, so these switches cannot show '
                    'notifications until you enable them in system settings.',
                    style: AppTextStyles.caption12,
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

// ---------------- PRIVACY & DATA ----------------

/// Privacy & Data page: what is stored locally vs on Supabase, plus the
/// real actions this app supports (sign-out / exit demo, erase all local
/// data). Every destructive action confirms first and reports honestly.
class PrivacyDataPage extends ConsumerStatefulWidget {
  const PrivacyDataPage({super.key});

  @override
  ConsumerState<PrivacyDataPage> createState() => _PrivacyDataPageState();
}

class _PrivacyDataPageState extends ConsumerState<PrivacyDataPage> {
  bool _busy = false;

  void _say(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<bool> _confirm(String title, String body, String action) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(title, style: AppTextStyles.section18),
        content: Text(body, style: AppTextStyles.secondary14),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(
              'Cancel',
              style: AppTextStyles.body14Bold.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              action,
              style: AppTextStyles.body14Bold.copyWith(color: AppColors.cta),
            ),
          ),
        ],
      ),
    );
    return ok == true;
  }

  Future<void> _signOut() async {
    final profile = ref.read(userProfileProvider).valueOrNull;
    if (profile == null) {
      _say('No profile is signed in on this device.');
      return;
    }
    final backendLive = ref.read(backendLiveProvider);
    final signedIn = ref.read(backendUserIdProvider) != null;
    final ok = await _confirm(
      signedIn ? 'Sign out?' : 'End demo access?',
      signedIn
          ? 'This signs you out on this device only. Everything stored on '
              'this phone stays saved here, and your Supabase account (with '
              'anything already synced to it) is untouched. Sign in again '
              'anytime to reconnect.'
          : backendLive
          ? 'Demo access on this device will be removed. Everything stored '
              'on this phone stays saved here. Sign in with an account, or '
              'start a new demo, anytime.'
          : 'Demo access on this device will be removed. Everything stored '
              'on this phone stays saved here. Nothing was ever uploaded, '
              'so there is nothing to delete anywhere else.',
      signedIn ? 'Sign out' : 'End demo',
    );
    if (!ok || !mounted) return;
    setState(() => _busy = true);
    try {
      if (backendLive) {
        try {
          await ref.read(authRepositoryProvider)?.signOut();
        } catch (_) {}
        await AuthScreen.clearOfflineMode();
        await clearPostSignInLink();
      }
      await ref.read(userProfileProvider.notifier).demoSignOut();
      if (mounted) context.go('/auth');
    } catch (error) {
      _say('Could not sign out: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Deletes the app-owned downloads folder (PDFs/images attached to
  /// subjects). Throws with context; callers abort the erase when this
  /// fails so a partial wipe is never reported as success.
  Future<void> _deleteDownloadedAttachments() async {
    Directory sources;
    try {
      final dir = await getApplicationDocumentsDirectory();
      sources = Directory('${dir.path}/sources');
    } catch (error) {
      throw StateError('Could not locate local storage ($error).');
    }
    try {
      if (await sources.exists()) {
        await sources.delete(recursive: true);
      }
    } catch (error) {
      throw StateError('Could not delete downloaded files ($error).');
    }
  }

  /// Resets in-memory state after storage is wiped so no stale rows,
  /// counts, or badges survive the erase. Controllers re-load (empty)
  /// from storage on rebuild; the notification badge is recounted too.
  void _resetInMemoryState() {
    ref.invalidate(userProfileProvider);
    ref.invalidate(homeControllerProvider);
    ref.invalidate(subjectsProvider);
    ref.invalidate(studyProgressProvider);
    ref.invalidate(notificationPrefsProvider);
    ref.invalidate(communityControllerProvider);
    ref.invalidate(communityStoreProvider);
    ref.invalidate(syncStatusProvider);
    ref.invalidate(roboShellColorProvider);
    ref.invalidate(roboShapeProvider);
    unawaited(NotificationService.instance.reloadUnreadCount());
  }

  Future<void> _eraseAll() async {
    final ok = await _confirm(
      'Erase all local data?',
      'This permanently deletes on this device only: your profile, '
      'subjects with chapters, topics and attached files (downloaded '
      'PDFs and images included), tasks, study sessions, daily goal, '
      'notification settings and history, quiz best scores, community '
      'friends and invitations, synced-session markers, feedback drafts '
      'and sent log, and app settings.\n\n'
      'It does NOT delete your Supabase account or anything already '
      'synced to it — those stay on the server. It DOES clear the saved '
      'sign-in on this device, so you will need to sign in again '
      'afterwards.\n\n'
      'Temporary image caches managed by Android are left for the system '
      'to clean. This cannot be undone.',
      'Erase everything',
    );
    if (!ok || !mounted) return;
    setState(() => _busy = true);
    try {
      // 1. Cancel OS-side effects first (scheduled reminders, live timer).
      try {
        await NotificationService.instance.cancelAllScheduled();
      } catch (_) {}
      try {
        await NotificationService.instance.cancelLiveTimer();
      } catch (_) {}
      // 2. Delete downloaded attachments (abort before touching prefs if
      // this fails, so success is never claimed after a partial wipe).
      await _deleteDownloadedAttachments();
      // 3. Wipe local storage (SharedPreferences holds every record type
      // listed above, plus the saved Supabase session).
      final prefs = await SharedPreferences.getInstance();
      final cleared = await prefs.clear();
      if (!cleared) throw StateError('Device storage refused the erase.');
      // 4. Reset in-memory state so the UI rebuilds empty immediately.
      _resetInMemoryState();
      _say('All local data erased.');
      await Future<void>.delayed(const Duration(milliseconds: 900));
      if (mounted) context.go('/');
    } catch (error) {
      _say('Could not erase data: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(userProfileProvider).valueOrNull;
    final subjects = ref
        .watch(subjectsProvider)
        .where((s) => !s.archived)
        .length;
    final tasks = ref.watch(homeControllerProvider).allTasks.length;
    final progress = ref.watch(studyProgressProvider);
    final backendOn = ref.watch(backendLiveProvider);
    final signedIn = ref.watch(backendUserIdProvider) != null;
    final email = ref.watch(backendUserEmailProvider);

    Widget stat(String label, String value) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          children: [
            Expanded(child: Text(label, style: AppTextStyles.body14)),
            Text(value, style: AppTextStyles.body14Bold),
          ],
        ),
      );
    }

    Widget docLine(String text) {
      return Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Text(text, style: AppTextStyles.caption12),
      );
    }

    return DetailScaffold(
      title: 'Privacy & Data',
      children: [
        DetailCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Your account', style: AppTextStyles.body14Bold),
              const SizedBox(height: 4),
              if (signedIn)
                Text(
                  'Signed in${email != null && email.isNotEmpty ? ' as $email' : ''}. '
                  'Only you can read and change your synced records; friends '
                  'see just your display name, avatar style, and leaderboard '
                  'totals you opted to share.',
                  style: AppTextStyles.caption12,
                )
              else if (backendOn)
                Text(
                  'Running offline or in demo mode: everything below stays '
                  'on this phone and nothing is uploaded until you sign in.',
                  style: AppTextStyles.caption12,
                )
              else
                Text(
                  'Demo access, no account here: everything below stays on '
                  'this phone and nothing is ever uploaded.',
                  style: AppTextStyles.caption12,
                ),
            ],
          ),
        ),
        DetailCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Your stored data', style: AppTextStyles.body14Bold),
              stat('Profile', profile == null ? 'not set up' : 'set up'),
              stat('Subjects', '$subjects'),
              stat('Tasks', '$tasks'),
              stat('Study sessions', '${progress.sessions.length}'),
              stat('Daily goal', '${progress.dailyStudyGoalMinutes}m'),
              docLine(
                'On this device only, kept as plain app data (not '
                'encrypted): your profile and avatar choice, subjects with '
                'chapters, topics and attached files (downloaded PDFs and '
                'images live in the app\u2019s private files folder), tasks '
                'with schedules, study sessions, the daily goal, '
                'notification switches and history, quiz best scores, '
                'community friends and invitations, synced-session markers, '
                'feedback drafts and sent log, and app settings.',
              ),
              docLine(
                signedIn || backendOn
                    ? 'On Supabase while signed in: your community profile '
                        '(display name, avatar style, leaderboard and sharing '
                        'flags), friend requests and friendships, single-use '
                        'invitation tokens (hash only), and ended study '
                        'sessions with per-day totals. Row-level security '
                        'means only you can read or change your rows; '
                        'friends see only shared totals.'
                    : 'Nothing is sent to any server in this mode: there is '
                        'no account here, and exiting demo only ends demo '
                        'access on this phone.',
              ),
              docLine(
                'What syncs: ended study sessions upload (each has a stable '
                'id, so retries never duplicate it) and your community '
                'profile mirrors the sharing toggles. Everything else stays '
                'on this device. Signing out clears only the saved sign-in '
                '— local records stay saved here. Erasing deletes local '
                'copies (including of synced items) but never your Supabase '
                'account or server records.',
              ),
            ],
          ),
        ),
        DetailCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Your rights & choices', style: AppTextStyles.body14Bold),
              docLine(
                'Access & portability: your records are visible in the app — '
                'request a copy of them via Profile → Feedback.',
              ),
              docLine(
                'Correction: edit or delete subjects, tasks, profile and '
                'sessions directly in the app.',
              ),
              docLine(
                'Deletion: “Erase all local data” removes on-device copies '
                'immediately. To also delete your Supabase account and '
                'synced records, send a deletion request via Profile → '
                'Feedback — there is no in-app server-delete button yet.',
              ),
              docLine(
                'Opt-out: no ads and no analytics are built in, and nothing '
                'is sold. Sharing with friends and the leaderboard is '
                'opt-in (Friends → Privacy toggles) and can be switched '
                'off any time.',
              ),
              docLine(
                'Retention: on-device data stays until you erase it, synced '
                'records stay until you request deletion, and feedback '
                'emails stay in the support inbox so they can be actioned. '
                'The app is not directed at children under 13.',
              ),
            ],
          ),
        ),
        DetailRow(
          icon: Icons.logout_outlined,
          title: signedIn
              ? 'Sign out'
              : backendOn
              ? 'Sign out of demo access'
              : 'Exit demo',
          subtitle: signedIn
              ? 'Signs out on this device; data stays saved'
              : 'Keeps study data, ends demo access',
          onTap: _busy ? () {} : _signOut,
        ),
        DetailRow(
          icon: Icons.delete_outline,
          title: 'Erase all local data',
          subtitle: _busy
              ? 'Working…'
              : 'Deletes on-device data, keeps your account',
          onTap: _busy ? () {} : _eraseAll,
        ),
      ],
    );
  }
}

// ---------------- HELP ----------------

/// Help page: searchable, organized guide. Categories + articles come from
/// [help_guide.dart] and describe only behaviour verified in this codebase.
class HelpPage extends StatefulWidget {
  const HelpPage({super.key});

  @override
  State<HelpPage> createState() => _HelpPageState();
}

class _HelpPageState extends State<HelpPage> {
  final _search = TextEditingController();
  String _query = '';
  String _categoryId = 'start';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final results = searchHelpArticles(_query);
    final visible = _query.trim().isEmpty
        ? helpArticlesIn(_categoryId)
        : results;
    return DetailScaffold(
      title: 'Help',
      children: [
        DetailCard(
          child: TextField(
            controller: _search,
            textInputAction: TextInputAction.search,
            style: AppTextStyles.body14,
            decoration: InputDecoration(
              hintText: 'Search the guide…',
              hintStyle: AppTextStyles.body14.copyWith(
                color: AppColors.textMuted.withValues(alpha: 0.75),
              ),
              prefixIcon: const Icon(
                Icons.search,
                color: AppColors.textSecondary,
              ),
              suffixIcon: _query.isEmpty
                  ? null
                  : IconButton(
                      tooltip: 'Clear search',
                      onPressed: () {
                        _search.clear();
                        setState(() => _query = '');
                      },
                      icon: const Icon(
                        Icons.clear,
                        color: AppColors.textSecondary,
                      ),
                    ),
              filled: true,
              fillColor: AppColors.surface2,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 14,
              ),
              border: const OutlineInputBorder(
                borderRadius: BorderRadius.all(Radius.circular(14)),
                borderSide: BorderSide.none,
              ),
            ),
            onChanged: (v) => setState(() => _query = v),
          ),
        ),
        if (_query.trim().isEmpty) ...[
          SizedBox(
            height: 40,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: helpCategories.length,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (ctx, i) {
                final c = helpCategories[i];
                final selected = c.id == _categoryId;
                return ChoiceChip(
                  label: Text(c.title),
                  selected: selected,
                  selectedColor: AppColors.cta,
                  backgroundColor: AppColors.surface,
                  labelStyle: AppTextStyles.caption13.copyWith(
                    color: selected
                        ? AppColors.onCta
                        : AppColors.textPrimary,
                  ),
                  onSelected: (_) {
                    HapticFeedback.selectionClick();
                    setState(() => _categoryId = c.id);
                  },
                );
              },
            ),
          ),
          const SizedBox(height: 8),
        ],
        if (visible.isEmpty)
          DetailCard(
            child: Text(
              'No guide articles match “${_query.trim()}”. Try fewer words, '
              'or browse the categories.',
              style: AppTextStyles.caption12,
            ),
          )
        else
          for (final article in visible)
            DetailCard(
              child: Material(
                color: Colors.transparent,
                borderRadius: BorderRadius.circular(12),
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () {
                    SystemSound.play(SystemSoundType.click);
                    HapticFeedback.selectionClick();
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) =>
                            HelpArticlePage(article: article),
                      ),
                    );
                  },
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              article.title,
                              style: AppTextStyles.body14,
                            ),
                            const SizedBox(height: 2),
                            Text(
                              article.body.first,
                              style: AppTextStyles.caption12,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      const Icon(
                        Icons.chevron_right,
                        color: AppColors.textSecondary,
                      ),
                    ],
                  ),
                ),
              ),
            ),
      ],
    );
  }
}

/// Single guide article: title + readable paragraphs, same detail frame.
class HelpArticlePage extends StatelessWidget {
  final HelpArticle article;
  const HelpArticlePage({super.key, required this.article});

  @override
  Widget build(BuildContext context) {
    return DetailScaffold(
      title: article.title,
      children: [
        DetailCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var i = 0; i < article.body.length; i++) ...[
                Text(article.body[i], style: AppTextStyles.secondary14),
                if (i < article.body.length - 1) const SizedBox(height: 10),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

// ---------------- FEEDBACK ----------------

/// Feedback page: validated form submitted through the Supabase
/// `send-feedback` Edge Function when the backend is configured, with the
/// Vercel `/api/feedback` endpoint as fallback; both relay via Resend to
/// the support inbox.
///
/// Behaviour:
/// - validates category / subject / message / optional contact email first;
/// - shows a loading state and ignores duplicate taps while submitting;
/// - on backend acceptance: clears the form + draft, shows confirmation;
/// - on any failure: keeps the draft (memory + device) so the user can retry.
class FeedbackPage extends ConsumerStatefulWidget {
  const FeedbackPage({super.key});

  @override
  ConsumerState<FeedbackPage> createState() => _FeedbackPageState();
}

class _FeedbackPageState extends ConsumerState<FeedbackPage> {
  static const _storageKey = 'studyup.feedback.v1';
  static const _draftKey = 'studyup.feedback.draft.v1';

  final _subject = TextEditingController();
  final _message = TextEditingController();
  final _contact = TextEditingController();
  String _category = 'bug';
  String? _subjectError;
  String? _messageError;
  String? _contactError;
  bool _busy = false;
  int _sentCount = 0;

  @override
  void initState() {
    super.initState();
    _loadState();
  }

  @override
  void dispose() {
    _subject.dispose();
    _message.dispose();
    _contact.dispose();
    super.dispose();
  }

  Future<void> _loadState() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_storageKey);
      final draftRaw = prefs.getString(_draftKey);
      if (!mounted) return;
      if (raw != null) {
        final list = jsonDecode(raw) as List<Object?>;
        _sentCount = list.length;
      }
      if (draftRaw != null) {
        try {
          final draft = jsonDecode(draftRaw) as Map<String, dynamic>;
          _subject.text = (draft['subject'] as String?) ?? '';
          _message.text = (draft['message'] as String?) ?? '';
          _contact.text = (draft['contactEmail'] as String?) ?? '';
          final cat = (draft['category'] as String?) ?? 'bug';
          if (feedbackCategories.contains(cat)) _category = cat;
        } catch (_) {
          // Corrupt draft: ignore, start fresh.
        }
      }
      if (mounted) setState(() {});
    } catch (_) {
      // Counts/drafts are informational; never block the form.
    }
  }

  Future<void> _saveDraft() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _draftKey,
        jsonEncode({
          'category': _category,
          'subject': _subject.text,
          'message': _message.text,
          'contactEmail': _contact.text,
          'at': DateTime.now().toIso8601String(),
        }),
      );
    } catch (_) {
      // Draft persistence is best-effort only.
    }
  }

  Future<void> _clearDraft() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_draftKey);
    } catch (_) {}
  }

  void _say(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  bool _validate() {
    final sErr = validateFeedbackSubject(_subject.text);
    final mErr = validateFeedbackMessage(_message.text);
    final cErr = validateFeedbackContactEmail(_contact.text);
    setState(() {
      _subjectError = sErr;
      _messageError = mErr;
      _contactError = cErr;
    });
    return sErr == null && mErr == null && cErr == null;
  }

  Future<void> _submit() async {
    if (_busy) return; // prevent duplicate taps
    FocusScope.of(context).unfocus();
    if (!_validate()) {
      HapticFeedback.selectionClick();
      return;
    }
    setState(() => _busy = true);
    try {
      // Transport selection lives in FeedbackSubmitter: Supabase Edge
      // Function first, then the hosted Vercel endpoint when the function
      // is not deployed yet. Any failure preserves the draft; only a
      // confirmed acceptance resets the form.
      final contact = _contact.text.trim().isEmpty ? null : _contact.text;
      final result = await ref.read(feedbackSubmitterProvider).submit(
            category: _category,
            subject: _subject.text,
            message: _message.text,
            contactEmail: contact,
            platform: Platform.operatingSystem,
          );
      // Success = backend accepted (Resend queued). Only now reset the form.
      try {
        final prefs = await SharedPreferences.getInstance();
        final raw = prefs.getString(_storageKey);
        final list = raw == null
            ? <Object?>[]
            : List<Object?>.from(jsonDecode(raw) as List);
        list.add({
          'category': _category,
          'subject': _subject.text.trim(),
          'at': DateTime.now().toIso8601String(),
          if (result.resendId != null) 'id': result.resendId,
        });
        await prefs.setString(_storageKey, jsonEncode(list));
        if (mounted) setState(() => _sentCount = list.length);
      } catch (_) {
        // Sent-log is informational; success was already confirmed.
      }
      await _clearDraft();
      _subject.clear();
      _message.clear();
      _contact.clear();
      if (mounted) {
        setState(() {
          _category = 'bug';
          _subjectError = null;
          _messageError = null;
          _contactError = null;
        });
      }
      _say(
        'Thanks — your feedback is on its way to the StudyUp inbox. '
        'Replies are only possible if you left a contact email, and they '
        'can take a few days.',
      );
    } on FeedbackException catch (e) {
      // Preserve the draft for retry (memory already holds it; persist too).
      await _saveDraft();
      _say(e.message);
    } catch (_) {
      await _saveDraft();
      _say('Could not send feedback. Your draft is kept — please retry.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Transport selection lives in FeedbackSubmitter: the Supabase Edge
    // Function when the backend is live, with an automatic fallback to the
    // hosted Vercel endpoint when the function is not deployed yet.
    return DetailScaffold(
      title: 'Feedback',
      children: [
        DetailCard(
          child: Text(
            'Tell us what is broken, confusing or missing — bug '
            'reports and ideas both help. Sending posts only the '
            'fields below (plus app version and platform) to the '
            'StudyUp support inbox; nothing else from your device '
            'is sent.',
            style: AppTextStyles.caption12,
          ),
        ),
        DetailCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Category', style: AppTextStyles.caption13),
              const SizedBox(height: 6),
              DropdownButtonFormField<String>(
                initialValue: _category,
                dropdownColor: AppColors.surface2,
                style: AppTextStyles.body14,
                decoration: InputDecoration(
                  filled: true,
                  fillColor: AppColors.surface2,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 14,
                  ),
                  border: const OutlineInputBorder(
                    borderRadius: BorderRadius.all(Radius.circular(14)),
                    borderSide: BorderSide.none,
                  ),
                ),
                items: [
                  for (final c in feedbackCategories)
                    DropdownMenuItem(
                      value: c,
                      child: Text(feedbackCategoryLabel(c)),
                    ),
                ],
                onChanged: _busy
                    ? null
                    : (v) {
                        if (v != null) setState(() => _category = v);
                      },
              ),
              const SizedBox(height: 10),
              AppTextField(
                controller: _subject,
                label: 'Subject',
                hintText: 'e.g. Timer kept running',
                textInputAction: TextInputAction.next,
                textCapitalization: TextCapitalization.sentences,
                errorText: _subjectError,
                onChanged: (_) {
                  if (_subjectError != null) {
                    setState(() => _subjectError = null);
                  }
                },
              ),
              const SizedBox(height: 10),
              AppTextField(
                controller: _message,
                label: 'Message',
                hintText: 'What happened, step by step…',
                maxLines: 4,
                textCapitalization: TextCapitalization.sentences,
                errorText: _messageError,
                onChanged: (_) {
                  if (_messageError != null) {
                    setState(() => _messageError = null);
                  }
                },
              ),
              const SizedBox(height: 10),
              AppTextField(
                controller: _contact,
                label: 'Contact email (optional)',
                hintText: 'you@example.com — only for replies',
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.done,
                errorText: _contactError,
                onChanged: (_) {
                  if (_contactError != null) {
                    setState(() => _contactError = null);
                  }
                },
                onSubmitted: (_) => _submit(),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: PrimaryButton(
                  label: _busy ? 'Sending…' : 'Send feedback',
                  onPressed: _busy ? null : _submit,
                ),
              ),
              if (_sentCount > 0) ...[
                const SizedBox(height: 8),
                Text(
                  '$_sentCount sent from this device',
                  style: AppTextStyles.caption12,
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}
