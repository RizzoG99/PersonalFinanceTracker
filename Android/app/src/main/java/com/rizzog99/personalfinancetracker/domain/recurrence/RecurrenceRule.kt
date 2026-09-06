package com.rizzog99.personalfinancetracker.domain.recurrence

import java.math.BigDecimal
import java.time.Instant

enum class RecurrenceFrequency {
    WEEKLY,
    MONTHLY,
    YEARLY,

    ;

    companion object
}

data class RecurrenceRule(
    val id: String,
    val frequency: RecurrenceFrequency,
    val interval: Int,
    val startDate: Instant,
    val endDate: Instant?,
    val lastMaterializedDate: Instant?,
    val amount: BigDecimal,
    val note: String,
    val categoryLabel: String,
    val categoryId: String?,
    val currencyCode: String,
    val goalId: String?,
)

data class NewRecurrenceRule(
    val frequency: RecurrenceFrequency,
    val interval: Int,
    val startDate: Instant,
    val amount: BigDecimal,
    val note: String,
    val categoryLabel: String,
    val categoryId: String?,
    val currencyCode: String,
    val goalId: String? = null,
)
