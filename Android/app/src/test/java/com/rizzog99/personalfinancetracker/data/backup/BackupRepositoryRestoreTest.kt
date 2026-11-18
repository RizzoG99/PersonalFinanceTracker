package com.rizzog99.personalfinancetracker.data.backup

import android.content.Context
import androidx.room.Room
import androidx.test.core.app.ApplicationProvider
import com.rizzog99.personalfinancetracker.data.local.PersonalFinanceDatabase
import com.rizzog99.personalfinancetracker.data.repository.GoalRepository
import com.rizzog99.personalfinancetracker.domain.category.DefaultCategories
import com.rizzog99.personalfinancetracker.data.repository.RoomCategoryRepository
import com.rizzog99.personalfinancetracker.data.repository.RoomGoalRepository
import com.rizzog99.personalfinancetracker.data.repository.RoomTransactionRepository
import com.rizzog99.personalfinancetracker.domain.category.NewCategory
import com.rizzog99.personalfinancetracker.domain.category.TransactionType
import com.rizzog99.personalfinancetracker.domain.goal.NewGoal
import com.rizzog99.personalfinancetracker.domain.transaction.FinanceTransaction
import java.math.BigDecimal
import java.time.Instant
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.async
import kotlinx.coroutines.withTimeout
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.awaitCancellation
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.launch
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withContext
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner

/**
 * #316: a restore validates the whole file before touching data and replaces it atomically.
 *
 * The database is built like production (`PersonalFinanceApplication`): no
 * `allowMainThreadQueries`. Robolectric's test thread is the main thread, so AC-03 restores from
 * it the way `SettingsSheet` does; AC-01/02 restore on `Dispatchers.IO` so they reach the
 * replace step instead of failing early on a main-thread check.
 */
@RunWith(RobolectricTestRunner::class)
class BackupRepositoryRestoreTest {
    private lateinit var database: PersonalFinanceDatabase
    private lateinit var transactions: RoomTransactionRepository
    private lateinit var categories: RoomCategoryRepository
    private lateinit var goals: RoomGoalRepository

    @Before
    fun setUp() = runBlocking {
        val context = ApplicationProvider.getApplicationContext<Context>()
        database = Room.inMemoryDatabaseBuilder(context, PersonalFinanceDatabase::class.java).build()
        transactions = RoomTransactionRepository(database)
        categories = RoomCategoryRepository(database)
        goals = RoomGoalRepository(database)

        val groceries = categories.add(category("Groceries", TransactionType.EXPENSE))
        val salary = categories.add(category("Salary", TransactionType.INCOME))
        transactions.insertBatch(
            listOf(
                transaction("seed-1", "-12.50", groceries.name, groceries.id),
                transaction("seed-2", "1500.00", salary.name, salary.id),
            ),
        )
        goals.add(NewGoal("Holiday", BigDecimal("900.00"), null, "categoryIndigo", "star.fill"))
        Unit
    }

    @After
    fun tearDown() {
        database.close()
    }

    @Test
    fun ac01_invalidFilesAreRejectedAndLedgerUnchanged() = runBlocking {
        val before = seededLedger()
        val invalidFiles = mapOf(
            "empty object" to "{}",
            "newer version" to validBackup(version = "2"),
            "fractional version" to validBackup(version = "1.9"),
            "string version" to validBackup(version = "\"1\""),
            "bad amount" to validBackup(amount = "\"abc\""),
            "missing goals" to """{"version":1,"categories":[],"transactions":[]}""",
            "not json" to "not json",
            "null transaction id" to validBackup().replace("\"id\":\"bk-1\"", "\"id\":null"),
            "numeric note" to validBackup().replace("\"note\":\"October rent\"", "\"note\":42"),
            "trailing garbage" to validBackup() + " garbage",
            "two objects" to validBackup() + validBackup(),
            "trailing comment" to validBackup() + " /* garbage */",
            "trailing NUL" to validBackup() + "\u0000garbage",
        )
        for ((case, json) in invalidFiles) {
            val failure = withContext(Dispatchers.IO) { runCatching { repository().import(json.byteInputStream()) } }
            assertTrue("$case should be rejected", failure.isFailure)
            assertEquals("$case must leave the ledger unchanged", before, ledger())
        }
    }

    @Test
    fun ac02_failureAtLastWriteRollsBack() = runBlocking {
        val before = seededLedger()
        val failingGoals = object : GoalRepository by goals {
            override suspend fun add(goal: NewGoal) = error("disk full")
        }
        val failure = withContext(Dispatchers.IO) {
            runCatching { repository(failingGoals).import(validBackup().byteInputStream()) }
        }
        assertTrue(failure.isFailure)
        assertEquals(before, ledger())
    }

    @Test
    fun ac02_cancellationMidRestoreRollsBack() = runBlocking {
        val before = seededLedger()
        val started = CompletableDeferred<Unit>()
        val hangingGoals = object : GoalRepository by goals {
            override suspend fun add(goal: NewGoal): Nothing {
                started.complete(Unit)
                awaitCancellation()
            }
        }
        val restore = launch(Dispatchers.IO) { repository(hangingGoals).import(validBackup().byteInputStream()) }
        started.await()
        restore.cancel()
        restore.join()
        assertEquals(before, ledger())
    }

    @Test
    fun ac03_validBackupReplacesLedgerFromMainThread() = runBlocking {
        // A screen already observing the ledger must see the restored data, not only a fresh read.
        val subscribed = CompletableDeferred<Unit>()
        val refreshed = async(Dispatchers.IO) {
            transactions.observeAll().first { rows ->
                subscribed.complete(Unit)
                rows.singleOrNull()?.id == "bk-1"
            }
        }
        subscribed.await()

        // Trailing whitespace (an editor's final newline) is still a valid file.
        repository().import((validBackup() + "\n").byteInputStream())

        withTimeout(5_000) { refreshed.await() }

        val rent = categories.observeAll().first().single()
        assertEquals("Rent" to TransactionType.EXPENSE, rent.name to rent.type)
        val restored = transactions.observeAll().first().single()
        assertEquals("bk-1", restored.id)
        assertEquals(0, BigDecimal("-7.30").compareTo(restored.amount))
        assertEquals(rent.id, restored.categoryId)
        val car = goals.observeAll().first().single()
        assertEquals("Car", car.name)
        assertEquals(0, BigDecimal("5000.00").compareTo(car.targetAmount))
    }

    @Test
    fun ac03_validEmptyBackupLeavesDefaultCategoriesOnly() = runBlocking {
        repository().import("""{"version":1,"categories":[],"transactions":[],"goals":[]}""".byteInputStream())

        assertEquals(emptyList<Any>(), transactions.observeAll().first())
        assertEquals(emptyList<Any>(), goals.observeAll().first())
        assertEquals(
            DefaultCategories.all.map { it.name to it.type }.toSet(),
            categories.observeAll().first().map { it.name to it.type }.toSet(),
        )
    }

    private fun repository(goalRepository: GoalRepository = goals) =
        BackupRepository(database, transactions, categories, goalRepository)

    /** Ids, names and exact amounts of every record, so "unchanged" means more than equal counts. */
    private suspend fun ledger(): List<String> {
        val rows = categories.observeAll().first().map { "category ${it.id} ${it.name} ${it.type}" } +
            transactions.observeAll().first().map { "transaction ${it.id} ${it.amount.plain()} ${it.categoryId}" } +
            goals.observeAll().first().map { "goal ${it.id} ${it.name} ${it.targetAmount.plain()}" }
        return rows.sorted()
    }

    /** Precondition: the seeded ledger is really there, so "unchanged" cannot pass on an empty one. */
    private suspend fun seededLedger(): List<String> = ledger().also { rows ->
        assertEquals(5, rows.size)
        assertTrue(rows.any { it.startsWith("transaction seed-1 -12.5 ") })
        assertTrue(rows.any { it.startsWith("transaction seed-2 1500 ") })
    }

    private fun validBackup(version: String = "1", amount: String = "\"-7.30\"") = """
        {"version":$version,"exportedAt":"2026-11-01T10:00:00Z",
         "categories":[{"name":"Rent","iconToken":"house.fill","type":"EXPENSE","colorToken":"categoryIndigo","currencyCode":"EUR"}],
         "transactions":[{"id":"bk-1","timestamp":"2026-10-31T08:00:00Z","amount":$amount,"note":"October rent",
                          "categoryLabel":"Rent","currencyCode":"EUR"}],
         "goals":[{"name":"Car","targetAmount":"5000.00","colorToken":"categoryTeal","iconToken":"car.fill"}]}
    """.trimIndent()

    private fun BigDecimal.plain() = stripTrailingZeros().toPlainString()

    private fun category(name: String, type: TransactionType) =
        NewCategory(name, "tag.fill", type, "categoryIndigo", null, "EUR")

    private fun transaction(id: String, amount: String, label: String, categoryId: String) = FinanceTransaction(
        id = id,
        timestamp = Instant.parse("2026-10-15T09:00:00Z"),
        amount = BigDecimal(amount),
        note = "",
        categoryLabel = label,
        categoryId = categoryId,
        currencyCode = "EUR",
        goalId = null,
        recurrenceRuleId = null,
    )
}
