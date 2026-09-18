package com.rizzog99.personalfinancetracker.domain.import

import com.rizzog99.personalfinancetracker.domain.category.DefaultCategories
import com.rizzog99.personalfinancetracker.domain.category.FinanceCategory
import com.rizzog99.personalfinancetracker.domain.category.TransactionType
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class CategoryAutoMapperTest {
    private fun category(name: String, type: TransactionType) =
        FinanceCategory(id = name, name = name, iconToken = "tag", type = type, colorToken = "categoryIndigo", monthlyBudget = null, currencyCode = "EUR")

    /**
     * The pool the app actually seeds, so these expectations are what a real user sees. Identical
     * to iOS's default set, which is why the corpus below is shared between the two platforms.
     */
    private val expensePool: List<FinanceCategory> = DefaultCategories.all
        .filter { it.type == TransactionType.EXPENSE }
        .map { category(it.name, TransactionType.EXPENSE) }

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
    fun `an emoji-prefixed name still matches the category exactly`() {
        assertEquals("Restaurants", CategoryAutoMapper.bestMatch("🍕 Restaurants", expensePool)?.name)
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

    /**
     * The synonym table is flattened into a lookup last-write-wins, so a word listed under two keys
     * silently resolves to whichever was written last. Prevented, not debugged.
     */
    @Test
    fun `no word appears under two canonical keys`() {
        val owner = mutableMapOf<String, String>()
        val duplicates = mutableListOf<String>()
        CategoryAutoMapper.synonyms.forEach { (key, words) ->
            words.forEach { word ->
                owner[word]?.let { duplicates += "$word: $it & $key" }
                owner[word] = key
            }
        }
        assertTrue("words with two owners: ${duplicates.sorted()}", duplicates.isEmpty())
    }

    /**
     * Shared corpus with iOS's `CategoryAutoMapperTests`. Every row was a failure before the table
     * was filled in: either a silent misfile ("Petrol" to Pets, "Bollette" to Gas) or a needless
     * "create a new category" prompt. Keep the two lists in step.
     */
    @Test
    fun `lands CSV category names on the right seeded category`() {
        val corpus = listOf(
            // Italian — the language the table was originally written for.
            "Spesa" to "Groceries",
            "Ristoranti" to "Restaurants",          // plural; the table only had "ristorante"
            "Benzina" to "Gas",                     // was Public Transport
            "Carburante" to "Gas",                  // was Public Transport
            "Affitto" to "Rent/Mortgage",           // was unmatched: stem `house`, label says "Rent"
            "Bollette" to "Utilities",              // was Gas, via an order-dependent tie
            "Farmacia" to "Healthcare",
            "Palestra" to "Gym & Fitness",
            "Abbonamenti" to "Streaming Services",  // was unmatched
            "Animali" to "Pets",
            "Trasporti" to "Public Transport",
            "Viaggi" to "Travel",
            "Istruzione" to "Education",            // was Books & Education
            "Parrucchiere" to "Personal Care",      // was unmatched: stem `beauty`
            "Telefono" to "Phone Bill",             // was unmatched
            "Prelievo contante" to "Banking Fees",  // was unmatched
            "Vestiti" to "Clothing",                // was Shopping
            "Altro" to "Other",
            // English — the table had almost no English in it, so most of these were unmatched.
            "Petrol" to "Gas",                      // was Pets: "petrol".startsWith("pet")
            "Fuel" to "Gas",
            "Rent" to "Rent/Mortgage",
            "Mortgage" to "Rent/Mortgage",
            "Bills" to "Utilities",
            "Dining out" to "Restaurants",
            "Eating out" to "Restaurants",
            "Coffee" to "Coffee & Drinks",
            "Car" to "Car Maintenance",
            "Train" to "Public Transport",
            "Parking" to "Public Transport",
            "Subscriptions" to "Streaming Services",
            "Haircut" to "Personal Care",
            "Doctor" to "Healthcare",
            "Vet" to "Pets",
            "Gym" to "Gym & Fitness",
            "Utilities Bill" to "Utilities",
        )
        val failures = corpus.mapNotNull { (csv, expected) ->
            val got = CategoryAutoMapper.bestMatch(csv, expensePool)?.name
            if (got == expected) null else "$csv -> ${got ?: "unmatched"} (want $expected)"
        }
        assertTrue(failures.joinToString("\n"), failures.isEmpty())
    }

    /**
     * A category the app has no answer for must stay unmatched. Guessing here is worse than
     * prompting: a wrong mapping looks exactly as settled as a right one.
     */
    @Test
    fun `unknown categories stay unmatched`() {
        listOf("Insurance", "Taxes", "Netflix").forEach {
            assertNull(it, CategoryAutoMapper.bestMatch(it, expensePool))
        }
    }
}
