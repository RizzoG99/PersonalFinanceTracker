package com.rizzog99.personalfinancetracker.features.activity

import android.content.Context
import androidx.room.Room
import androidx.test.core.app.ApplicationProvider
import com.rizzog99.personalfinancetracker.R
import com.rizzog99.personalfinancetracker.data.local.PersonalFinanceDatabase
import com.rizzog99.personalfinancetracker.data.local.RecurrenceRuleEntity
import com.rizzog99.personalfinancetracker.data.repository.RoomCategoryRepository
import com.rizzog99.personalfinancetracker.data.repository.RoomGoalRepository
import com.rizzog99.personalfinancetracker.data.repository.RoomRecurrenceRepository
import com.rizzog99.personalfinancetracker.data.repository.RoomTransactionRepository
import com.rizzog99.personalfinancetracker.domain.category.FinanceCategory
import com.rizzog99.personalfinancetracker.domain.category.TransactionType
import com.rizzog99.personalfinancetracker.domain.goal.NewGoal
import com.rizzog99.personalfinancetracker.domain.transaction.FinanceTransaction
import com.rizzog99.personalfinancetracker.features.states.FakeCategoryRepository
import com.rizzog99.personalfinancetracker.features.states.FakeTransactionRepository
import java.math.BigDecimal
import java.time.Instant
import java.time.ZoneId
import java.util.Collections
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.launch
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.test.UnconfinedTestDispatcher
import kotlinx.coroutines.test.resetMain
import kotlinx.coroutines.test.setMain
import kotlinx.coroutines.withTimeout
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner

/**
 * #285 AC-01..AC-05 through [ActivityViewModel] on a real (in-memory) Room store.
 *
 * Fixture F (issue #285): t1 "Caffè bar" −3.00 Coffee & Drinks; t2 "Caffè casa" −12.50 Groceries,
 * goal g1; t3 "Netflix" −9.99 Streaming Services, rule r1; t4 "Stipendio" +1500.00 Salary.
 */
@OptIn(ExperimentalCoroutinesApi::class)
@RunWith(RobolectricTestRunner::class)
class ActivityBulkSelectionTest {
    private val zone = ZoneId.of("Europe/Rome")
    private lateinit var database: PersonalFinanceDatabase
    private lateinit var transactions: RoomTransactionRepository
    private lateinit var categories: RoomCategoryRepository
    private lateinit var fixture: List<FinanceTransaction>
    private lateinit var goalId: String

    @Before
    fun setUp() = runBlocking {
        Dispatchers.setMain(UnconfinedTestDispatcher())
        val context = ApplicationProvider.getApplicationContext<Context>()
        database = Room.inMemoryDatabaseBuilder(context, PersonalFinanceDatabase::class.java).allowMainThreadQueries().build()
        transactions = RoomTransactionRepository(database)
        categories = RoomCategoryRepository(database)
        categories.seedDefaultsIfEmpty()
        goalId = RoomGoalRepository(database).add(NewGoal(name = "Holiday", targetAmount = BigDecimal("500"))).id
        database.recurrenceRuleDao().insert(
            RecurrenceRuleEntity(
                id = "r1", frequency = "MONTHLY", interval = 1,
                startDateEpochMillis = Instant.parse("2026-01-12T10:00:00Z").toEpochMilli(), endDateEpochMillis = null,
                lastMaterializedDateEpochMillis = Instant.parse("2026-03-12T10:00:00Z").toEpochMilli(),
                amountDecimal = "-9.99", note = "Netflix", categoryLabel = "Streaming Services", categoryId = null,
                currencyCode = "EUR", goalId = null,
            ),
        )
        fixture = listOf(
            row("t1", "2026-03-14", "Caffè bar", "-3.00", category("Coffee & Drinks", TransactionType.EXPENSE)),
            row("t2", "2026-03-13", "Caffè casa", "-12.50", category("Groceries", TransactionType.EXPENSE), goal = goalId),
            row("t3", "2026-03-12", "Netflix", "-9.99", category("Streaming Services", TransactionType.EXPENSE), rule = "r1"),
            row("t4", "2026-03-10", "Stipendio", "1500.00", category("Salary", TransactionType.INCOME)),
        )
        fixture.forEach { transactions.upsert(it) }
        assertEquals("precondition: fixture stored", 4, transactions.observeAll().first().size)
    }

    @After
    fun tearDown() {
        database.close()
        Dispatchers.resetMain()
    }

    private suspend fun category(name: String, type: TransactionType): FinanceCategory =
        categories.observeAll().first().first { it.name == name && it.type == type }

    private fun row(id: String, date: String, note: String, amount: String, category: FinanceCategory, goal: String? = null, rule: String? = null) =
        FinanceTransaction(
            id = id, timestamp = Instant.parse("${date}T10:00:00Z"), amount = BigDecimal(amount), note = note,
            categoryLabel = category.name, categoryId = category.id, currencyCode = "EUR", goalId = goal, recurrenceRuleId = rule,
        )

    private fun viewModel() = ActivityViewModel(transactions, categories, RoomRecurrenceRepository(database), zone)

    private suspend fun ActivityViewModel.await(what: String = "state", predicate: (ActivityUiState) -> Boolean): ActivityUiState =
        try {
            withTimeout(5_000) { uiState.first { !it.isLoading && predicate(it) } }
        } catch (e: kotlinx.coroutines.TimeoutCancellationException) {
            throw AssertionError("never: $what (last: selected=${uiState.value.checkedIds})", e)
        }

    private suspend fun stored(): Map<String, FinanceTransaction> = transactions.observeAll().first().associateBy { it.id }

    private fun FinanceTransaction.assertSameAs(expected: FinanceTransaction) {
        assertEquals(0, expected.amount.compareTo(amount))
        assertEquals(expected.copy(amount = amount), this)
    }

    @Test
    fun ac01_selectAllTakesVisibleOnlyAndFiltersPrune() = runBlocking {
        val vm = viewModel()
        val keep = launch { vm.uiState.collect {} }
        vm.await("loaded") { it.allTransactions.size == 4 }
        vm.updateSearch("caffè")
        vm.await("search applied") { it.visibleTransactions.map { t -> t.id }.toSet() == setOf("t1", "t2") }
        assertNull("precondition: not selecting", vm.uiState.value.checkedIds)

        vm.startSelection("t1")
        vm.await("t1 selected") { it.checkedIds == setOf("t1") }
        vm.selectAllVisible()
        vm.await("select all = visible") { it.checkedIds == setOf("t1", "t2") }

        vm.updateSearch("caffè bar")
        vm.await("pruned to t1") { it.checkedIds == setOf("t1") }
        // Widening the search again must not bring t2 back: pruning dropped it.
        vm.updateSearch("caffè")
        vm.await("still t1") { it.visibleTransactions.size == 2 && it.checkedIds == setOf("t1") }

        vm.exitSelection()
        vm.await("exited") { it.checkedIds == null }
        assertEquals(fixture.associateBy { it.id }.keys, stored().keys)
        keep.cancel()
    }

    @Test
    fun ac01_rowDeletedElsewhereLeavesTheSelection() = runBlocking {
        val vm = viewModel()
        val keep = launch { vm.uiState.collect {} }
        vm.await("loaded") { it.allTransactions.size == 4 }
        vm.startSelection("t1")
        vm.toggleSelection("t2")
        vm.await("two selected") { it.checkedIds == setOf("t1", "t2") }
        transactions.delete("t1")
        vm.await("t1 pruned") { it.checkedIds == setOf("t2") }
        keep.cancel()
    }

    @Test
    fun ac02_bulkCategoryFlipsSignClearsGoalAndUndoRestores() = runBlocking {
        val vm = viewModel()
        val keep = launch { vm.uiState.collect {} }
        vm.await("loaded") { it.allTransactions.size == 4 }
        vm.startSelection("t1")
        vm.toggleSelection("t2")
        vm.await("two selected") { it.checkedIds == setOf("t1", "t2") }
        val salary = category("Salary", TransactionType.INCOME)

        val result = vm.bulkSetCategory(salary)
        assertNotNull(result)
        assertEquals(2, result!!.count)
        assertNull("leaves selection mode", vm.uiState.value.checkedIds)
        val after = stored()
        assertEquals(0, BigDecimal("3.00").compareTo(after.getValue("t1").amount))
        assertEquals(0, BigDecimal("12.50").compareTo(after.getValue("t2").amount))
        listOf("t1", "t2").forEach {
            assertEquals("Salary", after.getValue(it).categoryLabel)
            assertEquals(salary.id, after.getValue(it).categoryId)
            assertNull(after.getValue(it).goalId)
        }
        assertEquals("Caffè casa", after.getValue("t2").note)
        assertEquals(fixture[1].timestamp, after.getValue("t2").timestamp)
        after.getValue("t3").assertSameAs(fixture[2])

        assertTrue(vm.restore(result.prior))
        val restored = stored()
        fixture.forEach { restored.getValue(it.id).assertSameAs(it) }
        keep.cancel()
    }

    @Test
    fun ac03_bulkDeleteRemovesAllKeepsRuleAndUndoRestores() = runBlocking {
        val vm = viewModel()
        val keep = launch { vm.uiState.collect {} }
        vm.await("loaded") { it.allTransactions.size == 4 }
        vm.startSelection("t1")
        vm.toggleSelection("t2")
        vm.toggleSelection("t3")
        vm.await("three selected") { it.checkedIds == setOf("t1", "t2", "t3") }

        val result = vm.bulkDelete()
        assertEquals(3, result!!.count)
        assertEquals(setOf("t4"), stored().keys)
        val rule = database.recurrenceRuleDao().get("r1")
        assertNotNull("the rule survives", rule)
        assertNull("the rule is not closed", rule!!.endDateEpochMillis)

        assertTrue(vm.restore(result.prior))
        val restored = stored()
        fixture.forEach { restored.getValue(it.id).assertSameAs(it) }
        keep.cancel()
    }

    @Test
    fun ac03_failedBatchReportsAndChangesNothing() = runBlocking {
        val failing = FakeTransactionRepository(fixture, writeFailure = IllegalStateException("SQLITE_CONSTRAINT /data/x.db"))
        val vm = ActivityViewModel(failing, FakeCategoryRepository(emptyList()), RoomRecurrenceRepository(database), zone)
        val keep = launch { vm.uiState.collect {} }
        vm.await("loaded") { it.allTransactions.size == 4 }
        vm.startSelection("t1")
        vm.toggleSelection("t2")
        vm.await("two selected") { it.checkedIds == setOf("t1", "t2") }

        assertNull(vm.bulkDelete())
        assertEquals(R.string.activity_update_failed, vm.error.value)
        assertEquals("no row-by-row fallback", 0, failing.singleWrites)
        keep.cancel()
    }

    @Test
    fun ac04_amountKeepsSignAndNoteReplacesWithUndo() = runBlocking {
        val vm = viewModel()
        val keep = launch { vm.uiState.collect {} }
        vm.await("loaded") { it.allTransactions.size == 4 }
        vm.startSelection("t1")
        vm.toggleSelection("t4")
        vm.await("two selected") { it.checkedIds == setOf("t1", "t4") }
        val amount = vm.bulkSetAmount(BigDecimal("20"))!!
        stored().let {
            assertEquals(0, BigDecimal("-20").compareTo(it.getValue("t1").amount))
            assertEquals(0, BigDecimal("20").compareTo(it.getValue("t4").amount))
        }
        assertTrue(vm.restore(amount.prior))
        stored().let {
            it.getValue("t1").assertSameAs(fixture[0])
            it.getValue("t4").assertSameAs(fixture[3])
        }

        vm.startSelection("t1")
        vm.toggleSelection("t2")
        vm.await("two selected again") { it.checkedIds == setOf("t1", "t2") }
        val note = vm.bulkSetNote("Spesa")!!
        stored().let {
            assertEquals("Spesa", it.getValue("t1").note)
            assertEquals("Spesa", it.getValue("t2").note)
            assertEquals(goalId, it.getValue("t2").goalId)
        }
        assertTrue(vm.restore(note.prior))
        val restored = stored()
        fixture.forEach { restored.getValue(it.id).assertSameAs(it) }
        keep.cancel()
    }

    @Test
    fun ac05_eachBulkWriteRefreshesTheLedgerOnce() = runBlocking {
        val vm = viewModel()
        val keep = launch { vm.uiState.collect {} }
        vm.await("loaded") { it.allTransactions.size == 4 }
        val emissions = Collections.synchronizedList(mutableListOf<List<FinanceTransaction>>())
        val watcher = launch(Dispatchers.Default) { transactions.observeAll().collect { emissions += it } }
        val targets = setOf("t1", "t2", "t3")

        suspend fun emissionsDuring(block: suspend () -> Unit): Int {
            withTimeout(5_000) { while (emissions.isEmpty()) delay(10) }
            delay(300)
            val before = emissions.size
            block()
            delay(600)
            return emissions.size - before
        }

        suspend fun selectThree() {
            vm.startSelection("t1")
            vm.toggleSelection("t2")
            vm.toggleSelection("t3")
            vm.await("three selected") { it.checkedIds == setOf("t1", "t2", "t3") }
        }

        selectThree()
        var edit: ActivityViewModel.BulkResult? = null
        assertEquals("bulk edit", 1, emissionsDuring { edit = vm.bulkSetNote("x") })
        assertEquals("undo of the edit", 1, emissionsDuring { vm.restore(edit!!.prior) })
        selectThree()
        var deleted: ActivityViewModel.BulkResult? = null
        assertEquals("bulk delete", 1, emissionsDuring { deleted = vm.bulkDelete() })
        assertEquals("undo of the delete", 1, emissionsDuring { vm.restore(deleted!!.prior) })
        watcher.cancel()
        // No snapshot ever showed the three rows half-written (R11): all old or all new.
        emissions.forEach { snapshot ->
            val rows = snapshot.filter { it.id in targets }
            val edited = rows.count { it.note == "x" }
            assertTrue("partial edit in $rows", edited == 0 || edited == 3)
            assertTrue("partial delete: ${rows.map { it.id }}", rows.size == 0 || rows.size == 3)
        }
        keep.cancel()
    }
}
