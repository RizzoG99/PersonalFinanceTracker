package com.rizzog99.personalfinancetracker.security

import android.accessibilityservice.AccessibilityServiceInfo
import android.view.accessibility.AccessibilityWindowInfo
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.semantics.getOrNull
import androidx.compose.ui.test.SemanticsMatcher
import androidx.compose.ui.test.assertIsFocused
import androidx.compose.ui.test.hasClickAction
import androidx.compose.ui.test.hasContentDescription
import androidx.compose.ui.test.hasSetTextAction
import androidx.compose.ui.test.hasText
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
import com.rizzog99.personalfinancetracker.data.security.PinLock
import com.rizzog99.personalfinancetracker.domain.security.PinCodec
import com.rizzog99.personalfinancetracker.features.security.AppLockSession
import com.rizzog99.personalfinancetracker.navigation.NavShellMarkers
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.runBlocking
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.rules.ExternalResource
import org.junit.rules.RuleChain
import org.junit.runner.RunWith

/**
 * #319 (`DRIFT-2026-10-PRIVACY`): the app relocks after 30 s away or a screen-off, and unlocking
 * puts the user back where they were — frozen iOS `BiometricAuthService` / `AuthenticationWrapper`
 * at `b649dfff`.
 *
 * Drives the production [MainActivity]. Leaving and returning are real `onStop`/`onStart` calls
 * (`moveToState`); only the clock is injected, so 30 s of absence costs no wall time.
 */
@RunWith(AndroidJUnit4::class)
class ForegroundRelockTest {

    val rule = createAndroidComposeRule<MainActivity>()

    /** A known PIN before the activity starts, so every test begins at the cold gate. */
    @get:Rule
    val chain: RuleChain = RuleChain
        .outerRule(object : ExternalResource() {
            override fun before() = runBlocking {
                // Startup seeding and PIN loading must not race the reset below.
                app.databaseProbed.first { it }
                app.pinLockRepository.state.first { it !is PinLock.Unknown }
                app.database.clearAllTables()
                app.categoryRepository.seedDefaultsIfEmpty()
                app.preferencesRepository.setBiometricEnabled(false)
                app.pinLockRepository.setPin(hash = PinCodec.hash(PIN, SALT), salt = SALT)
            }
        })
        .around(rule)

    private val m = NavShellMarkers()
    private var now = 1_000_000L
    private lateinit var session: AppLockSession

    private val instrumentation get() = InstrumentationRegistry.getInstrumentation()
    private val app: PersonalFinanceApplication
        get() = instrumentation.targetContext.applicationContext as PersonalFinanceApplication

    private fun string(id: Int) = instrumentation.targetContext.getString(id)
    private val pinTitle get() = hasText(string(R.string.pin_unlock_title))

    private fun pinShown() = rule.onAllNodes(pinTitle).fetchSemanticsNodes().isNotEmpty()

    private fun enterPin() {
        PIN.forEach { digit ->
            rule.onNode(
                hasText(digit.toString()) and SemanticsMatcher.expectValue(SemanticsProperties.Role, Role.Button),
            ).performClick()
        }
        rule.waitUntil(DEADLINE) { !pinShown() }
    }

    @Before
    fun unlockAtTheColdGate() {
        assertTrue("precondition: PIN set", app.pinLockRepository.state.value is PinLock.Set)
        rule.waitUntil(DEADLINE) { pinShown() }
        rule.activityRule.scenario.onActivity {
            session = ViewModelProvider(it)[AppLockSession::class.java]
            session.clock = { now }
        }
        enterPin()
        rule.waitUntil(DEADLINE) { rule.onAllNodes(m.anyTab).fetchSemanticsNodes().isNotEmpty() }
    }

    @After
    fun restoreDevice() {
        shell("input keyevent KEYCODE_WAKEUP")
        shell("wm dismiss-keyguard")
        runBlocking { app.pinLockRepository.clearPin() }
    }

    /** Leaves the foreground for [millis] of injected time: a real `onStop`, then `onStart`. */
    private fun awayFor(millis: Long) {
        rule.activityRule.scenario.moveToState(Lifecycle.State.CREATED)
        now += millis
        rule.activityRule.scenario.moveToState(Lifecycle.State.RESUMED)
        rule.waitForIdle()
    }

    private fun shell(command: String): String =
        instrumentation.uiAutomation.executeShellCommand(command).use { pfd ->
            java.io.FileInputStream(pfd.fileDescriptor).use { String(it.readBytes()).trim() }
        }

    private fun screenOffAndOn() {
        shell("input keyevent KEYCODE_SLEEP")
        rule.waitUntil(DEADLINE) { rule.activityRule.scenario.state == Lifecycle.State.CREATED }
        shell("input keyevent KEYCODE_WAKEUP")
        shell("wm dismiss-keyguard")
        rule.waitUntil(DEADLINE) { rule.activityRule.scenario.state == Lifecycle.State.RESUMED }
        rule.waitForIdle()
    }

    @Test
    fun ac01_relocksAtThirtySecondsAndReturnsToTheSameTab(): Unit = with(m) {
        rule.selectTab(insightsTab)
        rule.assertOnly(insightsTab)

        awayFor(29_999)
        assertFalse("29.999 s away is inside the grace", pinShown())
        rule.assertOnly(insightsTab)

        awayFor(30_000)
        rule.waitUntil(DEADLINE) { pinShown() }

        enterPin()
        rule.assertOnly(insightsTab)
        rule.assertSingleShell()
    }

    /**
     * The same boundary through a real departure: the Home key. The return brings the same task and
     * instance forward (NEW_TASK | REORDER_TO_FRONT); a launcher intent or the scenario did not on
     * the tablet AVD.
     */
    @Test
    fun ac01_realHomeDeparture() {
        assertFalse("precondition: unlocked", pinShown())
        shell("input keyevent KEYCODE_HOME")
        rule.waitUntil(DEADLINE) { rule.activityRule.scenario.state == Lifecycle.State.CREATED }
        now += 30_000
        shell("am start -W -f 0x10020000 -n ${instrumentation.targetContext.packageName}/.MainActivity")
        rule.waitUntil(DEADLINE) { rule.activityRule.scenario.state == Lifecycle.State.RESUMED }
        rule.waitUntil(DEADLINE) { pinShown() }
    }

    @Test
    fun ac02_relockCoversTheOpenSheetAndKeepsItsDraftAndFocus() {
        // An emulator with a hardware keyboard never raises the soft one; without it the
        // "keyboard is down while locked" half below would pass for the wrong reason.
        val showIme = shell("settings get secure show_ime_with_hard_keyboard")
        shell("settings put secure show_ime_with_hard_keyboard 1")
        try {
            relockOverDraft()
        } finally {
            shell("settings put secure show_ime_with_hard_keyboard ${showIme.ifBlank { "0" }}")
        }
    }

    private fun relockOverDraft() {
        val add = hasContentDescription(string(R.string.add_transaction)) and hasClickAction()
        rule.onNode(add).performClick()
        rule.waitUntil(DEADLINE) { rule.onAllNodes(hasSetTextAction()).fetchSemanticsNodes().size == 2 }
        rule.onAllNodes(hasSetTextAction())[0].performTextInput("12,50")
        val note = hasSetTextAction() and hasText(string(R.string.note))
        rule.onNode(note).performClick()
        rule.onNode(note).performTextInput("Coffee")
        rule.waitUntil(DEADLINE) { imeWindowShown() }
        // One real key event before leaving, so the field's input session is the one key events reach.
        // In this harness `input text` lands only after `performTextInput` has started that session;
        // without this step the key events after unlock were not heard either (recorded on PR #399).
        shell("input text X")
        rule.waitUntil(DEADLINE) {
            rule.onAllNodes(hasSetTextAction() and hasText("CoffeeX")).fetchSemanticsNodes().isNotEmpty()
        }
        val amountBefore = editableText(0)
        assertTrue("precondition: an amount was typed, got '$amountBefore'", amountBefore.isNotBlank())
        assertFalse("precondition: unlocked", pinShown())
        instrumentation.uiAutomation.waitForIdle(1_000, 10_000) // #398: let the keyboard settle.

        awayFor(30_000)
        rule.waitUntil(DEADLINE) { pinShown() }

        // The window TalkBack and the keyboard follow is the lock, not the sheet underneath.
        runCatching {
            rule.waitUntil(DEADLINE) { string(R.string.pin_unlock_title) in activeWindowTexts() }
        }.onFailure {
            shell("screencap -p /data/local/tmp/ac02-failure.png")
            throw AssertionError("the lock is not the active window; windows:\n${windowDump()}", it)
        }
        assertFalse(
            "the sheet's draft must not be readable in the active window while locked",
            activeWindowTexts().any { "Coffee" in it },
        )
        instrumentation.uiAutomation.waitForIdle(500, 5_000)
        assertFalse("the keyboard must be down while locked", imeWindowShown())

        enterPin()
        assertEquals(amountBefore, editableText(0))
        // Given back once the sheet's window has focus again, which is a frame or two after unlock.
        val noteWithDraft = hasSetTextAction() and hasText("CoffeeX")
        rule.waitUntil(DEADLINE) {
            rule.onAllNodes(noteWithDraft and SemanticsMatcher.expectValue(SemanticsProperties.Focused, true))
                .fetchSemanticsNodes().isNotEmpty()
        }
        rule.onNode(noteWithDraft).assertIsFocused()

        // Focused is not enough: typing must still reach the field, through real key events.
        shell("input text More")
        runCatching {
            rule.waitUntil(DEADLINE) {
                rule.onAllNodes(hasSetTextAction() and hasText("CoffeeXMore")).fetchSemanticsNodes().isNotEmpty()
            }
        }.onFailure {
            val fields = rule.onAllNodes(hasSetTextAction()).fetchSemanticsNodes().map { node ->
                node.config.getOrNull(SemanticsProperties.EditableText)?.text
            }
            throw AssertionError("typing after unlock did not reach Note; fields now: $fields", it)
        }
    }

    /**
     * Wide layouts edit inline, in the shell's own window: the shell's focus release and the
     * editor's must not undo each other (code review r1).
     */
    @Test
    fun ac02_wideInlineEditorKeepsDraftAndFocus(): Unit = with(m) {
        var widthDp = 0
        rule.activityRule.scenario.onActivity { widthDp = it.resources.configuration.screenWidthDp }
        org.junit.Assume.assumeTrue("the inline editor needs an expanded width (≥ 840 dp)", widthDp >= 840)
        rule.selectTab(activityTab)
        val note = hasSetTextAction() and hasText(string(R.string.note))
        rule.waitUntil(DEADLINE) { rule.onAllNodes(note).fetchSemanticsNodes().isNotEmpty() }
        rule.onNode(note).performClick()
        rule.onNode(note).performTextInput("Inline")
        instrumentation.uiAutomation.waitForIdle(1_000, 10_000) // #398: let the keyboard settle.
        assertTrue("precondition: draft typed", rule.onAllNodes(hasText("Inline") and hasSetTextAction()).fetchSemanticsNodes().isNotEmpty())

        awayFor(30_000)
        rule.waitUntil(DEADLINE) { pinShown() }
        enterPin()

        val inline = hasSetTextAction() and hasText("Inline")
        rule.waitUntil(DEADLINE) {
            rule.onAllNodes(inline and SemanticsMatcher.expectValue(SemanticsProperties.Focused, true))
                .fetchSemanticsNodes().isNotEmpty()
        }
    }

    @Test
    fun ac03_screenOffRelocksInFront() {
        assertFalse("precondition: unlocked", pinShown())
        screenOffAndOn()
        rule.waitUntil(DEADLINE) { pinShown() }
    }

    @Test
    fun ac03_screenOffWhileAwayRelocksEvenOnAQuickReturn() {
        rule.activityRule.scenario.moveToState(Lifecycle.State.CREATED)
        // The broadcast is asynchronous to the key event: wait until it has reached this process
        // (and, through the main looper, the activity's own receiver) before coming back.
        val screenOff = java.util.concurrent.CountDownLatch(1)
        val probe = object : android.content.BroadcastReceiver() {
            override fun onReceive(context: android.content.Context, intent: android.content.Intent) {
                screenOff.countDown()
            }
        }
        androidx.core.content.ContextCompat.registerReceiver(
            instrumentation.targetContext,
            probe,
            android.content.IntentFilter(android.content.Intent.ACTION_SCREEN_OFF),
            androidx.core.content.ContextCompat.RECEIVER_NOT_EXPORTED,
        )
        try {
            shell("input keyevent KEYCODE_SLEEP")
            assertTrue("no screen-off broadcast", screenOff.await(DEADLINE, java.util.concurrent.TimeUnit.MILLISECONDS))
            instrumentation.waitForIdleSync()
        } finally {
            instrumentation.targetContext.unregisterReceiver(probe)
        }
        shell("input keyevent KEYCODE_WAKEUP")
        shell("wm dismiss-keyguard")
        now += 2_000
        rule.activityRule.scenario.moveToState(Lifecycle.State.RESUMED)
        rule.waitForIdle()
        rule.waitUntil(DEADLINE) { pinShown() }
    }

    @Test
    fun ac04_recreationKeepsTheSessionAndTheTab(): Unit = with(m) {
        rule.selectTab(insightsTab)
        rule.activityRule.scenario.recreate()
        rule.waitForIdle()

        assertFalse("a configuration change is not a departure", pinShown())
        rule.assertOnly(insightsTab)
        rule.assertSingleShell()
    }

    @Test
    fun ac08_withoutAPinNothingRelocks(): Unit = with(m) {
        runBlocking { app.pinLockRepository.clearPin() }
        rule.waitForIdle()
        rule.selectTab(insightsTab)

        awayFor(60_000)
        assertFalse(pinShown())
        screenOffAndOn()
        assertFalse(pinShown())
        rule.assertOnly(insightsTab)
    }

    private fun editableText(index: Int): String =
        rule.onAllNodes(hasSetTextAction())[index].fetchSemanticsNode()
            .config.getOrNull(SemanticsProperties.EditableText)?.text.orEmpty()

    /**
     * Every text and description in the window TalkBack would read. Walked by hand: Compose's
     * accessibility provider does not implement `findAccessibilityNodeInfosByText`, so that search
     * finds nothing in any Compose window.
     */
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

    private fun windowDump(): String {
        val automation = instrumentation.uiAutomation
        automation.serviceInfo = automation.serviceInfo.apply {
            flags = flags or AccessibilityServiceInfo.FLAG_RETRIEVE_INTERACTIVE_WINDOWS
        }
        return automation.windows.joinToString("\n") { w ->
            val root = w.root
            "type=${w.type} layer=${w.layer} active=${w.isActive} focused=${w.isFocused} " +
                "pkg=${root?.packageName} title=${w.title} children=${root?.childCount}"
        }
    }

    /** The real input-method window, not this app's view of its insets. */
    private fun imeWindowShown(): Boolean {
        val automation = instrumentation.uiAutomation
        automation.serviceInfo = automation.serviceInfo.apply {
            flags = flags or AccessibilityServiceInfo.FLAG_RETRIEVE_INTERACTIVE_WINDOWS
        }
        return automation.windows.any { it.type == AccessibilityWindowInfo.TYPE_INPUT_METHOD }
    }

    private companion object {
        const val PIN = "123456"
        const val SALT = "relock-test-salt"
        const val DEADLINE = 20_000L
    }
}
