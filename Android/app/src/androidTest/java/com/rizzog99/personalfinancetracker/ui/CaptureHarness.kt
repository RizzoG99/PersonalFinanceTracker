package com.rizzog99.personalfinancetracker.ui

import android.content.Context
import android.content.ContextWrapper
import android.content.res.Configuration
import android.content.res.Resources
import android.graphics.Bitmap
import androidx.compose.ui.graphics.asAndroidBitmap
import androidx.compose.ui.semantics.SemanticsNode
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.semantics.getOrNull
import androidx.compose.ui.test.captureToImage
import androidx.compose.ui.test.junit4.ComposeTestRule
import androidx.compose.ui.test.onRoot
import androidx.test.platform.app.InstrumentationRegistry
import com.rizzog99.personalfinancetracker.ui.theme.ThemeMode
import java.io.File
import java.util.Locale

/**
 * The shared screenshot-and-hierarchy harness for the parity evidence matrices (#111 `AC-06`,
 * #112 `AC-06`).
 *
 * Extracted rather than copied, and that is the point. #111 recorded a harness bug that
 * manufactured a defect production did not have — content wrapped in a bare `Box` sets no
 * `LocalContentColor`, so dark cells rendered black-on-black and looked like a contrast failure.
 * A second hand-written harness is a second chance to reintroduce exactly that. There is one
 * capture path, and both matrices run through it.
 *
 * What is *not* here is the composition wrapper: each matrix hosts its own production composables
 * with its own locals, because that is the part that must mirror its real host.
 */
object CaptureHarness {

    /** One cell of a matrix: an appearance/locale/width/font-scale combination. */
    data class Cell(
        val id: String,
        val locale: Locale? = null,
        val widthDp: Int = 411,
        val theme: ThemeMode = ThemeMode.LIGHT,
        val fontScale: Float = 1f,
    )

    /**
     * Where a matrix writes its cells.
     *
     * External storage first, because `adb pull` reaches it without `run-as`. It is not always
     * there — on an AVD with no emulated storage `getExternalFilesDir` answers `null`, and
     * `File(null, name)` silently resolves against the test process's working directory, which is
     * `/`. The cells then go nowhere writable and the matrix reports success having photographed
     * nothing. Falling back to `filesDir` keeps the evidence on disk; it is reachable with
     * `run-as` on a debuggable build.
     */
    fun outputDir(name: String): File {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val base = context.getExternalFilesDir(null) ?: context.filesDir
        return File(base, name).apply { mkdirs() }
    }

    fun writePng(rule: ComposeTestRule, dir: File, name: String) {
        val bitmap = rule.onRoot().captureToImage().asAndroidBitmap()
        File(dir, "$name.png").outputStream().use {
            bitmap.compress(Bitmap.CompressFormat.PNG, 100, it)
        }
    }

    /**
     * The hierarchy half: every readable string with its bounds, so a reviewer can check for
     * zero-size actions and clipped copy without eyeballing a PNG.
     */
    fun writeSemantics(rule: ComposeTestRule, dir: File, name: String) {
        val out = StringBuilder()
        fun walk(node: SemanticsNode, depth: Int) {
            val text = node.config.getOrNull(SemanticsProperties.Text)?.joinToString { it.text }
            val description = node.config.getOrNull(SemanticsProperties.ContentDescription)
                ?.joinToString()
            val heading = node.config.getOrNull(SemanticsProperties.Heading) != null
            val progress = node.config.getOrNull(SemanticsProperties.ProgressBarRangeInfo)
            val live = node.config.getOrNull(SemanticsProperties.LiveRegion)
            val selected = node.config.getOrNull(SemanticsProperties.Selected)
            if (text != null || description != null || progress != null) {
                out.append(" ".repeat(depth * 2))
                    .append("text=").append(text)
                    .append(" desc=").append(description)
                    .append(" heading=").append(heading)
                    .append(" selected=").append(selected)
                    .append(" progress=").append(progress)
                    .append(" liveRegion=").append(live)
                    .append(" bounds=").append(node.boundsInRoot)
                    .append(" touch=").append(node.touchBoundsInRoot)
                    .append('\n')
            }
            node.children.forEach { walk(it, depth + 1) }
        }
        walk(rule.onRoot(useUnmergedTree = true).fetchSemanticsNode(), 0)
        File(dir, "$name.txt").writeText(out.toString())
    }

    /**
     * Localized resources over the *same* context chain.
     *
     * A bare `createConfigurationContext` returns the right strings but is not on the chain
     * `LocalActivityResultRegistryOwner` walks to find the Activity, so anything hosting a launcher
     * — Home's photo picker, for one — throws before a label can be read. Wrapping keeps the
     * Activity reachable and swaps only the resources.
     */
    fun localeContext(base: Context, locale: Locale?): Context = locale?.let {
        val localized = base.createConfigurationContext(
            Configuration(base.resources.configuration)
                .apply { setLocales(android.os.LocaleList(it)) },
        )
        object : ContextWrapper(base) {
            override fun getResources(): Resources = localized.resources
        }
    } ?: base
}
