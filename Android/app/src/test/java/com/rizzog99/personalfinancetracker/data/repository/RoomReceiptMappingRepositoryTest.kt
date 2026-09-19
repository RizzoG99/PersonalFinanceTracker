package com.rizzog99.personalfinancetracker.data.repository

import android.content.Context
import androidx.room.Room
import androidx.test.core.app.ApplicationProvider
import com.rizzog99.personalfinancetracker.data.local.PersonalFinanceDatabase
import kotlinx.coroutines.runBlocking
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner

@RunWith(RobolectricTestRunner::class)
class RoomReceiptMappingRepositoryTest {
    private lateinit var database: PersonalFinanceDatabase
    private lateinit var repository: ReceiptMappingRepository

    @Before
    fun setUp() {
        val context = ApplicationProvider.getApplicationContext<Context>()
        database = Room.inMemoryDatabaseBuilder(context, PersonalFinanceDatabase::class.java)
            .allowMainThreadQueries()
            .build()
        repository = RoomReceiptMappingRepository(database)
    }

    @After
    fun tearDown() {
        database.close()
    }

    @Test
    fun `AC-05_1 surrounding whitespace addresses the same mapping`() = runBlocking {
        repository.remember("  Conad  ", "groceries")

        assertEquals("groceries", repository.categoryIdFor("Conad"))
        assertEquals("groceries", repository.categoryIdFor("\tConad\t"))
        assertEquals(1, database.merchantCategoryMappingDao().count())
    }

    @Test
    fun `AC-05_2 case differences address the same mapping`() = runBlocking {
        repository.remember("CONAD", "groceries")

        assertEquals("groceries", repository.categoryIdFor("conad"))
        assertEquals("groceries", repository.categoryIdFor("Conad"))
        assertEquals(1, database.merchantCategoryMappingDao().count())
    }

    @Test
    fun `AC-05_3 accented and unaccented merchants stay distinct like the frozen contract`() = runBlocking {
        repository.remember("  Caffè Roma  ", "coffee")
        repository.remember("CAFFE ROMA", "restaurants")

        assertEquals("coffee", repository.categoryIdFor("caffè roma"))
        assertEquals("restaurants", repository.categoryIdFor("Caffe Roma"))
        assertEquals(2, database.merchantCategoryMappingDao().count())
    }

    @Test
    fun `AC-05_4 relearning a known merchant upserts rather than accumulating`() = runBlocking {
        repository.remember("Esselunga", "groceries")
        repository.remember("esselunga ", "household")

        assertEquals("household", repository.categoryIdFor("ESSELUNGA"))
        assertEquals(1, database.merchantCategoryMappingDao().count())
    }

    @Test
    fun `AC-05_5 an unknown merchant has no mapping`() = runBlocking {
        repository.remember("Conad", "groceries")

        assertNull(repository.categoryIdFor("Lidl"))
    }
}
