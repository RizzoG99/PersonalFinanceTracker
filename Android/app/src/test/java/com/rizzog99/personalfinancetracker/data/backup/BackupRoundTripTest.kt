package com.rizzog99.personalfinancetracker.data.backup

import android.content.Context
import androidx.room.Room
import androidx.room.withTransaction
import androidx.test.core.app.ApplicationProvider
import com.rizzog99.personalfinancetracker.data.local.CreditCardEntity
import com.rizzog99.personalfinancetracker.data.local.HealthScoreSnapshotEntity
import com.rizzog99.personalfinancetracker.data.local.MerchantCategoryMappingEntity
import com.rizzog99.personalfinancetracker.data.local.PersonalFinanceDatabase
import com.rizzog99.personalfinancetracker.data.repository.RoomCategoryRepository
import com.rizzog99.personalfinancetracker.data.repository.RoomGoalRepository
import com.rizzog99.personalfinancetracker.data.repository.RoomRecurrenceRepository
import com.rizzog99.personalfinancetracker.data.repository.RoomTransactionRepository
import com.rizzog99.personalfinancetracker.domain.category.NewCategory
import com.rizzog99.personalfinancetracker.domain.category.TransactionType
import com.rizzog99.personalfinancetracker.domain.goal.NewGoal
import com.rizzog99.personalfinancetracker.domain.recurrence.NewRecurrenceRule
import com.rizzog99.personalfinancetracker.domain.recurrence.RecurrenceFrequency
import com.rizzog99.personalfinancetracker.domain.transaction.FinanceTransaction
import java.io.ByteArrayOutputStream
import java.math.BigDecimal
import java.time.Instant
import java.time.ZoneOffset
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withContext
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner

/**
 * #317: a backup keeps record ids, category links, recurring rules and goal contributions.
 *
 * The fixture holds what name-only relinking loses: same-name income and expense categories, a
 * renamed category (its id no longer derives from its name), a funded goal, an auto-record rule
 * with a materialization cursor, a stopped rule and a forecast-only rule, plus the legacy and
 * learned tables a restore used to wipe without restoring.
 */
@RunWith(RobolectricTestRunner::class)
class BackupRoundTripTest {
    private lateinit var database: PersonalFinanceDatabase
    private lateinit var transactions: RoomTransactionRepository
    private lateinit var categories: RoomCategoryRepository
    private lateinit var goals: RoomGoalRepository
    private lateinit var rules: RoomRecurrenceRepository

    private val utc = ZoneOffset.UTC
    private val materializedThrough = Instant.parse("2026-10-20T00:00:00Z")

    @Before
    fun setUp() {
        val context = ApplicationProvider.getApplicationContext<Context>()
        database = Room.inMemoryDatabaseBuilder(context, PersonalFinanceDatabase::class.java).build()
        transactions = RoomTransactionRepository(database)
        categories = RoomCategoryRepository(database)
        goals = RoomGoalRepository(database)
        rules = RoomRecurrenceRepository(database)
    }

    @After
    fun tearDown() {
        database.close()
    }

    @Test
    fun ac01_roundTripKeepsIdsLinksRulesAndGoalProgress() = runBlocking {
        seedFixture()
        val before = tables()
        val backup = export()

        // Restore onto a device whose data has changed since the backup.
        val car = goals.observeAll().first().single()
        goals.delete(car.id)
        categories.add(NewCategory("Stray", "tag.fill", TransactionType.EXPENSE))
        val legacy = withContext(Dispatchers.IO) { repository().import(backup.inputStream()) }

        assertFalse(legacy)
        assertEquals(before, tables())

        val restoredCar = goals.observeAll().first().single()
        assertEquals(car.id, restoredCar.id)
        val contributions = transactions.observeAll().first().filter { it.goalId == restoredCar.id }
        assertEquals(0, BigDecimal("-200").compareTo(contributions.sumOf { it.amount }))

        val bonus = categories.observeAll().first().filter { it.name == "Bonus" }.associateBy { it.type }
        val bonusRows = transactions.observeAll().first().filter { it.categoryLabel == "Bonus" }
        assertEquals(bonus.getValue(TransactionType.INCOME).id, bonusRows.single { it.amount.signum() > 0 }.categoryId)
        assertEquals(bonus.getValue(TransactionType.EXPENSE).id, bonusRows.single { it.amount.signum() < 0 }.categoryId)

        // App start after the restore: the preserved cursor means nothing is recorded twice.
        rules.materializeDue(materializedThrough, utc)
        assertEquals(before, tables())
    }

    /** #284 AC-04 / D-06: travels and tags round-trip with their ids. */
    @Test
    fun travelsRoundTripWithTheirIds() = runBlocking {
        seedFixture()
        val travels = com.rizzog99.personalfinancetracker.data.repository.RoomTravelRepository(database)
        val someId = transactions.observeAll().first().first().id
        val trip = travels.addAndAssign("Barcellona", "airplane", listOf(someId))
        val before = tables()
        val backup = export()

        travels.delete(trip.id)
        assertFalse(withContext(Dispatchers.IO) { repository().import(backup.inputStream()) })

        assertEquals(before, tables())
        assertEquals(listOf(trip), travels.observeAll().first())
        assertEquals(trip.id, transactions.observeAll().first().single { it.id == someId }.travelId)
    }

    /** #284 D-06: a v2 file written before travels existed still restores, every row in no travel. */
    @Test
    fun aV2FileFromBeforeTravelsStillRestores() = runBlocking {
        seedFixture()
        val root = org.json.JSONObject(export().decodeToString())
        val tablesJson = root.getJSONObject("tables")
        tablesJson.remove("travels")
        val rows = tablesJson.getJSONArray("transactions")
        for (i in 0 until rows.length()) rows.getJSONObject(i).remove("travelId")
        val expected = tables()
        // The device has moved on since: a travel and a tag the old file knows nothing about.
        val travels = com.rizzog99.personalfinancetracker.data.repository.RoomTravelRepository(database)
        travels.addAndAssign("Since", "car", listOf(transactions.observeAll().first().first().id))
        transactions.delete(transactions.observeAll().first().last().id)

        assertFalse(withContext(Dispatchers.IO) { repository().import(root.toString().byteInputStream()) })

        assertEquals(expected, tables())
        assertEquals(emptyList<Any>(), travels.observeAll().first())
        assertEquals(emptyList<String?>(), transactions.observeAll().first().mapNotNull { it.travelId })
    }

    @Test
    fun ac03_legacyV1RelinksByNameAndTypeAndKeepsUnbackedTables() = runBlocking {
        seedFixture()
        val bonusExpenseId = categories.observeAll().first().single { it.name == "Bonus" && it.type == TransactionType.EXPENSE }.id
        database.merchantCategoryMappingDao().upsert(MerchantCategoryMappingEntity("bar", bonusExpenseId))
        val untouched = tables().filterKeys { it in setOf("credit_cards", "health_score_snapshots") }

        val legacy = withContext(Dispatchers.IO) { repository().import(legacyV1.byteInputStream()) }

        assertTrue(legacy)
        val bonus = categories.observeAll().first().filter { it.name == "Bonus" }.associateBy { it.type }
        val restored = transactions.observeAll().first().associateBy { it.id }
        assertEquals(setOf("v1-income", "v1-expense", "v1-goal"), restored.keys)
        assertEquals(bonus.getValue(TransactionType.INCOME).id, restored.getValue("v1-income").categoryId)
        assertEquals(bonus.getValue(TransactionType.EXPENSE).id, restored.getValue("v1-expense").categoryId)
        assertEquals(listOf(null, null, null), restored.values.map { it.goalId })
        assertEquals(untouched, tables().filterKeys { it in untouched.keys })
        assertEquals(emptyList<Map<String, Any?>>(), tables().getValue("recurrence_rules"))
        // "bar" still resolves; "esselunga" pointed at the renamed Food category, which v1 brings
        // back under a name-derived id, so it could never resolve again and is dropped.
        assertEquals(bonusExpenseId, bonus.getValue(TransactionType.EXPENSE).id)
        assertEquals(bonusExpenseId, database.merchantCategoryMappingDao().categoryIdFor("bar"))
        assertTrue(categories.observeAll().first().any { it.name == "Food" })
        assertEquals(null, database.merchantCategoryMappingDao().categoryIdFor("esselunga"))
    }

    @Test
    fun ac04_inconsistentV2FilesAreRejectedAndDataUnchanged() = runBlocking {
        seedFixture()
        val before = tables()
        val good = String(export())
        val carId = goals.observeAll().first().single().id
        val invalid = mapOf(
            "newer version" to good.replaceFirst("\"version\":2", "\"version\":3"),
            "dangling goal link" to good.replace("\"goalId\":\"$carId\"", "\"goalId\":\"00000000-0000-0000-0000-000000000000\""),
            "bad decimal" to good.replace("\"targetAmountDecimal\":\"5000\"", "\"targetAmountDecimal\":\"abc\""),
            "number for text" to good.replace("\"targetAmountDecimal\":\"5000\"", "\"targetAmountDecimal\":5000"),
            "unknown table" to good.replaceFirst("\"goals\":", "\"ghosts\":"),
            "omitted autoRecord" to org.json.JSONObject(good).apply {
                getJSONObject("tables").getJSONArray("recurrence_rules").getJSONObject(0).remove("autoRecord")
            }.toString(),
        )
        for ((case, json) in invalid) {
            assertTrue("$case fixture must differ from the valid file", json != good)
            val failure = withContext(Dispatchers.IO) { runCatching { repository().import(json.byteInputStream()) } }
            assertTrue("$case should be rejected", failure.isFailure)
            assertEquals("$case must leave the data unchanged", before, tables())
        }
    }

    @Test
    fun ac02_backupCoversEveryTableExceptTheDerivedForecastCache() = runBlocking {
        val all = withContext(Dispatchers.IO) {
            database.withTransaction {
                database.query(
                    "SELECT name FROM sqlite_master WHERE type = 'table' AND name NOT IN ('android_metadata', 'room_master_table') AND name NOT LIKE 'sqlite_%'",
                    null,
                ).use { c -> buildSet { while (c.moveToNext()) add(c.getString(0)) } }
            }
        }
        assertEquals(all - "daily_forecast_cache", BackupRepository.BACKED_UP_TABLES.toSet())
    }

    private suspend fun seedFixture() {
        val bonusIncome = categories.add(NewCategory("Bonus", "gift.fill", TransactionType.INCOME, "categoryTeal"))
        val bonusExpense = categories.add(NewCategory("Bonus", "gift", TransactionType.EXPENSE, "categoryRose", BigDecimal("120.50")))
        val food = categories.add(NewCategory("Groceries", "cart.fill", TransactionType.EXPENSE)).let {
            categories.update(it.copy(name = "Food"))
        }
        val car = goals.add(NewGoal("Car", BigDecimal("5000"), Instant.parse("2027-06-30T00:00:00Z"), "categoryTeal", "car.fill"))
        transactions.insertBatch(
            listOf(
                transaction("t-bonus-in", "300", "Bonus", bonusIncome.id),
                transaction("t-bonus-out", "-40", "Bonus", bonusExpense.id),
                transaction("t-food", "-25.10", "Food", food.id),
                transaction("t-goal-1", "-150", "→ Car", null, goalId = car.id),
                transaction("t-goal-2", "-50", "→ Car", null, goalId = car.id),
            ),
        )
        val rent = NewRecurrenceRule(
            RecurrenceFrequency.MONTHLY, 1, Instant.parse("2026-08-01T00:00:00Z"),
            BigDecimal("-700"), "Rent", "Food", food.id, "EUR",
        )
        rules.createAndMaterialize(rent)
        val gym = rules.create(rent.copy(amount = BigDecimal("-30"), note = "Gym", startDate = Instant.parse("2026-07-01T00:00:00Z")))
        database.recurrenceRuleDao().close(gym.id, Instant.parse("2026-09-30T00:00:00Z").toEpochMilli())
        rules.create(rent.copy(amount = BigDecimal("-55"), note = "Phone", autoRecord = false, goalId = car.id))
        rules.materializeDue(materializedThrough, utc)

        database.creditCardDao().insert(CreditCardEntity("card-1", "Visa", "4242", "120.5", "2000", "categoryIndigo", "EUR"))
        database.healthScoreSnapshotDao().upsert(HealthScoreSnapshotEntity("hs-1", 1_760_000_000_000, 72, 60, 80, 70, 75))
        database.merchantCategoryMappingDao().upsert(MerchantCategoryMappingEntity("esselunga", food.id))

        // Precondition: the rule really materialized, so "no duplicates" is not vacuous.
        assertTrue(transactions.observeAll().first().count { it.recurrenceRuleId != null } >= 3)
    }

    private suspend fun export(): ByteArray =
        ByteArrayOutputStream().also { out -> withContext(Dispatchers.IO) { repository().export(out) } }.toByteArray()

    /** Every column of every row, per table, order-independent. */
    private suspend fun tables(): Map<String, List<Map<String, Any?>>> = withContext(Dispatchers.IO) {
        database.withTransaction {
            listOf(
                "categories", "goals", "recurrence_rules", "travels", "transactions",
                "credit_cards", "health_score_snapshots", "merchant_category_mappings",
            ).associateWith { table ->
                database.query("SELECT * FROM `$table`", null).use { c ->
                    buildList {
                        while (c.moveToNext()) {
                            add((0 until c.columnCount).associate { i -> c.getColumnName(i) to if (c.isNull(i)) null else c.getString(i) })
                        }
                    }.sortedBy { it.toString() }
                }
            }
        }
    }

    private fun repository() = BackupRepository(database, transactions, categories, goals)

    private fun transaction(id: String, amount: String, label: String, categoryId: String?, goalId: String? = null) =
        FinanceTransaction(
            id = id,
            timestamp = Instant.parse("2026-10-05T09:00:00Z"),
            amount = BigDecimal(amount),
            note = id,
            categoryLabel = label,
            categoryId = categoryId,
            currencyCode = "EUR",
            goalId = goalId,
            recurrenceRuleId = null,
        )

    private val legacyV1 = """
        {"version":1,"exportedAt":"2026-09-01T10:00:00Z",
         "categories":[{"name":"Bonus","iconToken":"gift.fill","type":"INCOME"},
                       {"name":"Bonus","iconToken":"gift","type":"EXPENSE"},
                       {"name":"Food","iconToken":"cart.fill","type":"EXPENSE"}],
         "transactions":[{"id":"v1-income","timestamp":"2026-08-31T08:00:00Z","amount":"300","note":"","categoryLabel":"Bonus","currencyCode":"EUR"},
                         {"id":"v1-expense","timestamp":"2026-08-31T09:00:00Z","amount":"-40","note":"","categoryLabel":"Bonus","currencyCode":"EUR"},
                         {"id":"v1-goal","timestamp":"2026-08-31T10:00:00Z","amount":"-150","note":"","categoryLabel":"→ Car","currencyCode":"EUR",
                          "goalId":"0f8fad5b-d9cb-469f-a165-70867728950e"}],
         "goals":[{"name":"Car","targetAmount":"5000"}]}
    """.trimIndent()
}
