package com.rizzog99.personalfinancetracker.data.local

import androidx.room.Database
import androidx.room.migration.Migration
import androidx.room.RoomDatabase
import androidx.sqlite.db.SupportSQLiteDatabase
import com.rizzog99.personalfinancetracker.domain.category.CategoryNameValidator

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
                backfillNormalizedNames(db)
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

        /**
         * The one registration point. `PersonalFinanceApplication` and the migration tests both read
         * this, so a new migration cannot reach production without the suite covering it.
         */
        val MIGRATIONS: Array<Migration> = arrayOf(MIGRATION_1_2, MIGRATION_2_3)

        /**
         * Backfilled in Kotlin rather than with `lower(trim(name))`. SQLite's `trim()` strips only
         * U+0020 and its `lower()` is ASCII-only on Android's build, so the SQL version could store
         * a value the app would never compute — and `(normalizedName, type)` then stops catching the
         * duplicates the column exists to catch.
         */
        private fun backfillNormalizedNames(db: SupportSQLiteDatabase) {
            val names = mutableListOf<Pair<String, String>>()
            db.query("SELECT id, name FROM categories").use { cursor ->
                while (cursor.moveToNext()) {
                    names += cursor.getString(0) to cursor.getString(1)
                }
            }
            names.forEach { (id, name) ->
                db.execSQL(
                    "UPDATE categories SET normalizedName = ? WHERE id = ?",
                    arrayOf(CategoryNameValidator.normalized(name), id),
                )
            }
        }
    }
}
