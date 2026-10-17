package com.studyup.studyup

import android.content.Intent
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * Hosts the "studyup/study_timer" channel. Dart drives the single
 * [StudyTimerService] through it (check-in, parameter updates, check-out,
 * cancel); the service owns the one ongoing Live Progress notification.
 * Failures are reported back so Dart can log them — study tracking itself
 * never depends on this bridge.
 */
class MainActivity : FlutterActivity() {
    private val timerChannelName = "studyup/study_timer"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            timerChannelName,
        ).setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "checkIn", "update" -> {
                        val action = if (call.method == "checkIn") {
                            StudyTimerService.ACTION_CHECKIN
                        } else {
                            StudyTimerService.ACTION_UPDATE
                        }
                        startTimerService(action, call)
                        result.success(null)
                    }
                    "checkOut" -> {
                        val intent = Intent(this, StudyTimerService::class.java).apply {
                            this.action = StudyTimerService.ACTION_CHECKOUT
                            putExtra(
                                StudyTimerService.EXTRA_ELAPSED_SEC,
                                (call.argument<Int>("elapsedSec") ?: 0),
                            )
                            putExtra(
                                StudyTimerService.EXTRA_GOAL_MIN,
                                (call.argument<Int>("goalMin") ?: 480),
                            )
                            call.argument<String>("dayKey")?.let {
                                putExtra(StudyTimerService.EXTRA_DAY_KEY, it)
                            }
                        }
                        // Plain startService: check-out never foregrounds
                        // (it stops ticks and posts a dismissible entry), so
                        // startForegroundService would impose an FGS duty the
                        // service never fulfills — that kills the app.
                        startService(intent)
                        result.success(null)
                    }
                    "cancel" -> {
                        val intent = Intent(this, StudyTimerService::class.java).apply {
                            this.action = StudyTimerService.ACTION_CANCEL
                        }
                        // Same as above: teardown must not use
                        // startForegroundService.
                        startService(intent)
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            } catch (e: Exception) {
                result.error("TIMER_SERVICE", e.message, null)
            }
        }
    }

    private fun startTimerService(action: String, call: MethodCall) {
        val intent = Intent(this, StudyTimerService::class.java).apply {
            this.action = action
            putExtra(
                StudyTimerService.EXTRA_BANKED_SEC,
                (call.argument<Int>("bankedSec") ?: 0),
            )
            putExtra(
                StudyTimerService.EXTRA_ANCHOR_MS,
                (call.argument<Number>("anchorUtcMs")?.toLong() ?: 0L),
            )
            putExtra(
                StudyTimerService.EXTRA_GOAL_MIN,
                (call.argument<Int>("goalMin") ?: 480),
            )
            call.argument<String>("dayKey")?.let {
                putExtra(StudyTimerService.EXTRA_DAY_KEY, it)
            }
        }
        startTimerServiceIntent(intent)
    }

    private fun startTimerServiceIntent(intent: Intent) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            startForegroundService(intent)
        } else {
            startService(intent)
        }
    }
}
