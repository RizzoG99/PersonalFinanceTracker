package com.rizzog99.personalfinancetracker

import android.app.Application
import androidx.room.Room
import com.rizzog99.personalfinancetracker.data.local.PersonalFinanceDatabase
import com.rizzog99.personalfinancetracker.data.preferences.UserPreferencesRepository
import com.rizzog99.personalfinancetracker.data.repository.CategoryRepository
import com.rizzog99.personalfinancetracker.data.repository.RecurrenceRepository
import com.rizzog99.personalfinancetracker.data.repository.ReceiptMappingRepository
import com.rizzog99.personalfinancetracker.data.repository.RoomCategoryRepository
import com.rizzog99.personalfinancetracker.data.repository.RoomRecurrenceRepository
import com.rizzog99.personalfinancetracker.data.repository.RoomReceiptMappingRepository
import com.rizzog99.personalfinancetracker.data.repository.RoomTransactionRepository
import com.rizzog99.personalfinancetracker.data.repository.TransactionRepository
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
            .addMigrations(PersonalFinanceDatabase.MIGRATION_1_2)
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

    val recurrenceRepository: RecurrenceRepository by lazy {
        RoomRecurrenceRepository(database)
    }

    val receiptMappingRepository: ReceiptMappingRepository by lazy {
        RoomReceiptMappingRepository(database)
    }

    private val recurrenceMaterializationMutex = Mutex()

    override fun onCreate() {
        super.onCreate()
        applicationScope.launch {
            categoryRepository.seedDefaultsIfEmpty()
        }
        materializeRecurringTransactions()
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
