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
}
