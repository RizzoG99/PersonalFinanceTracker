package com.rizzog99.personalfinancetracker.data.preferences

import android.content.Context
import androidx.datastore.core.DataStore
import androidx.datastore.preferences.core.Preferences
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.core.stringPreferencesKey
import com.rizzog99.personalfinancetracker.domain.import.CsvColumnMapping
import com.rizzog99.personalfinancetracker.domain.import.SignConvention
import java.security.MessageDigest
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.map
import org.json.JSONObject

/** One remembered import layout: how its columns map, plus the category answers given for it. */
data class ImportProfile(
    val mapping: CsvColumnMapping,
    val categorySelections: Map<String, String> = emptyMap(),
)

/**
 * Remembers column and category mappings per bank-file layout so re-importing a monthly statement
 * is prefilled, mirroring iOS's `ImportProfileStore`.
 *
 * Shares the `user_preferences` store rather than opening its own: it is one key, and keeping it in
 * the audited preference surface means the AC-06 key inventory covers it too.
 *
 * ponytail: one JSON blob under one key, same as iOS. Split per-signature keys only if the blob
 * ever grows past a handful of layouts.
 */
class ImportProfileRepository(private val dataStore: DataStore<Preferences>) {

    constructor(context: Context) : this(context.userPreferencesDataStore)

    internal object Keys {
        val importProfiles = stringPreferencesKey("import_profiles_v1")

        val all: List<Preferences.Key<*>> = listOf(importProfiles)
    }

    /** Signature -> profile, for every layout that decodes. */
    val profiles: Flow<Map<String, ImportProfile>> = dataStore.data.map { decode(it[Keys.importProfiles]) }

    suspend fun profile(signature: String): ImportProfile? = profiles.first()[signature]

    /**
     * The read-modify-write happens inside a single `edit` transform, so two saves for different
     * signatures running at once both survive; reading the blob outside the transform would lose
     * one of them.
     */
    suspend fun save(profile: ImportProfile, signature: String) {
        dataStore.edit { prefs ->
            val merged = decode(prefs[Keys.importProfiles]) + (signature to profile)
            prefs[Keys.importProfiles] = encode(merged)
        }
    }

    companion object {
        /**
         * Layout fingerprint: header row plus delimiter, hashed. Unit separator between headers so
         * `["a,b"]` and `["a","b"]` cannot collide. Mirrors iOS's `signature(headers:delimiter:)`
         * construction — U+001F between headers, U+001E before the delimiter — pinned by golden
         * vectors in the tests. Whether the two platforms must agree on the digest belongs to the
         * portable-archive work (#84/#87), not here.
         */
        fun signature(headers: List<String>, delimiter: Char): String {
            val payload = headers.joinToString("\u001F") + "\u001E" + delimiter
            return MessageDigest.getInstance("SHA-256")
                .digest(payload.toByteArray(Charsets.UTF_8))
                .joinToString("") { "%02x".format(it) }
        }

        private fun encode(profiles: Map<String, ImportProfile>): String {
            val root = JSONObject()
            profiles.forEach { (signature, profile) ->
                val mapping = JSONObject()
                    .put("date", profile.mapping.date)
                    .put("amount", profile.mapping.amount)
                    .put("category", profile.mapping.category)
                    .put("note", profile.mapping.note)
                    .put("type", profile.mapping.type)
                    .put("dateFormat", profile.mapping.dateFormat)
                    .put("signConvention", profile.mapping.signConvention.name)
                root.put(
                    signature,
                    JSONObject()
                        .put("mapping", mapping)
                        .put("categorySelections", JSONObject(profile.categorySelections)),
                )
            }
            return root.toString()
        }

        /**
         * Tolerant per-entry decode: a layout whose JSON is unreadable — or whose required columns
         * are missing — is skipped on its own, leaving every other remembered layout intact. An
         * unrecognized sign convention falls back to [SignConvention.SIGNED] rather than discarding
         * the rest of that layout's mapping. Nothing is rewritten or cleared on a read.
         */
        private fun decode(raw: String?): Map<String, ImportProfile> {
            val root = raw?.let { runCatching { JSONObject(it) }.getOrNull() } ?: return emptyMap()
            return root.keys().asSequence().mapNotNull { signature ->
                runCatching {
                    val entry = root.getJSONObject(signature)
                    val mapping = entry.getJSONObject("mapping")
                    val profile = ImportProfile(
                        mapping = CsvColumnMapping(
                            date = mapping.getString("date"),
                            amount = mapping.getString("amount"),
                            category = mapping.optStringOrNull("category"),
                            note = mapping.optStringOrNull("note"),
                            type = mapping.optStringOrNull("type"),
                            dateFormat = mapping.optString("dateFormat", "dd/MM/yyyy"),
                            signConvention = runCatching {
                                SignConvention.valueOf(mapping.optString("signConvention"))
                            }.getOrDefault(SignConvention.SIGNED),
                        ),
                        categorySelections = entry.optJSONObject("categorySelections")
                            ?.let { selections ->
                                selections.keys().asSequence()
                                    .mapNotNull { key -> selections.optStringOrNull(key)?.let { key to it } }
                                    .toMap()
                            }
                            .orEmpty(),
                    )
                    signature to profile
                }.getOrNull()
            }.toMap()
        }

        /** `optString` turns a JSON null into `"null"`; this keeps an absent column absent. */
        private fun JSONObject.optStringOrNull(name: String): String? =
            if (isNull(name)) null else optString(name).takeIf { it.isNotEmpty() }
    }
}
