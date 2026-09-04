package com.rizzog99.personalfinancetracker.data.local

import androidx.room.Database
import androidx.room.migration.Migration
import androidx.room.RoomDatabase
import androidx.sqlite.db.SupportSQLiteDatabase

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
    version = 2,
    exportSchema = true,
)
abstract class PersonalFinanceDatabase : RoomDatabase() {
    abstract fun transactionDao(): TransactionDao
    abstract fun categoryDao(): CategoryDao
    abstract fun recurrenceRuleDao(): RecurrenceRuleDao

    companion object {
        val MIGRATION_1_2 = object : Migration(1, 2) {
            override fun migrate(db: SupportSQLiteDatabase) {
                db.execSQL(
                    "ALTER TABLE categories ADD COLUMN normalizedName TEXT NOT NULL DEFAULT ''",
                )
                db.execSQL(
                    "UPDATE categories SET normalizedName = lower(trim(name))",
                )
                db.execSQL("DROP INDEX IF EXISTS index_categories_name_type")
                db.execSQL(
                    "CREATE UNIQUE INDEX IF NOT EXISTS index_categories_normalizedName_type " +
                        "ON categories (normalizedName, type)",
                )
            }
        }
    }
}
