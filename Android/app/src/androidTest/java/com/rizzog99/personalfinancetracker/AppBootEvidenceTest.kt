package com.rizzog99.personalfinancetracker

import androidx.lifecycle.Lifecycle
import androidx.test.core.app.ActivityScenario
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.rizzog99.personalfinancetracker.data.security.PinLock
import com.rizzog99.personalfinancetracker.domain.category.NewCategory
import com.rizzog99.personalfinancetracker.domain.category.TransactionType
import com.rizzog99.personalfinancetracker.domain.credit.NewCreditCard
import com.rizzog99.personalfinancetracker.domain.goal.NewGoal
import com.rizzog99.personalfinancetracker.domain.insight.HealthScoreSnapshot
import com.rizzog99.personalfinancetracker.domain.recurrence.NewRecurrenceRule
import com.rizzog99.personalfinancetracker.domain.recurrence.RecurrenceFrequency
import com.rizzog99.personalfinancetracker.domain.transaction.FinanceTransaction
import com.rizzog99.personalfinancetracker.ui.theme.ThemeMode
import java.math.BigDecimal
import java.time.Instant
import java.time.LocalTime
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.FixMethodOrder
import org.junit.Test
import org.junit.runner.RunWith
import org.junit.runners.MethodSorters

/**
 * Parity `M1-APP-BOOT` (#109) evidence that only the production app process can give: these run
 * against the installed `PersonalFinanceApplication`, its real `personal_finance.db`, its real
 * `user_preferences` DataStore, and its real Keystore-backed PIN file.
 *
 * The AC-04 pair is deliberately two tests, not one. `seed` writes, the process is force-stopped
 * from outside, and `verify` reads back in a **different** process — which is the only way a JVM or
 * single-process test cannot fake. Running them in one invocation proves nothing about durability,
 * so the evidence run invokes each separately with `-e class ...#<method>`.
 *
 * [FixMethodOrder] exists only so a whole-suite run is not order-dependent: without it JUnit can
 * schedule `verify` before `seed` and the suite fails on a cleared device. Be clear about what that
 * whole-suite pass is worth — it exercises both halves in **one** process, so it proves the
 * assertions hold, not that anything survived a restart. The durability claim rests on the
 * two-invocation run, and the two mutations that back it: dropping only the database fails
 * `verify` on "the seeded category must still exist", and dropping only the preferences file fails
 * it on the profile name.
 *
 * Method names are plain identifiers: D8 refuses to dex a lambda inside a method whose name
 * contains spaces below DEX version 040 (same constraint as `KeystorePinSecretStoreTest`).
 *
 * Out of scope on purpose: navigation behavior (#110) and PIN/biometric behavior (#80). The PIN
 * here is written and read only to exercise the `PinLock.Unknown -> Set` startup branch.
 */
@RunWith(AndroidJUnit4::class)
@FixMethodOrder(MethodSorters.NAME_ASCENDING)
class AppBootEvidenceTest {

    private val app: PersonalFinanceApplication
        get() = ApplicationProvider.getApplicationContext()

    /**
     * `AC-02`/`AC-05`: the production launcher activity reaches RESUMED in a freshly created
     * process. Complements the adb evidence rather than replacing it — this proves the lifecycle
     * state the screenshots cannot, and the screenshots prove the frame this cannot.
     */
    @Test
    fun ac02ProductionActivityReachesAUsableResumedState() {
        ActivityScenario.launch(MainActivity::class.java).use { scenario ->
            assertEquals(Lifecycle.State.RESUMED, scenario.state)
            scenario.onActivity { activity ->
                assertTrue(
                    "the activity must be attached to the production Application",
                    activity.application is PersonalFinanceApplication,
                )
                assertTrue("the window must have content", !activity.isFinishing)
            }
        }
    }

    /** `AC-04` step 1 — writes representative production-format state through real repositories. */
    @Test
    fun ac04SeedRepresentativeProductionState() = runBlocking {
        val category = app.categoryRepository.add(
            NewCategory(
                name = CATEGORY_NAME,
                iconToken = "cart.fill",
                type = TransactionType.EXPENSE,
                colorToken = "categoryIndigo",
                monthlyBudget = BigDecimal("250.00"),
            ),
        )
        val goal = app.goalRepository.add(
            NewGoal(name = GOAL_NAME, targetAmount = GOAL_TARGET, deadline = GOAL_DEADLINE),
        )
        val rule = app.recurrenceRepository.create(
            NewRecurrenceRule(
                frequency = RecurrenceFrequency.MONTHLY,
                interval = 1,
                startDate = RULE_START,
                amount = RULE_AMOUNT,
                note = RULE_NOTE,
                categoryLabel = category.name,
                categoryId = category.id,
                currencyCode = "EUR",
            ),
        )

        // An expense (negative) and an income (positive), both exact decimals, one linked to the
        // goal and one to the recurrence rule, so relationships are part of what has to survive.
        app.transactionRepository.upsert(
            FinanceTransaction(
                id = EXPENSE_ID,
                timestamp = EXPENSE_AT,
                amount = EXPENSE_AMOUNT,
                note = EXPENSE_NOTE,
                categoryLabel = category.name,
                categoryId = category.id,
                currencyCode = "EUR",
                goalId = null,
                recurrenceRuleId = rule.id,
            ),
        )
        app.transactionRepository.upsert(
            FinanceTransaction(
                id = INCOME_ID,
                timestamp = INCOME_AT,
                amount = INCOME_AMOUNT,
                note = INCOME_NOTE,
                categoryLabel = category.name,
                categoryId = category.id,
                currencyCode = "EUR",
                goalId = goal.id,
                recurrenceRuleId = null,
            ),
        )

        // Advanced records: a credit card and a health-score snapshot.
        app.creditCardRepository.add(
            NewCreditCard(
                name = CARD_NAME,
                lastFour = CARD_LAST_FOUR,
                balance = CARD_BALANCE,
                limit = CARD_LIMIT,
            ),
        )
        app.insightRepository.saveSnapshot(
            HealthScoreSnapshot(
                id = SNAPSHOT_ID,
                timestamp = SNAPSHOT_AT,
                score = 72,
                savingsScore = 18,
                stabilityScore = 20,
                adherenceScore = 19,
                subscriptionScore = 15,
            ),
        )

        // Non-secret preferences, every one of them different from its default so a silent reset
        // is detectable rather than indistinguishable from "never written".
        app.preferencesRepository.setUserFullName(PROFILE_NAME)
        app.preferencesRepository.setPayCycleStartDay(PAY_CYCLE_START_DAY)
        app.preferencesRepository.setThemeMode(ThemeMode.LIGHT)
        app.preferencesRepository.setHideBalance(true)
        app.preferencesRepository.setHealthScoreIgnoreSubscriptions(true)
        app.preferencesRepository.setDailyReminderEnabled(true)
        app.preferencesRepository.setDailyReminderTime(REMINDER_TIME)

        // Written here so the file exists on disk; the seed run does not assert on it.
        writeSeedMarker(category.id, goal.id, rule.id)
    }

    /**
     * `AC-04` step 2 — the same records, read back in a process created after a force-stop. Exact
     * values, not "some rows exist": a reset that replaced the data with plausible defaults has to
     * fail this.
     */
    @Test
    fun ac04VerifyRepresentativeProductionStateSurvivesProcessRecreation() = runBlocking {
        val ids = readSeedMarker()

        val categories = app.categoryRepository.observeAll().first()
        val category = categories.firstOrNull { it.id == ids.categoryId }
        assertNotNull("the seeded category must still exist", category)
        assertEquals(CATEGORY_NAME, category!!.name)
        assertEquals(0, BigDecimal("250.00").compareTo(category.monthlyBudget))
        assertTrue(
            "the 38 seeded defaults must not have been re-seeded on top",
            categories.count { it.name == CATEGORY_NAME } == 1,
        )

        val transactions = app.transactionRepository.observeAll().first()
        val expense = transactions.firstOrNull { it.id == EXPENSE_ID }
        val income = transactions.firstOrNull { it.id == INCOME_ID }
        assertNotNull("the seeded expense must still exist", expense)
        assertNotNull("the seeded income must still exist", income)
        // compareTo, not equals: scale is not what durability promises, value is.
        assertEquals("expense amount must be exact", 0, EXPENSE_AMOUNT.compareTo(expense!!.amount))
        assertEquals("income amount must be exact", 0, INCOME_AMOUNT.compareTo(income!!.amount))
        assertEquals(EXPENSE_NOTE, expense.note)
        assertEquals(INCOME_NOTE, income.note)
        assertEquals(EXPENSE_AT, expense.timestamp)
        assertEquals(INCOME_AT, income.timestamp)
        assertEquals("the recurrence link must survive", ids.ruleId, expense.recurrenceRuleId)
        assertEquals("the goal link must survive", ids.goalId, income.goalId)
        assertEquals(ids.categoryId, expense.categoryId)

        val goal = app.goalRepository.observeAll().first().firstOrNull { it.id == ids.goalId }
        assertNotNull("the seeded goal must still exist", goal)
        assertEquals(GOAL_NAME, goal!!.name)
        assertEquals(0, GOAL_TARGET.compareTo(goal.targetAmount))
        assertEquals(GOAL_DEADLINE, goal.deadline)

        val card = app.creditCardRepository.observeAll().first().firstOrNull { it.name == CARD_NAME }
        assertNotNull("the seeded credit card must still exist", card)
        assertEquals(CARD_LAST_FOUR, card!!.lastFour)
        assertEquals(0, CARD_BALANCE.compareTo(card.balance))
        assertEquals(0, CARD_LIMIT.compareTo(card.limit))

        val snapshot = app.insightRepository.recentSnapshots(10).firstOrNull { it.id == SNAPSHOT_ID }
        assertNotNull("the seeded health-score snapshot must still exist", snapshot)
        assertEquals(72, snapshot!!.score)
        assertEquals(SNAPSHOT_AT, snapshot.timestamp)

        // Settings must not be silently reset: each of these differs from its own default.
        assertEquals(PROFILE_NAME, app.preferencesRepository.userFullName.first())
        assertEquals(PAY_CYCLE_START_DAY, app.preferencesRepository.payCycleStartDay.first())
        assertEquals(ThemeMode.LIGHT, app.preferencesRepository.themeMode.first())
        assertTrue(app.preferencesRepository.hideBalance.first())
        assertTrue(app.preferencesRepository.healthScoreIgnoreSubscriptions.first())
        assertTrue(app.preferencesRepository.dailyReminderEnabled.first())
        assertEquals(REMINDER_TIME, app.preferencesRepository.dailyReminderTime.first())
    }

    /**
     * `AC-05` support: stores a PIN so the next cold launch takes the `PinLock.Unknown -> Set`
     * branch. Writing and reading the secret is all this touches — unlock, biometrics, and lockout
     * remain #80's.
     */
    @Test
    fun ac05StorePinForColdLaunchGateEvidence() = runBlocking {
        app.pinLockRepository.setPin(hash = PIN_HASH, salt = PIN_SALT)
        app.pinLockRepository.load()
        val state = app.pinLockRepository.state.value
        assertTrue("the stored PIN must resolve to Set, not Unknown: $state", state is PinLock.Set)
        assertEquals(PIN_HASH, (state as PinLock.Set).secret.hash)
        assertEquals(PIN_SALT, state.secret.salt)
    }

    /** `AC-05` support: removes the PIN again so the evidence install ends in a known state. */
    @Test
    fun ac05ClearPinAfterColdLaunchGateEvidence() = runBlocking {
        app.pinLockRepository.clearPin()
        app.pinLockRepository.load()
        assertEquals(PinLock.NotSet, app.pinLockRepository.state.value)
    }

    /**
     * `AC-05`: `load()` must always leave [PinLock.Unknown], because `Unknown` renders a blank
     * surface for the life of the process. Proven here in the production process against the real
     * store rather than a fake, so a Keystore that behaves differently on a device than in a JVM
     * test cannot hide a stranded startup.
     */
    @Test
    fun ac05PinLockAlwaysResolvesAwayFromUnknownOnTheRealStore() = runBlocking {
        app.pinLockRepository.load()
        val state = app.pinLockRepository.state.value
        assertTrue("startup must never be left Unknown: $state", state !is PinLock.Unknown)
    }

    private data class SeedIds(val categoryId: String, val goalId: String, val ruleId: String)

    private fun writeSeedMarker(categoryId: String, goalId: String, ruleId: String) {
        app.filesDir.resolve(MARKER).writeText("$categoryId\n$goalId\n$ruleId")
    }

    private fun readSeedMarker(): SeedIds {
        val file = app.filesDir.resolve(MARKER)
        assertTrue("the seed step must have run first (missing $MARKER)", file.exists())
        val lines = file.readLines()
        return SeedIds(lines[0], lines[1], lines[2])
    }

    private companion object {
        const val MARKER = "ac04-seed-ids.txt"

        const val CATEGORY_NAME = "AC04 Groceries"
        const val EXPENSE_ID = "ac04-expense"
        const val INCOME_ID = "ac04-income"
        const val EXPENSE_NOTE = "AC04 weekly shop"
        const val INCOME_NOTE = "AC04 salary"
        const val GOAL_NAME = "AC04 Holiday fund"
        const val RULE_NOTE = "AC04 rent"
        const val CARD_NAME = "AC04 Card"
        const val CARD_LAST_FOUR = "4417"
        const val SNAPSHOT_ID = "ac04-snapshot"
        const val PROFILE_NAME = "AC04 Tester"
        const val PAY_CYCLE_START_DAY = 15
        const val PIN_HASH = "ac04d7f1b96c2e5084a3"
        const val PIN_SALT = "ac0431c8ea7d5b60f29e"

        // Exact decimals with real scale, including a fraction Double cannot represent.
        val EXPENSE_AMOUNT: BigDecimal = BigDecimal("-134.57")
        val INCOME_AMOUNT: BigDecimal = BigDecimal("2480.10")
        val GOAL_TARGET: BigDecimal = BigDecimal("4200.99")
        val RULE_AMOUNT: BigDecimal = BigDecimal("-950.00")
        // Positive: a card balance is the amount owed, and the repository rejects a negative one.
        val CARD_BALANCE: BigDecimal = BigDecimal("312.45")
        val CARD_LIMIT: BigDecimal = BigDecimal("3000.00")

        val EXPENSE_AT: Instant = Instant.parse("2026-09-12T10:30:00Z")
        val INCOME_AT: Instant = Instant.parse("2026-09-01T06:00:00Z")
        val GOAL_DEADLINE: Instant = Instant.parse("2027-06-30T00:00:00Z")
        val RULE_START: Instant = Instant.parse("2026-01-05T08:00:00Z")
        val SNAPSHOT_AT: Instant = Instant.parse("2026-09-15T22:00:00Z")
        val REMINDER_TIME: LocalTime = LocalTime.of(7, 45)
    }
}
