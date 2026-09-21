package com.rizzog99.personalfinancetracker.domain.import

import com.rizzog99.personalfinancetracker.domain.category.CategoryNameValidator
import com.rizzog99.personalfinancetracker.domain.category.FinanceCategory
import com.rizzog99.personalfinancetracker.domain.category.TransactionType

/** One category to create, plus every CSV label that should end up pointing at it. */
data class PlannedCategory(
    val name: String,
    val type: TransactionType,
    val labels: List<String>,
)

data class CategoryCreationPlan(
    /** csv label -> id of an existing category whose name it would have collided with. */
    val reuseExisting: Map<String, String>,
    /** Exactly one entry per distinct (normalized name, type). */
    val create: List<PlannedCategory>,
)

/**
 * Works out which categories an import actually needs to create.
 *
 * The `categories` table has a unique index on (normalizedName, type), and category inserts abort
 * on conflict. Creating one category per *CSV label* therefore fails the whole import whenever two
 * labels collapse to the same name — which is routine, because [forCategoryName] strips emoji, so
 * "🎁 Regali" and "Regali" are the same category and "📺Abbonamenti" and "Abbonamenti" are too. The
 * failure surfaced as "Couldn't import transactions", with nothing imported and nothing said about
 * why.
 *
 * Collapsing on the same key the database does is what keeps the two in agreement. Labels whose
 * name is already taken by an existing category reuse it rather than trying to insert a second one.
 */
object ImportCategoryPlanner {
    fun plan(
        labels: Collection<String>,
        existing: List<FinanceCategory>,
        typeOf: (String) -> TransactionType,
    ): CategoryCreationPlan {
        val existingByKey = existing.associateBy { CategoryNameValidator.normalized(it.name) to it.type }
        val reuse = mutableMapOf<String, String>()
        // Insertion-ordered so the created categories come out in the order the labels appeared,
        // which keeps a re-run of the same file producing the same thing.
        val grouped = LinkedHashMap<Pair<String, TransactionType>, PlannedCategory>()

        for (label in labels) {
            val type = typeOf(label)
            val name = label.forCategoryName()
            val key = CategoryNameValidator.normalized(name) to type
            val alreadyThere = existingByKey[key]
            if (alreadyThere != null) {
                reuse[label] = alreadyThere.id
                continue
            }
            val planned = grouped[key]
            grouped[key] = planned?.copy(labels = planned.labels + label)
                ?: PlannedCategory(name = name, type = type, labels = listOf(label))
        }
        return CategoryCreationPlan(reuseExisting = reuse, create = grouped.values.toList())
    }
}

/**
 * The name a CSV label becomes as a category. Drops anything `CategoryNameValidator` would reject,
 * emoji included, so the result is a name the user could have typed themselves.
 */
fun String.forCategoryName(): String = filter { character ->
    character.isLetterOrDigit() || character.isWhitespace() ||
        character in setOf('&', '/', '-', '\'', '.', ',', '(', ')')
}.trim().ifBlank { "Other" }
