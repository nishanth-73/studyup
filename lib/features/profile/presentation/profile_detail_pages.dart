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
/// [iconColor] lets destructive actions stand out from ordinary rows.
class DetailRow extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String? subtitle;
  final VoidCallback onTap;
  const DetailRow({
    super.key,
    required this.icon,
    this.iconColor = Colors.white,
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
              Icon(icon, color: iconColor, size: 20),
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

/// Privacy & Data page: a short, honest summary of what the app stores
/// on this device vs online, plus the real actions it supports
/// (sign-out / exit demo, erase local data). Destructive actions confirm
/// first and only claim success after the operation succeeds.
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
    if (!ref.read(backendLiveProvider)) {
      _say(
        'Sign-out is unavailable because the authentication backend is disconnected.',
      );
      return;
    }
    final signedIn = ref.read(backendUserIdProvider) != null;
    final ok = await _confirm(
      'Sign out?',
      signedIn
          ? 'Sign out of your account on this device? You may need to sign '
                'in again to access your account.'
          : 'Clear the saved sign-in session on this device?',
      'Sign Out',
    );
    if (!ok || !mounted) return;
    setState(() => _busy = true);
    try {
      final auth = ref.read(authRepositoryProvider);
      if (auth == null) throw StateError('Authentication is unavailable.');
      await auth.signOut();
      await clearPostSignInLink();
      if (mounted) context.go('/auth');
    } catch (_) {
      _say('Could not sign out. Please try again.');
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
    ref.invalidate(syncStatusProvider);
    ref.invalidate(roboShellColorProvider);
    ref.invalidate(roboShapeProvider);
    unawaited(NotificationService.instance.reloadUnreadCount());
  }

  Future<void> _eraseAll() async {
    final ok = await _confirm(
      'Erase local data?',
      'Delete the data stored on this device? This removes your profile, '
          'subjects and attached files, tasks, study sessions and '
          'settings, and clears the saved sign-in. Your online account and '
          'anything already synced are not deleted. This cannot be undone.',
      'Erase Data',
    );
    if (!ok || !mounted) return;
    setState(() => _busy = true);
    try {
      // 1. Clear the local auth session without deleting the online account.
      if (ref.read(backendUserIdProvider) != null) {
        final auth = ref.read(authRepositoryProvider);
        if (auth == null) throw StateError('Authentication is unavailable.');
        await auth.signOut();
      }
      // 2. Cancel OS-side effects (scheduled reminders, live timer).
      try {
        await NotificationService.instance.cancelAllScheduled();
      } catch (_) {}
      try {
        await NotificationService.instance.cancelLiveTimer();
      } catch (_) {}
      // 3. Delete downloaded attachments (abort before touching prefs if
      // this fails, so success is never claimed after a partial wipe).
      await _deleteDownloadedAttachments();
      // 4. Wipe local storage (SharedPreferences holds every record type
      // listed above, plus the saved Supabase session).
      final prefs = await SharedPreferences.getInstance();
      final cleared = await prefs.clear();
      if (!cleared) throw StateError('Device storage refused the erase.');
      // 5. Reset in-memory state so the UI rebuilds empty immediately.
      _resetInMemoryState();
      _say('All local data erased.');
      await Future<void>.delayed(const Duration(milliseconds: 900));
      if (mounted) context.go('/');
    } catch (_) {
      _say('Could not erase data. Please try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final subjects = ref
        .watch(subjectsProvider)
        .where((s) => !s.archived)
        .length;
    final tasks = ref.watch(homeControllerProvider).allTasks.length;
    final progress = ref.watch(studyProgressProvider);
    final backendOn = ref.watch(backendLiveProvider);
    final signedIn = ref.watch(backendUserIdProvider) != null;
    final email = ref.watch(backendUserEmailProvider);

    final accountLine = signedIn
        ? 'Signed in${email != null && email.isNotEmpty ? ' as $email' : ''}.'
        : backendOn
        ? 'No active account on this device. Sign in to use protected features.'
        : 'Authentication backend unavailable. Protected features cannot be used.';

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

    Widget line(String text) {
      return Padding(
        padding: const EdgeInsets.only(top: 5),
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
              Text('Your Data', style: AppTextStyles.body14Bold),
              const SizedBox(height: 5),
              Text(accountLine, style: AppTextStyles.caption12),
              const SizedBox(height: 6),
              stat('Subjects', '$subjects'),
              stat('Tasks', '$tasks'),
              stat('Study sessions', '${progress.sessions.length}'),
              stat('Daily goal', '${progress.dailyStudyGoalMinutes}m'),
              line(
                'This includes your profile (name and avatar), subjects with '
                'chapters, topics and attached files, tasks with reminders, '
                'study sessions, notification settings and quiz best '
                'scores.',
              ),
            ],
          ),
        ),
        DetailCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Data Storage & Services', style: AppTextStyles.body14Bold),
              line(
                'Everything is kept on this device first, as plain app data '
                '(not encrypted).',
              ),
              line(
                signedIn
                    ? 'While you are signed in, your saved study intervals '
                          'sync to an online database so they follow your '
                          'account. Only you can read or change your synced '
                          'records.'
                    : backendOn
                    ? 'Nothing is uploaded while you are signed out. Sign in '
                          'to sync your finished study intervals to your '
                          'account.'
                    : 'This build has no account connection; sign-in is '
                          'required before protected data is available.',
              ),
              line(
                'Attached files (PDFs and images) always stay on this '
                'device.',
              ),
              if (backendOn)
                line('Sign-in uses email and password, or Google.'),
            ],
          ),
        ),
        DetailRow(
          icon: Icons.logout_outlined,
          title: 'Sign out',
          subtitle: signedIn
              ? 'Signs out on this device; your data stays saved'
              : 'Clear the saved sign-in session on this device',
          onTap: _busy ? () {} : _signOut,
        ),
        DetailRow(
          icon: Icons.delete_outline,
          iconColor: AppColors.error,
          title: 'Erase local data',
          subtitle: _busy
              ? 'Working…'
              : 'Deletes everything stored on this device',
          onTap: _busy ? () {} : _eraseAll,
        ),
      ],
    );
  }
}

// ---------------- HELP ----------------

/// Help page: four compact, expandable how-to topics from [help_guide.dart]
/// that describe only behaviour verified in this codebase.
class HelpPage extends StatefulWidget {
  const HelpPage({super.key});

  @override
  State<HelpPage> createState() => _HelpPageState();
}

class _HelpPageState extends State<HelpPage> {
  String? _openId;

  @override
  Widget build(BuildContext context) {
    return DetailScaffold(
      title: 'Help',
      children: [
        DetailCard(
          child: Text(
            'Quick answers for everyday tasks. Tap a topic to expand it.',
            style: AppTextStyles.caption12,
          ),
        ),
        for (final topic in helpTopics)
          _HelpTopicCard(
            topic: topic,
            expanded: _openId == topic.id,
            onToggle: () {
              SystemSound.play(SystemSoundType.click);
              HapticFeedback.selectionClick();
              setState(() => _openId = _openId == topic.id ? null : topic.id);
            },
          ),
      ],
    );
  }
}

/// One expandable help topic: icon + title row, bullet lines when open.
class _HelpTopicCard extends StatelessWidget {
  final HelpTopic topic;
  final bool expanded;
  final VoidCallback onToggle;
  const _HelpTopicCard({
    required this.topic,
    required this.expanded,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    return DetailCard(
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onToggle,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(topic.icon, size: 20, color: AppColors.cta),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(topic.title, style: AppTextStyles.body14),
                  ),
                  Icon(
                    expanded ? Icons.expand_less : Icons.expand_more,
                    color: AppColors.textSecondary,
                  ),
                ],
              ),
              if (expanded) ...[
                const SizedBox(height: 10),
                for (final line in topic.lines)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          margin: const EdgeInsets.only(top: 7, right: 8),
                          width: 5,
                          height: 5,
                          decoration: const BoxDecoration(
                            color: AppColors.cta,
                            shape: BoxShape.circle,
                          ),
                        ),
                        Expanded(
                          child: Text(line, style: AppTextStyles.caption12),
                        ),
                      ],
                    ),
                  ),
              ],
            ],
          ),
        ),
      ),
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
/// - validates category / subject / message / required contact email first;
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
      final contact = _contact.text.trim();
      final result = await ref
          .read(feedbackSubmitterProvider)
          .submit(
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
                label: 'Contact email (required)',
                hintText: 'you@example.com',
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
