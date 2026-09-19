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
        RecurrenceRuleEntity::class,
        CreditCardEntity::class,
        HealthScoreSnapshotEntity::class,
        DailyForecastCacheEntity::class,
        MerchantCategoryMappingEntity::class,
    ],
    version = 3,
    exportSchema = true,
)
abstract class PersonalFinanceDatabase : RoomDatabase() {
    abstract fun transactionDao(): TransactionDao
    abstract fun categoryDao(): CategoryDao
    abstract fun goalDao(): GoalDao
    abstract fun recurrenceRuleDao(): RecurrenceRuleDao
    abstract fun creditCardDao(): CreditCardDao
    abstract fun healthScoreSnapshotDao(): HealthScoreSnapshotDao
    abstract fun dailyForecastCacheDao(): DailyForecastCacheDao
    abstract fun merchantCategoryMappingDao(): MerchantCategoryMappingDao

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

        /**
         * No structural change. `credit_cards` was briefly dropped from the entity set and has been
         * restored with its original v2 columns, so a v2 database already carries the table with
         * byte-identical CREATE SQL and nothing needs to run here.
         */
        val MIGRATION_2_3 = object : Migration(2, 3) {
            override fun migrate(db: SupportSQLiteDatabase) = Unit
        }
    }
}
