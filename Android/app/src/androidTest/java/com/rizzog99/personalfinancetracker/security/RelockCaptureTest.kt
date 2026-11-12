package com.rizzog99.personalfinancetracker.security

import android.app.LocaleManager
import android.graphics.Bitmap
import android.os.Build
import android.os.LocaleList
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.semantics.getOrNull
import androidx.compose.ui.test.SemanticsMatcher
import androidx.compose.ui.test.assert
import androidx.compose.ui.test.assertCountEquals
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.hasAnyDescendant
import androidx.compose.ui.test.hasClickAction
import androidx.compose.ui.test.hasContentDescription
import androidx.compose.ui.test.hasSetTextAction
import androidx.compose.ui.test.hasText
import androidx.compose.ui.test.isRoot
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performTextInput
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.ViewModelProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.rizzog99.personalfinancetracker.MainActivity
import com.rizzog99.personalfinancetracker.PersonalFinanceApplication
import com.rizzog99.personalfinancetracker.R
import com.rizzog99.personalfinancetracker.domain.security.PinCodec
import com.rizzog99.personalfinancetracker.features.security.AppLockSession
import com.rizzog99.personalfinancetracker.ui.CaptureHarness
import com.rizzog99.personalfinancetracker.ui.theme.ThemeMode
import java.io.File
import java.util.Locale
import com.rizzog99.personalfinancetracker.data.security.PinLock
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.runBlocking
import org.junit.After
import org.junit.Assert.assertTrue
import org.junit.Assume.assumeTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.ExternalResource
import org.junit.rules.RuleChain
import org.junit.runner.RunWith

/**
 * #319 `AC-07`: the relocked state — PIN screen over the shell *and* an open Add Transaction sheet —
 * in every cell the contract names, on the real activity: EN/IT, light/dark, 100 %/200 % text.
 * Width comes from the device: run once on `Pixel_7a` (compact) and once on `Pixel_Tablet` (wide).
 *
 * Full-screen PNGs through `UiAutomation`, because the lock, the sheet and the shell are three
 * windows and `captureToImage()` sees one. Per cell it also asserts what TalkBack depends on: the
 * title is a heading, every key is a labelled button, and the active window holds the lock and
 * none of the draft underneath.
 *
 * Needs per-app locales (API 33+) and an unsecured window for screenshots (API 33+, D-02).
 */
@RunWith(AndroidJUnit4::class)
class RelockCaptureTest {

    val rule = createAndroidComposeRule<MainActivity>()

    @get:Rule
    val chain: RuleChain = RuleChain
        .outerRule(object : ExternalResource() {
            override fun before() = runBlocking {
                app.databaseProbed.first { it }
                app.pinLockRepository.state.first { it !is PinLock.Unknown }
                app.database.clearAllTables()
                app.categoryRepository.seedDefaultsIfEmpty()
                app.preferencesRepository.setBiometricEnabled(false)
                app.pinLockRepository.setPin(hash = PinCodec.hash(PIN, SALT), salt = SALT)
            }
        })
        .around(rule)

    private val instrumentation get() = InstrumentationRegistry.getInstrumentation()
    private val app: PersonalFinanceApplication
        get() = instrumentation.targetContext.applicationContext as PersonalFinanceApplication
    private var now = 1_000_000L
    private val dir: File by lazy { CaptureHarness.outputDir("relock-319") }

    private fun shell(command: String) {
        instrumentation.uiAutomation.executeShellCommand(command).use { pfd ->
            java.io.FileInputStream(pfd.fileDescriptor).use { it.readBytes() }
        }
    }

    private fun string(id: Int, locale: Locale) =
        CaptureHarness.localeContext(instrumentation.targetContext, locale).getString(id)

    private fun pinTitle(locale: Locale) = hasText(string(R.string.pin_unlock_title, locale))
    private fun pinShown(locale: Locale) = rule.onAllNodes(pinTitle(locale)).fetchSemanticsNodes().isNotEmpty()

    private fun key(digit: Char) =
        hasText(digit.toString()) and SemanticsMatcher.expectValue(SemanticsProperties.Role, Role.Button)

    private fun enterPin(locale: Locale) {
        PIN.forEach { rule.onNode(key(it)).performClick() }
        rule.waitUntil(DEADLINE) { !pinShown(locale) }
    }

    @After
    fun restoreDevice() {
        shell("settings put system font_scale 1.0")
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            instrumentation.targetContext.getSystemService(LocaleManager::class.java)
                .applicationLocales = LocaleList.getEmptyLocaleList()
        }
        runBlocking {
            app.preferencesRepository.setThemeMode(ThemeMode.SYSTEM)
            app.pinLockRepository.clearPin()
        }
    }

    private fun apply(cell: CaptureHarness.Cell) {
        val locale = requireNotNull(cell.locale)
        instrumentation.targetContext.getSystemService(LocaleManager::class.java)
            .applicationLocales = LocaleList(locale)
        shell("settings put system font_scale ${cell.fontScale}")
        runBlocking { app.preferencesRepository.setThemeMode(cell.theme) }
        instrumentation.waitForIdleSync()
        rule.waitForIdle()
    }

    @Test
    fun ac07_relockedOverAnOpenSheet_matrix() {
        assumeTrue("per-app locales and capturable windows need API 33+", Build.VERSION.SDK_INT >= 33)
        rule.waitUntil(DEADLINE) { pinShown(Locale.ENGLISH) || pinShown(Locale.ITALIAN) }
        rule.activityRule.scenario.onActivity {
            ViewModelProvider(it)[AppLockSession::class.java].clock = { now }
        }
        enterPin(Locale.ENGLISH)

        val cells = listOf(Locale.ENGLISH, Locale.ITALIAN).flatMap { locale ->
            listOf(ThemeMode.LIGHT, ThemeMode.DARK).flatMap { theme ->
                listOf(1f, 2f).map { scale ->
                    CaptureHarness.Cell(
                        id = "${locale.language}-${theme.name.lowercase()}-${(scale * 100).toInt()}",
                        locale = locale,
                        theme = theme,
                        fontScale = scale,
                    )
                }
            }
        }
        val device = Build.MODEL.replace(' ', '_')
        cells.forEach { cell -> captureCell(cell, device) }
    }

    private fun captureCell(cell: CaptureHarness.Cell, device: String) {
        val locale = requireNotNull(cell.locale)
        apply(cell)

        val add = hasContentDescription(string(R.string.add_transaction, locale)) and hasClickAction()
        rule.waitUntil(DEADLINE) { rule.onAllNodes(add).fetchSemanticsNodes().size == 1 }
        rule.onNode(add).performClick()
        rule.waitUntil(DEADLINE) { rule.onAllNodes(hasSetTextAction()).fetchSemanticsNodes().size == 2 }
        rule.onAllNodes(hasSetTextAction())[0].performTextInput("12,50")
        val note = hasSetTextAction() and hasText(string(R.string.note, locale))
        rule.onNode(note).performClick()
        rule.onNode(note).performTextInput(DRAFT)
        instrumentation.uiAutomation.waitForIdle(1_000, 10_000) // #398: let the keyboard settle.

        rule.activityRule.scenario.moveToState(Lifecycle.State.CREATED)
        now += 30_000
        rule.activityRule.scenario.moveToState(Lifecycle.State.RESUMED)
        rule.waitUntil(DEADLINE) { pinShown(locale) }

        // What TalkBack depends on.
        rule.onNode(pinTitle(locale)).assertIsDisplayed()
            .assert(SemanticsMatcher.keyIsDefined(SemanticsProperties.Heading))
        "0123456789".forEach { rule.onNode(key(it)).assertIsDisplayed() }
        rule.onAllNodes(hasContentDescription(string(R.string.backspace, locale))).assertCountEquals(1)
        rule.waitUntil(DEADLINE) { string(R.string.pin_unlock_title, locale) in activeWindowTexts() }
        assertTrue(
            "${cell.id}: the draft must not be readable in the active window",
            activeWindowTexts().none { DRAFT in it },
        )

        val name = "relocked-${cell.id}-$device"
        instrumentation.uiAutomation.waitForIdle(300, 5_000)
        File(dir, "$name.png").outputStream().use {
            instrumentation.uiAutomation.takeScreenshot().compress(Bitmap.CompressFormat.PNG, 100, it)
        }
        writeLockSemantics(locale, File(dir, "$name.txt"))

        enterPin(locale)
        // Back, not the sheet's close button: Home has its own "Dismiss" (the reminder card). The
        // first Back may only close the keyboard the restored focus brought back.
        // Each Back is given time to land before the next: on the API 34 CI emulator a quicker loop
        // left the sheet open and the next cell stacked a second one.
        val sheetOpen = { rule.onAllNodes(hasSetTextAction()).fetchSemanticsNodes().isNotEmpty() }
        repeat(5) {
            if (sheetOpen()) {
                shell("input keyevent KEYCODE_BACK")
                instrumentation.uiAutomation.waitForIdle(500, 5_000)
                rule.waitForIdle()
            }
        }
        rule.waitUntil(DEADLINE) { !sheetOpen() }
    }

    /** What TalkBack can read in the active window (walked: Compose has no text search). */
    private fun activeWindowTexts(): List<String> {
        val out = mutableListOf<String>()
        fun walk(node: android.view.accessibility.AccessibilityNodeInfo?) {
            node ?: return
            node.text?.let { out += it.toString() }
            node.contentDescription?.let { out += it.toString() }
            for (i in 0 until node.childCount) walk(node.getChild(i))
        }
        walk(instrumentation.uiAutomation.rootInActiveWindow)
        return out
    }

    /** The lock window's semantics only, one line per labelled node with its bounds. */
    private fun writeLockSemantics(locale: Locale, file: File) {
        val root = rule.onNode(isRoot() and hasAnyDescendant(pinTitle(locale)), useUnmergedTree = true)
            .fetchSemanticsNode()
        val out = StringBuilder()
        fun walk(node: androidx.compose.ui.semantics.SemanticsNode, depth: Int) {
            val text = node.config.getOrNull(SemanticsProperties.Text)?.joinToString { it.text }
            val desc = node.config.getOrNull(SemanticsProperties.ContentDescription)?.joinToString()
            val heading = node.config.getOrNull(SemanticsProperties.Heading) != null
            val role = node.config.getOrNull(SemanticsProperties.Role)
            if (text != null || desc != null || heading || role != null) {
                out.append(" ".repeat(depth * 2))
                    .append("text=").append(text).append(" desc=").append(desc)
                    .append(" heading=").append(heading).append(" role=").append(role)
                    .append(" bounds=").append(node.boundsInWindow).append('\n')
            }
            node.children.forEach { walk(it, depth + 1) }
        }
        walk(root, 0)
        file.writeText(out.toString())
    }

    private companion object {
        const val PIN = "123456"
        const val SALT = "relock-capture-salt"
        const val DRAFT = "Coffee"
        const val DEADLINE = 20_000L
    }
}
