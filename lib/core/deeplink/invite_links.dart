import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../router/app_router.dart';
import '../../features/social/data/social_remote.dart';

/// Invitation deep-link intake (App Links plus custom-scheme fallback).
///
/// Accepted formats (the token is what matters, not the host):
/// an App Link with path `/i/TOKEN` on the configured HTTPS host
/// (verified when assetlinks plus the manifest host match; otherwise the
/// browser fallback page applies), or the custom scheme
/// `studyup://invite/TOKEN` which works with no hosting at all.
///
/// Cold start ([AppLinks.getInitialLink]) and warm links
/// ([AppLinks.uriLinkStream]) both route to `/invite/TOKEN`. The token is
/// held as a pending invite when the recipient must sign in first, then
/// resumed after auth.
class InviteLinks {
  InviteLinks._();

  static const _pendingKey = 'studyup.pendingInviteToken.v1';
  static StreamSubscription<Uri>? _sub;
  static bool _started = false;

  /// Starts listening. Safe to call once from [main]; never throws.
  static Future<void> start() async {
    if (_started) return;
    _started = true;
    try {
      final links = AppLinks();
      final initial = await links.getInitialLink();
      if (initial != null) _route(initial);
      _sub = links.uriLinkStream.listen(_route, onError: (_) {});
    } catch (error) {
      debugPrint('Invite links unavailable: $error');
    }
  }

  static void _route(Uri uri) {
    final token = parseInviteToken(uri);
    if (token == null) return;
    try {
      appRouter.go('/invite/$token');
    } catch (error) {
      debugPrint('Invite route failed: $error');
    }
  }

  /// Stash a token across the sign-in/onboarding flow.
  static Future<void> stashPending(String token) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_pendingKey, token);
  }

  static Future<String?> takePending() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString(_pendingKey);
    if (token != null && token.isNotEmpty) {
      await prefs.remove(_pendingKey);
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
