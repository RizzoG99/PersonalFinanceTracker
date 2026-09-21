package com.rizzog99.personalfinancetracker.domain.goal

import java.math.BigDecimal
import java.time.Instant

/** A user-defined saving target. Funding is represented by transactions linked to [id]. */
data class FinanceGoal(
    val id: String,
    val name: String,
    val targetAmount: BigDecimal,
    val deadline: Instant?,
    val colorToken: String,
    val iconToken: String,
    val createdAt: Instant,
)

data class NewGoal(
    val name: String,
    val targetAmount: BigDecimal,
    val deadline: Instant? = null,
    val colorToken: String = "categoryIndigo",
    val iconToken: String = "star.fill",
)
