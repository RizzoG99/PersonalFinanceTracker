package com.rizzog99.personalfinancetracker.domain.import

import com.rizzog99.personalfinancetracker.domain.category.FinanceCategory
import com.rizzog99.personalfinancetracker.domain.category.TransactionType
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class ImportCategoryPlannerTest {
    private fun category(id: String, name: String, type: TransactionType) =
        FinanceCategory(id = id, name = name, iconToken = "tag", type = type, colorToken = "categoryIndigo", monthlyBudget = null, currencyCode = "EUR")

    private fun plan(
        labels: List<String>,
        existing: List<FinanceCategory> = emptyList(),
        type: TransactionType = TransactionType.EXPENSE,
    ) = ImportCategoryPlanner.plan(labels, existing) { type }

    /**
     * The import failure behind "Couldn't import transactions. Try again."
     *
     * Category names drop emoji, so these two labels are one category as far as the unique
     * (normalizedName, type) index is concerned. Creating one per label aborted the insert and took
     * the whole import — all 1634 transactions — down with it.
     */
    @Test
    fun `labels that differ only by emoji collapse to a single created category`() {
        val result = plan(listOf("Regali", "🎁 Regali"))

        assertEquals(1, result.create.size)
        assertEquals("Regali", result.create.single().name)
        assertEquals(listOf("Regali", "🎁 Regali"), result.create.single().labels)
    }

    @Test
    fun `case and surrounding space do not make a second category either`() {
        val result = plan(listOf("Abbonamenti", "  abbonamenti ", "📺Abbonamenti"))

        assertEquals(1, result.create.size)
        assertEquals(3, result.create.single().labels.size)
    }

    /** Same name, different kind: the index is on (name, type), so these are genuinely two. */
    @Test
    fun `the same name under both types stays two categories`() {
        val result = ImportCategoryPlanner.plan(listOf("Bonus expense", "Bonus income"), emptyList()) { label ->
            if (label.endsWith("income")) TransactionType.INCOME else TransactionType.EXPENSE
        }

        assertEquals(2, result.create.size)
    }

    /** Creating a second "Groceries" would abort exactly the same way as a duplicate label. */
    @Test
    fun `a label whose name already exists reuses that category instead of creating one`() {
        val groceries = category("groceries-id", "Groceries", TransactionType.EXPENSE)
        val result = plan(listOf("🛒 Groceries"), existing = listOf(groceries))

        assertTrue(result.create.isEmpty())
        assertEquals("groceries-id", result.reuseExisting["🛒 Groceries"])
    }

    @Test
    fun `an existing category of the other type does not block creation`() {
        val incomeGift = category("gift-id", "Gift", TransactionType.INCOME)
        val result = plan(listOf("Gift"), existing = listOf(incomeGift), type = TransactionType.EXPENSE)

        assertEquals(1, result.create.size)
        assertTrue(result.reuseExisting.isEmpty())
    }

    /** An emoji-only label strips to nothing; it still has to become a nameable category. */
    @Test
    fun `an emoji-only label falls back to Other rather than an empty name`() {
        val result = plan(listOf("🎁"))

        assertEquals("Other", result.create.single().name)
    }
}
