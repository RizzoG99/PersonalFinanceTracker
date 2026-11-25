package com.rizzog99.personalfinancetracker.domain.travel

import java.time.Instant

/**
 * A named folder for the expenses of one trip (#284), frozen iOS `Models/TravelModel.swift:16-23`.
 *
 * Membership is a transaction's `travelId`, like iOS's raw UUID tag. A travel only changes how
 * Activity draws its members; budgets, insights and Safe to Spend still see each one on its own.
 */
data class FinanceTravel(
    val id: String,
    val name: String,
    /** The iOS SF Symbol name, stored as-is so the data stays portable (D-05). */
    val symbolName: String,
    val createdAt: Instant,
)

/** iOS `TravelFormSheet.symbolChoices`, in its order. */
val TRAVEL_SYMBOLS = listOf("airplane", "beach.umbrella", "mountain.2", "building.2", "car", "tram", "sailboat", "backpack")

/** iOS `TravelFormSheet.nameLimit`. */
const val TRAVEL_NAME_LIMIT = 24
