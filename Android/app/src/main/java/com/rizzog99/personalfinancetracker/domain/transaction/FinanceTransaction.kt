package com.rizzog99.personalfinancetracker.domain.transaction

import java.math.BigDecimal
import java.time.Instant

data class FinanceTransaction(
    val id: String,
    val timestamp: Instant,
    val amount: BigDecimal,
    val note: String,
    val categoryLabel: String,
    val categoryId: String?,
    val currencyCode: String,
    val goalId: String?,
    val recurrenceRuleId: String?,
)
