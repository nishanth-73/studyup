package com.studyup.studyup

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.content.res.Configuration
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.widget.RemoteViews
import androidx.core.app.NotificationCompat
import java.time.LocalDate
import java.time.ZoneId

/**
 * Foreground service behind the single ongoing Live Progress notification.
 *
 * - Started ONLY by an explicit user Check In (Dart side gates on the
 *   Live-progress preference) via ACTION_CHECKIN/ACTION_UPDATE intents.
 * - Ticks once per second on a Handler; every frame recomputes the
 *   displayed time from persisted timestamps (anchor + banked seconds),
 *   never from a tick counter, so the value stays exact.
 * - Local-day rollover is handled per tick: past-midnight seconds count
 *   toward the new day and yesterday never leaks into today.
 * - START_STICKY + persisted parameters let the OS restart the service
 *   after ordinary process death; check-out stops the ticks and leaves a
 *   dismissible frozen-time entry under the same notification id.
 * - No WorkManager, no exact alarms, no duplicate timers: one service,
 *   one notification id, one Handler loop.
 * - System appearance: the notification card background is owned by
 *   Android (DecoratedCustomViewStyle, never setColor/setColorized(true)
 *   and no hardcoded layout background), and all text uses
 *   TextAppearance.Compat.Notification.* so Light/Dark follows the
 *   phone's system uiMode — never the time of day. While running, the
 *   1s tick re-notifies and therefore re-applies the current theme
 *   within a second of a Light/Dark switch; while paused,
 *   onConfigurationChanged re-posts the frozen frame for the same
 *   reason.
 */
class StudyTimerService : Service() {

    private val handler = Handler(Looper.getMainLooper())
    private var ticking = false

    private var bankedSec: Long = 0
    private var anchorUtcMs: Long = 0
    private var goalMin: Int = 480
    private var dayKey: String = ""

    // Last posted frame, so a system Light/Dark (uiMode) change can
    // re-post the same content and let Android re-inflate the
    // RemoteViews in the new theme — even when paused (no ticks).
    private var lastElapsed: Long = 0
    private var lastPercent: Int = 0
    private var lastRunning: Boolean = false
    private var lastFrozenElapsed: Int? = null
    private var hasPostedFrame: Boolean = false

    private val tickRunnable = object : Runnable {
        override fun run() {
            if (!ticking) return
            postFrame(running = true)
            handler.postDelayed(this, 1000L)
        }
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_CHECKIN, ACTION_UPDATE -> {
                readExtras(intent)
                persist(running = true)
                beginForeground()
                beginTicks()
            }
            ACTION_CHECKOUT -> {
                val elapsed = intent.getIntExtra(EXTRA_ELAPSED_SEC, 0).coerceAtLeast(0)
                goalMin = intent.getIntExtra(EXTRA_GOAL_MIN, goalMin).coerceAtLeast(1)
                val day = intent.getStringExtra(EXTRA_DAY_KEY)
                if (!day.isNullOrEmpty()) dayKey = day
                persist(running = false, banked = elapsed.toLong())
                stopTicks()
                stopForegroundCompat(detach = true)
                postFrame(running = false, frozenElapsed = elapsed)
                stopSelf()
            }
            ACTION_CANCEL -> {
                persist(running = false)
                stopTicks()
                stopSelf()
                notificationManager().cancel(NOTIF_ID)
            }
            else -> {
                // Restart after process death (START_STICKY redelivery with
                // a null intent) or an explicit resume: recover from prefs.
                if (readPersisted()) {
                    beginForeground()
                    beginTicks()
                } else {
                    stopSelf()
                }
            }
        }
        return START_STICKY
    }

    override fun onDestroy() {
        stopTicks()
        super.onDestroy()
    }

    override fun onConfigurationChanged(newConfig: Configuration) {
        super.onConfigurationChanged(newConfig)
        // System Light/Dark switch: re-post the current frame (same id,
        // no duplicate) so Android re-inflates the RemoteViews with the
        // new theme's system colors. Running frames recompute elapsed
        // from timestamps; paused frames reuse the frozen value.
        if (!hasPostedFrame) return
        try {
            if (lastRunning && ticking) {
                postFrame(running = true)
            } else {
                postFrame(running = false, frozenElapsed = lastFrozenElapsed ?: lastElapsed.toInt())
            }
        } catch (_: Exception) {
            // Never crash the service on a theme re-apply.
        }
    }

    // ---------- ticking ----------

    private fun beginTicks() {
        if (ticking) return
        ticking = true
        handler.post(tickRunnable)
    }

    private fun stopTicks() {
        ticking = false
        handler.removeCallbacks(tickRunnable)
    }

    /** Recomputes and posts the tray entry; handles midnight rollover. */
    private fun postFrame(running: Boolean, frozenElapsed: Int? = null) {
        val today = LocalDate.now().toString()
        val elapsed: Long
        val midnightMs = LocalDate.now()
            .atStartOfDay(ZoneId.systemDefault())
            .toInstant()
            .toEpochMilli()
        if (running) {
            if (today != dayKey) {
                // New local day: today's count restarts; the Dart side's
                // midnight-split aggregation owns historical truth, this
                // entry only ever displays the current day.
                dayKey = today
                bankedSec = 0
                anchorUtcMs = midnightMs
                persist(running = true)
            }
            val now = System.currentTimeMillis()
            val liveAnchor = anchorUtcMs.coerceAtLeast(midnightMs)
            elapsed = bankedSec + ((now - liveAnchor) / 1000L).coerceAtLeast(0)
        } else {
            elapsed = (frozenElapsed?.toLong() ?: bankedSec).coerceAtLeast(0)
        }
        val percent = if (goalMin <= 0) {
            0
        } else {
            ((elapsed * 100L) / (goalMin * 60L)).coerceIn(0, 100).toInt()
        }
        lastElapsed = elapsed
        lastPercent = percent
        lastRunning = running
        lastFrozenElapsed = frozenElapsed ?: if (!running) elapsed.toInt() else lastFrozenElapsed
        hasPostedFrame = true
        notificationManager().notify(NOTIF_ID, buildNotification(elapsed, percent, running))
    }

    // ---------- notification ----------

    private fun liveViews(
        elapsedSec: Long,
        percent: Int,
        expanded: Boolean,
    ): RemoteViews {
        val views = RemoteViews(
            packageName,
            if (expanded) {
                R.layout.live_progress_notification_expanded
            } else {
                R.layout.live_progress_notification
            },
        )
        views.setTextViewText(R.id.live_timer, formatHms(elapsedSec))
        views.setProgressBar(R.id.live_bar, 100, percent, false)
        return views
    }

    private fun buildNotification(
        elapsedSec: Long,
        percent: Int,
        running: Boolean,
    ): Notification {
        ensureChannel(notificationManager())
        val builder = NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_stat_studyup)
            .setCustomContentView(liveViews(elapsedSec, percent, expanded = false))
            .setCustomBigContentView(liveViews(elapsedSec, percent, expanded = true))
            .setStyle(NotificationCompat.DecoratedCustomViewStyle())
            // System owns the card: never setColor()/colorized-custom-bg.
            // setColorized(false) keeps the native Light/Dark notification
            // background (and icon treatment) instead of forcing our own.
            .setColorized(false)
            .setOngoing(running)
            .setAutoCancel(false)
            .setOnlyAlertOnce(true)
            .setPriority(NotificationCompat.PRIORITY_DEFAULT)
        launchIntent()?.let { builder.setContentIntent(it) }
        return builder.build()
    }

    private fun beginForeground() {
        // startForeground itself posts the entry, so no separate notify()
        // call (and no duplicate) is needed here.
        val notification = buildNotification(
            elapsedSec = currentElapsed(),
            percent = currentPercent(),
            running = true,
        )
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                startForeground(
                    NOTIF_ID,
                    notification,
                    ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC,
                )
            } else {
                @Suppress("DEPRECATION")
                startForeground(NOTIF_ID, notification)
            }
        } catch (security: SecurityException) {
            // Missing runtime state (e.g. revoked permission path):
            // never crash the app from the service; timing truth lives
            // in the Dart session store regardless.
            stopSelf()
        }
    }

    private fun stopForegroundCompat(detach: Boolean) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            stopForeground(
                if (detach) {
                    STOP_FOREGROUND_DETACH
                } else {
                    STOP_FOREGROUND_REMOVE
                },
            )
        } else {
            @Suppress("DEPRECATION")
            stopForeground(detach)
        }
    }

    private fun currentElapsed(): Long {
        val midnightMs = LocalDate.now()
            .atStartOfDay(ZoneId.systemDefault())
            .toInstant()
            .toEpochMilli()
        val liveAnchor = anchorUtcMs.coerceAtLeast(midnightMs)
        return bankedSec +
            ((System.currentTimeMillis() - liveAnchor) / 1000L).coerceAtLeast(0)
    }

    private fun currentPercent(): Int {
        if (goalMin <= 0) return 0
        return ((currentElapsed() * 100L) / (goalMin * 60L))
            .coerceIn(0, 100)
            .toInt()
    }

    private fun formatHms(totalSeconds: Long): String {
        val h = (totalSeconds / 3600).toString().padStart(2, '0')
        val m = ((totalSeconds % 3600) / 60).toString().padStart(2, '0')
        val s = (totalSeconds % 60).toString().padStart(2, '0')
        return "$h:$m:$s"
    }

    // ---------- persistence ----------

    private fun prefs() = getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

    private fun readExtras(intent: Intent) {
        bankedSec = intent
            .getIntExtra(EXTRA_BANKED_SEC, bankedSec.coerceAtMost(3600000).toInt())
            .toLong()
            .coerceAtLeast(0)
        val anchor = intent.getLongExtra(EXTRA_ANCHOR_MS, anchorUtcMs)
        if (anchor > 0) anchorUtcMs = anchor
        goalMin = intent.getIntExtra(EXTRA_GOAL_MIN, goalMin).coerceAtLeast(1)
        val day = intent.getStringExtra(EXTRA_DAY_KEY)
        if (!day.isNullOrEmpty()) dayKey = day
    }

    private fun persist(running: Boolean, banked: Long? = null) {
        prefs().edit()
            .putLong(KEY_BANKED, banked ?: bankedSec)
            .putLong(KEY_ANCHOR, anchorUtcMs)
            .putInt(KEY_GOAL, goalMin)
            .putString(KEY_DAY, dayKey)
            .putBoolean(KEY_RUNNING, running)
            .apply()
    }

    private fun readPersisted(): Boolean {
        val p = prefs()
        if (!p.getBoolean(KEY_RUNNING, false)) return false
        bankedSec = p.getLong(KEY_BANKED, 0)
        anchorUtcMs = p.getLong(KEY_ANCHOR, 0)
        goalMin = p.getInt(KEY_GOAL, 480).coerceAtLeast(1)
        dayKey = p.getString(KEY_DAY, "") ?: ""
        return true
    }

    // ---------- platform helpers ----------

    private fun notificationManager(): NotificationManager =
        getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

    private fun ensureChannel(manager: NotificationManager) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            manager.createNotificationChannel(
                NotificationChannel(
                    CHANNEL_ID,
                    "Study sessions",
                    NotificationManager.IMPORTANCE_DEFAULT,
                ),
            )
        }
    }

    private fun launchIntent(): PendingIntent? {
        val intent: android.content.Intent =
            packageManager.getLaunchIntentForPackage(packageName) ?: return null
        var flags = PendingIntent.FLAG_UPDATE_CURRENT
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            flags = flags or PendingIntent.FLAG_IMMUTABLE
        }
        return PendingIntent.getActivity(this, 0, intent, flags)
    }

    companion object {
        const val CHANNEL_ID = "studyup_session"

        /** Must stay identical to the Dart liveNotificationId. */
        const val NOTIF_ID = 0x5E5510

        const val ACTION_CHECKIN = "com.studyup.studyup.action.CHECKIN"
        const val ACTION_UPDATE = "com.studyup.studyup.action.UPDATE"
        const val ACTION_CHECKOUT = "com.studyup.studyup.action.CHECKOUT"
        const val ACTION_CANCEL = "com.studyup.studyup.action.CANCEL"
        const val ACTION_RESUME = "com.studyup.studyup.action.RESUME"

        const val EXTRA_BANKED_SEC = "bankedSec"
        const val EXTRA_ANCHOR_MS = "anchorUtcMs"
        const val EXTRA_GOAL_MIN = "goalMin"
        const val EXTRA_DAY_KEY = "dayKey"
        const val EXTRA_ELAPSED_SEC = "elapsedSec"

        private const val PREFS_NAME = "studyup.fgs.v1"
        private const val KEY_BANKED = "bankedSec"
        private const val KEY_ANCHOR = "anchorUtcMs"
        private const val KEY_GOAL = "goalMin"
        private const val KEY_DAY = "dayKey"
        private const val KEY_RUNNING = "running"
    }
}
