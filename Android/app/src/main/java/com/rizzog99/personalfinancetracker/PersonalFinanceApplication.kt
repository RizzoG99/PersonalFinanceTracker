package com.rizzog99.personalfinancetracker

import android.app.Application
import androidx.room.Room
import com.rizzog99.personalfinancetracker.data.local.PersonalFinanceDatabase
import com.rizzog99.personalfinancetracker.data.preferences.UserPreferencesRepository
import com.rizzog99.personalfinancetracker.data.repository.CategoryRepository
import com.rizzog99.personalfinancetracker.data.repository.RoomCategoryRepository
import com.rizzog99.personalfinancetracker.data.repository.RoomTransactionRepository
import com.rizzog99.personalfinancetracker.data.repository.TransactionRepository
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch

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

    override fun onCreate() {
        super.onCreate()
        applicationScope.launch {
            categoryRepository.seedDefaultsIfEmpty()
        }
    }
}
