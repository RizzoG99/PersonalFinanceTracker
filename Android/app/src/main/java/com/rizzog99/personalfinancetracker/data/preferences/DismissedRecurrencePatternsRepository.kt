package com.rizzog99.personalfinancetracker.data.preferences

import android.content.Context
import androidx.datastore.core.DataStore
import androidx.datastore.preferences.core.Preferences
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.core.stringPreferencesKey
import androidx.datastore.preferences.preferencesDataStore
import com.rizzog99.personalfinancetracker.domain.recurrence.DismissedRecurrencePattern
import com.rizzog99.personalfinancetracker.domain.recurrence.RecurrenceDetector
import com.rizzog99.personalfinancetracker.domain.recurrence.RecurrenceSuggestion
import java.math.BigDecimal
import kotlinx.coroutines.flow.first
import org.json.JSONArray
import org.json.JSONObject

private val Context.dismissedRecurrenceDataStore by preferencesDataStore(name = "dismissed_recurrence_patterns")

/**
 * Suggestions the user answered "Not fixed" to (#295), so detection never offers them again.
 * DataStore rather than Room, like iOS's UserDefaults (`DismissedRecurrencePatterns.swift`): a
 * short list of user choices, not ledger data. Cleared by Delete all data.
 * ponytail: not in backups, like iOS — a restore may re-offer a few.
 */
class DismissedRecurrencePatternsRepository(private val dataStore: DataStore<Preferences>) {
    constructor(context: Context) : this(context.dismissedRecurrenceDataStore)

    private val key = stringPreferencesKey("patterns")

    suspend fun all(): List<DismissedRecurrencePattern> = decode(dataStore.data.first()[key])

    suspend fun dismiss(suggestions: List<RecurrenceSuggestion>) {
        if (suggestions.isEmpty()) return
        dataStore.edit { prefs ->
            val patterns = decode(prefs[key]) + suggestions.map(RecurrenceDetector::dismissalPattern)
            prefs[key] = encode(patterns)
        }
    }

    suspend fun clear() {
        dataStore.edit { it.remove(key) }
    }

    /** Puts back what [all] returned before a [clear] whose wipe then rolled back (#320). */
    suspend fun restore(patterns: List<DismissedRecurrencePattern>) {
        if (patterns.isEmpty()) return
        dataStore.edit { it[key] = encode(patterns) }
    }

    private fun encode(patterns: List<DismissedRecurrencePattern>): String = JSONArray().apply {
        patterns.forEach { pattern ->
            put(
                JSONObject()
                    .put("note", pattern.note)
                    .put("amount", pattern.amount.toPlainString())
                    .apply { pattern.goalId?.let { put("goalId", it) } },
            )
        }
    }.toString()

    /** An unreadable value reads as "nothing dismissed", like iOS's `try?` decode. */
    private fun decode(json: String?): List<DismissedRecurrencePattern> = runCatching {
        val array = JSONArray(json ?: return emptyList())
        List(array.length()) { index ->
            val item = array.getJSONObject(index)
            DismissedRecurrencePattern(
                note = item.getString("note"),
                amount = BigDecimal(item.getString("amount")),
                goalId = if (item.has("goalId")) item.getString("goalId") else null,
            )
        }
    }.getOrDefault(emptyList())
}
