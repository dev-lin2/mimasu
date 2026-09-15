package com.handypick.mimasu.downloads

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.IBinder
import androidx.core.app.NotificationCompat
import com.handypick.mimasu.MainActivity

/**
 * Keeps downloads running when the app is not in front.
 *
 * Android will kill ordinary background work within seconds of the user
 * leaving, and an episode takes minutes. A foreground service with a visible
 * notification is the only way to do this that the platform supports — and
 * the notification is not a formality, it is how the user stays aware that
 * their connection is in use.
 */
class DownloadService : Service() {

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        DownloadEngine.initialise(applicationContext)
        createChannel()
        DownloadEngine.onChanged = { refresh() }
    }

    override fun onStartCommand(
        intent: Intent?,
        flags: Int,
        startId: Int,
    ): Int {
        startForeground(NOTIFICATION_ID, buildNotification())
        refresh()
        // Restarting with no queue would leave an empty notification; the
        // engine's own index is what survives process death.
        return START_NOT_STICKY
    }

    override fun onDestroy() {
        DownloadEngine.onChanged = null
        super.onDestroy()
    }

    private fun refresh() {
        if (!DownloadEngine.hasWork()) {
            stopForeground(STOP_FOREGROUND_REMOVE)
            stopSelf()
            return
        }
        manager().notify(NOTIFICATION_ID, buildNotification())
    }

    private fun manager() =
        getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

    private fun createChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val channel = NotificationChannel(
            CHANNEL_ID,
            "Downloads",
            NotificationManager.IMPORTANCE_LOW,
        ).apply {
            description = "Progress for episodes being saved for offline"
            setShowBadge(false)
        }
        manager().createNotificationChannel(channel)
    }

    private fun buildNotification(): Notification {
        val active = DownloadEngine.active()
        val remaining = DownloadEngine.snapshot().count {
            it.state == DownloadEngine.State.QUEUED
        }

        val content = when {
            active == null && remaining == 0 -> "Finishing up"
            active == null -> "$remaining waiting"
            remaining == 0 -> active.subtitle
            else -> "${active.subtitle}  ·  $remaining waiting"
        }

        val builder = NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle(active?.title ?: "Downloading")
            .setContentText(content)
            .setSmallIcon(android.R.drawable.stat_sys_download)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setContentIntent(openApp())

        if (active != null) {
            val total = active.total
            if (total > 0) {
                val percent = (active.bytes * 100 / total)
                    .coerceIn(0, 100)
                    .toInt()
                builder.setProgress(100, percent, false)
            } else {
                builder.setProgress(0, 0, true)
            }
        }
        return builder.build()
    }

    private fun openApp(): PendingIntent = PendingIntent.getActivity(
        this,
        0,
        Intent(this, MainActivity::class.java),
        PendingIntent.FLAG_IMMUTABLE,
    )

    companion object {
        private const val CHANNEL_ID = "downloads"
        private const val NOTIFICATION_ID = 1001

        fun ensureRunning(context: Context) {
            val intent = Intent(context, DownloadService::class.java)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(intent)
            } else {
                context.startService(intent)
            }
        }
    }
}
