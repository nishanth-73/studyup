import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/backend/feedback_config.dart';
import 'core/backend/supabase_client.dart';
import 'core/backend/supabase_config.dart';
import 'core/deeplink/invite_links.dart';
import 'core/notifications/notification_service.dart';
import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Local notifications are initialized exactly once at startup so
  // controllers can schedule reminders from anywhere afterwards.
  // Startup itself must never fail: even if device storage or the
  // notification plugin is broken, the app still launches and studies.
  try {
    await NotificationService.instance.init();
  } catch (_) {
    // Intentionally silent: timer/screens work without notifications.
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
  // Deep-link intake (invite URLs + custom scheme) for warm and cold
  // starts. No-ops until the first link arrives.
  unawaitedInviteLinks();
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

class StudyUpApp extends StatelessWidget {
  const StudyUpApp({super.key});
  @override
  Widget build(BuildContext context) {
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
