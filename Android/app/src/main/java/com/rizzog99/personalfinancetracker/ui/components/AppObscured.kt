package com.rizzog99.personalfinancetracker.ui.components

import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.staticCompositionLocalOf
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
    private val releasers = mutableSetOf<() -> Unit>()

    fun add(release: () -> Unit) = releasers.add(release)
    fun remove(release: () -> Unit) = releasers.remove(release)
    fun releaseAll() = releasers.toList().forEach { it() }
}

val LocalTextFocusReleasers = staticCompositionLocalOf<TextFocusReleasers?> { null }

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
        val release: () -> Unit = {
            noteFocus.value()
            focusManager.clearFocus(force = true)
        }
        registry.add(release)
        onDispose { registry.remove(release) }
    }
}
