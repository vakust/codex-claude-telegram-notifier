package com.vakust.notifierv3.ui

import android.Manifest
import android.app.PendingIntent
import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.media.AudioAttributes
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import com.vakust.notifierv3.MainActivity
import com.vakust.notifierv3.R
import com.vakust.notifierv3.model.EventItem

class EventNotifier(private val context: Context) {
    private val managerCompat = NotificationManagerCompat.from(context)

    fun notificationsPermissionGranted(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) return true
        return ContextCompat.checkSelfPermission(
            context,
            Manifest.permission.POST_NOTIFICATIONS
        ) == PackageManager.PERMISSION_GRANTED
    }

    fun postEventNotification(item: EventItem, soundEnabled: Boolean) {
        if (!notificationsPermissionGranted()) return
        if (!managerCompat.areNotificationsEnabled()) return

        ensureChannels()
        val source = displaySource(item.source)
        val type = item.type.lowercase()
        val title = when (type) {
            "done" -> "$source done"
            "command_failed" -> "$source failed"
            "last_text" -> "$source final text"
            else -> "$source update"
        }
        val body = extractPayloadText(item.payload).ifBlank {
            "${item.type} at ${item.ts}"
        }.take(280)

        val channelId = if (soundEnabled) CHANNEL_SOUND else CHANNEL_SILENT
        val builder = NotificationCompat.Builder(context, channelId)
            .setSmallIcon(R.drawable.ic_stat_notifier)
            .setContentTitle(title)
            .setContentText(body)
            .setStyle(NotificationCompat.BigTextStyle().bigText(body))
            .setContentIntent(buildOpenAppIntent(item))
            .setAutoCancel(true)
            .setPriority(NotificationCompat.PRIORITY_HIGH)

        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
            if (soundEnabled) {
                builder.setDefaults(NotificationCompat.DEFAULT_SOUND or NotificationCompat.DEFAULT_VIBRATE)
            } else {
                builder.setSilent(true)
            }
        } else {
            builder.setSilent(!soundEnabled)
        }

        managerCompat.notify(stableId(item), builder.build())
    }

    private fun buildOpenAppIntent(item: EventItem): PendingIntent {
        val openIntent = Intent(context, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP
            putExtra("from_notification", true)
            putExtra("event_id", item.event_id)
            putExtra("event_type", item.type)
            putExtra("event_source", item.source)
        }
        val requestCode = stableId(item)
        val flags = PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        return PendingIntent.getActivity(context, requestCode, openIntent, flags)
    }

    private fun ensureChannels() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val mgr = context.getSystemService(Context.NOTIFICATION_SERVICE) as? NotificationManager ?: return

        val soundUri: Uri = Settings.System.DEFAULT_NOTIFICATION_URI
        val attrs = AudioAttributes.Builder()
            .setUsage(AudioAttributes.USAGE_NOTIFICATION)
            .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
            .build()

        val soundChannel = NotificationChannel(
            CHANNEL_SOUND,
            "Notifier events (sound)",
            NotificationManager.IMPORTANCE_HIGH
        ).apply {
            description = "Final messages and failures with sound."
            enableVibration(true)
            setSound(soundUri, attrs)
        }
        val silentChannel = NotificationChannel(
            CHANNEL_SILENT,
            "Notifier events (silent)",
            NotificationManager.IMPORTANCE_LOW
        ).apply {
            description = "Final messages and failures without sound."
            setSound(null, null)
            enableVibration(false)
        }
        mgr.createNotificationChannel(soundChannel)
        mgr.createNotificationChannel(silentChannel)
    }

    private fun stableId(item: EventItem): Int {
        val key = if (item.event_id.isNotBlank()) item.event_id else "${item.ts}|${item.source}|${item.type}"
        return key.hashCode()
    }

    private fun displaySource(source: String): String {
        return when {
            source.equals("codex", ignoreCase = true) -> "Codex"
            source.equals("cc", ignoreCase = true) -> "Cloud Code"
            source.isBlank() -> "Notifier"
            else -> source
        }
    }

    private fun extractPayloadText(payload: Map<String, Any?>): String {
        val preferred = listOf("text", "message", "caption", "summary", "status", "note", "body")
        for (key in preferred) {
            val value = payload[key] ?: continue
            val out = value.toString().trim()
            if (out.isNotBlank()) return out
        }
        return payload.entries
            .take(2)
            .joinToString(" | ") { "${it.key}=${it.value}" }
    }

    companion object {
        private const val CHANNEL_SOUND = "notifier_events_sound"
        private const val CHANNEL_SILENT = "notifier_events_silent"
    }
}
