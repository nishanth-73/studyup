import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Platform bridge to the native study-timer foreground service
/// (Android: exact 4-line RemoteViews card, 1s ticks, survives recents
/// removal via START_STICKY). Every call is safe on all platforms:
/// unsupported platforms, widget tests, and a missing native handler
/// resolve to a silent no-op so study logic and the in-app timer keep
/// working regardless. Study tracking never depends on this bridge.
class StudyTimerBridge {
  StudyTimerBridge._();

  static const MethodChannel _channel = MethodChannel('studyup/study_timer');

  static Future<void> _call(String method, [Map<String, Object>? args]) async {
    try {
      await _channel.invokeMethod(method, args);
    } on MissingPluginException catch (_) {
      // Tests, non-Android platforms, or an older install: no handler.
    } on AssertionError catch (_) {
      // Plain unit tests run without a Flutter binding.
    } on StateError catch (_) {
      // Same as above for late/uninitialized bindings.
    } catch (error, stackTrace) {
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stackTrace,
          library: 'study timer bridge',
          context: ErrorDescription('while calling $method'),
        ),
      );
    }
  }

  /// Starts (or adopts) the foreground service with fresh anchor/goal
  /// parameters. Idempotent: calling it twice never spawns a duplicate.
  static Future<void> checkIn({
    required int bankedSec,
    required int anchorUtcMs,
    required int goalMin,
    required String dayKey,
  }) => _call('checkIn', {
    'bankedSec': bankedSec,
    'anchorUtcMs': anchorUtcMs,
    'goalMin': goalMin,
    'dayKey': dayKey,
  });

  /// Pushes fresh parameters (resume, goal change, restart adopt) to the
  /// running service. Starts it if it died while a session is active.
  static Future<void> update({
    required int bankedSec,
    required int anchorUtcMs,
    required int goalMin,
    required String dayKey,
  }) => _call('update', {
    'bankedSec': bankedSec,
    'anchorUtcMs': anchorUtcMs,
    'goalMin': goalMin,
    'dayKey': dayKey,
  });

  /// Stops the ticks and flips the same tray entry to a dismissible
  /// frozen-time status. Accumulated duration is preserved Dart-side.
  static Future<void> checkOut({
    required int elapsedSec,
    required int goalMin,
    required String dayKey,
  }) => _call('checkOut', {
    'elapsedSec': elapsedSec,
    'goalMin': goalMin,
    'dayKey': dayKey,
  });

  /// Stops the service (if any) and clears the tray entry.
  static Future<void> cancel() => _call('cancel');
}
