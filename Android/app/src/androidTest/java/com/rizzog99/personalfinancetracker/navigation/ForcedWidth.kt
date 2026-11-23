package com.rizzog99.personalfinancetracker.navigation

import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.unit.Density

/**
 * Lays [content] out at a real [widthDp], not just a claimed one: on a narrower device (the phone
 * CI profile) it lowers the density until the screen's pixels span [widthDp]. A no-op where the
 * device is already that wide. Overriding `screenWidthDp` alone picks the wide branch but still
 * measures in the phone's 411dp, which #283's 240dp drawer leaves too narrow for the content.
 * ponytail: replace with `DeviceConfigurationOverride.ForcedSize` once ui-test ≥ 1.7 (BOM upgrade).
 */
@Composable
fun ForcedWidth(widthDp: Int, content: @Composable () -> Unit) {
    val widthPx = LocalContext.current.resources.displayMetrics.widthPixels
    val density = LocalDensity.current
    // Always the same provider, so changing the width at runtime keeps the content's state.
    val fitting = if (widthPx / density.density >= widthDp) density else Density(widthPx.toFloat() / widthDp, density.fontScale)
    CompositionLocalProvider(LocalDensity provides fitting, content = content)
}
