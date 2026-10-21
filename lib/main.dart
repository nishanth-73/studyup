import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/backend/feedback_config.dart';
import 'core/backend/supabase_client.dart';
import 'core/backend/supabase_config.dart';
import 'core/notifications/notification_service.dart';
import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'features/auth/data/auth_controller.dart';
import 'features/social/data/social_providers.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Local notifications are initialized exactly once at startup so
  // controllers can schedule reminders from anywhere afterwards.
  // Startup itself must never fail: even if device storage or the
  // notification plugin is broken, the app still launches and studies.
  try {
    await NotificationService.instance.init().timeout(
      const Duration(seconds: 5),
    );
  } catch (error, stackTrace) {
    debugPrint(
      '[notifications] initialization failed; continuing without OS alerts: '
      '$error\n$stackTrace',
    );
  }
  // Local `.env` fallback for SUPABASE_URL / SUPABASE_ANON_KEY
  // (dart-defines still win). Absent or unreadable file = offline mode.
  try {
    await dotenv.load(fileName: '.env');
    SupabaseConfig.loadFileEnv(dotenv.env);
    FeedbackConfig.loadFileEnv(dotenv.env);
  } catch (_) {
    // No .env — dart-defines or offline mode apply.
  }
  // Supabase backend (graceful offline when credentials are missing).
  await initBackend();
  runApp(
    ProviderScope(
      // No stretch overscroll anywhere: on Android the stretch effect
      // distorts list content past its bounds — straight under the
      // transparent floating nav buttons, where it reads as "clipped".
      // Edge glow keeps overscroll feedback without moving content.
      child: ScrollConfiguration(
        behavior: const MaterialScrollBehavior().copyWith(overscroll: false),
        child: const StudyUpApp(),
      ),
    ),
  );
}

/// App root.
///
/// It keeps [sessionSyncTriggerProvider] alive after startup navigation,
/// but only for the account verified as the owner of this device's local
/// study data. A different signed-in account never syncs these records.
class StudyUpApp extends ConsumerWidget {
  const StudyUpApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final userId = ref.watch(backendUserIdProvider);
    if (userId != null &&
        ref.watch(localAccountDataAccessProvider(userId)).valueOrNull == true) {
      ref.watch(sessionSyncTriggerProvider);
    }
    return MaterialApp.router(
      title: 'StudyUp — Phase 1 UI',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark,
      darkTheme: AppTheme.dark,
      themeMode: ThemeMode.dark,
      routerConfig: appRouter,
    );
  }
}
