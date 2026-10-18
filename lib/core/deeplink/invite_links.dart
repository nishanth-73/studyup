import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../router/app_router.dart';
import '../backend/supabase_config.dart';
import '../../features/social/data/social_remote.dart';

/// Invitation deep-link intake (App Links plus custom-scheme fallback).
///
/// Accepted formats (the token is what matters, not the host):
/// an App Link with path `/i/TOKEN` on the configured HTTPS host
/// (verified when assetlinks plus the manifest host match; otherwise the
/// browser fallback page applies), or the custom scheme
/// `studyup://invite/TOKEN` which works with no hosting at all.
///
/// COLD start ([InviteLinks.consumeInitialLink], called from `main`
/// before `runApp`) and WARM links ([InviteLinks.start], subscribed after
/// the first frame) both end up on `/invite/TOKEN`. The token is stashed
/// as a pending invite when the recipient must sign in first, then
/// resumed after auth.
class InviteLinks {
  InviteLinks._();

  static const _pendingKey = 'studyup.pendingInviteToken.v1';
  static StreamSubscription<Uri>? _sub;
  static bool _started = false;

  /// Cold start: the link the app was LAUNCHED with.
  ///
  /// Called from `main()` BEFORE `runApp`, so the invitation code is in
  /// hand before any widget exists — navigating from the listener before
  /// the router is attached is what made the first tap fail. Returns the
  /// invitation code, `'invalid'` when the path looks like an invitation
  /// but carries no usable code (so the screen can show a friendly error),
  /// or null when the app was not opened from an invitation link.
  static Future<String?> consumeInitialLink() async {
    try {
      final initial = await AppLinks().getInitialLink();
      if (initial == null) return null;
      final token = parseInviteToken(initial);
      debugPrint('[invite] cold-start link $initial -> token ${token ?? 'none'}');
      if (token != null) return token;
      return _isInviteLink(initial) ? 'invalid' : null;
    } catch (error) {
      debugPrint('[invite] cold-start link intake failed: $error');
      return null;
    }
  }

  /// Starts listening for links delivered while the app is already open
  /// (warm starts, e.g. tapping the link again from the browser or from a
  /// chat app). Safe to call once from `main` after `runApp`; never throws.
  static Future<void> start() async {
    if (_started) return;
    _started = true;
    try {
      final links = AppLinks();
      _sub = links.uriLinkStream.listen(_route, onError: (_) {});
    } catch (error) {
      debugPrint('Invite links unavailable: $error');
    }
  }

  static void _route(Uri uri) {
    final parsedToken = parseInviteToken(uri);
    if (parsedToken == null && !_isInviteLink(uri)) return;
    final token = parsedToken ?? 'invalid';
    debugPrint('[invite] warm link $uri -> /invite/$token');
    try {
      appRouter.go('/invite/${Uri.encodeComponent(token)}');
    } catch (error) {
      debugPrint('[invite] navigation to /invite/$token failed: $error');
    }
  }

  static bool _isInviteLink(Uri uri) {
    final scheme = uri.scheme.toLowerCase();
    final path = uri.pathSegments.where((part) => part.isNotEmpty).toList();
    if (scheme == 'http' || scheme == 'https') {
      return path.isNotEmpty && (path.first == 'i' || path.first == 'invite');
    }
    if (scheme != 'studyup' &&
        scheme != SupabaseConfig.inviteScheme.toLowerCase()) {
      return false;
    }
    final host = uri.host.toLowerCase();
    return host == 'invite' ||
        host == 'i' ||
        (path.isNotEmpty && (path.first == 'invite' || path.first == 'i'));
  }

  /// Stash a token across the sign-in/onboarding flow.
  static Future<void> stashPending(String token) async {
    debugPrint('[invite] stashing pending token $token');
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_pendingKey, token);
  }

  static Future<String?> takePending() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString(_pendingKey);
    if (token != null && token.isNotEmpty) {
      await prefs.remove(_pendingKey);
      debugPrint('[invite] resumed pending token $token');
      return token;
    }
    return null;
  }

  /// Non-consuming peek for routing decisions (the owning screen calls
  /// [takePending] when it actually takes over the token).
  static Future<String?> peekPending() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString(_pendingKey);
    return (token != null && token.isNotEmpty) ? token : null;
  }

  static Future<void> dispose() async {
    await _sub?.cancel();
    _sub = null;
  }
}

/// Call from main() after runApp. Fire-and-forget by design.
void unawaitedInviteLinks() {
  // ignore: discarded_futures
  InviteLinks.start();
}
