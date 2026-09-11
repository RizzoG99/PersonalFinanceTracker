package com.rizzog99.personalfinancetracker.data.repository

import android.content.Context
import androidx.room.Room
import androidx.test.core.app.ApplicationProvider
import com.rizzog99.personalfinancetracker.data.local.PersonalFinanceDatabase
import com.rizzog99.personalfinancetracker.domain.goal.NewGoal
import java.math.BigDecimal
import java.time.Instant
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.runBlocking
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner

@RunWith(RobolectricTestRunner::class)
class RoomGoalRepositoryTest {
    private lateinit var database: PersonalFinanceDatabase
    private lateinit var repository: GoalRepository

    @Before
    fun setUp() {
        val context = ApplicationProvider.getApplicationContext<Context>()
        database = Room.inMemoryDatabaseBuilder(context, PersonalFinanceDatabase::class.java)
            .allowMainThreadQueries()
            .build()
        repository = RoomGoalRepository(database)
    }

    @After
    fun tearDown() {
        database.close()
    }

    @Test
    fun `persists exact targets and supports editing and deleting a goal`() = runBlocking {
        val created = repository.add(
            NewGoal(
                name = "Emergency buffer",
                targetAmount = BigDecimal("2500.50"),
                deadline = Instant.parse("2027-01-01T00:00:00Z"),
                colorToken = "categoryTeal",
                iconToken = "cross.circle.fill",
            ),
        )

        assertEquals(0, BigDecimal("2500.50").compareTo(repository.observeAll().first().single().targetAmount))

        repository.update(created.copy(name = "Emergency fund", targetAmount = BigDecimal("3000.25")))
        val updated = repository.observeAll().first().single()
        assertEquals(created.id, updated.id)
        assertEquals("Emergency fund", updated.name)
        assertEquals(0, BigDecimal("3000.25").compareTo(updated.targetAmount))

        repository.delete(updated.id)
        assertEquals(emptyList<Any>(), repository.observeAll().first())
    }
}
