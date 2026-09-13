package com.rizzog99.personalfinancetracker.work

import android.app.PendingIntent
import android.content.Context
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.work.CoroutineWorker
import androidx.work.WorkerParameters
import com.rizzog99.personalfinancetracker.MainActivity
import com.rizzog99.personalfinancetracker.R

class DailyReminderWorker(
    context: Context,
    params: WorkerParameters,
) : CoroutineWorker(context, params) {
    override suspend fun doWork(): Result = try {
        val intent = MainActivity::class.java.let { clazz ->
            PendingIntent.getActivity(
                applicationContext,
                0,
                android.content.Intent(applicationContext, clazz),
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
        }

        val notification = NotificationCompat.Builder(applicationContext, CHANNEL_ID)
            .setSmallIcon(android.R.drawable.ic_dialog_info)
            .setContentTitle(applicationContext.getString(R.string.daily_reminder_notification_title))
            .setContentText(applicationContext.getString(R.string.daily_reminder_notification_message))
            .setPriority(NotificationCompat.PRIORITY_DEFAULT)
            .setContentIntent(intent)
            .setAutoCancel(true)
            .build()

        NotificationManagerCompat.from(applicationContext).notify(NOTIFICATION_ID, notification)
        Result.success()
    } catch (e: Exception) {
        Result.retry()
    }

    companion object {
        const val CHANNEL_ID = "daily_reminder"
        const val NOTIFICATION_ID = 1
        const val WORK_NAME = "daily_reminder"
    }
}
