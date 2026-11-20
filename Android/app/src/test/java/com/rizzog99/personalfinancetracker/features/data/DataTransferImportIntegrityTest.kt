package com.rizzog99.personalfinancetracker.features.data

import android.content.Context
import androidx.datastore.preferences.core.PreferenceDataStoreFactory
import androidx.room.Room
import androidx.test.core.app.ApplicationProvider
import com.rizzog99.personalfinancetracker.data.local.PersonalFinanceDatabase
import com.rizzog99.personalfinancetracker.data.preferences.DismissedRecurrencePatternsRepository
import com.rizzog99.personalfinancetracker.data.repository.RoomCategoryRepository
import com.rizzog99.personalfinancetracker.data.repository.RoomRecurrenceRepository
import com.rizzog99.personalfinancetracker.data.repository.RoomTransactionRepository
import com.rizzog99.personalfinancetracker.domain.import.ImportReconciler
import com.rizzog99.personalfinancetracker.domain.recurrence.NewRecurrenceRule
import com.rizzog99.personalfinancetracker.domain.recurrence.RecurrenceFrequency
import com.rizzog99.personalfinancetracker.domain.recurrence.RecurrenceRule
import com.rizzog99.personalfinancetracker.domain.recurrence.RecurrenceSuggestion
import com.rizzog99.personalfinancetracker.domain.transaction.FinanceTransaction
import java.io.File
import java.math.BigDecimal
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneOffset
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.test.UnconfinedTestDispatcher
import kotlinx.coroutines.test.resetMain
import kotlinx.coroutines.test.setMain
import kotlinx.coroutines.withTimeout
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner

/**
 * #314 through the production import path ([DataTransferViewModel.import] / [planRecurring]),
 * against a real in-memory Room database: the duplicate key and the auto-recorded-payment match
 * hold at commit time, not only in the preview, and a rule batch is all-or-nothing.
 */
@OptIn(ExperimentalCoroutinesApi::class)
@RunWith(RobolectricTestRunner::class)
class DataTransferImportIntegrityTest {
    private lateinit var database: PersonalFinanceDatabase
    private lateinit var transactions: RoomTransactionRepository
    private lateinit var recurrence: RoomRecurrenceRepository
    private lateinit var storeScope: CoroutineScope
    private lateinit var storeFile: File
    private lateinit var vm: DataTransferViewModel
    private var nextId = 0

    @Before
    fun setUp() {
        Dispatchers.setMain(UnconfinedTestDispatcher())
        val context = ApplicationProvider.getApplicationContext<Context>()
        database = Room.inMemoryDatabaseBuilder(context, PersonalFinanceDatabase::class.java).allowMainThreadQueries().build()
        transactions = RoomTransactionRepository(database)
        recurrence = RoomRecurrenceRepository(database)
        storeFile = File(context.filesDir, "dismissed-integrity-test.preferences_pb").apply { delete() }
        storeScope = CoroutineScope(Dispatchers.IO + SupervisorJob())
        val dismissed = DismissedRecurrencePatternsRepository(PreferenceDataStoreFactory.create(scope = storeScope) { storeFile })
        vm = DataTransferViewModel(transactions, RoomCategoryRepository(database), recurrence, dismissed, clock = { day(3, 10) })
    }

    @After
    fun tearDown() {
        storeScope.cancel()
        database.close()
        storeFile.delete()
        Dispatchers.resetMain()
    }

    private fun day(month: Int, dayOfMonth: Int): Instant = LocalDate.of(2026, month, dayOfMonth).atTime(12, 0).toInstant(ZoneOffset.UTC)

    /** A fresh id each call, like a re-parsed file. */
    private fun row(note: String, amount: String, date: Instant) = FinanceTransaction(
        id = "csv-${nextId++}", timestamp = date, amount = BigDecimal(amount), note = note, categoryLabel = "Bills",
        categoryId = null, currencyCode = "EUR", goalId = null, recurrenceRuleId = null,
    )

    private fun importRows(rows: List<FinanceTransaction>): List<FinanceTransaction>? = runBlocking {
        val done = CompletableDeferred<List<FinanceTransaction>?>()
        vm.import(rows, emptyMap()) { done.complete(it) }
        withTimeout(10_000) { done.await() }
    }

    private fun all() = runBlocking { transactions.observeAll().first() }

    /** A Netflix auto-record rule that wrote its 1 March payment. */
    private fun seedAutoRecordedNetflix() = runBlocking {
        recurrence.createAndMaterialize(
            NewRecurrenceRule(
                frequency = RecurrenceFrequency.MONTHLY, interval = 1, startDate = day(3, 1), amount = BigDecimal("-9.99"),
                note = "Netflix", categoryLabel = "Bills", categoryId = null, currencyCode = "EUR",
            ),
        )
        assertEquals(1, all().size)
    }

    @Test
    fun `ac01 importing the same file twice saves its rows once`() {
        val file = { listOf(row("Rent", "-750.00", day(3, 1)), row("Salary", "2000.00", day(3, 27))) }
        importRows(file())
        importRows(file())

        assertEquals(2, all().size)
    }

    @Test
    fun `ac03 a bank row matching an auto-recorded payment within three days is not saved again`() {
        seedAutoRecordedNetflix()

        // Bank's copy of the same payment, 2 days later with its own note; a second -9.99 the
        // single generated row can't absorb; one 4 days off; one with a different amount.
        val saved = importRows(
            listOf(
                row("NETFLIX.COM 4471", "-9.99", day(3, 3)),
                row("NETFLIX.COM 4472", "-9.990", day(3, 2)),
                row("Cinema", "-9.99", day(3, 5)),
                row("Netflix plus", "-12.99", day(3, 1)),
            ),
        )

        val notes = all().map { it.note }.sorted()
        assertEquals(listOf("Cinema", "NETFLIX.COM 4472", "Netflix", "Netflix plus"), notes)
        assertEquals(3, saved?.size)
    }

    @Test
    fun `ac03 the preview counts a matched bank row as a duplicate`() {
        seedAutoRecordedNetflix()
        val incoming = listOf(row("NETFLIX.COM 4471", "-9.99", day(3, 3)), row("Rent", "-750.00", day(3, 1)))

        val (fresh, duplicates) = ImportReconciler.split(incoming, all())

        assertEquals(listOf("Rent"), fresh.map { it.note })
        assertEquals(listOf("NETFLIX.COM 4471"), duplicates.map { it.note })
    }

    @Test
    fun `ac02 a rule batch that fails half way saves no rule`() = runBlocking {
        fun suggestion(note: String, interval: Int) = RecurrenceSuggestion(
            frequency = RecurrenceFrequency.MONTHLY, interval = interval, amount = BigDecimal("-50"), note = note,
            categoryLabel = "Bills", categoryId = null, currencyCode = "EUR", occurrenceCount = 3, nextDate = day(4, 1),
            occurrenceDates = listOf(day(1, 1), day(2, 1), day(3, 1)), amountsIdentical = true, goalId = null,
        )
        val done = CompletableDeferred<Boolean>()
        // The second rule is invalid (interval 0), so the repository rejects it after the first was written.
        vm.planRecurring(listOf(suggestion("Gym", 1), suggestion("Broken", 0)), emptyList()) { done.complete(it) }

        assertFalse(withTimeout(10_000) { done.await() })
        assertEquals(emptyList<RecurrenceRule>(), recurrence.activeRules(day(3, 10)))
    }
}
