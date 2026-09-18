package com.rizzog99.personalfinancetracker.domain.import

import com.rizzog99.personalfinancetracker.domain.category.FinanceCategory
import com.rizzog99.personalfinancetracker.domain.category.TransactionType
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class CategoryAutoMapperTest {
    private fun category(name: String, type: TransactionType) =
        FinanceCategory(id = name, name = name, iconToken = "tag", type = type, colorToken = "categoryIndigo", monthlyBudget = null, currencyCode = "EUR")

    @Test
    fun `exact name match wins regardless of case`() {
        val pool = listOf(category("Groceries", TransactionType.EXPENSE))
        assertEquals("Groceries", CategoryAutoMapper.bestMatch("groceries", pool)?.name)
    }

    @Test
    fun `matches across languages via the synonym table`() {
        val pool = listOf(category("Transport", TransactionType.EXPENSE))
        assertEquals("Transport", CategoryAutoMapper.bestMatch("Trasporti", pool)?.name)
        assertEquals("Transport", CategoryAutoMapper.bestMatch("🏍️ Moto", pool)?.name)
    }

    @Test
    fun `matches a leading emoji category via keyword overlap`() {
        val pool = listOf(category("Groceries", TransactionType.EXPENSE))
        assertEquals("Groceries", CategoryAutoMapper.bestMatch("🛒 Spesa", pool)?.name)
    }

    @Test
    fun `falls back to substring match when no synonym applies`() {
        val pool = listOf(category("Books & Education", TransactionType.EXPENSE))
        assertEquals("Books & Education", CategoryAutoMapper.bestMatch("Books", pool)?.name)
    }

    @Test
    fun `returns null when nothing matches`() {
        val pool = listOf(category("Salary", TransactionType.INCOME))
        assertNull(CategoryAutoMapper.bestMatch("Groceries", pool))
    }
}
