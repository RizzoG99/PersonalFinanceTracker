package com.rizzog99.personalfinancetracker.features.data

import android.content.Context
import androidx.datastore.preferences.core.PreferenceDataStoreFactory
import androidx.room.Room
import androidx.test.core.app.ApplicationProvider
import com.rizzog99.personalfinancetracker.data.local.GoalEntity
import com.rizzog99.personalfinancetracker.data.local.PersonalFinanceDatabase
import com.rizzog99.personalfinancetracker.data.preferences.DismissedRecurrencePatternsRepository
import com.rizzog99.personalfinancetracker.data.repository.RecurrenceRepository
import com.rizzog99.personalfinancetracker.data.repository.RoomCategoryRepository
import com.rizzog99.personalfinancetracker.data.repository.RoomRecurrenceRepository
import com.rizzog99.personalfinancetracker.data.repository.RoomTransactionRepository
import com.rizzog99.personalfinancetracker.domain.recurrence.NewRecurrenceRule
import com.rizzog99.personalfinancetracker.domain.recurrence.RecurrenceRule
import com.rizzog99.personalfinancetracker.domain.recurrence.RecurrenceSuggestion
import com.rizzog99.personalfinancetracker.domain.transaction.FinanceTransaction
import java.io.File
import java.math.BigDecimal
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
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
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner

/**
 * #295 AC-01/03/04 through the production import path: [DataTransferViewModel.import] saves the
 * November file, [DataTransferViewModel.suggestRecurring] detects over the whole history, and
 * [DataTransferViewModel.planRecurring] saves forecast-only rules and remembers "Not fixed".
 */
@OptIn(ExperimentalCoroutinesApi::class)
@RunWith(RobolectricTestRunner::class)
class DataTransferRecurringTest {
    private val today: Instant = day(2026, 11, 3)
    private lateinit var database: PersonalFinanceDatabase
    private lateinit var transactions: RoomTransactionRepository
    private lateinit var recurrence: RoomRecurrenceRepository
    private lateinit var storeScope: CoroutineScope
    private lateinit var storeFile: File
    private lateinit var dismissed: DismissedRecurrencePatternsRepository
    private var nextId = 0

    @Before
    fun setUp() {
        Dispatchers.setMain(UnconfinedTestDispatcher())
        val context = ApplicationProvider.getApplicationContext<Context>()
        database = Room.inMemoryDatabaseBuilder(context, PersonalFinanceDatabase::class.java).allowMainThreadQueries().build()
        transactions = RoomTransactionRepository(database)
        recurrence = RoomRecurrenceRepository(database)
        storeFile = File(context.filesDir, "dismissed-vm-test.preferences_pb").apply { delete() }
        storeScope = CoroutineScope(Dispatchers.IO + SupervisorJob())
        dismissed = DismissedRecurrencePatternsRepository(PreferenceDataStoreFactory.create(scope = storeScope) { storeFile })
    }

    @After
    fun tearDown() {
        storeScope.cancel()
        database.close()
        storeFile.delete()
        Dispatchers.resetMain()
    }

    private fun viewModel(recurrenceRepository: RecurrenceRepository = recurrence) =
        DataTransferViewModel(transactions, RoomCategoryRepository(database), recurrenceRepository, dismissed, clock = { today })

    private fun day(year: Int, month: Int, day: Int): Instant = LocalDate.of(year, month, day).atTime(12, 0).toInstant(ZoneOffset.UTC)

    private fun row(note: String, amount: String, date: Instant, goalId: String? = null) = FinanceTransaction(
        id = "t${nextId++}", timestamp = date, amount = BigDecimal(amount), note = note, categoryLabel = if (goalId != null) "→ Emergency fund" else "Bills",
        categoryId = null, currencyCode = "EUR", goalId = goalId, recurrenceRuleId = null,
    )

    /** Aug–Oct already in the ledger; the imported file holds only November's rent. */
    private fun seedHistory() = runBlocking {
        database.goalDao().insert(GoalEntity("goal-G", "Emergency fund", "5000", null, "accentTeal", "umbrella", 0))
        transactions.insertBatch(
            listOf(
                row("Affitto agosto", "-750.00", day(2026, 8, 1)), row("Affitto settembre", "-750.00", day(2026, 9, 1)),
                row("Affitto ottobre", "-750.00", day(2026, 10, 1)),
                row("Luce", "-62.10", day(2026, 8, 5)), row("Luce", "-66.40", day(2026, 9, 5)), row("Luce", "-58.90", day(2026, 10, 5)),
                row("", "-200.00", day(2026, 8, 10), "goal-G"), row("", "-200.00", day(2026, 9, 10), "goal-G"), row("", "-200.00", day(2026, 10, 10), "goal-G"),
                row("App", "-6", day(2026, 9, 20)), row("App", "-6", day(2026, 10, 20)),
            ),
        )
    }

    private fun DataTransferViewModel.importNovember() = runBlocking {
        val done = CompletableDeferred<List<FinanceTransaction>?>()
        import(listOf(row("Affitto novembre", "-750.00", day(2026, 11, 1))), emptyMap()) { done.complete(it) }
        requireNotNull(withTimeout(10_000) { done.await() }) { "the import itself must succeed" }
    }

    private fun DataTransferViewModel.suggest(): List<RecurrenceSuggestion>? = runBlocking {
        val done = CompletableDeferred<List<RecurrenceSuggestion>?>()
        suggestRecurring { done.complete(it) }
        withTimeout(10_000) { done.await() }
    }

    private fun DataTransferViewModel.plan(selected: List<RecurrenceSuggestion>, rejected: List<RecurrenceSuggestion>): Boolean = runBlocking {
        val done = CompletableDeferred<Boolean>()
        planRecurring(selected, rejected) { done.complete(it) }
        withTimeout(10_000) { done.await() }
    }

    @Test
    fun `ac01 ac03 ac04 import, detect over history, plan the checked ones and remember the unchecked`() = runBlocking {
        seedHistory()
        val vm = viewModel()
        vm.importNovember()

        val suggestions = requireNotNull(vm.suggest())
        assertEquals(listOf("Affitto novembre", "", "Luce", "App").map { it.take(7) }, suggestions.map { it.note.take(7) })
        assertEquals(4, suggestions[0].occurrenceCount)
        assertEquals(setOf(0, 1, 2), initialRecurringSelection(suggestions))

        val selection = initialRecurringSelection(suggestions)
        assertTrue(vm.plan(suggestions.filterIndexed { i, _ -> i in selection }, suggestions.filterIndexed { i, _ -> i !in selection }))

        val rules = recurrence.activeRules(today).sortedBy { it.amount }
        assertEquals(3, rules.size)
        assertTrue("import plans forecast-only rules", rules.none(RecurrenceRule::autoRecord))
        val rent = rules.first()
        assertEquals(0, BigDecimal("-750.00").compareTo(rent.amount))
        assertEquals(day(2026, 11, 1), rent.startDate)
        assertEquals(day(2026, 11, 1), rent.lastMaterializedDate)
        assertEquals(listOf("app"), dismissed.all().map { it.note })

        // Planned and dismissed patterns are not suggested again, and nothing is recorded.
        assertEquals(emptyList<RecurrenceSuggestion>(), vm.suggest())
        val before = transactions.observeAll().first().size
        recurrence.materializeDue(through = day(2026, 12, 20), zoneId = ZoneId.of("UTC"))
        assertEquals(before, transactions.observeAll().first().size)
    }

    @Test
    fun `ac04 Done with nothing checked remembers every suggestion as not fixed`() = runBlocking {
        seedHistory()
        val vm = viewModel()
        val suggestions = requireNotNull(vm.suggest())

        assertTrue(vm.plan(emptyList(), suggestions))

        assertEquals(emptyList<RecurrenceRule>(), recurrence.activeRules(today))
        assertEquals(suggestions.size, dismissed.all().size)
        assertEquals(emptyList<RecurrenceSuggestion>(), vm.suggest())
    }

    @Test
    fun `a failing save reports false instead of crashing`() = runBlocking {
        seedHistory()
        val failing = object : RecurrenceRepository by recurrence {
            override suspend fun createAll(rules: List<NewRecurrenceRule>): List<RecurrenceRule> = error("disk full")
        }
        val vm = viewModel(failing)
        val suggestions = requireNotNull(vm.suggest())

        assertFalse(vm.plan(suggestions.take(1), emptyList()))
        assertEquals(emptyList<Any>(), dismissed.all())
    }

    @Test
    fun `a failing detection reports null instead of crashing`() = runBlocking {
        val failing = object : RecurrenceRepository by recurrence {
            override suspend fun activeRules(asOf: Instant): List<RecurrenceRule> = error("database closed")
        }
        assertNull(viewModel(failing).suggest())
    }
}
