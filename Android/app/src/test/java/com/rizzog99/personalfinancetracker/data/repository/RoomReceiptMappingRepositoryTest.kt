package com.rizzog99.personalfinancetracker.data.repository

import android.content.Context
import androidx.room.Room
import androidx.test.core.app.ApplicationProvider
import com.rizzog99.personalfinancetracker.data.local.PersonalFinanceDatabase
import kotlinx.coroutines.runBlocking
import org.junit.After
import org.junit.Assert.assertEquals
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
    fun `merchant mapping is normalized and remembers the latest category`() = runBlocking {
        repository.remember("  Caffè Roma  ", "coffee")
        repository.remember("CAFFE ROMA", "restaurants")

        assertEquals("restaurants", repository.categoryIdFor("caffè roma"))
    }
}
