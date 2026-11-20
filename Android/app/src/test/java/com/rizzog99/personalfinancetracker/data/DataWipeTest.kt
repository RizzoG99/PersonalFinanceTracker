package com.rizzog99.personalfinancetracker.data

import android.content.Context
import androidx.datastore.core.DataStore
import androidx.datastore.preferences.core.PreferenceDataStoreFactory
import androidx.datastore.preferences.core.Preferences
import androidx.datastore.preferences.core.emptyPreferences
import java.io.IOException
import kotlinx.coroutines.flow.flowOf
import androidx.room.Room
import androidx.test.core.app.ApplicationProvider
import com.rizzog99.personalfinancetracker.data.local.PersonalFinanceDatabase
import com.rizzog99.personalfinancetracker.data.preferences.DismissedRecurrencePatternsRepository
import com.rizzog99.personalfinancetracker.data.repository.CategoryRepository
import com.rizzog99.personalfinancetracker.data.repository.RoomCategoryRepository
import com.rizzog99.personalfinancetracker.data.repository.RoomRecurrenceRepository
import com.rizzog99.personalfinancetracker.domain.category.DefaultCategories
import com.rizzog99.personalfinancetracker.domain.recurrence.DismissedRecurrencePattern
import com.rizzog99.personalfinancetracker.domain.recurrence.RecurrenceFrequency
import com.rizzog99.personalfinancetracker.domain.recurrence.RecurrenceSuggestion
import java.io.File
import java.math.BigDecimal
import java.time.Instant
import java.time.ZoneOffset
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.runBlocking
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner

/**
 * #320 `AC-05`: Delete all data erases the ledger in one Room transaction, reseeds the default
 * categories inside it, keeps the learned merchant mappings (D-02, frozen iOS `DataWipeService.swift`
 * does not delete `MerchantCategoryMapping`), and leaves no rule that could recreate a transaction.
 */
@RunWith(RobolectricTestRunner::class)
class DataWipeTest {
    private lateinit var database: PersonalFinanceDatabase
    private lateinit var patterns: DismissedRecurrencePatternsRepository
    private val storeScope = CoroutineScope(Dispatchers.IO + SupervisorJob())
    private lateinit var file: File

    @Before
    fun setUp() = runBlocking {
        val context = ApplicationProvider.getApplicationContext<Context>()
        database = Room.inMemoryDatabaseBuilder(context, PersonalFinanceDatabase::class.java).allowMainThreadQueries().build()
        file = File(context.filesDir, "wipe-test.preferences_pb").apply { delete() }
        patterns = DismissedRecurrencePatternsRepository(PreferenceDataStoreFactory.create(scope = storeScope) { file })
        patterns.dismiss(
            listOf(
                RecurrenceSuggestion(
                    frequency = RecurrenceFrequency.MONTHLY, interval = 1, amount = BigDecimal("-12.99"), note = "Netflix",
                    categoryLabel = "Bills", categoryId = null, currencyCode = "EUR", occurrenceCount = 2,
                    nextDate = Instant.EPOCH, occurrenceDates = listOf(Instant.EPOCH), amountsIdentical = true, goalId = null,
                ),
            ),
        )
        seedOneOfEverything()
    }

    @After
    fun tearDown() {
        database.close()
        storeScope.cancel()
        file.delete()
    }

    private fun exec(sql: String) = database.openHelper.writableDatabase.execSQL(sql)

    private fun count(table: String): Int = database.query("SELECT COUNT(*) FROM `$table`", null).use { it.moveToFirst(); it.getInt(0) }

    private fun categoryNames(): List<String> =
        database.query("SELECT name FROM categories ORDER BY name", null).use { c -> buildList { while (c.moveToNext()) add(c.getString(0)) } }

    private fun seedOneOfEverything() {
        exec("INSERT INTO categories VALUES ('cat-custom','Pets','pets','pawprint','expense','teal',NULL,'EUR')")
        exec("INSERT INTO goals VALUES ('goal-1','Trip','1000',NULL,'blue','airplane',0)")
        // Monthly from 2026-01-01, auto-recording, never materialized: due every month since.
        exec(
            "INSERT INTO recurrence_rules VALUES ('rule-1','monthly',1,${Instant.parse("2026-01-01T09:00:00Z").toEpochMilli()}," +
                "NULL,NULL,'-12.99','Netflix','Bills','cat-custom','EUR',NULL,1)",
        )
        exec("INSERT INTO transactions VALUES ('tx-1',0,'-12.99','Netflix','Pets','cat-custom','EUR','goal-1','rule-1')")
        exec("INSERT INTO credit_cards VALUES ('card-1','Visa','4242','-100','1000','red','EUR')")
        exec("INSERT INTO health_score_snapshots VALUES ('hs-1',0,70,70,70,70,70)")
        exec("INSERT INTO daily_forecast_cache VALUES (1,'2026-11',20,'[]')")
        exec("INSERT INTO merchant_category_mappings VALUES ('esselunga','cat-custom')")
    }

    private val ledgerTables = listOf(
        "transactions", "recurrence_rules", "goals", "credit_cards", "health_score_snapshots", "daily_forecast_cache",
    )

    @Test
    fun `ac05 wipe erases the ledger keeps merchant mappings and reseeds the defaults`() = runBlocking {
        ledgerTables.forEach { assertEquals("precondition: $it seeded", 1, count(it)) }
        assertTrue("precondition: custom category", "Pets" in categoryNames())

        wipeAllData(database, RoomCategoryRepository(database), patterns)

        ledgerTables.forEach { assertEquals("$it after wipe", 0, count(it)) }
        assertEquals(DefaultCategories.all.map { it.name }.sorted(), categoryNames())
        assertEquals("merchant mapping kept (D-02)", 1, count("merchant_category_mappings"))
        assertEquals(emptyList<DismissedRecurrencePattern>(), patterns.all())

        RoomRecurrenceRepository(database).materializeDue(Instant.parse("2027-01-01T00:00:00Z"), ZoneOffset.UTC)
        assertEquals("no rule survives to recreate a transaction", 0, count("transactions"))
    }

    @Test
    fun `ac05 a reseed failure rolls the whole wipe back`() = runBlocking {
        val real = RoomCategoryRepository(database)
        // The real reseed writes first, so the rollback has to undo inserted defaults too.
        val failingSeed = object : CategoryRepository by real {
            override suspend fun seedDefaultsIfEmpty() {
                real.seedDefaultsIfEmpty()
                throw IllegalStateException("disk full")
            }
        }

        try {
            wipeAllData(database, failingSeed, patterns)
            fail("the wipe must report the failure")
        } catch (expected: IllegalStateException) {
            // Reported to the caller, which shows the generic failure message (AC-06).
        }

        ledgerTables.forEach { assertEquals("$it untouched", 1, count(it)) }
        assertEquals("categories exactly as before", listOf("Pets"), categoryNames())
        assertEquals("answers untouched", 1, patterns.all().size)
    }

    @Test
    fun `ac05 a failure clearing the answers after the commit still reports success`() = runBlocking {
        val brokenStore = object : DataStore<Preferences> {
            override val data = flowOf(emptyPreferences())
            override suspend fun updateData(transform: suspend (t: Preferences) -> Preferences): Preferences =
                throw IOException("read-only file system")
        }

        // Returns normally: the ledger is gone, so "Nothing was changed" would be false.
        wipeAllData(database, RoomCategoryRepository(database), DismissedRecurrencePatternsRepository(brokenStore))

        ledgerTables.forEach { assertEquals("$it after wipe", 0, count(it)) }
        assertEquals(DefaultCategories.all.map { it.name }.sorted(), categoryNames())
    }
}
