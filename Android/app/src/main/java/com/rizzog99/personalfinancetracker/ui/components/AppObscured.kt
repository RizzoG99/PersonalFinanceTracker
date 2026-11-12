package com.rizzog99.personalfinancetracker.ui.components

import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.material3.MaterialTheme
import androidx.compose.ui.Modifier
import androidx.compose.ui.composed
import androidx.compose.ui.draw.drawWithContent
import androidx.compose.ui.platform.LocalFocusManager

/**
 * Whether the app is away, behind Overview, or relocked (#319). Provided once by the shell; sheets
 * and dialogs inherit it. Read it to know when to give back what was released.
 *
 * A function reading snapshot state, not a provided `Boolean`: a sheet is its own subcomposition
 * and may recompose before the shell re-provides a value, so a provided value can be a frame stale —
 * exactly the frame in which the form would give focus back to a field that is leaving. Read it
 * inside `snapshotFlow`, which sees the activity's writes as they are applied.
 */
val LocalAppObscured = staticCompositionLocalOf<() -> Boolean> { { false } }

/**
 * Every window's way to drop its text focus, called *synchronously* by the activity as it leaves
 * or as Overview takes over — frozen iOS resigns first responder at that moment
 * (`AuthenticationWrapper.swift:300-314` at `b649dfff`).
 *
 * Synchronous because the moment matters: Compose pauses recomposition once the activity stops, so
 * an effect keyed on [LocalAppObscured] would only run on the return, in the same frame the lock
 * window is added. A focused Compose 1.6 text field under a newly added window crashed the process
 * in `CursorAnchorInfoController.updateCursorAnchorInfo` (#319).
 *
 * Each window (the shell, and every sheet or dialog with a text field) is its own focus owner, which
 * is why each registers itself instead of the shell clearing focus once.
 */
class TextFocusReleasers {
    /** One per registration: note which field had focus, then clear the window's focus. */
    class Releaser(val noteFocus: () -> Unit, val clear: () -> Unit)

    private val releasers = mutableSetOf<Releaser>()

    fun add(releaser: Releaser) = releasers.add(releaser)
    fun remove(releaser: Releaser) = releasers.remove(releaser)

    /**
     * Every note before any clear: two registrations can share a window (the shell and the tablet's
     * inline editor), and clearing first would leave the editor nothing to remember.
     */
    fun releaseAll() {
        val all = releasers.toList()
        all.forEach { it.noteFocus() }
        all.forEach { it.clear() }
    }
}

val LocalTextFocusReleasers = staticCompositionLocalOf<TextFocusReleasers?> { null }

/**
 * iOS's app-switcher cover (#319 AC-05, D-11), drawn by each window over itself: while the app is
 * obscured this paints a plain surface instead of the content. Overview shows the app as a *live*
 * tile, which neither `FLAG_SECURE` nor `setRecentsScreenshotEnabled` hides.
 *
 * ponytail: a draw-only cover on every window that shows content (the shell and each sheet), not one
 * cover window on top. Adding a window while a sheet's keyboard was still animating in crashed
 * Compose 1.6's text input; drawing changes no window, layout or focus.
 */
fun Modifier.coverWhenObscured(): Modifier = composed {
    val obscured = LocalAppObscured.current
    val cover = MaterialTheme.colorScheme.surface
    drawWithContent { if (obscured()) drawRect(cover) else drawContent() }
}

/**
 * Registers *this* window's focus manager. [beforeRelease] runs first, so a form can note which
 * field had focus and restore it once [LocalAppObscured] is false again.
 *
 * ponytail: one call per window that holds a text field.
 */
@Composable
fun ReleaseTextFocusWhileObscured(beforeRelease: () -> Unit = {}) {
    val registry = LocalTextFocusReleasers.current ?: return
    val focusManager = LocalFocusManager.current
    val noteFocus = rememberUpdatedState(beforeRelease)
    DisposableEffect(registry, focusManager) {
        val releaser = TextFocusReleasers.Releaser(
            noteFocus = { noteFocus.value() },
            clear = { focusManager.clearFocus(force = true) },
        )
        registry.add(releaser)
        onDispose { registry.remove(releaser) }
    }
}
