package com.studyup.studyup

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build

/**
 * Restarts the study timer after a reboot or app update, but ONLY when a
 * session was actively checked in (persisted running flag). Ordinary
 * process death is already covered by START_STICKY; this receiver covers
 * the boot/update case. All failures are swallowed: background recovery
 * must never crash the receiver.
 */
class StudyTimerBootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent?) {
        val action = intent?.action ?: return
        if (action != Intent.ACTION_BOOT_COMPLETED &&
            action != Intent.ACTION_MY_PACKAGE_REPLACED
        ) {
            return
        }
        try {
            val prefs = context.getSharedPreferences(
                "studyup.fgs.v1",
                Context.MODE_PRIVATE,
            )
            if (!prefs.getBoolean("running", false)) return
            val resume = Intent(context, StudyTimerService::class.java).apply {
                this.action = StudyTimerService.ACTION_RESUME
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(resume)
            } else {
                context.startService(resume)
            }
        } catch (_: Exception) {
            // Recovery is best-effort (OEM/background restrictions apply).
        }
    }
}
