package com.rizzog99.personalfinancetracker.security

import android.content.Context
import android.content.ContextWrapper
import android.content.res.Configuration
import android.content.res.Resources
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.SemanticsActions
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.semantics.getOrNull
import androidx.compose.ui.test.SemanticsMatcher
import androidx.compose.ui.test.assert
import androidx.compose.ui.test.assertCountEquals
import androidx.compose.ui.test.assertHasClickAction
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.assertIsEnabled
import androidx.compose.ui.test.assertIsNotEnabled
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.hasText
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performSemanticsAction
import androidx.compose.ui.unit.Density
import androidx.compose.ui.unit.dp
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.rizzog99.personalfinancetracker.R
import com.rizzog99.personalfinancetracker.domain.security.PinCodec
import com.rizzog99.personalfinancetracker.features.security.PinUnlockScreen
import com.rizzog99.personalfinancetracker.ui.theme.PersonalFinanceTheme
import com.rizzog99.personalfinancetracker.ui.theme.ThemeMode
import java.util.Locale
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/** Production PIN-gate accessibility evidence for #113/#140. */
@RunWith(AndroidJUnit4::class)
class PinGateAccessibilityTest {

    @get:Rule
    val rule = createComposeRule()

    private fun host(locale: Locale = Locale.ENGLISH, fontScale: Float = 1f) {
        val salt = "a11y-pin-salt"
        val expectedHash = PinCodec.hash("999999", salt)
        rule.setContent {
            val base = LocalContext.current
            val context = localeContext(base, locale)
            val configuration = Configuration(context.resources.configuration).apply {
                screenWidthDp = 411
                this.fontScale = fontScale
            }
            val density = LocalDensity.current
            CompositionLocalProvider(
                LocalContext provides context,
                LocalConfiguration provides configuration,
                LocalDensity provides Density(density.density, fontScale),
            ) {
                PersonalFinanceTheme(themeMode = ThemeMode.LIGHT) {
                    PinUnlockScreen(
                        expectedHash = expectedHash,
                        expectedSalt = salt,
                        biometricEnabled = false,
                        onUnlocked = {},
                    )
                }
            }
        }
        rule.waitForIdle()
    }

    private fun localeContext(base: Context, locale: Locale): Context {
        val localized = base.createConfigurationContext(
            Configuration(base.resources.configuration)
                .apply { setLocales(android.os.LocaleList(locale)) },
        )
        return object : ContextWrapper(base) {
            override fun getResources(): Resources = localized.resources
        }
    }

    private fun string(id: Int, locale: Locale = Locale.ENGLISH): String {
        val base = InstrumentationRegistry.getInstrumentation().targetContext
        return localeContext(base, locale).getString(id)
    }

    private fun pressDigit(digit: String) {
        rule.onNodeWithText(digit)
            .performSemanticsAction(SemanticsActions.OnClick) { it() }
        rule.waitForIdle()
    }

    @Test
    fun ac03_backspaceIsTruthfullyDisabledUntilThereIsSomethingToDelete() {
        host()
        val backspace = rule.onNodeWithContentDescription(string(R.string.backspace))
        backspace.assertHasClickAction().assertIsNotEnabled()

        pressDigit("1")
        backspace.assertIsEnabled()
        backspace.performSemanticsAction(SemanticsActions.OnClick) { it() }
        rule.waitForIdle()
        backspace.assertIsNotEnabled()
    }

    @Test
    fun ac05_incorrectPinHasPersistentEnglishNonColorFeedbackAndOneLiveRegion() {
        host()
        repeat(6) { pressDigit("0") }
        val error = string(R.string.pin_incorrect)
        rule.waitUntil(3_000) {
            rule.onAllNodes(hasText(error)).fetchSemanticsNodes().isNotEmpty()
        }

        val node = rule.onNodeWithText(error).assertIsDisplayed().fetchSemanticsNode()
        assertEquals(
            LiveRegionMode.Assertive,
            node.config.getOrNull(SemanticsProperties.LiveRegion),
        )
        rule.mainClock.advanceTimeBy(1_000)
        rule.onNodeWithText(error).assertIsDisplayed()
        rule.onAllNodes(
            SemanticsMatcher.expectValue(
                SemanticsProperties.LiveRegion,
                LiveRegionMode.Assertive,
            ),
            useUnmergedTree = true,
        ).assertCountEquals(1)

        pressDigit("1")
        rule.onNodeWithText(error).assertDoesNotExist()
    }

    @Test
    fun ac05_incorrectPinIsItalianReachableAt200PercentAndKeyTargetsRemainLarge() {
        host(locale = Locale.ITALIAN, fontScale = 2f)
        repeat(6) { pressDigit("0") }
        val error = string(R.string.pin_incorrect, Locale.ITALIAN)
        rule.waitUntil(3_000) {
            rule.onAllNodes(hasText(error)).fetchSemanticsNodes().isNotEmpty()
        }

        rule.onNodeWithText(error).assertIsDisplayed()
        rule.onNodeWithText(string(R.string.pin_unlock_title, Locale.ITALIAN))
            .assert(SemanticsMatcher.keyIsDefined(SemanticsProperties.Heading))

        val digit = rule.onNodeWithText("5").assertHasClickAction().fetchSemanticsNode()
        assertEquals(Role.Button, digit.config.getOrNull(SemanticsProperties.Role))
        with(digit.layoutInfo.density) {
            assertTrue(digit.boundsInRoot.width.toDp().value >= 47.5f)
            assertTrue(digit.boundsInRoot.height.toDp().value >= 47.5f)
            assertTrue(digit.touchBoundsInRoot.width.toDp().value >= 47.5f)
            assertTrue(digit.touchBoundsInRoot.height.toDp().value >= 47.5f)
        }
        rule.onNodeWithContentDescription(string(R.string.backspace, Locale.ITALIAN)).assertIsDisplayed()
    }
}
