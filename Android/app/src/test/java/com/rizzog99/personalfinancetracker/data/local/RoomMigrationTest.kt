package com.rizzog99.personalfinancetracker.data.local

import android.content.Context
import android.database.sqlite.SQLiteConstraintException
import androidx.room.Room
import androidx.room.testing.MigrationTestHelper
import androidx.test.core.app.ApplicationProvider
import androidx.test.platform.app.InstrumentationRegistry
import com.rizzog99.personalfinancetracker.data.repository.RoomCategoryRepository
import com.rizzog99.personalfinancetracker.data.repository.RoomTransactionRepository
import com.rizzog99.personalfinancetracker.domain.category.NewCategory
import com.rizzog99.personalfinancetracker.domain.category.TransactionType
import com.rizzog99.personalfinancetracker.domain.transaction.FinanceTransaction
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.runBlocking
import org.json.JSONObject
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner

/**
 * Room schema migration and durability parity (`M1-DATA-MIGRATIONS`).
 *
 * Every test here seeds a *file-backed* source-version database through [MigrationTestHelper],
 * migrates it, and then reopens it through the **production** [PersonalFinanceDatabase] builder with
 * the production migration list, asserting exact domain values through the production repositories.
 * Proving that migration SQL executes is not the point; proving that every record is still reachable
 * as the app sees it is.
 */
@RunWith(RobolectricTestRunner::class)
class RoomMigrationTest {
    private val databaseName = "m1-data-migrations.db"
    private lateinit var context: Context

    @get:Rule
    val helper = MigrationTestHelper(
        InstrumentationRegistry.getInstrumentation(),
        PersonalFinanceDatabase::class.java,
    )

    private var openDatabase: PersonalFinanceDatabase? = null

    @After
    fun tearDown() {
        openDatabase?.close()
        ApplicationProvider.getApplicationContext<Context>().deleteDatabase(databaseName)
    }

    @Test
    fun `AC-01_1 AC-04_1 the 1 to 2 path validates schema 2 and every v1 record stays exact`() = runBlocking {
        helper.createDatabase(databaseName, 1).use(MigrationFixtures::seedVersion1)

        // runMigrationsAndValidate is what makes this an AC-01 proof rather than a smoke test: it
        // compares the migrated database against the exported 2.json and throws on any divergence.
        helper.runMigrationsAndValidate(databaseName, 2, true, PersonalFinanceDatabase.MIGRATION_1_2).close()

        // The production database is version 3, so opening it also runs the 2→3 no-op. That is the
        // real upgrade path a v1 install takes.
        val database = openProductionDatabase()
        assertEverySeededRecordIsExact(database)
        assertEquals(3, database.userVersion())
    }

    @Test
    fun `AC-02_1 the 2 to 3 path validates schema 3 and leaves credit-card records accessible`() = runBlocking {
        helper.createDatabase(databaseName, 2).use(MigrationFixtures::seedVersion2)

        helper.runMigrationsAndValidate(databaseName, 3, true, PersonalFinanceDatabase.MIGRATION_2_3).close()

        val database = openProductionDatabase()
        assertEverySeededRecordIsExact(database)
        // Named separately from the shared assertion because the v2 credit-card table is the record
        // type #121 found v3 had dropped; 2→3 has to carry it through untouched.
        assertEquals(2, database.creditCardDao().observeAll().first().size)
        assertEquals("Revolving Visa", requireNotNull(database.creditCardDao().get(MigrationFixtures.BOUNDARY_CARD_ID)).name)
    }

    @Test
    fun `AC-03_1 AC-04_2 the full 1 to 3 path yields the same records and constraints as the sequential path`() = runBlocking {
        helper.createDatabase(databaseName, 1).use(MigrationFixtures::seedVersion1)

        helper.runMigrationsAndValidate(databaseName, 3, true, *PersonalFinanceDatabase.MIGRATIONS).close()

        val database = openProductionDatabase()
        assertEverySeededRecordIsExact(database)
        assertEquals(3, database.userVersion())
        assertSchemaContractHolds(database)
    }

    @Test
    fun `AC-06_1 a migrated database keeps every row index and constraint across close and reopen`() = runBlocking {
        helper.createDatabase(databaseName, 1).use(MigrationFixtures::seedVersion1)
        // The first open migrates 1→3; the second proves the migrated file survives a real reopen.
        openProductionDatabase()

        val reopened = openProductionDatabase()
        assertEverySeededRecordIsExact(reopened)
        assertEquals(3, reopened.userVersion())
        assertSchemaContractHolds(reopened)
    }

    /**
     * The backfill has to agree with the app's own normalizer for *any* stored name, not just for
     * the ASCII ones. Each name below breaks a different SQLite built-in: `trim()` strips only
     * U+0020, and `lower()` is ASCII-only on Android's build (a desktop SQLite may fold accents,
     * which is exactly why an environment-independent assertion is needed here).
     */
    @Test
    fun `AC-01_2 the normalizedName backfill stores what the app itself would store`() = runBlocking {
        val adversarialNames = mapOf(
            "cat-tab" to "\tOffice Supplies ",
            "cat-accent" to "CAFFÈ Bar",
            "cat-nbsp" to "Rent\u00A0",
        )
        helper.createDatabase(databaseName, 1).use { db ->
            adversarialNames.forEach { (id, name) ->
                db.execSQL(
                    "INSERT INTO categories (id, name, iconToken, type, colorToken, monthlyBudgetDecimal, currencyCode) " +
                        "VALUES (?, ?, 'basket', 'expense', 'accentTeal', NULL, 'EUR')",
                    arrayOf(id, name),
                )
            }
        }
        val database = openProductionDatabase()

        adversarialNames.forEach { (id, name) ->
            assertEquals(
                "normalizedName for [$name] must match the app's normalizer",
                MigrationFixtures.expectedNormalizedName(name),
                database.normalizedNameOf(id),
            )
        }

        // And the backfilled value has to be the one the unique index actually enforces on: adding
        // the same name in a different case must collide with the migrated row.
        val collision = assertThrows(SQLiteConstraintException::class.java) {
            runBlocking {
                RoomCategoryRepository(database)
                    .add(NewCategory(name = "office supplies", iconToken = "cup", type = TransactionType.EXPENSE))
            }
        }
        assertTrue(
            "the collision must come from the normalizedName index: ${collision.message}",
            collision.message?.contains("UNIQUE constraint failed") == true,
        )
    }

    @Test
    fun `AC-07_1 the exported schemas match the active database identity and each other where the migration is a no-op`() {
        val runtimeIdentity = openProductionDatabase().query("SELECT identity_hash FROM room_master_table", null).use {
            it.moveToFirst()
            it.getString(0)
        }

        assertEquals(
            "the active database must match the exported schema 3",
            exportedIdentityHash(3),
            runtimeIdentity,
        )
        // v2 and v3 are the same contract — the table set only ever diverged inside an unreleased
        // development window — which is exactly why MIGRATION_2_3 is correctly a no-op.
        assertEquals(
            "MIGRATION_2_3 may only stay empty while 2.json and 3.json describe the same schema",
            exportedIdentityHash(2),
            exportedIdentityHash(3),
        )
    }

    /** Indices, foreign keys, and the unique constraint — declared *and* actually enforced. */
    private suspend fun assertSchemaContractHolds(database: PersonalFinanceDatabase) {
        assertTrue(
            "no foreign key may dangle after migration",
            database.query("PRAGMA foreign_key_check", null).use { it.count } == 0,
        )

        val transactionIndices = database.query(
            "SELECT name FROM sqlite_master WHERE type = 'index' AND tbl_name = 'transactions'",
            null,
        ).use { cursor ->
            buildList { while (cursor.moveToNext()) add(cursor.getString(0)) }
        }
        listOf("timestampEpochMillis", "categoryId", "goalId", "recurrenceRuleId").forEach { column ->
            assertTrue(
                "index_transactions_$column must survive migration",
                transactionIndices.contains("index_transactions_$column"),
            )
        }
        assertTrue(
            "the normalizedName uniqueness index must survive migration",
            database.query(
                "SELECT name FROM sqlite_master WHERE type = 'index' AND name = 'index_categories_normalizedName_type'",
                null,
            ).use { it.count } == 1,
        )

        // SET NULL has to be live, not merely declared: deleting a category must blank the reference
        // and keep the historical transaction.
        RoomCategoryRepository(database).delete(MigrationFixtures.INCOME_CATEGORY_ID)
        val transactions = RoomTransactionRepository(database).observeAll().first().associateBy(FinanceTransaction::id)
        assertEquals(3, transactions.size)
        val orphaned = requireNotNull(transactions[MigrationFixtures.PRE_EPOCH_TRANSACTION_ID])
        assertNull("deleting a category must null the reference, not the transaction", orphaned.categoryId)
        assertEquals("💰 Income", orphaned.categoryLabel)
    }

    private fun openProductionDatabase(): PersonalFinanceDatabase {
        openDatabase?.close()
        return Room.databaseBuilder(applicationContext(), PersonalFinanceDatabase::class.java, databaseName)
            .addMigrations(*PersonalFinanceDatabase.MIGRATIONS)
            .allowMainThreadQueries()
            .build()
            .also { openDatabase = it }
    }

    private fun applicationContext(): Context {
        if (!::context.isInitialized) context = ApplicationProvider.getApplicationContext()
        return context
    }

    private fun PersonalFinanceDatabase.userVersion(): Int =
        query("PRAGMA user_version", null).use {
            it.moveToFirst()
            it.getInt(0)
        }

    /** Read from assets — the same copy of the exported schema MigrationTestHelper validates against. */
    private fun exportedIdentityHash(version: Int): String {
        val json = applicationContext().assets
            .open("com.rizzog99.personalfinancetracker.data.local.PersonalFinanceDatabase/$version.json")
            .use { it.readBytes().decodeToString() }
        return JSONObject(json).getJSONObject("database").getString("identityHash")
    }
}
