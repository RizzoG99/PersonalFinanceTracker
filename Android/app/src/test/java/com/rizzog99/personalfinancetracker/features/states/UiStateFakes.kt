package com.rizzog99.personalfinancetracker.features.states

import androidx.datastore.core.DataStore
import androidx.datastore.preferences.core.Preferences
import androidx.datastore.preferences.core.emptyPreferences
import com.rizzog99.personalfinancetracker.data.repository.CategoryRepository
import com.rizzog99.personalfinancetracker.data.repository.GoalRepository
import com.rizzog99.personalfinancetracker.data.repository.RecurrenceRepository
import com.rizzog99.personalfinancetracker.data.repository.TransactionRepository
import com.rizzog99.personalfinancetracker.domain.category.FinanceCategory
import com.rizzog99.personalfinancetracker.domain.category.NewCategory
import com.rizzog99.personalfinancetracker.domain.category.TransactionType
import com.rizzog99.personalfinancetracker.domain.goal.FinanceGoal
import com.rizzog99.personalfinancetracker.domain.goal.NewGoal
import com.rizzog99.personalfinancetracker.domain.recurrence.NewRecurrenceRule
import com.rizzog99.personalfinancetracker.domain.recurrence.RecurrenceRule
import com.rizzog99.personalfinancetracker.domain.transaction.FinanceTransaction
import java.math.BigDecimal
import java.time.Instant
import java.time.ZoneId
import java.util.concurrent.atomic.AtomicInteger
import kotlinx.coroutines.awaitCancellation
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.flow
import kotlinx.coroutines.flow.onCompletion
import kotlinx.coroutines.flow.onStart

/**
 * Fixtures for the `M1-UI-STATES` (#111) state-machine evidence.
 *
 * The distinction these exist to make testable is AC-02's: "an empty ledger" and "the repository
 * could not answer" are different states with different copy, and a fake that can only return rows
 * cannot tell them apart. Every fake here can therefore do three things — return rows, return no
 * rows, and fail — and counts how many times it was subscribed, which is what AC-05's "exactly
 * once" and "no concurrent duplicate work" are measured against.
 */

/** The technical text injected into failures. No user-facing string may ever contain it (AC-04). */
const val INJECTED_TECHNICAL_MESSAGE: String =
    "SQLiteDiskIOException: disk I/O error (code 1802) while compiling: " +
        "SELECT * FROM transactions -- /data/user/0/com.rizzog99.personalfinancetracker/databases/finance.db"

/**
 * @param emitDelayMillis how long the source stays subscribed-but-silent before its first emission.
 *   Non-zero opens a real in-flight window, which AC-05's "**while retry is active**, repeated taps
 *   must not start concurrent duplicate work" needs in order to mean anything: with an immediate
 *   emission there is never a moment when a second tap could overlap the first, so the assertion
 *   would hold against a ViewModel with no concurrency protection at all. Virtual time under
 *   `runTest` makes it free — this is a test-side window, not a fake delay in production.
 */
class CountingFlowSource<T>(
    private val value: T?,
    private val emitDelayMillis: Long = 0,
) {
    /** Total subscriptions since construction — AC-05's "exactly once per activation". */
    val subscriptions = AtomicInteger(0)

    /** Subscriptions currently live — AC-05's "no concurrent duplicate work". */
    val active = AtomicInteger(0)

    /** Highest number of simultaneously live subscriptions ever observed. */
    val peakActive = AtomicInteger(0)

    fun flow(): Flow<T> = flow {
        delay(emitDelayMillis)
        if (value == null) throw IllegalStateException(INJECTED_TECHNICAL_MESSAGE)
        emit(value)
        // A Room flow stays open after its first emission; ending here would let a collector look
        // "finished" when production would still be subscribed.
        awaitCancellation()
    }.onStart {
        subscriptions.incrementAndGet()
        val live = active.incrementAndGet()
        peakActive.updateAndGet { previous -> maxOf(previous, live) }
    }.onCompletion { active.decrementAndGet() }
}

class FakeTransactionRepository(
    transactions: List<FinanceTransaction>?,
    private val writeFailure: Throwable? = null,
    emitDelayMillis: Long = 0,
) : TransactionRepository {
    val source = CountingFlowSource(transactions, emitDelayMillis)

    override fun observeAll(): Flow<List<FinanceTransaction>> = source.flow()

    override suspend fun upsert(transaction: FinanceTransaction) {
        writeFailure?.let { throw it }
    }

    override suspend fun insertBatch(transactions: List<FinanceTransaction>) {
        writeFailure?.let { throw it }
    }

    override suspend fun delete(id: String) {
        writeFailure?.let { throw it }
    }

    override suspend fun deleteThisAndFuture(recurrenceRuleId: String, cutoff: Instant) {
        writeFailure?.let { throw it }
    }
}

class FakeCategoryRepository(
    categories: List<FinanceCategory>? = emptyList(),
    private val seedFailure: Throwable? = null,
) : CategoryRepository {
    val source = CountingFlowSource(categories)

    override fun observeAll(): Flow<List<FinanceCategory>> = source.flow()

    override suspend fun add(category: NewCategory): FinanceCategory = error("unused")

    override suspend fun update(category: FinanceCategory): FinanceCategory = error("unused")

    override suspend fun delete(id: String) = Unit

    override suspend fun seedDefaultsIfEmpty() {
        seedFailure?.let { throw it }
    }
}

class FakeGoalRepository(goals: List<FinanceGoal>? = emptyList()) : GoalRepository {
    val source = CountingFlowSource(goals)

    override fun observeAll(): Flow<List<FinanceGoal>> = source.flow()

    override suspend fun add(goal: NewGoal): FinanceGoal = error("unused")

    override suspend fun update(goal: FinanceGoal): FinanceGoal = error("unused")

    override suspend fun delete(id: String) = Unit
}

/** An in-memory [DataStore] so preference-backed flows never touch a file in a JVM test. */
class FakePreferencesDataStore : DataStore<Preferences> {
    private val state = MutableStateFlow(emptyPreferences())
    override val data: Flow<Preferences> = state

    override suspend fun updateData(
        transform: suspend (t: Preferences) -> Preferences,
    ): Preferences = transform(state.value).also { state.value = it }
}

fun transaction(
    id: String,
    amount: String,
    note: String = "",
    categoryLabel: String = "🍔 Food",
    timestamp: Instant = Instant.parse("2026-09-15T12:00:00Z"),
): FinanceTransaction = FinanceTransaction(
    id = id,
    timestamp = timestamp,
    amount = BigDecimal(amount),
    note = note,
    categoryLabel = categoryLabel,
    categoryId = null,
    currencyCode = "EUR",
    goalId = null,
    recurrenceRuleId = null,
)

fun category(id: String, name: String): FinanceCategory = FinanceCategory(
    id = id,
    name = name,
    iconToken = "cart",
    type = TransactionType.EXPENSE,
    colorToken = "accent",
    monthlyBudget = null,
    currencyCode = "EUR",
)

/** Never exercised by these tests; present only to satisfy `ActivityViewModel`'s constructor. */
class UnusedRecurrenceRepository : RecurrenceRepository {
    override suspend fun createAndMaterialize(rule: NewRecurrenceRule): RecurrenceRule = error("unused")

    override suspend fun create(rule: NewRecurrenceRule): RecurrenceRule = error("unused")

    override suspend fun materializeDue(through: Instant, zoneId: ZoneId) = Unit

    override suspend fun updateThisAndFuture(occurrence: FinanceTransaction) = error("unused")
}
