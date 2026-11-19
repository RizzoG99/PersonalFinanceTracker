package com.rizzog99.personalfinancetracker.data

import com.rizzog99.personalfinancetracker.data.local.PersonalFinanceDatabase
import com.rizzog99.personalfinancetracker.data.preferences.DismissedRecurrencePatternsRepository
import com.rizzog99.personalfinancetracker.data.repository.CategoryRepository
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

/**
 * Settings > Delete all data: the ledger, then the user choices that describe it (iOS
 * `DataWipeService.swift:16` clears the "Not fixed" answers too, so they can't outlive the data).
 */
suspend fun wipeAllData(
    database: PersonalFinanceDatabase,
    categoryRepository: CategoryRepository,
    dismissedPatterns: DismissedRecurrencePatternsRepository,
) {
    withContext(Dispatchers.IO) { database.clearAllTables() }
    categoryRepository.seedDefaultsIfEmpty()
    dismissedPatterns.clear()
}
