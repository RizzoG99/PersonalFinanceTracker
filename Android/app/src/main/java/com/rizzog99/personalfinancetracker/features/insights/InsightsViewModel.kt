package com.rizzog99.personalfinancetracker.features.insights

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import androidx.lifecycle.viewmodel.initializer
import androidx.lifecycle.viewmodel.viewModelFactory
import com.rizzog99.personalfinancetracker.data.preferences.UserPreferencesRepository
import com.rizzog99.personalfinancetracker.data.repository.GoalRepository
import com.rizzog99.personalfinancetracker.data.repository.TransactionRepository
import com.rizzog99.personalfinancetracker.domain.goal.FinanceGoal
import com.rizzog99.personalfinancetracker.domain.goal.NewGoal
import com.rizzog99.personalfinancetracker.domain.paycycle.FinancialPeriod
import com.rizzog99.personalfinancetracker.domain.paycycle.PayCycleService
import com.rizzog99.personalfinancetracker.domain.transaction.FinanceTransaction
import java.math.BigDecimal
import java.time.Clock
import java.time.Instant
import java.time.ZoneId
import java.util.UUID
import kotlinx.coroutines.launch
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.stateIn

data class CategorySpending(val label: String, val amount: BigDecimal)

data class GoalProgress(val goal: FinanceGoal, val currentAmount: BigDecimal)
data class PaceInsight(val direction: PaceDirection, val percent: Int? = null)
enum class PaceDirection { UP, DOWN, FLAT, BUILDING }
data class HealthComponent(val name: String, val score: Int, val max: Int = 25)
data class FinancialHealth(val score: Int, val components: List<HealthComponent>)

data class InsightsUiState(
    val isLoading: Boolean = true,
    val period: FinancialPeriod? = null,
    val currencyCode: String = "EUR",
    val income: BigDecimal = BigDecimal.ZERO,
    val expenses: BigDecimal = BigDecimal.ZERO,
    val goals: List<GoalProgress> = emptyList(),
    val paceInsight: PaceInsight = PaceInsight(PaceDirection.BUILDING),
    val health: FinancialHealth? = null,
    val categorySpending: List<CategorySpending> = emptyList(),
)

class InsightsViewModel(
    private val transactionRepository: TransactionRepository,
    private val goalRepository: GoalRepository,
    private val preferencesRepository: UserPreferencesRepository,
    private val clock: Clock = Clock.systemDefaultZone(),
    private val zoneId: ZoneId = ZoneId.systemDefault(),
) : ViewModel() {
    val uiState: StateFlow<InsightsUiState> = combine(
        transactionRepository.observeAll(),
        goalRepository.observeAll(),
        preferencesRepository.payCycleStartDay,
        preferencesRepository.baseCurrency,
    ) { transactions, goals, payCycleStartDay, currencyCode ->
        val period = PayCycleService.currentFinancialMonth(payCycleStartDay, clock)
        val periodTransactions = transactions.filter { it.timestamp.atZone(zoneId).toLocalDate() in period }
        val expenseTransactions = transactions.filter { it.amount < BigDecimal.ZERO && it.goalId == null }
        val financialMonths = PayCycleService.financialMonths(6, period.endInclusive, payCycleStartDay)
        val recentStart = financialMonths.firstOrNull()?.start
        val recentTransactions = recentStart?.let { start -> transactions.filter { it.timestamp.atZone(zoneId).toLocalDate() >= start } }.orEmpty()
        val previousPeriod = PayCycleService.financialMonthContaining(period.start.minusDays(1), payCycleStartDay)
        val currentSpend = expenseTransactions.inPeriod(period, zoneId)
        val previousSpend = expenseTransactions.inPeriod(previousPeriod, zoneId)
        InsightsUiState(
            isLoading = false,
            period = period,
            currencyCode = currencyCode,
            income = periodTransactions.filter { it.amount > BigDecimal.ZERO }
                .fold(BigDecimal.ZERO) { total, transaction -> total + transaction.amount },
            expenses = periodTransactions.filter { it.amount < BigDecimal.ZERO }
                .fold(BigDecimal.ZERO) { total, transaction -> total + transaction.amount.abs() },
            goals = goals.map { goal ->
                GoalProgress(
                    goal = goal,
                    currentAmount = transactions.asSequence()
                        .filter { it.goalId == goal.id }
                        .fold(BigDecimal.ZERO) { total, transaction -> total + transaction.amount.abs() },
                )
            },
            paceInsight = paceInsight(currentSpend, previousSpend),
            health = recentTransactions.takeIf { it.isNotEmpty() }?.let { health(it, expenseTransactions, financialMonths, zoneId) },
            categorySpending = expenseTransactions.filter { it.timestamp.atZone(zoneId).toLocalDate() in period }
                .groupBy { it.categoryLabel }
                .map { (label, items) -> CategorySpending(label, items.fold(BigDecimal.ZERO) { total, item -> total + item.amount.abs() }) }
                .sortedByDescending(CategorySpending::amount),
        )
    }.stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), InsightsUiState())

    companion object {
        fun factory(
            transactionRepository: TransactionRepository,
            goalRepository: GoalRepository,
            preferencesRepository: UserPreferencesRepository,
        ) = viewModelFactory {
            initializer { InsightsViewModel(transactionRepository, goalRepository, preferencesRepository) }
        }
    }

    fun addGoal(goal: NewGoal, onFinished: (Boolean) -> Unit) = viewModelScope.launch {
        onFinished(runCatching { goalRepository.add(goal) }.isSuccess)
    }

    fun updateGoal(goal: FinanceGoal, onFinished: (Boolean) -> Unit) = viewModelScope.launch {
        onFinished(runCatching { goalRepository.update(goal) }.isSuccess)
    }

    fun deleteGoal(goal: FinanceGoal, onFinished: (Boolean) -> Unit) = viewModelScope.launch {
        onFinished(runCatching { goalRepository.delete(goal.id) }.isSuccess)
    }

    fun addFunds(goal: FinanceGoal, amount: BigDecimal, currencyCode: String, onFinished: (Boolean) -> Unit) = viewModelScope.launch {
        val result = runCatching {
            require(amount > BigDecimal.ZERO) { "A contribution must be greater than zero." }
            transactionRepository.upsert(
                FinanceTransaction(
                    id = UUID.randomUUID().toString(),
                    timestamp = Instant.now(),
                    amount = amount.negate(),
                    note = "",
                    categoryLabel = "→ ${goal.name}",
                    categoryId = null,
                    currencyCode = currencyCode,
                    goalId = goal.id,
                    recurrenceRuleId = null,
                ),
            )
        }
        onFinished(result.isSuccess)
    }
}

private fun List<FinanceTransaction>.inPeriod(period: FinancialPeriod, zoneId: ZoneId) =
    asSequence().filter { it.timestamp.atZone(zoneId).toLocalDate() in period }
        .fold(BigDecimal.ZERO) { total, transaction -> total + transaction.amount.abs() }

private fun paceInsight(current: BigDecimal, previous: BigDecimal): PaceInsight {
    if (previous <= BigDecimal.ZERO) return PaceInsight(PaceDirection.BUILDING)
    val percent = current.subtract(previous).abs().multiply(BigDecimal(100)).divide(previous, 0, java.math.RoundingMode.DOWN).toInt()
    return when {
        current < previous.multiply(BigDecimal("0.95")) -> PaceInsight(PaceDirection.DOWN, percent)
        current > previous.multiply(BigDecimal("1.10")) -> PaceInsight(PaceDirection.UP, percent)
        else -> PaceInsight(PaceDirection.FLAT)
    }
}

private fun health(
    transactions: List<FinanceTransaction>,
    expenses: List<FinanceTransaction>,
    months: List<FinancialPeriod>,
    zoneId: ZoneId,
): FinancialHealth {
    val income = transactions.filter { it.amount > BigDecimal.ZERO }.fold(BigDecimal.ZERO) { total, item -> total + item.amount }
    val totalExpenses = expenses.filter { item -> months.any { item.timestamp.atZone(zoneId).toLocalDate() in it } }
        .fold(BigDecimal.ZERO) { total, item -> total + item.amount.abs() }
    val savingsRate = if (income > BigDecimal.ZERO) income.subtract(totalExpenses).divide(income, 4, java.math.RoundingMode.DOWN) else BigDecimal.ZERO
    val savings = savingsRate.divide(BigDecimal("0.20"), 4, java.math.RoundingMode.DOWN).multiply(BigDecimal(25)).toInt().coerceIn(0, 25)
    val activeMonths = months.count { expenses.inPeriod(it, zoneId) > BigDecimal.ZERO }
    val stability = (activeMonths * 25 / months.size).coerceIn(0, 25)
    val subscriptions = expenses.filter { it.categoryLabel.contains("subscri", true) || it.categoryLabel.contains("stream", true) }
        .fold(BigDecimal.ZERO) { total, item -> total + item.amount.abs() }
    val subscriptionRatio = if (totalExpenses > BigDecimal.ZERO) subscriptions.divide(totalExpenses, 4, java.math.RoundingMode.DOWN) else BigDecimal.ZERO
    val subscription = BigDecimal.ONE.subtract(subscriptionRatio.divide(BigDecimal("0.15"), 4, java.math.RoundingMode.DOWN)).multiply(BigDecimal(25)).toInt().coerceIn(0, 25)
    val components = listOf(
        HealthComponent("Savings rate", savings),
        HealthComponent("Stability", stability),
        HealthComponent("Budget", 25),
        HealthComponent("Subscriptions", subscription),
    )
    return FinancialHealth(components.sumOf(HealthComponent::score), components)
}
