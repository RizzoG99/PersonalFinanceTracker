package com.rizzog99.personalfinancetracker.security

import android.content.res.Configuration
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.wrapContentWidth
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.key
import androidx.compose.runtime.mutableStateOf
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.test.SemanticsMatcher
import androidx.compose.ui.test.assertWidthIsEqualTo
import androidx.compose.ui.test.hasContentDescription
import androidx.compose.ui.test.hasText
import androidx.compose.ui.test.isHeading
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.performClick
import androidx.compose.ui.unit.Density
import androidx.compose.ui.unit.dp
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.rizzog99.personalfinancetracker.data.security.PinSecret
import com.rizzog99.personalfinancetracker.domain.security.PinCodec
import com.rizzog99.personalfinancetracker.features.security.PinSetupScreen
import com.rizzog99.personalfinancetracker.features.security.PinVerifyScreen
import com.rizzog99.personalfinancetracker.ui.CaptureHarness
import com.rizzog99.personalfinancetracker.ui.theme.PersonalFinanceTheme
import com.rizzog99.personalfinancetracker.ui.theme.ThemeMode
import java.io.File
import java.util.Locale
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/**
 * #320 visual evidence: the current-PIN step, the Delete-all-data gate and the "must be different"
 * error, across language, theme, width and text size. No iOS captures exist (D-04): compared with
 * frozen `PINSetupView` / `PINConfirmationView` copy and structure at b649dff.
 */
@RunWith(AndroidJUnit4::class)
class PinChangeResetCaptureTest {

    @get:Rule
    val rule = createComposeRule()

    private val dir: File get() = CaptureHarness.outputDir("pin-change-reset")
    private val secret = PinSecret(PinCodec.hash("135790", SALT), SALT)

    private val wideAvailable: Boolean
        get() = InstrumentationRegistry.getInstrumentation().targetContext.resources.configuration.screenWidthDp >= 900

    private val cells = buildList {
        add(CaptureHarness.Cell("en-light-compact"))
        add(CaptureHarness.Cell("it-light-compact", locale = Locale.ITALIAN))
        add(CaptureHarness.Cell("en-dark-compact", theme = ThemeMode.DARK))
        add(CaptureHarness.Cell("it-dark-compact", locale = Locale.ITALIAN, theme = ThemeMode.DARK))
        add(CaptureHarness.Cell("en-light-compact-large-text", fontScale = 2.0f))
        add(CaptureHarness.Cell("it-light-compact-large-text", locale = Locale.ITALIAN, fontScale = 2.0f))
        // Only where the device really is that wide: a 900 dp host on a phone is squeezed (#376).
        if (wideAvailable) {
            add(CaptureHarness.Cell("en-light-wide", widthDp = 900))
            add(CaptureHarness.Cell("it-dark-wide", locale = Locale.ITALIAN, widthDp = 900, theme = ThemeMode.DARK))
        }
    }

    private enum class Screen { CURRENT, DELETE_GATE, MUST_DIFFER }

    private data class Copy(val current: String, val gate: String, val gateSubtitle: String, val newPin: String, val mustDiffer: String, val close: String)

    private val copy = mapOf(
        "en" to Copy("Enter current PIN", "Enter your PIN", "Required before erasing all data", "Enter new PIN", "New PIN must be different from the current one.", "Dismiss"),
        "it" to Copy("Inserisci il PIN attuale", "Inserisci il PIN", "Richiesto prima di eliminare tutti i dati", "Inserisci il nuovo PIN", "Il nuovo PIN deve essere diverso da quello attuale.", "Chiudi"),
    )

    @Test
    fun pinScreensAcrossLanguageThemeWidthAndTextSize() {
        val cell = mutableStateOf(cells.first())
        val screen = mutableStateOf(Screen.CURRENT)

        rule.setContent {
            val current = cell.value
            val context = CaptureHarness.localeContext(LocalContext.current, current.locale)
            val configuration = Configuration(context.resources.configuration).apply {
                screenWidthDp = current.widthDp
                fontScale = current.fontScale
            }
            CompositionLocalProvider(
                LocalContext provides context,
                LocalConfiguration provides configuration,
                LocalDensity provides Density(LocalDensity.current.density, current.fontScale),
            ) {
                PersonalFinanceTheme(themeMode = current.theme) {
                    Surface(color = MaterialTheme.colorScheme.surface, contentColor = MaterialTheme.colorScheme.onSurface, modifier = Modifier.fillMaxSize()) {
                        Box(Modifier.wrapContentWidth(Alignment.Start).width(current.widthDp.dp).testTag(HOST)) {
                            // A fresh composition per cell and screen: no digits carried over.
                            key(current.id, screen.value) {
                                val text = copy.getValue(current.locale?.language ?: "en")
                                when (screen.value) {
                                    Screen.CURRENT -> PinVerifyScreen(text.current, null, secret, onVerified = {}, onCancel = {})
                                    Screen.DELETE_GATE -> PinVerifyScreen(text.gate, text.gateSubtitle, secret, onVerified = {}, onCancel = {})
                                    Screen.MUST_DIFFER -> PinSetupScreen(onCancel = {}, onPinCreated = {}, isChange = true, rejectNewPin = { true })
                                }
                            }
                        }
                    }
                }
            }
        }

        val index = StringBuilder("cell,screen,locale,widthDp,theme,fontScale,png,semantics\n")
        cells.forEach { c ->
            Screen.entries.forEach { s ->
                cell.value = c
                screen.value = s
                rule.waitForIdle()
                val text = copy.getValue(c.locale?.language ?: "en")
                rule.onNodeWithTag(HOST).assertWidthIsEqualTo(c.widthDp.dp)
                rule.onNode(hasContentDescription(text.close)).assertExists()
                rule.onNode(hasText("0") and SemanticsMatcher.expectValue(SemanticsProperties.Role, Role.Button)).assertExists()
                when (s) {
                    Screen.CURRENT -> rule.onNode(hasText(text.current) and isHeading()).assertExists()
                    Screen.DELETE_GATE -> {
                        rule.onNode(hasText(text.gate) and isHeading()).assertExists()
                        rule.onNode(hasText(text.gateSubtitle)).assertExists()
                    }
                    Screen.MUST_DIFFER -> {
                        repeat(6) { rule.onNode(hasText("1") and SemanticsMatcher.expectValue(SemanticsProperties.Role, Role.Button)).performClick() }
                        rule.waitUntil(20_000) { rule.onAllNodes(hasText(text.mustDiffer)).fetchSemanticsNodes().isNotEmpty() }
                        rule.onNode(hasText(text.newPin) and isHeading()).assertExists()
                    }
                }
                val id = "${c.id}-${s.name.lowercase()}"
                CaptureHarness.writePng(rule, dir, id)
                CaptureHarness.writeSemantics(rule, dir, id)
                index.append("$id,${s.name},${c.locale?.language ?: "en"},${c.widthDp},${c.theme},${c.fontScale},$id.png,$id.txt\n")
            }
        }
        File(dir, "index.csv").writeText(index.toString())
    }

    private companion object {
        const val HOST = "pin-change-reset-host"
        const val SALT = "capture-salt"
    }
}
