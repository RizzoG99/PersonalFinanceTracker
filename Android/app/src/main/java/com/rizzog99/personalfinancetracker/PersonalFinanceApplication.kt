package com.rizzog99.personalfinancetracker

import android.app.Application
import android.app.NotificationChannel
import android.app.NotificationManager
import android.os.Build
import androidx.room.Room
import androidx.work.WorkManager
import com.rizzog99.personalfinancetracker.data.backup.BackupRepository
import com.rizzog99.personalfinancetracker.data.local.PersonalFinanceDatabase
import com.rizzog99.personalfinancetracker.data.preferences.ImportProfileRepository
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
import com.rizzog99.personalfinancetracker.data.security.KeystorePinSecretStore
import com.rizzog99.personalfinancetracker.data.security.PinLockRepository
import com.rizzog99.personalfinancetracker.work.DailyReminderWorker
import com.rizzog99.personalfinancetracker.work.ReminderScheduler
import java.time.LocalTime
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
            .addMigrations(*PersonalFinanceDatabase.MIGRATIONS)
            .build()
    }

    val preferencesRepository: UserPreferencesRepository by lazy {
        UserPreferencesRepository(this)
    }

    val importProfileRepository: ImportProfileRepository by lazy {
        ImportProfileRepository(this)
    }

    /** PIN material lives in Keystore-backed storage, never in the preferences DataStore (#128). */
    val pinLockRepository: PinLockRepository by lazy {
        PinLockRepository(KeystorePinSecretStore(this), preferencesRepository)
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
        // Before anything can read the lock state: migrates a pre-#128 PIN out of the preferences
        // DataStore, then resolves PinLock.Unknown into the real state.
        applicationScope.launch { pinLockRepository.load() }
        // The stored time, not a constant: a reminder the user moved has to survive a relaunch.
        applicationScope.launch { applyDailyReminder() }
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

    /** Turns the daily reminder on or off, and brings the enqueued work in line with it. */
    fun setDailyReminderEnabled(enabled: Boolean) {
        applicationScope.launch {
            preferencesRepository.setDailyReminderEnabled(enabled)
            applyDailyReminder()
        }
    }

    /** Stores a new reminder time; an enabled reminder is rescheduled onto it (#129 AC-04). */
    fun setDailyReminderTime(time: LocalTime) {
        applicationScope.launch {
            preferencesRepository.setDailyReminderTime(time)
            applyDailyReminder()
        }
    }

    private suspend fun applyDailyReminder() {
        ReminderScheduler.apply(WorkManager.getInstance(this), preferencesRepository)
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
