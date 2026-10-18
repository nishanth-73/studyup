import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/app_shell.dart';
import '../../../core/widgets/ui_kit.dart';
import '../data/community_models.dart';
import '../data/community_store.dart';
import '../../social/data/social_providers.dart';
import '../../social/data/social_remote.dart';
import 'community_controller.dart';
import 'community_widgets.dart';

/// Friends: invite-code exchange, pending requests, friend list with
/// block/report, and privacy controls. Never shows contact details —
/// members carry display names only.
///
/// Signed in: the top section shows real server friends, live incoming
/// requests (realtime), and user search. The local invite-code flow
/// below stays as an offline fallback and is never mixed with server
/// data.
class FriendsScreen extends ConsumerStatefulWidget {
  const FriendsScreen({super.key});

  @override
  ConsumerState<FriendsScreen> createState() => _FriendsScreenState();
}

class _FriendsScreenState extends ConsumerState<FriendsScreen> {
  final _codeController = TextEditingController();
  String? _codeError;
  bool _busy = false;

  final _searchController = TextEditingController();
  List<Map<String, dynamic>> _searchResults = const [];
  bool _searching = false;
  String? _searchError;

  @override
  void dispose() {
    _codeController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _run(Future<String?> Function() call) async {
    setState(() => _busy = true);
    final error = await call();
    if (!mounted) return;
    setState(() => _busy = false);
    if (error != null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final community = ref.watch(communityControllerProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        title: Text('Friends', style: AppTextStyles.section18),
      ),
      body: SafeArea(
        bottom: false,
        child: community.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => ListView(
            padding: const EdgeInsets.all(20),
            children: [
              CommunityError(
                error: e,
                onRetry: () =>
                    ref.read(communityControllerProvider.notifier).refresh(),
              ),
            ],
          ),
          data: (data) => _body(context, data),
        ),
      ),
    );
  }

  Widget _body(BuildContext context, CommunityData data) {
    final pending = data.pendingIncoming;
    final friends = data.friends;
    final history = data.incoming
        .where((r) => r.status != FriendRequestStatus.pending)
        .toList();

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
      children: [
        if (ref.watch(socialLiveProvider)) ...[
          _remoteSection(),
          const SizedBox(height: 16),
        ],
        _inviteCard(data),
        const SizedBox(height: 12),
        _redeemCard(),
        const SizedBox(height: 16),
        if (pending.isNotEmpty) ...[
          Text('Requests', style: AppTextStyles.section18),
          const SizedBox(height: 8),
          for (final r in pending)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _requestRow(data, r),
            ),
          const SizedBox(height: 8),
        ],
        Text('My friends (${friends.length})', style: AppTextStyles.section18),
        const SizedBox(height: 8),
        if (friends.isEmpty)
          const CommunityEmpty(
            title: 'No friends yet',
            body: 'Share your invite code or enter a friend\u2019s code above.',
          )
        else
          for (final f in friends)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _friendRow(data, f),
            ),
        const SizedBox(height: 16),
        Text('Privacy', style: AppTextStyles.section18),
        const SizedBox(height: 8),
        _privacyCard(data),
        if (data.blockedIds.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text('Blocked', style: AppTextStyles.section18),
          const SizedBox(height: 8),
          for (final id in data.blockedIds)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _blockedRow(data, id),
            ),
        ],
        if (history.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text('Past requests', style: AppTextStyles.section18),
          const SizedBox(height: 8),
          for (final r in history.take(5))
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Text(
                '${r.fromName} · ${r.status.name}',
                style: AppTextStyles.secondary14,
              ),
            ),
        ],
        SizedBox(height: AppShell.scrollClearance(context)),
      ],
    );
  }

  /// Live server section: accepted friends, incoming requests
  /// (realtime), and display-name search. Demo/local rows never appear
  /// here — only authenticated Supabase records.
  Widget _remoteSection() {
    ref.watch(remoteRealtimeProvider);
    final friends = ref.watch(remoteFriendsProvider);
    final incoming = ref.watch(remoteIncomingProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('Connected friends', style: AppTextStyles.section18),
            const SizedBox(width: 8),
            const Pill(
              'LIVE',
              background: AppColors.green,
              foreground: AppColors.onCta,
            ),
          ],
        ),
        const SizedBox(height: 8),
        incoming.when(
          loading: () => const SizedBox.shrink(),
          error: (_, _) => const SizedBox.shrink(),
          data: (requests) => Column(
            children: [
              for (final r in requests)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _remoteRequestRow(r),
                ),
            ],
          ),
        ),
        friends.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, _) => const CommunityEmpty(
            title: 'Could not load friends',
            body: 'Check your connection and pull to retry.',
          ),
          data: (list) => Column(
            children: [
              if (list.isEmpty)
                const CommunityEmpty(
                  title: 'No connected friends yet',
                  body: 'Share an invite link from Community — they appear here after accepting.',
                )
              else
                for (final f in list)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _remoteFriendRow(f),
                  ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Text('Find friends', style: AppTextStyles.section18),
        const SizedBox(height: 8),
        CommunityCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Search opted-in StudyUp members by display name.',
                style: AppTextStyles.secondary14,
              ),
              const SizedBox(height: 10),
              AppTextField(
                controller: _searchController,
                hintText: 'Display name…',
                textInputAction: TextInputAction.search,
                onSubmitted: (_) => _searchUsers(),
              ),
              if (_searchError != null) ...[
                const SizedBox(height: 6),
                Text(
                  _searchError!,
                  style: AppTextStyles.caption12.copyWith(
                    color: AppColors.error,
                  ),
                ),
              ],
              const SizedBox(height: 10),
              PrimaryButton(
                label: _searching ? 'Searching…' : 'Search',
                onPressed: _searching ? null : _searchUsers,
              ),
              for (final u in _searchResults)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Row(
                    children: [
                      CommunityAvatar(
                        displayName: u['display_name'] as String? ?? '?',
                        avatarId: u['avatar_id'] as String? ?? 'robo-default',
                        blobVariant: 0,
                        radius: 15,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          u['display_name'] as String? ?? 'Study buddy',
                          style: AppTextStyles.body14,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      TextButton(
                        onPressed: _busy
                            ? null
                            : () => _sendRequest(u['user_id'] as String),
                        child: Text(
                          'Add',
                          style: AppTextStyles.caption13.copyWith(
                            color: AppColors.cta,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _searchUsers() async {
    final remote = ref.read(socialRemoteProvider);
    if (remote == null) return;
    final q = _searchController.text.trim();
    if (q.isEmpty) {
      setState(() => _searchError = 'Type a display name first.');
      return;
    }
    setState(() {
      _searching = true;
      _searchError = null;
    });
    try {
      final results = await remote.searchUsers(q);
      if (!mounted) return;
      setState(() {
        _searchResults = results;
        if (results.isEmpty) _searchError = 'No opted-in members found.';
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _searchError = 'Search failed. Check your connection.');
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  Future<void> _sendRequest(String userId) async {
    final remote = ref.read(socialRemoteProvider);
    if (remote == null) return;
    setState(() => _busy = true);
    try {
      await remote.sendFriendRequest(userId);
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Friend request sent.')));
      ref.invalidate(remoteIncomingProvider);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(_remoteError(error))));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _remoteRequestRow(RemoteRequest r) {
    return CommunityCard(
      child: Row(
        children: [
          CommunityAvatar(displayName: r.fromName, blobVariant: 0),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(r.fromName, style: AppTextStyles.body14Bold),
                Text(
                  'Wants to be your study buddy',
                  style: AppTextStyles.secondary12,
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: _busy ? null : () => _respondRemote(r.id, false),
            child: Text(
              'Decline',
              style: AppTextStyles.caption13.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
          ),
          const SizedBox(width: 4),
          FilledButton(
            onPressed: _busy ? null : () => _respondRemote(r.id, true),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.cta,
              foregroundColor: AppColors.onCta,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(100),
              ),
            ),
            child: const Text('Accept'),
          ),
        ],
      ),
    );
  }

  Future<void> _respondRemote(String requestId, bool accept) async {
    final remote = ref.read(socialRemoteProvider);
    if (remote == null) return;
    setState(() => _busy = true);
    try {
      await remote.respondToRequest(requestId, accept);
      ref.invalidate(remoteIncomingProvider);
      ref.invalidate(remoteFriendsProvider);
      ref.invalidate(remoteFriendsBoardProvider);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(_remoteError(error))));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _remoteFriendRow(RemoteFriend f) {
    return CommunityCard(
      child: Row(
        children: [
          CommunityAvatar(
            displayName: f.displayName,
            avatarId: f.avatarId,
            blobVariant: f.blobVariant,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(f.displayName, style: AppTextStyles.body14Bold),
                Text(
                  f.leaderboardOptIn
                      ? 'Competing on the leaderboard'
                      : 'Not sharing leaderboard totals',
                  style: AppTextStyles.secondary12,
                ),
              ],
            ),
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_horiz, color: AppColors.textSecondary),
            color: AppColors.surface2,
            onSelected: (v) async {
              if (v == 'remove') {
                final ok = await _confirm(
                  'Remove ${f.displayName} from friends?',
                );
                if (ok == true) {
                  try {
                    await ref
                        .read(socialRemoteProvider)
                        ?.removeFriend(f.userId);
                    ref.invalidate(remoteFriendsProvider);
                    ref.invalidate(remoteFriendsBoardProvider);
                  } catch (error) {
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(_remoteError(error))),
                      );
                    }
                  }
                }
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'remove', child: Text('Remove friend')),
            ],
          ),
        ],
      ),
    );
  }

  String _remoteError(Object error) {
    final m = error.toString().toLowerCase();
    if (m.contains('duplicate') ||
        m.contains('unique') ||
        m.contains('23505')) {
      return 'A request is already pending.';
    }
    if (m.contains('not recipient') || m.contains('not sender')) {
      return 'Not authorized for this request.';
    }
    if (m.contains('socketexception') || m.contains('network')) {
      return 'No connection. Retry when you are back online.';
    }
    return 'Something went wrong. Please retry.';
  }

  Widget _inviteCard(CommunityData data) {
    final code = data.myInviteCode;
    return CommunityCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('My invite code', style: AppTextStyles.body15),
          const SizedBox(height: 4),
          Text(
            'Share it with a friend. It carries your display name and this week\u2019s real study total — nothing private. Expires in 30 days.',
            style: AppTextStyles.secondary14,
          ),
          const SizedBox(height: 12),
          if (code != null) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.surface2,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                code,
                style: AppTextStyles.body14Bold.copyWith(color: AppColors.cta),
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: PrimaryButton(
                    label: 'Copy code',
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: code));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Invite code copied.')),
                      );
                    },
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: PrimaryButton(
                    label: _busy ? '...' : 'Refresh',
                    background: AppColors.surface2,
                    foreground: AppColors.textPrimary,
                    onPressed: _busy
                        ? null
                        : () => _run(
                            () => ref
                                .read(communityControllerProvider.notifier)
                                .myInviteCode()
                                .then((_) => null),
                          ),
                  ),
                ),
              ],
            ),
          ] else
            PrimaryButton(
              label: _busy ? '...' : 'Generate invite code',
              onPressed: _busy
                  ? null
                  : () => _run(
                      () => ref
                          .read(communityControllerProvider.notifier)
                          .myInviteCode()
                          .then((_) => null),
                    ),
            ),
        ],
      ),
    );
  }

  Widget _redeemCard() {
    return CommunityCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Enter a friend\u2019s code', style: AppTextStyles.body15),
          const SizedBox(height: 4),
          Text(
            'Their display name appears as a request you can accept or decline.',
            style: AppTextStyles.secondary14,
          ),
          const SizedBox(height: 10),
          AppTextField(
            controller: _codeController,
            hintText: 'SUP1-XXXX-XXXX…',
            errorText: _codeError,
            textCapitalization: TextCapitalization.characters,
            onSubmitted: (_) => _redeem(),
          ),
          const SizedBox(height: 10),
          PrimaryButton(
            label: _busy ? 'Checking…' : 'Send request',
            onPressed: _busy ? null : _redeem,
          ),
        ],
      ),
    );
  }

  Future<void> _redeem() async {
    final code = _codeController.text.trim();
    if (code.isEmpty) {
      setState(() => _codeError = 'Paste an invite code first.');
      return;
    }
    setState(() {
      _codeError = null;
      _busy = true;
    });
    final error = await ref
        .read(communityControllerProvider.notifier)
        .redeemCode(code);
    if (!mounted) return;
    setState(() => _busy = false);
    if (error != null) {
      setState(() => _codeError = error);
    } else {
      _codeController.clear();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Request received — accept it below.')),
      );
    }
  }

  Widget _requestRow(CommunityData data, FriendRequest r) {
    final member = data.members[r.fromId];
    final weekLabel = member != null && member.sharedWeekKey != null
        ? ' · ${formatHoursMinutes(member.sharedWeekSeconds)} this week'
        : '';
    return CommunityCard(
      child: Row(
        children: [
          CommunityAvatar(
            displayName: r.fromName,
            blobVariant: member?.blobVariant ?? 0,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(r.fromName, style: AppTextStyles.body14Bold),
                Text(
                  'Wants to be your study buddy$weekLabel',
                  style: AppTextStyles.secondary12,
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: _busy
                ? null
                : () => _run(
                    () => ref
                        .read(communityControllerProvider.notifier)
                        .declineRequest(r.id),
                  ),
            child: Text(
              'Decline',
              style: AppTextStyles.caption13.copyWith(
                color: AppTextStyles.secondary14.color,
              ),
            ),
          ),
          const SizedBox(width: 4),
          FilledButton(
            onPressed: _busy
                ? null
                : () => _run(
                    () => ref
                        .read(communityControllerProvider.notifier)
                        .acceptRequest(r.id),
                  ),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.cta,
              foregroundColor: AppColors.onCta,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(100),
              ),
            ),
            child: const Text('Accept'),
          ),
        ],
      ),
    );
  }

  Widget _friendRow(CommunityData data, CommunityMember m) {
    final selectedKey = weekKeyFor(DateTime.now());
    final shared = m.sharedWeekKey == selectedKey && m.sharedWeekSeconds > 0;
    return CommunityCard(
      child: Row(
        children: [
          CommunityAvatar(
            displayName: m.displayName,
            blobVariant: m.blobVariant,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(m.displayName, style: AppTextStyles.body14Bold),
                Text(
                  shared
                      ? '${formatHoursMinutes(m.sharedWeekSeconds)} this week · shared ${m.sharedAt != null ? _ago(m.sharedAt!) : ''}'
                      : 'No shared data this week',
                  style: AppTextStyles.secondary12,
                ),
              ],
            ),
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_horiz, color: AppColors.textSecondary),
            color: AppColors.surface2,
            onSelected: (v) => _friendAction(m.id, m.displayName, v),
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'remove', child: Text('Remove friend')),
              PopupMenuItem(value: 'block', child: Text('Block')),
              PopupMenuItem(value: 'report', child: Text('Report')),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _friendAction(String id, String name, String action) async {
    if (action == 'remove') {
      await _run(
        () => ref.read(communityControllerProvider.notifier).removeFriend(id),
      );
      return;
    }
    if (action == 'block') {
      final ok = await _confirm('Block $name? They disappear from Community.');
      if (ok == true) {
        await _run(
          () => ref.read(communityControllerProvider.notifier).blockUser(id),
        );
      }
      return;
    }
    final reason = await _askReason(name);
    if (reason != null && reason.trim().isNotEmpty) {
      await _run(
        () => ref
            .read(communityControllerProvider.notifier)
            .reportUser(id, reason.trim()),
      );
    }
  }

  Future<bool?> _confirm(String message) => showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: AppColors.surface,
      title: Text('Are you sure?', style: AppTextStyles.body15),
      content: Text(message, style: AppTextStyles.secondary14),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('Confirm'),
        ),
      ],
    ),
  );

  Future<String?> _askReason(String name) {
    final c = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text('Report $name', style: AppTextStyles.body15),
        content: AppTextField(controller: c, hintText: 'What happened?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, c.text),
            child: const Text('Report'),
          ),
        ],
      ),
    );
  }

  Widget _blockedRow(CommunityData data, String id) {
    final m = data.members[id];
    return CommunityCard(
      child: Row(
        children: [
          Expanded(
            child: Text(
              m?.displayName ?? 'Blocked user',
              style: AppTextStyles.body14,
            ),
          ),
          TextButton(
            onPressed: _busy
                ? null
                : () => _run(
                    () => ref
                        .read(communityControllerProvider.notifier)
                        .unblockUser(id),
                  ),
            child: Text(
              'Unblock',
              style: AppTextStyles.caption13.copyWith(color: AppColors.cta),
            ),
          ),
        ],
      ),
    );
  }

  Widget _privacyCard(CommunityData data) {
    final p = data.privacy;
    return CommunityCard(
      child: Column(
        children: [
          _toggle(
            'Leaderboard sharing',
            'Show my totals to friends',
            p.leaderboardOptIn,
            (v) => _savePrivacy(p.copyWith(leaderboardOptIn: v)),
          ),
          _toggle(
            'Live study status',
            'Friends see when I\u2019m studying (off by default)',
            p.shareLiveStatus,
            (v) => _savePrivacy(p.copyWith(shareLiveStatus: v)),
          ),
          _toggle(
            'Share current subject',
            'Include subject with live status',
            p.shareSubject,
            (v) => _savePrivacy(p.copyWith(shareSubject: v)),
            enabled: p.shareLiveStatus,
          ),
          _toggle(
            'Friend notifications',
            'Requests and accepted invites',
            p.friendNotifications,
            (v) => _savePrivacy(p.copyWith(friendNotifications: v)),
          ),
          _toggle(
            'Challenge notifications',
            'Invites and milestones',
            p.challengeNotifications,
            (v) => _savePrivacy(p.copyWith(challengeNotifications: v)),
          ),
        ],
      ),
    );
  }

  Widget _toggle(
    String title,
    String sub,
    bool value,
    ValueChanged<bool> onChanged, {
    bool enabled = true,
  }) {
    return Opacity(
      opacity: enabled ? 1 : 0.5,
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: AppTextStyles.body14Bold),
                Text(sub, style: AppTextStyles.secondary12),
              ],
            ),
          ),
          Switch(
            value: value,
            activeThumbColor: AppColors.cta,
            onChanged: enabled ? onChanged : null,
          ),
        ],
      ),
    );
  }

  Future<void> _savePrivacy(CommunityPrivacy p) async {
    await ref.read(communityControllerProvider.notifier).updatePrivacy(p);
    // Mirror visibility flags server-side so leaderboards honor them.
    final remote = ref.read(socialRemoteProvider);
    if (remote != null) {
      final self = ref.read(communitySelfProvider);
      try {
        await remote.upsertMyProfile(
          displayName: self.name,
          avatarId: self.avatarId,
          blobVariant: self.blob,
          leaderboardOptIn: p.leaderboardOptIn,
          shareLiveStatus: p.shareLiveStatus,
          shareSubject: p.shareSubject,
        );
      } catch (_) {}
    }
  }

  String _ago(DateTime t) {
    final d = DateTime.now().difference(t);
    if (d.inMinutes < 1) return 'just now';
    if (d.inHours < 1) return '${d.inMinutes}m ago';
    if (d.inDays < 1) return '${d.inHours}h ago';
    return '${d.inDays}d ago';
  }
}
