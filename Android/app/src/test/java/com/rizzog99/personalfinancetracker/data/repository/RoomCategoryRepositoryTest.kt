package com.rizzog99.personalfinancetracker.data.repository

import android.content.Context
import androidx.room.Room
import androidx.test.core.app.ApplicationProvider
import com.rizzog99.personalfinancetracker.data.local.PersonalFinanceDatabase
import com.rizzog99.personalfinancetracker.domain.category.NewCategory
import com.rizzog99.personalfinancetracker.domain.category.TransactionType
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.runBlocking
import org.junit.After
import org.junit.Assert.assertEquals
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
}
