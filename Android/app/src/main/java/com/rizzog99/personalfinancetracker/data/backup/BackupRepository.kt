package com.rizzog99.personalfinancetracker.data.backup

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
import kotlinx.coroutines.flow.first
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
 * Recurrence rules are not included: restoring a rule's future materialization correctly is a
 * larger feature on its own, so a restore brings back every transaction (including past
 * recurring occurrences) and every category/goal, but recurring series need to be re-created.
 */
class BackupRepository(
    private val database: PersonalFinanceDatabase,
    private val transactionRepository: TransactionRepository,
    private val categoryRepository: CategoryRepository,
    private val goalRepository: GoalRepository,
) {
    suspend fun export(output: OutputStream) {
        val transactions = transactionRepository.observeAll().first()
        val categories = categoryRepository.observeAll().first()
        val goals = goalRepository.observeAll().first()

        val root = JSONObject().apply {
            put("version", 1)
            put("exportedAt", Instant.now().toString())
            put(
                "categories",
                JSONArray(
                    categories.map { category ->
                        JSONObject().apply {
                            put("name", category.name)
                            put("iconToken", category.iconToken)
                            put("type", category.type.name)
                            put("colorToken", category.colorToken)
                            put("monthlyBudget", category.monthlyBudget?.toPlainString())
                            put("currencyCode", category.currencyCode)
                        }
                    },
                ),
            )
            put(
                "transactions",
                JSONArray(
                    transactions.map { transaction ->
                        JSONObject().apply {
                            put("id", transaction.id)
                            put("timestamp", transaction.timestamp.toString())
                            put("amount", transaction.amount.toPlainString())
                            put("note", transaction.note)
                            put("categoryLabel", transaction.categoryLabel)
                            put("categoryId", transaction.categoryId)
                            put("currencyCode", transaction.currencyCode)
                            put("goalId", transaction.goalId)
                        }
                    },
                ),
            )
            put(
                "goals",
                JSONArray(
                    goals.map { goal ->
                        JSONObject().apply {
                            put("name", goal.name)
                            put("targetAmount", goal.targetAmount.toPlainString())
                            put("deadline", goal.deadline?.toString())
                            put("colorToken", goal.colorToken)
                            put("iconToken", goal.iconToken)
                        }
                    },
                ),
            )
        }
        output.bufferedWriter().use { it.write(root.toString()) }
    }

    /**
     * Replaces all local data with the contents of [input], all or nothing (#316).
     *
     * The whole file is parsed before the database is touched, so an invalid file throws with the
     * data untouched. The replacement then runs in one Room transaction: a failed write or a
     * cancelled caller rolls it back. Safe to call from the main thread.
     */
    suspend fun import(input: InputStream) {
        val backup = withContext(Dispatchers.IO) { parse(input.bufferedReader().readText()) }

        database.withTransaction {
            // Same tables clearAllTables() empties, but inside this transaction: clearAllTables()
            // commits on its own and refuses the main thread.
            val tables = database.query(
                "SELECT name FROM sqlite_master WHERE type = 'table' " +
                    "AND name NOT IN ('android_metadata', 'room_master_table') AND name NOT LIKE 'sqlite_%'",
                null,
            ).use { cursor -> buildList { while (cursor.moveToNext()) add(cursor.getString(0)) } }
            tables.forEach { database.openHelper.writableDatabase.execSQL("DELETE FROM `$it`") }

            // categoryId in the backup is a generated id from the old install; category names are
            // the only stable identifier we can restore against, so re-create categories first and
            // remap transactions to the freshly generated ids by name.
            val idByName = backup.categories.associate { it.name to categoryRepository.add(it).id }
            transactionRepository.insertBatch(backup.transactions.map { it.copy(categoryId = idByName[it.categoryLabel]) })
            backup.goals.forEach { goalRepository.add(it) }
            // A backup without categories must not leave the app with none (as on a fresh install).
            categoryRepository.seedDefaultsIfEmpty()
        }
    }

    private class Backup(
        val categories: List<NewCategory>,
        val transactions: List<FinanceTransaction>,
        val goals: List<NewGoal>,
    )

    /** Throws on anything that is not a complete version-1 backup. */
    private fun parse(text: String): Backup {
        // JSONObject(text) alone stops after the first object and ignores whatever follows.
        val tokener = JSONTokener(text)
        val root = tokener.nextValue() as? JSONObject ?: throw JSONException("Backup is not a JSON object")
        // nextClean() skips whitespace and returns '\u0000' only at the end of the input.
        if (tokener.nextClean() != '\u0000') throw JSONException("Unexpected content after the backup")
        // Exact Integer 1: getInt() would coerce 1.9 or "1" to 1.
        require(root.opt("version") == 1) { "Unsupported backup version" }
        return Backup(
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
    }

    private fun JSONArray.objects() = (0 until length()).map(::getJSONObject)

    /** A required string field; getString() would turn JSON null or a number into text. */
    private fun JSONObject.text(name: String): String =
        get(name) as? String ?: throw JSONException("$name is not a string")
}
