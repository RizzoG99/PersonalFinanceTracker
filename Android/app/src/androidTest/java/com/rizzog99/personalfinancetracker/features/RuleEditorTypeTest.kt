package com.rizzog99.personalfinancetracker.features

import androidx.compose.ui.test.assertIsSelected
import androidx.compose.ui.test.hasClickAction
import androidx.compose.ui.test.hasContentDescription
import androidx.compose.ui.test.isEnabled
import androidx.compose.ui.test.hasText
import androidx.compose.ui.test.junit4.createComposeRule
import com.rizzog99.personalfinancetracker.R
import com.rizzog99.personalfinancetracker.domain.goal.NewGoal
import kotlinx.coroutines.runBlocking
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.performClick
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.rizzog99.personalfinancetracker.PersonalFinanceApplication
import com.rizzog99.personalfinancetracker.domain.category.FinanceCategory
import com.rizzog99.personalfinancetracker.domain.category.TransactionType
import com.rizzog99.personalfinancetracker.domain.transaction.FinanceTransaction
import com.rizzog99.personalfinancetracker.features.activity.TransactionEditorSheet
import com.rizzog99.personalfinancetracker.ui.theme.PersonalFinanceTheme
import java.math.BigDecimal
import java.time.Instant
import org.junit.Assert.assertEquals
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/**
 * #294 AC-02: a rule planned from an import can carry a category the store no longer has. Editing
 * an income one must keep it income; the editor used to fall back to Expense and save it negative.
 */
@RunWith(AndroidJUnit4::class)
class RuleEditorTypeTest {

    @get:Rule
    val rule = createComposeRule()

    private fun category(id: String, name: String, type: TransactionType) =
        FinanceCategory(id, name, "tag", type, "accent", null, "EUR")

    @Test
    fun ac02_incomeWithUnknownCategoryKeepsIncome() {
        val app = InstrumentationRegistry.getInstrumentation().targetContext.applicationContext as PersonalFinanceApplication
        val categories = listOf(
            category("food", "Food", TransactionType.EXPENSE),
            category("salary", "Salary", TransactionType.INCOME),
        )
        val salary = FinanceTransaction(
            id = "rule-salary",
            timestamp = Instant.parse("2026-01-27T09:00:00Z"),
            amount = BigDecimal("2000.00"),
            note = "Salary",
            categoryLabel = "Old salary",
            categoryId = "gone",
            currencyCode = "EUR",
            goalId = null,
            recurrenceRuleId = null,
        )
        var saved: FinanceTransaction? = null
        rule.setContent {
            PersonalFinanceTheme {
                TransactionEditorSheet(
                    editingTransaction = salary,
                    categories = categories,
                    receiptMappingRepository = app.receiptMappingRepository,
                    onDismiss = {},
                    onSave = { transaction, _, _ -> saved = transaction },
                )
            }
        }

        rule.onNodeWithContentDescription("Save").performClick()
        rule.waitForIdle()

        assertEquals(BigDecimal("2000.00"), saved?.amount)
        assertEquals("salary", saved?.categoryId)
    }

    /** #300 AC-02: a goal rule's template opens as Transfer and saves without gaining a category. */
    @Test
    fun ac02_goalRuleOpensAsTransfer() {
        val app = InstrumentationRegistry.getInstrumentation().targetContext.applicationContext as PersonalFinanceApplication
        val goal = runBlocking {
            app.database.clearAllTables()
            app.goalRepository.add(NewGoal("Emergency fund", BigDecimal("5000")))
        }
        val template = FinanceTransaction(
            id = "rule-ef",
            timestamp = Instant.parse("2026-01-27T09:00:00Z"),
            amount = BigDecimal("-200.00"),
            note = "",
            categoryLabel = "→ Emergency fund",
            categoryId = null,
            currencyCode = "EUR",
            goalId = goal.id,
            recurrenceRuleId = null,
        )
        var saved: FinanceTransaction? = null
        rule.setContent {
            PersonalFinanceTheme {
                TransactionEditorSheet(
                    editingTransaction = template,
                    categories = listOf(category("food", "Food", TransactionType.EXPENSE)),
                    receiptMappingRepository = app.receiptMappingRepository,
                    onDismiss = {},
                    onSave = { transaction, _, _ -> saved = transaction },
                    ruleCadence = "Monthly",
                )
            }
        }
        // Save as soon as it is possible: before #300 that was at once, and it gave the rule a category.
        val save = hasContentDescription("Save") and hasClickAction()
        rule.waitUntil(20_000) { rule.onAllNodes(save and isEnabled()).fetchSemanticsNodes().isNotEmpty() }
        rule.onNode(save).performClick()
        rule.waitForIdle()

        val edited = requireNotNull(saved)
        assertEquals(template.copy(amount = edited.amount), edited)
        assertEquals(0, template.amount.compareTo(edited.amount))
        rule.onNode(hasText(app.getString(R.string.transaction_type_transfer)) and hasClickAction()).assertIsSelected()
    }
}
