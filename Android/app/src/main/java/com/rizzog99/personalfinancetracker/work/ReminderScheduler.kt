package com.rizzog99.personalfinancetracker.work

import androidx.work.ExistingPeriodicWorkPolicy
import androidx.work.PeriodicWorkRequestBuilder
import androidx.work.WorkManager
import com.rizzog99.personalfinancetracker.data.preferences.UserPreferencesRepository
import java.time.Duration
import java.time.LocalTime
import java.time.ZonedDateTime
import java.time.temporal.ChronoUnit
import java.util.concurrent.TimeUnit
import kotlinx.coroutines.flow.first

/**
 * The single path from the stored reminder preferences to WorkManager (#129).
 *
 * It lives outside `PersonalFinanceApplication` so a test can drive the real production path with
 * an injected clock, and it holds no default of its own — the time always comes from
 * [UserPreferencesRepository.dailyReminderTime].
 */
object ReminderScheduler {

    /**
     * Wall-clock delay from [now] to the next [time]. A time that is exactly now counts as past,
     * so the reminder lands tomorrow rather than immediately.
     */
    fun initialDelay(now: ZonedDateTime, time: LocalTime): Duration {
        // Measured from whole seconds: the enqueued delay is expressed in seconds, and letting a
        // part-second remainder be truncated away would fire the reminder in the minute before the
        // one the user picked (20:59 for a 21:00 reminder).
        val from = now.truncatedTo(ChronoUnit.SECONDS)
        val today = from.with(time)
        val next = if (today.isAfter(from)) today else today.plusDays(1)
        return Duration.between(from, next)
    }

    /**
     * Enqueues the one daily reminder at [time] and returns the delay it was scheduled with.
     *
     * `CANCEL_AND_REENQUEUE`, not `KEEP`: with `KEEP` a changed time would be silently ignored and
     * the reminder would keep firing at the old one (AC-04). Duplicates are prevented by the unique
     * name, not by the policy — the policy only decides whose schedule wins.
     */
    fun schedule(
        workManager: WorkManager,
        time: LocalTime,
        now: ZonedDateTime = ZonedDateTime.now(),
    ): Duration {
        val delay = initialDelay(now, time)
        workManager.enqueueUniquePeriodicWork(
            DailyReminderWorker.WORK_NAME,
            ExistingPeriodicWorkPolicy.CANCEL_AND_REENQUEUE,
            PeriodicWorkRequestBuilder<DailyReminderWorker>(1, TimeUnit.DAYS)
                .setInitialDelay(delay.seconds, TimeUnit.SECONDS)
                .build(),
        )
        return delay
    }

    fun cancel(workManager: WorkManager) {
        workManager.cancelUniqueWork(DailyReminderWorker.WORK_NAME)
    }

    /**
     * Brings the enqueued work in line with what is stored: scheduled at the stored time when the
     * reminder is on, cancelled when it is off. Returns the delay used, or null when cancelled.
     */
    suspend fun apply(
        workManager: WorkManager,
        preferences: UserPreferencesRepository,
        now: ZonedDateTime = ZonedDateTime.now(),
    ): Duration? = if (preferences.dailyReminderEnabled.first()) {
        schedule(workManager, preferences.dailyReminderTime.first(), now)
    } else {
        cancel(workManager)
        null
    }
}
