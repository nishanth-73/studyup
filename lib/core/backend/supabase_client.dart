import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'supabase_config.dart';

/// Single reusable Supabase client for the whole app.
///
/// Initialized once in [main] via [initBackend]. When credentials are
/// missing the app keeps working fully offline (local demo mode) and
/// every social feature reports "Backend not connected" instead of
/// crashing or faking success. No secrets are stored here: the anon key
/// comes from dart-defines and RLS enforces all access server-side.
Future<void> initBackend() async {
  if (!SupabaseConfig.isConfigured) {
    debugPrint(
      'StudyUp backend: SUPABASE_URL/ANON_KEY missing — running offline.',
    );
    return;
  }
  try {
    await Supabase.initialize(
      url: SupabaseConfig.url,
      publishableKey: SupabaseConfig.anonKey,
    );
  } catch (error) {
    // Startup must never fail: offline mode covers storage/network faults.
    debugPrint('StudyUp backend init failed (offline mode): $error');
  }
}

/// True when a live Supabase client exists (initialized AND configured).
/// Screens gate every remote call on this — never assume connectivity.
final backendReadyProvider = Provider<bool>((ref) {
  if (!SupabaseConfig.isConfigured) return false;
  try {
    Supabase.instance.client;
    return true;
  } catch (_) {
    return false;
  }
});

/// Live Supabase client. Throws [StateError] when the backend is not
/// configured — callers must check [backendReadyProvider] first and show
/// the setup state instead.
SupabaseClient backendClient(WidgetRef ref) {
  if (!ref.watch(backendReadyProvider)) {
    throw StateError('Supabase backend is not connected.');
  }
  return Supabase.instance.client;
}
