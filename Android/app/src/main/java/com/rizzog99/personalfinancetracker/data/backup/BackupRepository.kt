package com.rizzog99.personalfinancetracker.data.backup

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
import kotlinx.coroutines.flow.first
import org.json.JSONArray
import org.json.JSONObject

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

    /** Replaces all local data with the contents of [input]. */
    suspend fun import(input: InputStream) {
        val root = JSONObject(input.bufferedReader().readText())
        val categoriesJson = root.optJSONArray("categories") ?: JSONArray()
        val transactionsJson = root.optJSONArray("transactions") ?: JSONArray()
        val goalsJson = root.optJSONArray("goals") ?: JSONArray()

        database.clearAllTables()

        // categoryId in the backup is a generated id from the old install; category names are
        // the only stable identifier we can restore against, so re-create categories first and
        // remap transactions/goals to the freshly generated ids by name.
        val idByName = HashMap<String, String>()
        for (i in 0 until categoriesJson.length()) {
            val json = categoriesJson.getJSONObject(i)
            val created = categoryRepository.add(
                NewCategory(
                    name = json.getString("name"),
                    iconToken = json.getString("iconToken"),
                    type = TransactionType.valueOf(json.getString("type")),
                    colorToken = json.optString("colorToken", "categoryIndigo"),
                    monthlyBudget = json.optString("monthlyBudget", null)?.let(::BigDecimal),
                    currencyCode = json.optString("currencyCode", "EUR"),
                ),
            )
            idByName[json.getString("name")] = created.id
        }

        val transactions = (0 until transactionsJson.length()).map { i ->
            val json = transactionsJson.getJSONObject(i)
            val categoryLabel = json.getString("categoryLabel")
            FinanceTransaction(
                id = json.getString("id"),
                timestamp = Instant.parse(json.getString("timestamp")),
                amount = BigDecimal(json.getString("amount")),
                note = json.getString("note"),
                categoryLabel = categoryLabel,
                categoryId = idByName[categoryLabel],
                currencyCode = json.getString("currencyCode"),
                goalId = null,
                recurrenceRuleId = null,
            )
        }
        transactionRepository.insertBatch(transactions)

        for (i in 0 until goalsJson.length()) {
            val json = goalsJson.getJSONObject(i)
            goalRepository.add(
                NewGoal(
                    name = json.getString("name"),
                    targetAmount = BigDecimal(json.getString("targetAmount")),
                    deadline = json.optString("deadline", null)?.let(Instant::parse),
                    colorToken = json.optString("colorToken", "categoryIndigo"),
                    iconToken = json.optString("iconToken", "star.fill"),
                ),
            )
        }
    }
}
