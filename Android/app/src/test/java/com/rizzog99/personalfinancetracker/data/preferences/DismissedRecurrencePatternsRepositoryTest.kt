package com.rizzog99.personalfinancetracker.data.preferences

import android.content.Context
import androidx.datastore.core.DataStore
import androidx.datastore.preferences.core.PreferenceDataStoreFactory
import androidx.datastore.preferences.core.Preferences
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.core.stringPreferencesKey
import androidx.room.Room
import androidx.test.core.app.ApplicationProvider
import com.rizzog99.personalfinancetracker.data.local.PersonalFinanceDatabase
import com.rizzog99.personalfinancetracker.data.repository.RoomCategoryRepository
import com.rizzog99.personalfinancetracker.data.wipeAllData
import com.rizzog99.personalfinancetracker.domain.recurrence.DismissedRecurrencePattern
import com.rizzog99.personalfinancetracker.domain.recurrence.RecurrenceFrequency
import com.rizzog99.personalfinancetracker.domain.recurrence.RecurrenceSuggestion
import java.io.File
import java.math.BigDecimal
import java.time.Instant
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancelAndJoin
import kotlinx.coroutines.runBlocking
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner

/** #295 AC-04: "Not fixed" answers persist across a relaunch and Delete all data clears them. */
@RunWith(RobolectricTestRunner::class)
class DismissedRecurrencePatternsRepositoryTest {
    private lateinit var file: File
    private var session: StoreSession? = null

    @Before
    fun setUp() {
        file = File(ApplicationProvider.getApplicationContext<Context>().filesDir, "dismissed-test.preferences_pb").apply { delete() }
    }

    @After
    fun tearDown() = runBlocking {
        session?.close()
        file.delete()
        Unit
    }

    private fun suggestion(note: String, amount: String, goalId: String? = null) = RecurrenceSuggestion(
        frequency = RecurrenceFrequency.MONTHLY, interval = 1, amount = BigDecimal(amount), note = note, categoryLabel = "Bills",
        categoryId = null, currencyCode = "EUR", occurrenceCount = 2, nextDate = Instant.EPOCH, occurrenceDates = listOf(Instant.EPOCH),
        amountsIdentical = true, goalId = goalId,
    )

    @Test
    fun `ac04 a dismissal survives a relaunch and a second dismissal keeps the first`() = runBlocking {
        DismissedRecurrencePatternsRepository(openStore()).dismiss(listOf(suggestion("App Store ottobre", "-6")))

        val relaunched = DismissedRecurrencePatternsRepository(restart())
        assertEquals(listOf(DismissedRecurrencePattern("app store", BigDecimal("-6"))), relaunched.all())

        relaunched.dismiss(listOf(suggestion("", "-200", goalId = "goal-G")))
        assertEquals(
            listOf(DismissedRecurrencePattern("app store", BigDecimal("-6")), DismissedRecurrencePattern("", BigDecimal("-200"), "goal-G")),
            DismissedRecurrencePatternsRepository(restart()).all(),
        )
    }

    @Test
    fun `an unreadable value reads as nothing dismissed`() = runBlocking {
        val store = openStore()
        store.edit { it[stringPreferencesKey("patterns")] = "{not json" }
        assertEquals(emptyList<DismissedRecurrencePattern>(), DismissedRecurrencePatternsRepository(store).all())
    }

    @Test
    fun `ac04 delete all data clears the dismissed patterns`() = runBlocking {
        val patterns = DismissedRecurrencePatternsRepository(openStore())
        patterns.dismiss(listOf(suggestion("Netflix", "-12.99")))
        val database = Room.inMemoryDatabaseBuilder(ApplicationProvider.getApplicationContext(), PersonalFinanceDatabase::class.java)
            .allowMainThreadQueries().build()
        try {
            wipeAllData(database, RoomCategoryRepository(database), patterns)
        } finally {
            database.close()
        }

        assertEquals(emptyList<DismissedRecurrencePattern>(), DismissedRecurrencePatternsRepository(restart()).all())
    }

    private fun openStore(): DataStore<Preferences> = StoreSession(file).also { session = it }.store

    /** Cancels the store's scope, waits for the file lock to be released, and rebuilds over it. */
    private suspend fun restart(): DataStore<Preferences> {
        requireNotNull(session).close()
        return openStore()
    }

    private class StoreSession(file: File) {
        private val job = SupervisorJob()
        val store: DataStore<Preferences> = PreferenceDataStoreFactory.create(scope = CoroutineScope(Dispatchers.IO + job)) { file }

        suspend fun close() = job.cancelAndJoin()
    }
}
