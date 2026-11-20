package com.rizzog99.personalfinancetracker.data.backup

import android.database.Cursor
import androidx.room.withTransaction
import com.rizzog99.personalfinancetracker.data.local.PersonalFinanceDatabase
import com.rizzog99.personalfinancetracker.data.repository.CategoryRepository
import com.rizzog99.personalfinancetracker.data.repository.GoalRepository
import com.rizzog99.personalfinancetracker.data.repository.TransactionRepository
import com.rizzog99.personalfinancetracker.domain.category.NewCategory
import com.rizzog99.personalfinancetracker.domain.category.TransactionType
import com.rizzog99.personalfinancetracker.domain.goal.NewGoal
import com.rizzog99.personalfinancetracker.domain.transaction.FinanceTransaction
import java.io.InputStream
import java.io.OutputStream
import java.math.BigDecimal
import java.time.Instant
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import org.json.JSONArray
import org.json.JSONException
import org.json.JSONObject
import org.json.JSONTokener

/**
 * Whole-app backup/restore as a single JSON file, written through the system file picker
 * (Storage Access Framework) so the user can target Google Drive, another cloud provider, or
 * local storage without this app needing Drive API credentials.
 *
 * Version 2 (#317) is a snapshot of every Android-owned Room table, row for row, so record ids,
 * category and goal links, recurring rules with their materialization cursor, and goal
 * contributions all survive. DataStore preferences are not part of it and a restore leaves them
 * alone. Version 1 files (categories, transactions, goals without ids) still restore, minus goal
 * links and recurring series; [import] reports that so the user can be told.
 */
class BackupRepository(
    private val database: PersonalFinanceDatabase,
    private val transactionRepository: TransactionRepository,
    private val categoryRepository: CategoryRepository,
    private val goalRepository: GoalRepository,
) {
    companion object {
        /** In restore order, so every foreign key finds its parent. The forecast cache is derived, hence absent. */
        val BACKED_UP_TABLES = listOf(
            "categories", "goals", "recurrence_rules", "transactions",
            "credit_cards", "health_score_snapshots", "merchant_category_mappings",
        )
        private const val VERSION = 2
        private const val FORECAST_CACHE = "daily_forecast_cache"

        /** What a v1 file replaces; legacy cards, health history and learned mappings are kept. */
        private val V1_TABLES = listOf("categories", "goals", "recurrence_rules", "transactions")

        /** Text columns the app decodes into an enum; any other value would crash the screen reading it. */
        private val ALLOWED_VALUES = mapOf(
            "categories.type" to setOf("income", "expense"),
            "recurrence_rules.frequency" to setOf("weekly", "monthly", "yearly"),
        )
    }

    suspend fun export(output: OutputStream) {
        // One read transaction: a consistent snapshot, off the main thread.
        val tables = database.withTransaction {
            JSONObject().apply { BACKED_UP_TABLES.forEach { put(it, rows(it)) } }
        }
        val root = JSONObject()
            .put("version", VERSION)
            .put("exportedAt", Instant.now().toString())
            .put("tables", tables)
        output.bufferedWriter().use { it.write(root.toString()) }
    }

    /**
     * Replaces the local data with the contents of [input], all or nothing (#316), and returns
     * true when it was a version-1 file, which carries no goal links or recurring series.
     *
     * The whole file is parsed and checked against the schema before the database is touched,
     * so an invalid file throws with the data untouched. The replacement then runs in one Room
     * transaction: a failed write, a dangling link or a cancelled caller rolls it back. Safe to
     * call from the main thread.
     */
    suspend fun import(input: InputStream): Boolean {
        val backup = withContext(Dispatchers.IO) { parse(input.bufferedReader().readText()) }
        database.withTransaction {
            when (backup) {
                is Snapshot -> {
                    clear(BACKED_UP_TABLES + FORECAST_CACHE)
                    backup.tables.forEach { (table, rows) -> rows.forEach { insert(table, it) } }
                }
                is LegacyBackup -> {
                    clear(V1_TABLES + FORECAST_CACHE)
                    // v1 has no category ids: relink by name and type, the type taken from the
                    // amount's sign as iOS does (BackupModels.swift:49-66), so same-name income and
                    // expense categories each keep their own transactions.
                    val idByKey = backup.categories.map { categoryRepository.add(it) }.associate { (it.name to it.type) to it.id }
                    transactionRepository.insertBatch(
                        backup.transactions.map { it.copy(categoryId = idByKey[it.categoryLabel to it.amount.type]) },
                    )
                    backup.goals.forEach { goalRepository.add(it) }
                }
            }
            // A backup without categories must not leave the app with none (as on a fresh install).
            categoryRepository.seedDefaultsIfEmpty()
            if (backup is LegacyBackup) {
                // Kept mappings whose category is gone (a renamed one comes back under a new id)
                // could never resolve again; drop them rather than keep dead preferences. After
                // seeding, so a mapping to a default category survives an empty v1 file.
                database.openHelper.writableDatabase.execSQL(
                    "DELETE FROM merchant_category_mappings WHERE categoryId NOT IN (SELECT id FROM categories)",
                )
            }
        }
        return backup is LegacyBackup
    }

    private sealed interface Backup
    private class Snapshot(val tables: List<Pair<String, List<Map<String, Any?>>>>) : Backup
    private class LegacyBackup(
        val categories: List<NewCategory>,
        val transactions: List<FinanceTransaction>,
        val goals: List<NewGoal>,
    ) : Backup

    private val BigDecimal.type get() = if (signum() < 0) TransactionType.EXPENSE else TransactionType.INCOME

    private fun clear(tables: List<String>) {
        // Inside the caller's transaction: clearAllTables() commits on its own and refuses the main thread.
        tables.forEach { database.openHelper.writableDatabase.execSQL("DELETE FROM `$it`") }
    }

    private fun insert(table: String, row: Map<String, Any?>) {
        database.openHelper.writableDatabase.execSQL(
            "INSERT INTO `$table` (${row.keys.joinToString { "`$it`" }}) VALUES (${row.keys.joinToString { "?" }})",
            row.values.toTypedArray(),
        )
    }

    private fun rows(table: String) = JSONArray().also { array ->
        database.query("SELECT * FROM `$table`", null).use { cursor ->
            while (cursor.moveToNext()) {
                array.put(
                    JSONObject().also { row ->
                        for (i in 0 until cursor.columnCount) {
                            row.put(
                                cursor.getColumnName(i),
                                when (cursor.getType(i)) {
                                    Cursor.FIELD_TYPE_NULL -> JSONObject.NULL
                                    Cursor.FIELD_TYPE_INTEGER -> cursor.getLong(i)
                                    Cursor.FIELD_TYPE_STRING -> cursor.getString(i)
                                    else -> error("Unsupported value in $table.${cursor.getColumnName(i)}")
                                },
                            )
                        }
                    },
                )
            }
        }
    }

    /** Declared SQLite type ("TEXT", "INTEGER") of each column of [table]. */
    private fun columnTypes(table: String): Map<String, String> =
        database.query("PRAGMA table_info(`$table`)", null).use { cursor ->
            buildMap {
                val name = cursor.getColumnIndexOrThrow("name")
                val type = cursor.getColumnIndexOrThrow("type")
                while (cursor.moveToNext()) put(cursor.getString(name), cursor.getString(type).uppercase())
            }
        }

    /** Throws on anything that is not a complete version-1 or version-2 backup. */
    private fun parse(text: String): Backup {
        // JSONObject(text) alone stops after the first object and ignores whatever follows.
        val tokener = JSONTokener(text)
        val root = tokener.nextValue() as? JSONObject ?: throw JSONException("Backup is not a JSON object")
        // Only JSON whitespace may follow (nextClean() would also skip comments and NUL).
        while (tokener.more()) {
            if (tokener.next() !in " \t\r\n") throw JSONException("Unexpected content after the backup")
        }
        // Exact Integer: getInt() would coerce 1.9 or "1" to 1.
        return when (root.opt("version")) {
            VERSION -> parseSnapshot(root.getJSONObject("tables"))
            1 -> parseV1(root)
            else -> throw IllegalArgumentException("Unsupported backup version")
        }
    }

    /**
     * Every table present, every column known and of its declared type, decimals parseable and
     * enum columns within range. NOT NULL, uniqueness and foreign keys are left to SQLite inside
     * the restore transaction, which rolls back on any violation.
     */
    private fun parseSnapshot(tables: JSONObject): Snapshot {
        val unknown = tables.keys().asSequence().toSet() - BACKED_UP_TABLES.toSet()
        if (unknown.isNotEmpty()) throw JSONException("Unknown tables: $unknown")
        return Snapshot(
            BACKED_UP_TABLES.map { table ->
                val types = columnTypes(table)
                table to tables.getJSONArray(table).objects().map { json ->
                    // Every column, every row: an omitted one would silently take SQLite's default
                    // (a missing goalId drops a contribution, a missing autoRecord records a forecast).
                    val columns = json.keys().asSequence().toSet()
                    if (columns != types.keys) throw JSONException("$table row columns ${columns.sorted()} != ${types.keys.sorted()}")
                    columns.associateWith { column ->
                        val value = json.get(column)
                        val type = types[column] ?: throw JSONException("Unknown column $table.$column")
                        when {
                            value == JSONObject.NULL -> null
                            type == "INTEGER" && (value is Int || value is Long) -> (value as Number).toLong()
                            type == "TEXT" && value is String -> value.also {
                                if (column.endsWith("Decimal")) BigDecimal(it)
                                ALLOWED_VALUES["$table.$column"]?.let { allowed -> require(it in allowed) { "Invalid $table.$column" } }
                            }
                            else -> throw JSONException("$table.$column has the wrong type")
                        }
                    }
                }
            },
        )
    }

    private fun parseV1(root: JSONObject) = LegacyBackup(
        categories = root.getJSONArray("categories").objects().map { json ->
            NewCategory(
                name = json.text("name"),
                iconToken = json.text("iconToken"),
                type = TransactionType.valueOf(json.text("type")),
                colorToken = json.optString("colorToken", "categoryIndigo"),
                monthlyBudget = json.optString("monthlyBudget", null)?.let(::BigDecimal),
                currencyCode = json.optString("currencyCode", "EUR"),
            )
        },
        transactions = root.getJSONArray("transactions").objects().map { json ->
            FinanceTransaction(
                id = json.text("id"),
                timestamp = Instant.parse(json.text("timestamp")),
                amount = BigDecimal(json.text("amount")),
                note = json.text("note"),
                categoryLabel = json.text("categoryLabel"),
                categoryId = null,
                currencyCode = json.text("currencyCode"),
                // v1 goals had no id, so their links cannot be restored.
                goalId = null,
                recurrenceRuleId = null,
            )
        },
        goals = root.getJSONArray("goals").objects().map { json ->
            NewGoal(
                name = json.text("name"),
                targetAmount = BigDecimal(json.text("targetAmount")),
                deadline = json.optString("deadline", null)?.let(Instant::parse),
                colorToken = json.optString("colorToken", "categoryIndigo"),
                iconToken = json.optString("iconToken", "star.fill"),
            )
        },
    )

    private fun JSONArray.objects() = (0 until length()).map(::getJSONObject)

    /** A required string field; getString() would turn JSON null or a number into text. */
    private fun JSONObject.text(name: String): String =
        get(name) as? String ?: throw JSONException("$name is not a string")
}
