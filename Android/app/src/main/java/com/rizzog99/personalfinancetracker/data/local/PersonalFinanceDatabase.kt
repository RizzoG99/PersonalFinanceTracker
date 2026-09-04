package com.rizzog99.personalfinancetracker.data.local

import androidx.room.Database
import androidx.room.RoomDatabase

@Database(
    entities = [
        TransactionEntity::class,
        CategoryEntity::class,
        GoalEntity::class,
        CreditCardEntity::class,
        RecurrenceRuleEntity::class,
        HealthScoreSnapshotEntity::class,
        DailyForecastCacheEntity::class,
        MerchantCategoryMappingEntity::class,
    ],
    version = 1,
    exportSchema = true,
)
abstract class PersonalFinanceDatabase : RoomDatabase() {
    abstract fun transactionDao(): TransactionDao
    abstract fun categoryDao(): CategoryDao
}
