package com.rizzog99.personalfinancetracker.features.states

import com.rizzog99.personalfinancetracker.data.preferences.UserPreferencesRepository
import com.rizzog99.personalfinancetracker.features.activity.ActivityViewModel
import com.rizzog99.personalfinancetracker.features.home.HomeViewModel
import com.rizzog99.personalfinancetracker.features.insights.InsightsViewModel
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.UnconfinedTestDispatcher
import kotlinx.coroutines.test.advanceUntilIdle
import kotlinx.coroutines.test.resetMain
import kotlinx.coroutines.test.runTest
import kotlinx.coroutines.test.setMain
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test

/**
 * `M1-UI-STATES` (#111) — the state machine from repository to rendered state, asserted at the
 * ViewModel boundary where the transitions actually happen.
 *
 * These are deliberately not Compose tests. A Compose test can show that a given state renders the
 * right copy; only this level can show that the state the screen is handed is the *correct* one —
 * that "no rows" and "the repository threw" do not collapse into the same value, and that a retry
 * runs once rather than twice.
 */
@OptIn(ExperimentalCoroutinesApi::class)
class UiStateTransitionTest {
    private val dispatcher = UnconfinedTestDispatcher()

    @Before
    fun setUp() {
        Dispatchers.setMain(dispatcher)
    }

    @After
    fun tearDown() {
        Dispatchers.resetMain()
    }

    private fun preferences() = UserPreferencesRepository(FakePreferencesDataStore())

    /**
     * `stateIn(..., WhileSubscribed)` produces nothing without a subscriber, so every test that
     * reads a state has to hold one open for as long as it reads.
     */
    private fun TestScope.keepSubscribed(state: StateFlow<*>): Job =
        backgroundScope.launch(dispatcher) { state.collect {} }

    // ---------------------------------------------------------------- AC-01 loading

    @Test
    fun `ac01 home starts in loading and leaves it once the repository answers`() = runTest(dispatcher) {
        val viewModel = HomeViewModel(
            transactionRepository = FakeTransactionRepository(listOf(transaction("t1", "-10.00"))),
            preferencesRepository = preferences(),
            categoryRepository = FakeCategoryRepository(listOf(category("c1", "Food"))),
        )
        assertTrue("before any subscriber, Home must report loading", viewModel.uiState.value.isLoading)

        keepSubscribed(viewModel.uiState)
        advanceUntilIdle()

        assertFalse("a successful load must leave the loading state", viewModel.uiState.value.isLoading)
        assertFalse("a successful load is not an error", viewModel.uiState.value.isError)
    }

    @Test
    fun `ac01 home does not stay loading forever when the repository fails`() = runTest(dispatcher) {
        val viewModel = HomeViewModel(
            transactionRepository = FakeTransactionRepository(transactions = null),
            preferencesRepository = preferences(),
            categoryRepository = FakeCategoryRepository(),
        )
        keepSubscribed(viewModel.uiState)
        advanceUntilIdle()

        val state = viewModel.uiState.value
        assertFalse(
            "a failed load must leave loading — a spinner that never resolves traps the user",
            state.isLoading,
        )
        assertTrue("a failed load must be reported as an error", state.isError)
    }

    @Test
    fun `ac01 insights starts in loading and leaves it once the repository answers`() = runTest(dispatcher) {
        val viewModel = InsightsViewModel(
            transactionRepository = FakeTransactionRepository(listOf(transaction("t1", "-10.00"))),
            goalRepository = FakeGoalRepository(),
            preferencesRepository = preferences(),
        )
        assertTrue(viewModel.uiState.value.isLoading)

        keepSubscribed(viewModel.uiState)
        advanceUntilIdle()

        assertFalse(viewModel.uiState.value.isLoading)
        assertFalse(viewModel.uiState.value.isError)
    }

    @Test
    fun `ac01 insights reports a repository failure instead of zeroed content`() = runTest(dispatcher) {
        val viewModel = InsightsViewModel(
            transactionRepository = FakeTransactionRepository(transactions = null),
            goalRepository = FakeGoalRepository(),
            preferencesRepository = preferences(),
        )
        keepSubscribed(viewModel.uiState)
        advanceUntilIdle()

        val state = viewModel.uiState.value
        assertFalse(state.isLoading)
        assertTrue("zero income and zero expenses must not stand in for a failed read", state.isError)
    }

    // ------------------------------------------------------- AC-02 first-run empty

    @Test
    fun `ac02 an empty ledger is reported as data absence not as an error`() = runTest(dispatcher) {
        val viewModel = activityViewModel(FakeTransactionRepository(emptyList()))
        keepSubscribed(viewModel.uiState)
        advanceUntilIdle()

        val state = viewModel.uiState.value
        assertTrue("no rows means no rows", state.allTransactions.isEmpty())
        assertFalse("an empty ledger is not a failure", state.isError)
        assertFalse(state.isLoading)
    }

    @Test
    fun `ac02 a repository failure is not reported as a first-run empty ledger`() = runTest(dispatcher) {
        val viewModel = activityViewModel(FakeTransactionRepository(transactions = null))
        keepSubscribed(viewModel.uiState)
        advanceUntilIdle()

        val state = viewModel.uiState.value
        assertTrue(
            "a failed read must not be dressed up as 'add your first transaction'",
            state.isError,
        )
        assertFalse(state.isLoading)
    }

    // ------------------------------------------------------------ AC-03 no results

    @Test
    fun `ac03 no results is distinguishable from an empty ledger`() = runTest(dispatcher) {
        val viewModel = activityViewModel(
            FakeTransactionRepository(listOf(transaction("t1", "-10.00", note = "coffee"))),
        )
        keepSubscribed(viewModel.uiState)
        advanceUntilIdle()

        viewModel.updateSearch("zzzz-no-such-note")
        advanceUntilIdle()

        val state = viewModel.uiState.value
        assertFalse("underlying data still exists", state.allTransactions.isEmpty())
        assertTrue("the query matches nothing", state.visibleTransactions.isEmpty())
        assertFalse("no results is not an error", state.isError)
    }

    @Test
    fun `ac03 clearing search and filters restores the results`() = runTest(dispatcher) {
        val viewModel = activityViewModel(
            FakeTransactionRepository(listOf(transaction("t1", "-10.00", note = "coffee"))),
        )
        keepSubscribed(viewModel.uiState)
        advanceUntilIdle()

        viewModel.updateSearch("zzzz-no-such-note")
        advanceUntilIdle()
        assertTrue(viewModel.uiState.value.visibleTransactions.isEmpty())

        viewModel.clearSearchAndFilters()
        advanceUntilIdle()

        assertEquals("", viewModel.uiState.value.searchText)
        assertEquals(1, viewModel.uiState.value.visibleTransactions.size)
    }

    // ------------------------------------------------------- AC-04 recoverable error

    @Test
    fun `ac04 a failed write never surfaces the injected technical text`() = runTest(dispatcher) {
        val viewModel = activityViewModel(
            FakeTransactionRepository(
                transactions = emptyList(),
                writeFailure = IllegalStateException(INJECTED_TECHNICAL_MESSAGE),
            ),
        )
        keepSubscribed(viewModel.uiState)
        advanceUntilIdle()

        val saved = viewModel.save(transaction("t1", "-10.00"))
        advanceUntilIdle()

        assertFalse("the write failed", saved)
        val shown = viewModel.error.value
        assertTrue("the failure must be reported to the user somehow", shown != null)
        assertNoTechnicalLeak(shown.toString())
    }

    @Test
    fun `ac04 a failed load never surfaces the injected technical text`() = runTest(dispatcher) {
        val viewModel = activityViewModel(FakeTransactionRepository(transactions = null))
        keepSubscribed(viewModel.uiState)
        advanceUntilIdle()

        assertTrue(viewModel.uiState.value.isError)
        assertNoTechnicalLeak(viewModel.uiState.value.toString())
    }

    // ---------------------------------------------------------------- AC-05 retry

    @Test
    fun `ac05 one retry activation resubscribes the load exactly once`() = runTest(dispatcher) {
        val repository = FakeTransactionRepository(transactions = null)
        val viewModel = HomeViewModel(
            transactionRepository = repository,
            preferencesRepository = preferences(),
            categoryRepository = FakeCategoryRepository(),
        )
        keepSubscribed(viewModel.uiState)
        advanceUntilIdle()
        assertEquals(1, repository.source.subscriptions.get())

        viewModel.retry()
        advanceUntilIdle()

        assertEquals("exactly one extra load per activation", 2, repository.source.subscriptions.get())
    }

    /**
     * The activations are deliberately **not** separated by `advanceUntilIdle()`. Letting each load
     * finish before the next tap would make `peakActive == 1` a property of the test's pacing
     * rather than of the ViewModel, and the assertion would then hold against a ViewModel with no
     * concurrency protection at all. The repository takes 500ms of virtual time to answer, so every
     * one of the five taps lands while a load is genuinely in flight.
     *
     * Both assertions are load-bearing, and they fail to different mutations:
     * `flatMapMerge` keeps every subscription alive and breaks `peakActive`; `flatMapConcat` waits
     * for a Room flow that never completes and breaks `subscriptions`.
     */
    @Test
    fun `ac05 repeated retry activations never run concurrent duplicate loads`() = runTest(dispatcher) {
        val repository = FakeTransactionRepository(
            listOf(transaction("t1", "-10.00")),
            emitDelayMillis = 500,
        )
        val viewModel = HomeViewModel(
            transactionRepository = repository,
            preferencesRepository = preferences(),
            categoryRepository = FakeCategoryRepository(),
        )
        keepSubscribed(viewModel.uiState)
        advanceUntilIdle()

        repeat(5) { viewModel.retry() }
        advanceUntilIdle()

        assertEquals(
            "at most one load may be in flight at a time",
            1,
            repository.source.peakActive.get(),
        )
        assertEquals(
            "and every activation must still start a load, not queue behind a flow that never ends",
            6,
            repository.source.subscriptions.get(),
        )
        assertFalse("the final load settles", viewModel.uiState.value.isLoading)
        assertFalse(viewModel.uiState.value.isError)
    }

    @Test
    fun `ac05 retry passes back through loading before it settles`() = runTest(dispatcher) {
        val repository = FakeTransactionRepository(
            listOf(transaction("t1", "-10.00")),
            emitDelayMillis = 500,
        )
        val viewModel = HomeViewModel(
            transactionRepository = repository,
            preferencesRepository = preferences(),
            categoryRepository = FakeCategoryRepository(),
        )
        keepSubscribed(viewModel.uiState)
        advanceUntilIdle()
        assertFalse(viewModel.uiState.value.isLoading)

        viewModel.retry()

        assertTrue(
            "the retry must show loading rather than jumping between settled states",
            viewModel.uiState.value.isLoading,
        )
        advanceUntilIdle()
        assertFalse(viewModel.uiState.value.isLoading)
    }

    @Test
    fun `ac05 a failed retry stays retryable`() = runTest(dispatcher) {
        val repository = FakeTransactionRepository(transactions = null)
        val viewModel = HomeViewModel(
            transactionRepository = repository,
            preferencesRepository = preferences(),
            categoryRepository = FakeCategoryRepository(),
        )
        keepSubscribed(viewModel.uiState)
        advanceUntilIdle()

        repeat(3) {
            viewModel.retry()
            advanceUntilIdle()
            assertTrue("still in the error state", viewModel.uiState.value.isError)
            assertFalse("and not stuck behind a spinner", viewModel.uiState.value.isLoading)
        }
        assertEquals(4, repository.source.subscriptions.get())
    }

    @Test
    fun `ac05 retry preserves the search text and filters`() = runTest(dispatcher) {
        val viewModel = activityViewModel(
            FakeTransactionRepository(listOf(transaction("t1", "-10.00", note = "coffee"))),
        )
        keepSubscribed(viewModel.uiState)
        advanceUntilIdle()

        viewModel.updateSearch("coffee")
        advanceUntilIdle()

        viewModel.retry()
        advanceUntilIdle()

        assertEquals("coffee", viewModel.uiState.value.searchText)
        assertEquals(1, viewModel.uiState.value.visibleTransactions.size)
    }

    private fun activityViewModel(transactions: FakeTransactionRepository) = ActivityViewModel(
        transactionRepository = transactions,
        categoryRepository = FakeCategoryRepository(listOf(category("c1", "Food"))),
        recurrenceRepository = UnusedRecurrenceRepository(),
    )
}

/**
 * AC-04's discrimination check. Asserting only `!contains(injectedMessage)` would pass on copy that
 * leaked a *different* exception, so the fragments below are checked individually.
 */
fun assertNoTechnicalLeak(text: String) {
    val forbidden = listOf(
        INJECTED_TECHNICAL_MESSAGE,
        "SQLiteDiskIOException",
        "IllegalStateException",
        "Exception",
        "SELECT",
        "/data/user/",
        ".db",
        "code 1802",
    )
    forbidden.forEach { fragment ->
        assertFalse(
            "user-facing copy leaked \"$fragment\" — actual copy: $text",
            text.contains(fragment, ignoreCase = true),
        )
    }
}
