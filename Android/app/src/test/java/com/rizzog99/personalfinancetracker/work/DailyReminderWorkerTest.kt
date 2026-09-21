package com.rizzog99.personalfinancetracker.work

import android.Manifest
import android.app.Application
import android.app.NotificationManager
import android.content.Context
import androidx.test.core.app.ApplicationProvider
import androidx.work.ListenableWorker
import androidx.work.testing.TestListenableWorkerBuilder
import kotlinx.coroutines.runBlocking
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config

/** #144: permission revocation must not turn a daily reminder into a failing/retrying worker. */
@RunWith(RobolectricTestRunner::class)
class DailyReminderWorkerTest {
    private lateinit var application: Application
    private lateinit var notificationManager: NotificationManager

    @Before
    fun setUp() {
        application = ApplicationProvider.getApplicationContext()
        notificationManager = application.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        notificationManager.cancelAll()
    }

    @After
    fun tearDown() {
        notificationManager.cancelAll()
    }

    @Test
    @Config(sdk = [33])
    fun `AC-144-01 denied notification permission finishes without posting or retrying`() = runBlocking {
        shadowOf(application).denyPermissions(Manifest.permission.POST_NOTIFICATIONS)

        val result = worker().doWork()

        assertEquals(ListenableWorker.Result.success(), result)
        assertEquals(0, shadowOf(notificationManager).size())
    }

    @Test
    @Config(sdk = [33])
    fun `AC-144-02 granted notification permission posts the reminder`() = runBlocking {
        shadowOf(application).grantPermissions(Manifest.permission.POST_NOTIFICATIONS)

        val result = worker().doWork()

        assertEquals(ListenableWorker.Result.success(), result)
        assertEquals(1, shadowOf(notificationManager).size())
    }

    @Test
    @Config(sdk = [32])
    fun `AC-144-03 pre Android 13 posts without the runtime permission`() = runBlocking {
        val result = worker().doWork()

        assertEquals(ListenableWorker.Result.success(), result)
        assertEquals(1, shadowOf(notificationManager).size())
    }

    private fun worker(): DailyReminderWorker =
        TestListenableWorkerBuilder<DailyReminderWorker>(application).build()
}
