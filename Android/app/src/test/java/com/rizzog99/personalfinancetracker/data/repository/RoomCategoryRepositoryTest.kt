package com.rizzog99.personalfinancetracker.data.repository

import android.content.Context
import androidx.room.Room
import androidx.test.core.app.ApplicationProvider
import com.rizzog99.personalfinancetracker.data.local.PersonalFinanceDatabase
import com.rizzog99.personalfinancetracker.domain.category.NewCategory
import com.rizzog99.personalfinancetracker.domain.category.TransactionType
import com.rizzog99.personalfinancetracker.domain.recurrence.NewRecurrenceRule
import com.rizzog99.personalfinancetracker.domain.recurrence.RecurrenceFrequency
import java.math.BigDecimal
import java.time.Instant
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.runBlocking
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner

@RunWith(RobolectricTestRunner::class)
class RoomCategoryRepositoryTest {
    private lateinit var database: PersonalFinanceDatabase
    private lateinit var repository: CategoryRepository

    @Before
    fun setUp() {
        val context = ApplicationProvider.getApplicationContext<Context>()
        database = Room.inMemoryDatabaseBuilder(context, PersonalFinanceDatabase::class.java)
            .allowMainThreadQueries()
            .build()
        repository = RoomCategoryRepository(database)
    }

    @After
    fun tearDown() {
        database.close()
    }

    @Test
    fun `seeds current iOS default categories once and keeps income and expense Other distinct`() = runBlocking {
        repository.seedDefaultsIfEmpty()
        repository.seedDefaultsIfEmpty()

        val categories = repository.observeAll().first()
        assertEquals(38, categories.size)
        assertEquals(2, categories.count { it.name == "Other" })
        assertTrue(categories.any { it.name == "Other" && it.type == TransactionType.INCOME })
        assertTrue(categories.any { it.name == "Other" && it.type == TransactionType.EXPENSE })
    }

    @Test(expected = android.database.sqlite.SQLiteConstraintException::class)
    fun `enforces case insensitive uniqueness within a category type`() {
        runBlocking {
            repository.add(
                NewCategory(name = "Other", iconToken = "ellipsis.circle", type = TransactionType.EXPENSE),
            )
            repository.add(
                NewCategory(name = " other ", iconToken = "ellipsis.circle", type = TransactionType.EXPENSE),
            )
        }
    }

    @Test
    fun `updates a category while keeping its identity and financial metadata`() = runBlocking {
        val original = repository.add(
            NewCategory(
                name = "Travel fund",
                iconToken = "airplane",
                type = TransactionType.EXPENSE,
                colorToken = "categoryAmber",
            ),
        )

        val updated = repository.update(
            original.copy(name = "Trips", iconToken = "luggage", colorToken = "categoryTeal"),
        )

        assertEquals(original.id, updated.id)
        assertEquals(TransactionType.EXPENSE, updated.type)
        assertEquals("Trips", updated.name)
        assertEquals("luggage", updated.iconToken)
        assertEquals("categoryTeal", updated.colorToken)
        assertEquals(original.currencyCode, updated.currencyCode)
    }

    /**
     * The database half of the import failure. `forCategoryName` strips emoji, so a CSV containing
     * both "Regali" and "🎁 Regali" asked for the same category twice; the second insert aborts and,
     * because the importer wrapped the whole thing in one runCatching, took all 1634 transactions
     * with it under the message "Couldn't import transactions. Try again."
     *
     * The constraint is correct and stays. `ImportCategoryPlanner` is what stops the importer
     * walking into it — see `ImportCategoryPlannerTest`.
     */
    @Test(expected = android.database.sqlite.SQLiteConstraintException::class)
    fun `rejects a second category whose name differs only by emoji and case`() {
        runBlocking {
            repository.add(NewCategory(name = "Regali", iconToken = "gift", type = TransactionType.EXPENSE))
            // What "🎁 Regali" becomes once forCategoryName() has dropped the emoji.
            repository.add(NewCategory(name = "Regali", iconToken = "tag", type = TransactionType.EXPENSE))
        }
    }

    @Test(expected = android.database.sqlite.SQLiteConstraintException::class)
    fun `rejects an update that duplicates a category in its type`() {
        runBlocking {
            val groceries = repository.add(
                NewCategory(name = "Groceries", iconToken = "cart", type = TransactionType.EXPENSE),
            )
            repository.add(
                NewCategory(name = "Dining", iconToken = "fork.knife", type = TransactionType.EXPENSE),
            )

            repository.update(groceries.copy(name = " dining "))
        }
    }

    @Test
    fun `AC-05 deleting a category nullifies links while preserving transaction snapshots`() = runBlocking {
        val category = repository.add(
            NewCategory(name = "Coffee", iconToken = "cup.and.saucer", type = TransactionType.EXPENSE),
        )
        val recurrenceRepository = RoomRecurrenceRepository(database)
        val transactionRepository = RoomTransactionRepository(database)
        val rule = recurrenceRepository.createAndMaterialize(
            NewRecurrenceRule(
                frequency = RecurrenceFrequency.MONTHLY,
                interval = 1,
                startDate = Instant.parse("2026-09-01T10:00:00Z"),
                amount = BigDecimal("-3.75"),
                note = "Espresso",
                categoryLabel = "Coffee snapshot",
                categoryId = category.id,
                currencyCode = "EUR",
            ),
        )

        repository.delete(category.id)

        val transaction = transactionRepository.observeAll().first().single()
        assertNull(transaction.categoryId)
        assertEquals("Coffee snapshot", transaction.categoryLabel)
        assertNull(database.recurrenceRuleDao().get(rule.id)?.categoryId)
    }
}
