package com.rizzog99.personalfinancetracker.data.local

import androidx.sqlite.db.SupportSQLiteDatabase
import com.rizzog99.personalfinancetracker.data.repository.RoomCategoryRepository
import com.rizzog99.personalfinancetracker.data.repository.RoomCreditCardRepository
import com.rizzog99.personalfinancetracker.data.repository.RoomGoalRepository
import com.rizzog99.personalfinancetracker.data.repository.RoomInsightRepository
import com.rizzog99.personalfinancetracker.data.repository.RoomReceiptMappingRepository
import com.rizzog99.personalfinancetracker.data.repository.RoomTransactionRepository
import com.rizzog99.personalfinancetracker.domain.category.FinanceCategory
import com.rizzog99.personalfinancetracker.domain.credit.CreditCard
import com.rizzog99.personalfinancetracker.domain.goal.FinanceGoal
import com.rizzog99.personalfinancetracker.domain.transaction.FinanceTransaction
import java.math.BigDecimal
import java.time.Instant
import kotlinx.coroutines.flow.first
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull

/**
 * One representative row set covering every model a source schema can hold, shared by the migration
 * suites so `1→2`, `2→3`, and `1→3` all start from identical input and can be asserted with the
 * same expectations.
 *
 * The values sit deliberately at the edges: 29-significant-digit amounts, the epoch itself, a
 * pre-epoch timestamp, a transaction with every relationship null, and a populated derived cache.
 * A category whose name carries a non-ASCII uppercase letter is included because the `1→2`
 * `normalizedName` backfill has to agree with what the app computes for it.
 */
internal object MigrationFixtures {
    const val EXPENSE_CATEGORY_ID = "cat-expense"
    const val INCOME_CATEGORY_ID = "cat-income"
    const val ACCENTED_CATEGORY_ID = "cat-accented"

    const val DEADLINE_GOAL_ID = "goal-deadline"
    const val OPEN_GOAL_ID = "goal-open"

    const val LINKED_RULE_ID = "rule-linked"
    const val BARE_RULE_ID = "rule-bare"

    const val LINKED_TRANSACTION_ID = "txn-linked"
    const val EPOCH_TRANSACTION_ID = "txn-epoch"
    const val PRE_EPOCH_TRANSACTION_ID = "txn-pre-epoch"

    const val BOUNDARY_CARD_ID = "card-boundary"
    const val ZERO_CARD_ID = "card-zero"

    const val OLDER_SNAPSHOT_ID = "snapshot-older"
    const val NEWER_SNAPSHOT_ID = "snapshot-newer"

    /** Longer than a `Double` can hold without rounding, so a float round trip cannot pass. */
    val LARGE_NEGATIVE_AMOUNT: BigDecimal = BigDecimal("-12345678901234567890.123456789")
    val SMALLEST_AMOUNT: BigDecimal = BigDecimal("0.000000001")
    val LARGE_POSITIVE_AMOUNT: BigDecimal = BigDecimal("99999999999999999999.99")
    val CARD_BALANCE: BigDecimal = BigDecimal("12345678901234567890.123456789")
    val CARD_LIMIT: BigDecimal = BigDecimal("99999999999999999999.000000001")
    val EXPENSE_BUDGET: BigDecimal = BigDecimal("250.75")

    val EPOCH: Instant = Instant.EPOCH
    val PRE_EPOCH: Instant = Instant.ofEpochMilli(-86_400_000L)
    val LINKED_TIMESTAMP: Instant = Instant.parse("2026-03-14T09:26:53.589Z")
    val GOAL_DEADLINE: Instant = Instant.parse("2027-01-31T23:59:59.999Z")
    val GOAL_CREATED_AT: Instant = Instant.parse("2026-01-02T07:15:00Z")
    val RULE_START: Instant = Instant.parse("2026-02-01T00:00:00Z")
    val RULE_END: Instant = Instant.parse("2026-12-31T00:00:00Z")
    val RULE_LAST_MATERIALIZED: Instant = Instant.parse("2026-03-01T00:00:00Z")
    val OLDER_SNAPSHOT_AT: Instant = Instant.parse("2026-02-01T10:00:00Z")
    val NEWER_SNAPSHOT_AT: Instant = Instant.parse("2026-03-01T10:00:00Z")

    const val FORECAST_MONTH_KEY = "2026-03"
    const val FORECAST_COMPUTED_UP_TO_DAY = 21
    const val FORECAST_DAY_VALUES_JSON = """[[1,"10.05"],[21,"987654321.000000001"]]"""

    const val ACCENTED_MERCHANT_KEY = "caffè roma"
    const val UNACCENTED_MERCHANT_KEY = "caffe roma"

    /** Names are stored as the app stores them: already trimmed, original case preserved. */
    private val categories = listOf(
        Category(EXPENSE_CATEGORY_ID, "Groceries & More", "basket", "expense", "accentTeal", "250.75"),
        Category(INCOME_CATEGORY_ID, "Stipendio", "wallet", "income", "accentGreen", null),
        Category(ACCENTED_CATEGORY_ID, "CAFFÈ Bar", "cup", "expense", "accentAmber", null),
    )

    private data class Category(
        val id: String,
        val name: String,
        val iconToken: String,
        val type: String,
        val colorToken: String,
        val monthlyBudgetDecimal: String?,
    )

    val categoryNamesById: Map<String, String> = categories.associate { it.id to it.name }

    /** Schema 1 has no `normalizedName` column; the `1→2` migration adds and backfills it. */
    fun seedVersion1(db: SupportSQLiteDatabase) {
        categories.forEach { category ->
            db.execSQL(
                "INSERT INTO categories (id, name, iconToken, type, colorToken, monthlyBudgetDecimal, currencyCode) " +
                    "VALUES (?, ?, ?, ?, ?, ?, 'EUR')",
                arrayOf(
                    category.id,
                    category.name,
                    category.iconToken,
                    category.type,
                    category.colorToken,
                    category.monthlyBudgetDecimal,
                ),
            )
        }
        seedSharedTables(db)
    }

    fun seedVersion2(db: SupportSQLiteDatabase) {
        categories.forEach { category ->
            db.execSQL(
                "INSERT INTO categories " +
                    "(id, name, normalizedName, iconToken, type, colorToken, monthlyBudgetDecimal, currencyCode) " +
                    "VALUES (?, ?, ?, ?, ?, ?, ?, 'EUR')",
                arrayOf(
                    category.id,
                    category.name,
                    expectedNormalizedName(category.name),
                    category.iconToken,
                    category.type,
                    category.colorToken,
                    category.monthlyBudgetDecimal,
                ),
            )
        }
        seedSharedTables(db)
    }

    /**
     * The `normalizedName` the app itself would store for [name]. Kept as a literal expression of
     * the contract rather than a call into `CategoryNameValidator`, so a change on either side of
     * the migration boundary shows up as a test failure instead of cancelling out.
     */
    fun expectedNormalizedName(name: String): String = name.trim().lowercase()

    /** Every table below is identical in schemas 1, 2, and 3. Insert order respects the FKs. */
    private fun seedSharedTables(db: SupportSQLiteDatabase) {
        db.execSQL(
            "INSERT INTO goals " +
                "(id, name, targetAmountDecimal, deadlineEpochMillis, colorToken, iconToken, createdAtEpochMillis) " +
                "VALUES (?, 'Vacation', '1500.00', ?, 'accentBlue', 'sun', ?)",
            arrayOf(DEADLINE_GOAL_ID, GOAL_DEADLINE.toEpochMilli(), GOAL_CREATED_AT.toEpochMilli()),
        )
        db.execSQL(
            "INSERT INTO goals " +
                "(id, name, targetAmountDecimal, deadlineEpochMillis, colorToken, iconToken, createdAtEpochMillis) " +
                "VALUES (?, 'Rainy Day', '0.01', NULL, 'accentGrey', 'umbrella', ?)",
            arrayOf(OPEN_GOAL_ID, GOAL_CREATED_AT.toEpochMilli()),
        )

        db.execSQL(
            "INSERT INTO recurrence_rules (id, frequency, `interval`, startDateEpochMillis, endDateEpochMillis, " +
                "lastMaterializedDateEpochMillis, amountDecimal, note, categoryLabel, categoryId, currencyCode, goalId) " +
                "VALUES (?, 'monthly', 1, ?, ?, ?, '-49.99', 'Netflix', '📺 Subscriptions', ?, 'EUR', ?)",
            arrayOf(
                LINKED_RULE_ID,
                RULE_START.toEpochMilli(),
                RULE_END.toEpochMilli(),
                RULE_LAST_MATERIALIZED.toEpochMilli(),
                EXPENSE_CATEGORY_ID,
                DEADLINE_GOAL_ID,
            ),
        )
        db.execSQL(
            "INSERT INTO recurrence_rules (id, frequency, `interval`, startDateEpochMillis, endDateEpochMillis, " +
                "lastMaterializedDateEpochMillis, amountDecimal, note, categoryLabel, categoryId, currencyCode, goalId) " +
                "VALUES (?, 'weekly', 2, ?, NULL, NULL, '1200.00', 'Payday', '💰 Income', NULL, 'EUR', NULL)",
            arrayOf(BARE_RULE_ID, RULE_START.toEpochMilli()),
        )

        db.execSQL(
            "INSERT INTO transactions (id, timestampEpochMillis, amountDecimal, note, categoryLabel, categoryId, " +
                "currencyCode, goalId, recurrenceRuleId) VALUES (?, ?, ?, 'Bulk buy', '🛒 Groceries', ?, 'EUR', ?, ?)",
            arrayOf(
                LINKED_TRANSACTION_ID,
                LINKED_TIMESTAMP.toEpochMilli(),
                LARGE_NEGATIVE_AMOUNT.toPlainString(),
                EXPENSE_CATEGORY_ID,
                DEADLINE_GOAL_ID,
                LINKED_RULE_ID,
            ),
        )
        db.execSQL(
            "INSERT INTO transactions (id, timestampEpochMillis, amountDecimal, note, categoryLabel, categoryId, " +
                "currencyCode, goalId, recurrenceRuleId) VALUES (?, ?, ?, 'Dust', '🛒 Groceries', NULL, 'EUR', NULL, NULL)",
            arrayOf(EPOCH_TRANSACTION_ID, EPOCH.toEpochMilli(), SMALLEST_AMOUNT.toPlainString()),
        )
        db.execSQL(
            "INSERT INTO transactions (id, timestampEpochMillis, amountDecimal, note, categoryLabel, categoryId, " +
                "currencyCode, goalId, recurrenceRuleId) VALUES (?, ?, ?, 'Backdated pay', '💰 Income', ?, 'EUR', NULL, NULL)",
            arrayOf(
                PRE_EPOCH_TRANSACTION_ID,
                PRE_EPOCH.toEpochMilli(),
                LARGE_POSITIVE_AMOUNT.toPlainString(),
                INCOME_CATEGORY_ID,
            ),
        )

        db.execSQL(
            "INSERT INTO credit_cards (id, name, lastFour, balanceDecimal, limitDecimal, colorToken, currencyCode) " +
                "VALUES (?, 'Revolving Visa', '4291', ?, ?, 'accentTeal', 'EUR')",
            arrayOf(BOUNDARY_CARD_ID, CARD_BALANCE.toPlainString(), CARD_LIMIT.toPlainString()),
        )
        db.execSQL(
            "INSERT INTO credit_cards (id, name, lastFour, balanceDecimal, limitDecimal, colorToken, currencyCode) " +
                "VALUES (?, 'Amex Gold', '0007', '0', '0', 'accentAmber', 'EUR')",
            arrayOf(ZERO_CARD_ID),
        )

        db.execSQL(
            "INSERT INTO health_score_snapshots " +
                "(id, timestampEpochMillis, score, savingsScore, stabilityScore, adherenceScore, subscriptionScore) " +
                "VALUES (?, ?, 61, 55, 70, 48, 80)",
            arrayOf(OLDER_SNAPSHOT_ID, OLDER_SNAPSHOT_AT.toEpochMilli()),
        )
        db.execSQL(
            "INSERT INTO health_score_snapshots " +
                "(id, timestampEpochMillis, score, savingsScore, stabilityScore, adherenceScore, subscriptionScore) " +
                "VALUES (?, ?, 74, 66, 81, 59, 88)",
            arrayOf(NEWER_SNAPSHOT_ID, NEWER_SNAPSHOT_AT.toEpochMilli()),
        )

        db.execSQL(
            "INSERT INTO daily_forecast_cache (id, monthKey, computedUpToDay, dayValuesJson) VALUES (1, ?, ?, ?)",
            arrayOf(FORECAST_MONTH_KEY, FORECAST_COMPUTED_UP_TO_DAY, FORECAST_DAY_VALUES_JSON),
        )

        db.execSQL(
            "INSERT INTO merchant_category_mappings (normalizedMerchant, categoryId) VALUES (?, ?)",
            arrayOf(ACCENTED_MERCHANT_KEY, ACCENTED_CATEGORY_ID),
        )
        db.execSQL(
            "INSERT INTO merchant_category_mappings (normalizedMerchant, categoryId) VALUES (?, ?)",
            arrayOf(UNACCENTED_MERCHANT_KEY, EXPENSE_CATEGORY_ID),
        )
    }
}

/**
 * Reads every seeded record back through the production repositories and asserts the exact domain
 * value. Migration SQL merely executing proves nothing; this is the part that proves the records are
 * still *accessible* as the app sees them.
 *
 * Recurrence rules go through `recurrenceRuleDao()` rather than `RecurrenceRepository`, which
 * exposes no read method — the DAO on the production database is their closest accessible boundary.
 */
internal suspend fun assertEverySeededRecordIsExact(database: PersonalFinanceDatabase) {
    val categories = RoomCategoryRepository(database).observeAll().first().associateBy(FinanceCategory::id)
    assertEquals(3, categories.size)
    val expense = requireNotNull(categories[MigrationFixtures.EXPENSE_CATEGORY_ID])
    assertEquals("Groceries & More", expense.name)
    assertEquals("basket", expense.iconToken)
    assertEquals("accentTeal", expense.colorToken)
    assertEquals("EUR", expense.currencyCode)
    assertExactAmount(MigrationFixtures.EXPENSE_BUDGET, requireNotNull(expense.monthlyBudget), "expense budget")
    assertNull("a null budget must stay null", requireNotNull(categories[MigrationFixtures.INCOME_CATEGORY_ID]).monthlyBudget)
    assertEquals("CAFFÈ Bar", requireNotNull(categories[MigrationFixtures.ACCENTED_CATEGORY_ID]).name)

    // The column exists to make (normalizedName, type) unique, so a migrated value that differs
    // from what the app computes would silently stop catching duplicates.
    MigrationFixtures.categoryNamesById.forEach { (id, name) ->
        assertEquals(
            "normalizedName for $name must match what the app stores",
            MigrationFixtures.expectedNormalizedName(name),
            database.normalizedNameOf(id),
        )
    }

    val goals = RoomGoalRepository(database).observeAll().first().associateBy(FinanceGoal::id)
    assertEquals(2, goals.size)
    val deadlineGoal = requireNotNull(goals[MigrationFixtures.DEADLINE_GOAL_ID])
    assertEquals("Vacation", deadlineGoal.name)
    assertExactAmount(BigDecimal("1500.00"), deadlineGoal.targetAmount, "goal target")
    assertEquals(MigrationFixtures.GOAL_DEADLINE, deadlineGoal.deadline)
    assertEquals(MigrationFixtures.GOAL_CREATED_AT, deadlineGoal.createdAt)
    assertNull("an open-ended goal keeps a null deadline", requireNotNull(goals[MigrationFixtures.OPEN_GOAL_ID]).deadline)

    val transactions = RoomTransactionRepository(database).observeAll().first().associateBy(FinanceTransaction::id)
    assertEquals(3, transactions.size)
    val linked = requireNotNull(transactions[MigrationFixtures.LINKED_TRANSACTION_ID])
    assertExactAmount(MigrationFixtures.LARGE_NEGATIVE_AMOUNT, linked.amount, "linked transaction amount")
    assertEquals(MigrationFixtures.LINKED_TIMESTAMP, linked.timestamp)
    assertEquals("Bulk buy", linked.note)
    assertEquals("🛒 Groceries", linked.categoryLabel)
    assertEquals(MigrationFixtures.EXPENSE_CATEGORY_ID, linked.categoryId)
    assertEquals(MigrationFixtures.DEADLINE_GOAL_ID, linked.goalId)
    assertEquals(MigrationFixtures.LINKED_RULE_ID, linked.recurrenceRuleId)

    val epochTransaction = requireNotNull(transactions[MigrationFixtures.EPOCH_TRANSACTION_ID])
    assertExactAmount(MigrationFixtures.SMALLEST_AMOUNT, epochTransaction.amount, "smallest amount")
    assertEquals(MigrationFixtures.EPOCH, epochTransaction.timestamp)
    assertNull("a null category must stay null", epochTransaction.categoryId)
    assertNull("a null goal must stay null", epochTransaction.goalId)
    assertNull("a null recurrence link must stay null", epochTransaction.recurrenceRuleId)

    val preEpoch = requireNotNull(transactions[MigrationFixtures.PRE_EPOCH_TRANSACTION_ID])
    assertExactAmount(MigrationFixtures.LARGE_POSITIVE_AMOUNT, preEpoch.amount, "pre-epoch amount")
    assertEquals(MigrationFixtures.PRE_EPOCH, preEpoch.timestamp)

    val linkedRule = requireNotNull(database.recurrenceRuleDao().get(MigrationFixtures.LINKED_RULE_ID))
    assertEquals("monthly", linkedRule.frequency)
    assertEquals(1, linkedRule.interval)
    assertEquals(MigrationFixtures.RULE_START.toEpochMilli(), linkedRule.startDateEpochMillis)
    assertEquals(MigrationFixtures.RULE_END.toEpochMilli(), linkedRule.endDateEpochMillis)
    assertEquals(MigrationFixtures.RULE_LAST_MATERIALIZED.toEpochMilli(), linkedRule.lastMaterializedDateEpochMillis)
    assertEquals("-49.99", linkedRule.amountDecimal)
    assertEquals(MigrationFixtures.EXPENSE_CATEGORY_ID, linkedRule.categoryId)
    assertEquals(MigrationFixtures.DEADLINE_GOAL_ID, linkedRule.goalId)

    val bareRule = requireNotNull(database.recurrenceRuleDao().get(MigrationFixtures.BARE_RULE_ID))
    assertEquals(2, bareRule.interval)
    assertNull("an open-ended rule keeps a null end date", bareRule.endDateEpochMillis)
    assertNull("an unmaterialized rule keeps a null cursor", bareRule.lastMaterializedDateEpochMillis)
    assertNull("an uncategorized rule keeps a null category", bareRule.categoryId)
    assertNull("an unlinked rule keeps a null goal", bareRule.goalId)

    val cards = RoomCreditCardRepository(database).observeAll().first()
    assertEquals(listOf("Amex Gold", "Revolving Visa"), cards.map(CreditCard::name))
    val boundaryCard = cards.single { it.id == MigrationFixtures.BOUNDARY_CARD_ID }
    assertEquals("4291", boundaryCard.lastFour)
    assertExactAmount(MigrationFixtures.CARD_BALANCE, boundaryCard.balance, "card balance")
    assertExactAmount(MigrationFixtures.CARD_LIMIT, boundaryCard.limit, "card limit")
    val zeroCard = cards.single { it.id == MigrationFixtures.ZERO_CARD_ID }
    assertExactAmount(BigDecimal.ZERO, zeroCard.balance, "zero balance")
    assertExactAmount(BigDecimal.ZERO, zeroCard.limit, "zero limit")

    val insights = RoomInsightRepository(database)
    val snapshots = insights.recentSnapshots(limit = 10)
    assertEquals(
        listOf(MigrationFixtures.NEWER_SNAPSHOT_ID, MigrationFixtures.OLDER_SNAPSHOT_ID),
        snapshots.map { it.id },
    )
    assertEquals(MigrationFixtures.NEWER_SNAPSHOT_AT, snapshots.first().timestamp)
    assertEquals(74, snapshots.first().score)
    assertEquals(66, snapshots.first().savingsScore)
    assertEquals(81, snapshots.first().stabilityScore)
    assertEquals(59, snapshots.first().adherenceScore)
    assertEquals(88, snapshots.first().subscriptionScore)
    assertEquals(MigrationFixtures.OLDER_SNAPSHOT_AT, snapshots.last().timestamp)
    assertEquals(61, snapshots.last().score)

    val forecast = requireNotNull(insights.forecastCache())
    assertEquals(MigrationFixtures.FORECAST_MONTH_KEY, forecast.monthKey)
    assertEquals(MigrationFixtures.FORECAST_COMPUTED_UP_TO_DAY, forecast.computedUpToDay)
    assertEquals(listOf(1, 21), forecast.dayValues.map { it.day })
    assertExactAmount(BigDecimal("10.05"), forecast.dayValues.first().amount, "forecast day 1")
    assertExactAmount(BigDecimal("987654321.000000001"), forecast.dayValues.last().amount, "forecast day 21")

    val mappings = RoomReceiptMappingRepository(database)
    assertEquals(MigrationFixtures.ACCENTED_CATEGORY_ID, mappings.categoryIdFor("  Caffè Roma "))
    assertEquals(MigrationFixtures.EXPENSE_CATEGORY_ID, mappings.categoryIdFor("CAFFE ROMA"))
}

/**
 * `compareTo` alone would accept a value of equal magnitude but different scale, and
 * `stripTrailingZeros` alone would accept an unequal one, so both have to hold.
 */
internal fun assertExactAmount(expected: BigDecimal, actual: BigDecimal, label: String) {
    assertEquals("$label magnitude", 0, expected.compareTo(actual))
    assertEquals("$label scale", expected.stripTrailingZeros(), actual.stripTrailingZeros())
}

internal fun PersonalFinanceDatabase.normalizedNameOf(categoryId: String): String =
    query("SELECT normalizedName FROM categories WHERE id = ?", arrayOf(categoryId)).use { cursor ->
        cursor.moveToFirst()
        cursor.getString(0)
    }
