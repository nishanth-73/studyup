import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:app_links/app_links.dart';

import '../../../core/router/app_router.dart';
import 'community_models.dart';
import '../presentation/community_providers.dart';

const String kPendingInviteTokenKey = 'studyup_pending_invite_token';

/// Extracts invitation token from any supported incoming URI scheme:
/// - `https://studyup-4x7z.vercel.app/invite/<token>`
/// - `https://studyup-4x7z.vercel.app/i/<token>`
/// - `studyup://invite/<token>`
/// - `studyup://i/<token>`
/// - Query parameter `?token=<token>`
String? extractInviteToken(Uri? uri) {
  if (uri == null) return null;

  // 1. Check query parameter `token`
  final queryToken = uri.queryParameters['token'];
  if (queryToken != null && _isValidTokenFormat(queryToken)) {
    return queryToken;
  }

  // 2. Check path segments: /invite/<token> or /i/<token>
  final segments = uri.pathSegments;
  if (segments.length >= 2) {
    if (segments[0].toLowerCase() == 'invite' || segments[0].toLowerCase() == 'i') {
      final t = segments[1].trim();
      if (_isValidTokenFormat(t)) return t;
    }
  }

  // 3. Custom scheme: studyup://invite/<token> or studyup://i/<token>
  if (uri.scheme == 'studyup') {
    final host = uri.host.toLowerCase();
    if (host == 'invite' || host == 'i') {
      if (segments.isNotEmpty) {
        final t = segments[0].trim();
        if (_isValidTokenFormat(t)) return t;
      }
    }
  }

  return null;
}

bool _isValidTokenFormat(String token) {
  final clean = token.trim();
  return clean.length >= 8 && RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(clean);
}

/// Manages the in-memory and persisted pending invitation token.
class PendingInviteTokenNotifier extends StateNotifier<String?> {
  PendingInviteTokenNotifier() : super(null) {
    _loadFromDisk();
  }

  Future<void> _loadFromDisk() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString(kPendingInviteTokenKey);
      if (saved != null && _isValidTokenFormat(saved)) {
        state = saved;
      }
    } catch (_) {}
  }

  Future<void> setToken(String token, {bool navigate = true}) async {
    final clean = token.trim();
    if (!_isValidTokenFormat(clean)) return;

    state = clean;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(kPendingInviteTokenKey, clean);
    } catch (_) {}

    if (navigate) {
      try {
        appRouter.go('/community');
      } catch (_) {}
    }
  }

  Future<void> clear() async {
    state = null;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(kPendingInviteTokenKey);
    } catch (_) {}
  }
}

final pendingInviteTokenProvider =
    StateNotifierProvider<PendingInviteTokenNotifier, String?>(
  (ref) => PendingInviteTokenNotifier(),
);

/// Provider to fetch invitation preview details for any token.
final invitePreviewProvider =
    FutureProvider.family<InvitePreviewData, String>((ref, token) async {
  final repo = ref.watch(communityRepositoryProvider);
  if (repo == null) {
    return const InvitePreviewData(status: 'invalid', inviterName: '');
  }
  return repo.getInvitePreview(token);
});

/// Service that initializes AppLinks listeners for cold and warm deep linking.
class InvitationLinkService {
  final Ref _ref;
  final AppLinks _appLinks;
  StreamSubscription<Uri>? _linkSub;

  InvitationLinkService(this._ref, [AppLinks? appLinks])
      : _appLinks = appLinks ?? AppLinks();

  Future<void> init() async {
    // 1. Check cold launch link
    try {
      final initialUri = await _appLinks.getInitialLink();
      if (initialUri != null) {
        _handleIncomingUri(initialUri);
      }
    } catch (e) {
      debugPrint('[InvitationLinkService] Error reading initial link: $e');
    }

    // 2. Listen to incoming links stream (warm launch / foreground)
    try {
      _linkSub = _appLinks.uriLinkStream.listen(
        (uri) => _handleIncomingUri(uri),
        onError: (err) {
          debugPrint('[InvitationLinkService] uriLinkStream error: $err');
        },
      );
    } catch (e) {
      debugPrint('[InvitationLinkService] Error attaching link stream: $e');
    }
  }

  void _handleIncomingUri(Uri uri) {
    final token = extractInviteToken(uri);
    if (token != null) {
      _ref.read(pendingInviteTokenProvider.notifier).setToken(token, navigate: true);
    }
  }

  void dispose() {
    _linkSub?.cancel();
  }
}

final invitationLinkServiceProvider = Provider<InvitationLinkService>((ref) {
  final service = InvitationLinkService(ref);
  service.init();
  ref.onDispose(() => service.dispose());
  return service;
});
