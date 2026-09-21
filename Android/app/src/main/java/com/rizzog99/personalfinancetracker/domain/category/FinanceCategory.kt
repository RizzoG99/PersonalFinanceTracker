package com.rizzog99.personalfinancetracker.domain.category

import java.math.BigDecimal

enum class TransactionType {
    INCOME,
    EXPENSE,

    ;

    companion object
}

data class FinanceCategory(
    val id: String,
    val name: String,
    val iconToken: String,
    val type: TransactionType,
    val colorToken: String,
    val monthlyBudget: BigDecimal?,
    val currencyCode: String,
)

data class NewCategory(
    val name: String,
    val iconToken: String,
    val type: TransactionType,
    val colorToken: String = "categoryIndigo",
    val monthlyBudget: BigDecimal? = null,
    val currencyCode: String = "EUR",
)
