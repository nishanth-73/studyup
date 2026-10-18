import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/deeplink/invite_links.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/ui_kit.dart';
import '../../auth/data/auth_controller.dart';
import '../../community/presentation/community_widgets.dart';
import '../../social/data/social_providers.dart';
import '../../social/data/social_remote.dart';

/// Invitation landing: shows WHO invited the recipient and asks for an
/// explicit Accept or Decline. Handles logged-out users (sign in first,
/// token is preserved), expired/invalid/used tokens, self-invites, existing
/// friendships, and network failures. Friendship is created server-side
/// only after authorized acceptance — never by opening the link, and never
/// by declining it.
class InviteAcceptScreen extends ConsumerStatefulWidget {
  final String token;

  const InviteAcceptScreen({super.key, required this.token});

  @override
  ConsumerState<InviteAcceptScreen> createState() => _InviteAcceptScreenState();
}

enum _Phase { checking, needsLogin, ready, working, done, failed, declined }

class _InviteAcceptScreenState extends ConsumerState<InviteAcceptScreen> {
  _Phase _phase = _Phase.checking;
  InvitePreview? _preview;
  String? _message;
  String? _friendName;

  @override
  void initState() {
    super.initState();
    // This route owns the token now: clear any stashed copy so the
    // startup gate cannot route back here after accept/dismiss.
    InviteLinks.takePending();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  /// Works before sign-in: the preview is public and accept authenticates
  /// only when the recipient taps the button. Null when the backend is
  /// not configured.
  SocialRemote? get _remote => ref.read(inviteRemoteProvider);

  Future<void> _load() async {
    final remote = _remote;
    if (remote == null) {
      setState(() {
        _phase = _Phase.failed;
        _message = 'Backend not connected yet. Ask your friend for the app setup, then open this link again.';
      });
      return;
    }
    try {
      final preview = await remote.previewInvitation(widget.token);
      if (!mounted) return;
      if (!preview.valid) {
        setState(() {
          _phase = _Phase.failed;
          _message = _reasonText(preview.reason);
        });
        return;
      }
      final userId = ref.read(backendUserIdProvider);
      setState(() {
        _preview = preview;
        _phase = userId == null ? _Phase.needsLogin : _Phase.ready;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _phase = _Phase.failed;
        _message = 'Could not load this invitation. Check your connection.';
      });
    }
  }

  String _reasonText(String reason) => switch (reason) {
    'expired' => 'This invitation expired. Ask for a fresh one.',
    'revoked' => 'This invitation was revoked by the sender.',
    'accepted' => 'This invitation was already used.',
    _ => 'This invitation link is invalid.',
  };

  Future<void> _accept() async {
    setState(() {
      _phase = _Phase.working;
      _message = null;
    });
    final remote = _remote;
    if (remote == null) {
      setState(() {
        _phase = _Phase.failed;
        _message = 'Backend not connected yet.';
      });
      return;
    }
    try {
      final name = await remote.acceptInvitation(widget.token);
      if (!mounted) return;
      // The friendship now exists server-side: refresh the friends list
      // and the friends leaderboard so the new friend appears immediately
      // (the realtime channel also covers this, but cannot be relied on
      // while offline/blocked).
      ref.invalidate(remoteFriendsProvider);
      ref.invalidate(remoteFriendsBoardProvider);
      setState(() {
        _phase = _Phase.done;
        _friendName = name;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _phase = _Phase.failed;
        _message = _acceptError(error);
      });
    }
  }

  /// Declining is purely local: nothing was created server-side yet (the
  /// friendship only exists after an accepted, server-validated call), so
  /// this just leaves the screen without joining the Community. The
  /// invitation itself stays active so the inviter can share it again.
  Future<void> _decline() async {
    setState(() {
      _phase = _Phase.declined;
    });
  }

  void _leave() => context.go('/home');

  Widget _declineButton() {
    return TextButton(
      onPressed: _decline,
      child: Text(
        'Decline',
        style: AppTextStyles.caption13.copyWith(color: AppColors.cta),
      ),
    );
  }

  String _acceptError(Object error) {
    final m = error.toString().toLowerCase();
    if (m.contains('self invite')) {
      return 'You cannot accept your own invitation.';
    }
    if (m.contains('already friends')) {
      return 'You are already friends. No duplicate created.';
    }
    if (m.contains('expired')) {
      return 'This invitation expired. Ask for a fresh one.';
    }
    if (m.contains('revoked')) return 'This invitation was revoked.';
    if (m.contains('already accepted')) {
      return 'This invitation was already used.';
    }
    if (m.contains('request pending')) {
      return 'A friend request between you is already pending — check Friends.';
    }
    if (m.contains('not authenticated')) {
      return 'Please sign in first, then accept.';
    }
    if (m.contains('socketexception') || m.contains('network')) {
      return 'No connection. Retry when you are back online.';
    }
    return 'Could not accept this invitation. Please retry.';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: _body(),
          ),
        ),
      ),
    );
  }

  Widget _body() {
    switch (_phase) {
      case _Phase.checking:
      case _Phase.working:
        return const Center(child: CircularProgressIndicator());
      case _Phase.failed:
        return _card(
          title: 'Invitation unavailable',
          body: _message ?? 'Something went wrong.',
          actions: [
            PrimaryButton(
              label: 'Back to StudyUp',
              onPressed: () => context.go('/home'),
            ),
          ],
        );
      case _Phase.needsLogin:
        return _card(
          title: 'You\u2019re invited!',
          body:
              '${_preview?.displayName ?? 'A friend'} invited you to join StudyUp. Sign in (or create an account) to accept — this invitation is saved and will resume right after.',
          actions: [
            PrimaryButton(
              label: 'Sign in / Sign up',
              onPressed: () async {
                await InviteLinks.stashPending(widget.token);
                if (mounted) context.go('/auth');
              },
            ),
            _declineButton(),
          ],
        );
      case _Phase.ready:
        return _card(
          title: 'You\u2019re invited!',
          body:
              '${_preview?.displayName ?? 'A friend'} invited you to join StudyUp.',
          actions: [
            Row(
              children: [
                CommunityAvatar(
                  displayName: _preview?.displayName ?? '?',
                  avatarId: _preview?.avatarId ?? 'robo-default',
                  blobVariant: 0,
                  radius: 24,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    _preview?.displayName ?? 'Study buddy',
                    style: AppTextStyles.body15,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            PrimaryButton(label: 'Accept invitation', onPressed: _accept),
            const SizedBox(height: 10),
            _declineButton(),
            const SizedBox(height: 12),
            Text(
              'Nothing happens until you tap Accept — opening this link never '
              'joins you to anyone.',
              style: AppTextStyles.secondary12,
            ),
          ],
        );
      case _Phase.declined:
        return _card(
          title: 'Invitation declined',
          body:
              'No worries — you have not been added to anyone\u2019s Community. '
              '${_preview?.displayName ?? 'Your friend'}\u2019s invitation is still '
              'valid if you change your mind.',
          actions: [
            PrimaryButton(label: 'Back to StudyUp', onPressed: _leave),
          ],
        );
      case _Phase.done:
        return _card(
          title: 'Connected!',
          body:
              'You and ${_friendName ?? 'your friend'} are now study buddies. Compete on the Community tab.',
          actions: [
            PrimaryButton(
              label: 'Open Community',
              onPressed: () => context.go('/community'),
            ),
          ],
        );
    }
  }

  Widget _card({
    required String title,
    required String body,
    required List<Widget> actions,
  }) {
    return CommunityCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(title, style: AppTextStyles.section18),
          const SizedBox(height: 8),
          Text(body, style: AppTextStyles.secondary14),
          const SizedBox(height: 16),
          for (var i = 0; i < actions.length; i++) ...[
            if (i > 0) const SizedBox(height: 10),
            actions[i],
          ],
        ],
      ),
    );
  }
}
