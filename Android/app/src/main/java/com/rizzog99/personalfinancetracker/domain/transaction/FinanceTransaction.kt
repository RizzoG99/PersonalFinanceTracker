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
    /** The travel this expense belongs to (#284), or none. Defaulted so existing call sites are unchanged. */
    val travelId: String? = null,
)
