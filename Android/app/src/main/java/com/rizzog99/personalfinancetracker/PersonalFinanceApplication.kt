package com.rizzog99.personalfinancetracker

import android.app.Application
import android.app.NotificationChannel
import android.app.NotificationManager
import android.os.Build
import androidx.room.Room
import androidx.work.ExistingPeriodicWorkPolicy
import androidx.work.PeriodicWorkRequestBuilder
import androidx.work.WorkManager
import com.rizzog99.personalfinancetracker.data.backup.BackupRepository
import com.rizzog99.personalfinancetracker.data.local.PersonalFinanceDatabase
import com.rizzog99.personalfinancetracker.data.preferences.UserPreferencesRepository
import com.rizzog99.personalfinancetracker.data.repository.CategoryRepository
import com.rizzog99.personalfinancetracker.data.repository.CreditCardRepository
import com.rizzog99.personalfinancetracker.data.repository.GoalRepository
import com.rizzog99.personalfinancetracker.data.repository.InsightRepository
import com.rizzog99.personalfinancetracker.data.repository.RecurrenceRepository
import com.rizzog99.personalfinancetracker.data.preferences.ReceiptCategoryMapRepository
import com.rizzog99.personalfinancetracker.data.repository.ReceiptMappingRepository
import com.rizzog99.personalfinancetracker.data.repository.RoomCategoryRepository
import com.rizzog99.personalfinancetracker.data.repository.RoomCreditCardRepository
import com.rizzog99.personalfinancetracker.data.repository.RoomGoalRepository
import com.rizzog99.personalfinancetracker.data.repository.RoomInsightRepository
import com.rizzog99.personalfinancetracker.data.repository.RoomRecurrenceRepository
import com.rizzog99.personalfinancetracker.data.repository.RoomReceiptMappingRepository
import com.rizzog99.personalfinancetracker.data.repository.RoomTransactionRepository
import com.rizzog99.personalfinancetracker.data.repository.TransactionRepository
import com.rizzog99.personalfinancetracker.work.DailyReminderWorker
import java.time.LocalDate
import java.time.LocalTime
import java.time.ZoneId
import java.time.ZonedDateTime
import java.util.concurrent.TimeUnit
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock

class PersonalFinanceApplication : Application() {
    private val applicationScope = CoroutineScope(SupervisorJob() + Dispatchers.IO)

    val database: PersonalFinanceDatabase by lazy {
        Room.databaseBuilder(this, PersonalFinanceDatabase::class.java, "personal_finance.db")
            .addMigrations(
                PersonalFinanceDatabase.MIGRATION_1_2,
                PersonalFinanceDatabase.MIGRATION_2_3,
            )
            .build()
    }

    val preferencesRepository: UserPreferencesRepository by lazy {
        UserPreferencesRepository(this)
    }

    val transactionRepository: TransactionRepository by lazy {
        RoomTransactionRepository(database)
    }

    val categoryRepository: CategoryRepository by lazy {
        RoomCategoryRepository(database)
    }

    val goalRepository: GoalRepository by lazy {
        RoomGoalRepository(database)
    }

    val recurrenceRepository: RecurrenceRepository by lazy {
        RoomRecurrenceRepository(database)
    }

    val creditCardRepository: CreditCardRepository by lazy {
        RoomCreditCardRepository(database)
    }

    val insightRepository: InsightRepository by lazy {
        RoomInsightRepository(database)
    }

    val receiptMappingRepository: ReceiptMappingRepository by lazy {
        RoomReceiptMappingRepository(database)
    }

    val receiptCategoryMapRepository: ReceiptCategoryMapRepository by lazy {
        ReceiptCategoryMapRepository(this)
    }

    val backupRepository: BackupRepository by lazy {
        BackupRepository(database, transactionRepository, categoryRepository, goalRepository)
    }

    private val recurrenceMaterializationMutex = Mutex()

    override fun onCreate() {
        super.onCreate()
        applicationScope.launch {
            categoryRepository.seedDefaultsIfEmpty()
        }
        createNotificationChannel()
        materializeRecurringTransactions()
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val name = getString(R.string.daily_reminder_notification_title)
            val descriptionText = getString(R.string.daily_reminder_notification_message)
            val importance = NotificationManager.IMPORTANCE_DEFAULT
            val channel = NotificationChannel(DailyReminderWorker.CHANNEL_ID, name, importance).apply {
                description = descriptionText
            }
            val notificationManager: NotificationManager =
                getSystemService(NotificationManager::class.java)
            notificationManager.createNotificationChannel(channel)
        }
    }

    fun scheduleDailyReminder() {
        // Schedule for 8:00 PM (20:00) local time
        val reminderTime = LocalTime.of(20, 0)
        val now = ZonedDateTime.now(ZoneId.systemDefault())
        var nextReminder = now.withHour(reminderTime.hour).withMinute(reminderTime.minute).withSecond(0)

        // If the time has already passed today, schedule for tomorrow
        if (nextReminder.isBefore(now)) {
            nextReminder = nextReminder.plusDays(1)
        }

        val initialDelay = java.time.Duration.between(now, nextReminder).seconds
        val workRequest = PeriodicWorkRequestBuilder<DailyReminderWorker>(
            1,
            TimeUnit.DAYS,
        ).setInitialDelay(initialDelay, TimeUnit.SECONDS).build()

        WorkManager.getInstance(this).enqueueUniquePeriodicWork(
            DailyReminderWorker.WORK_NAME,
            ExistingPeriodicWorkPolicy.KEEP,
            workRequest,
        )
    }

    /**
     * Runs on launch and whenever the app returns to the foreground. The mutex makes those
     * overlapping lifecycle callbacks behave as one materialization pass, so an occurrence can
     * never be inserted twice from a stale recurrence cursor.
     */
    fun materializeRecurringTransactions() {
        applicationScope.launch {
            recurrenceMaterializationMutex.withLock {
                runCatching { recurrenceRepository.materializeDue() }
            }
        }
    }
}
