package com.rizzog99.personalfinancetracker.work

import android.content.Context
import androidx.datastore.core.DataStore
import androidx.datastore.preferences.core.PreferenceDataStoreFactory
import androidx.datastore.preferences.core.Preferences
import androidx.datastore.preferences.preferencesDataStoreFile
import androidx.test.core.app.ApplicationProvider
import androidx.work.Configuration
import androidx.work.WorkInfo
import androidx.work.WorkManager
import androidx.work.testing.SynchronousExecutor
import androidx.work.testing.WorkManagerTestInitHelper
import com.rizzog99.personalfinancetracker.data.preferences.UserPreferencesRepository
import java.io.File
import java.time.Duration
import java.time.Instant
import java.time.LocalTime
import java.time.ZoneId
import java.time.ZonedDateTime
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancelAndJoin
import kotlinx.coroutines.runBlocking
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertNull
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner

/**
 * Parity #129 (child of #118 `M1-DATA-PREFS`), AC-01 to AC-04.
 *
 * These drive the production [ReminderScheduler] against a real WorkManager (the test
 * initializer's, with a synchronous executor) and a real file-backed preferences DataStore, so the
 * assertions are about WorkManager's own scheduling state rather than about a mock.
 */
@RunWith(RobolectricTestRunner::class)
class ReminderSchedulerTest {

    private lateinit var context: Context
    private lateinit var workManager: WorkManager
    private lateinit var file: File
    private var session: StoreSession? = null

    @Before
    fun setUp() {
        context = ApplicationProvider.getApplicationContext()
        WorkManagerTestInitHelper.initializeTestWorkManager(
            context,
            Configuration.Builder().setExecutor(SynchronousExecutor()).build(),
        )
        workManager = WorkManager.getInstance(context)
        file = context.preferencesDataStoreFile("reminder_scheduler_ac")
        file.delete()
    }

    @After
    fun tearDown() = runBlocking {
        session?.close()
        file.delete()
        Unit
    }

    @Test
    fun `AC-01 a clean install schedules the reminder at 21 00, not at 20 00`() = runBlocking {
        val repository = UserPreferencesRepository(openStore())
        repository.setDailyReminderEnabled(true)

        ReminderScheduler.apply(workManager, repository, NOW)

        assertEquals(LocalTime.of(21, 0), scheduledLocalTime())
        assertNotEquals(LocalTime.of(20, 0), scheduledLocalTime())
    }

    @Test
    fun `AC-02 scheduling consumes the persisted time, whatever it is`() = runBlocking {
        // Discrimination: identical bodies, only the stored preference differs. An implementation
        // with any time of its own fails at least one of these.
        listOf(LocalTime.of(7, 30), LocalTime.of(0, 0), LocalTime.of(23, 59), LocalTime.of(12, 15))
            .forEach { stored ->
                val repository = UserPreferencesRepository(openStore())
                repository.setDailyReminderEnabled(true)
                repository.setDailyReminderTime(stored)

                ReminderScheduler.apply(workManager, repository, NOW)

                assertEquals(stored, scheduledLocalTime())
                session?.close()
                file.delete()
            }
    }

    @Test
    fun `AC-02 a time stored before a restart is the one scheduled after it`() = runBlocking {
        UserPreferencesRepository(openStore()).apply {
            setDailyReminderEnabled(true)
            setDailyReminderTime(LocalTime.of(6, 5))
        }

        // Store closed and rebuilt over the same file: the closest a JVM test gets to a relaunch,
        // and the only source the scheduler is allowed to read from.
        val reopened = UserPreferencesRepository(restart())
        ReminderScheduler.apply(workManager, reopened, NOW)

        assertEquals(LocalTime.of(6, 5), scheduledLocalTime())
    }

    @Test
    fun `AC-04 changing the time replaces the enqueued work instead of keeping it`() = runBlocking {
        val repository = UserPreferencesRepository(openStore())
        repository.setDailyReminderEnabled(true)
        repository.setDailyReminderTime(LocalTime.of(21, 0))
        ReminderScheduler.apply(workManager, repository, NOW)
        val firstId = singleActiveWork().id

        repository.setDailyReminderTime(LocalTime.of(7, 30))
        ReminderScheduler.apply(workManager, repository, NOW)

        // ExistingPeriodicWorkPolicy.KEEP would leave `firstId` enqueued at 21:00 and both of
        // these would fail.
        assertNotEquals(firstId, singleActiveWork().id)
        assertEquals(LocalTime.of(7, 30), scheduledLocalTime())
    }

    @Test
    fun `AC-04 repeated scheduling never produces a second reminder`() = runBlocking {
        val repository = UserPreferencesRepository(openStore())
        repository.setDailyReminderEnabled(true)

        repeat(5) { ReminderScheduler.apply(workManager, repository, NOW) }
        repository.setDailyReminderTime(LocalTime.of(8, 0))
        repeat(5) { ReminderScheduler.apply(workManager, repository, NOW) }

        assertEquals(1, activeWork().size)
        assertEquals(LocalTime.of(8, 0), scheduledLocalTime())
    }

    @Test
    fun `AC-04 disabling cancels the work and re-enabling uses the latest stored time`() = runBlocking {
        val repository = UserPreferencesRepository(openStore())
        repository.setDailyReminderEnabled(true)
        ReminderScheduler.apply(workManager, repository, NOW)
        assertEquals(1, activeWork().size)

        repository.setDailyReminderEnabled(false)
        assertNull(ReminderScheduler.apply(workManager, repository, NOW))
        assertEquals(emptyList<WorkInfo>(), activeWork())

        // Time changed while the reminder was off: re-enabling must pick up the new one.
        repository.setDailyReminderTime(LocalTime.of(9, 45))
        repository.setDailyReminderEnabled(true)
        ReminderScheduler.apply(workManager, repository, NOW)

        assertEquals(1, activeWork().size)
        assertEquals(LocalTime.of(9, 45), scheduledLocalTime())
    }

    @Test
    fun `AC-04 a reminder that is off is never enqueued in the first place`() = runBlocking {
        val repository = UserPreferencesRepository(openStore())

        assertNull(ReminderScheduler.apply(workManager, repository, NOW))

        assertEquals(emptyList<WorkInfo>(), activeWork())
    }

    @Test
    fun `the delay runs to today when the time is still ahead and to tomorrow otherwise`() {
        val now = ZonedDateTime.of(2026, 3, 10, 18, 30, 0, 0, ZoneId.of("Europe/Rome"))

        assertEquals(Duration.ofMinutes(150), ReminderScheduler.initialDelay(now, LocalTime.of(21, 0)))
        assertEquals(Duration.ofHours(24) - Duration.ofMinutes(30), ReminderScheduler.initialDelay(now, LocalTime.of(18, 0)))
        // Exactly now counts as past: fire tomorrow rather than instantly.
        assertEquals(Duration.ofHours(24), ReminderScheduler.initialDelay(now, LocalTime.of(18, 30)))
        // Whole seconds, so the enqueued delay cannot be truncated into the wrong minute: a
        // part-second `now` still lands exactly on 21:00 rather than a second before it.
        assertEquals(0, ReminderScheduler.initialDelay(now, LocalTime.of(7, 0)).nano)
        assertEquals(
            Duration.ofMinutes(150) - Duration.ofSeconds(41),
            ReminderScheduler.initialDelay(now.withSecond(41).withNano(900_000_000), LocalTime.of(21, 0)),
        )
    }

    /**
     * The wall-clock time WorkManager will next run the reminder at. This is WorkManager's own
     * state, read back from the enqueued [WorkInfo], not a value the scheduler reported.
     */
    private fun scheduledLocalTime(): LocalTime =
        Instant.ofEpochMilli(singleActiveWork().nextScheduleTimeMillis)
            .atZone(ZoneId.systemDefault())
            .toLocalTime()
            .withSecond(0)
            .withNano(0)

    private fun singleActiveWork(): WorkInfo = activeWork().single()

    /** Cancelled rows can linger briefly after a replace; only unfinished work is a reminder. */
    private fun activeWork(): List<WorkInfo> =
        workManager.getWorkInfosForUniqueWork(DailyReminderWorker.WORK_NAME).get()
            .filter { !it.state.isFinished }

    private fun openStore(): DataStore<Preferences> = StoreSession(file).also { session = it }.store

    private suspend fun restart(): DataStore<Preferences> {
        requireNotNull(session).close()
        return openStore()
    }

    private class StoreSession(file: File) {
        private val job = SupervisorJob()
        private val scope = CoroutineScope(Dispatchers.IO + job)
        val store: DataStore<Preferences> = PreferenceDataStoreFactory.create(scope = scope) { file }

        suspend fun close() = job.cancelAndJoin()
    }

    private companion object {
        /**
         * WorkManager stamps `nextScheduleTimeMillis` from the real clock plus the delay, so the
         * delay has to be measured from the real clock too for the readback to mean anything.
         */
        val NOW: ZonedDateTime get() = ZonedDateTime.now()
    }
}
