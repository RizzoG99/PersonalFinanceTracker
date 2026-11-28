package com.rizzog99.personalfinancetracker.features

import android.app.Activity
import android.content.Intent
import android.content.res.Configuration
import android.net.Uri
import androidx.activity.compose.LocalActivityResultRegistryOwner
import androidx.activity.result.ActivityResultRegistry
import androidx.activity.result.ActivityResultRegistryOwner
import androidx.activity.result.contract.ActivityResultContract
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material3.Surface
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.key
import androidx.compose.runtime.mutableStateOf
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.semantics.getOrNull
import androidx.compose.ui.test.assertCountEquals
import androidx.compose.ui.test.hasClickAction
import androidx.compose.ui.test.hasSetTextAction
import androidx.compose.ui.test.hasText
import androidx.compose.ui.test.junit4.StateRestorationTester
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performScrollTo
import androidx.compose.ui.test.performTextReplacement
import androidx.compose.ui.unit.Density
import androidx.core.app.ActivityOptionsCompat
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.rizzog99.personalfinancetracker.PersonalFinanceApplication
import com.rizzog99.personalfinancetracker.R
import com.rizzog99.personalfinancetracker.domain.category.FinanceCategory
import com.rizzog99.personalfinancetracker.domain.category.TransactionType
import com.rizzog99.personalfinancetracker.domain.receipt.SyntheticReceiptImage
import com.rizzog99.personalfinancetracker.domain.receipt.SyntheticReceiptImage.Kind
import com.rizzog99.personalfinancetracker.domain.transaction.FinanceTransaction
import com.rizzog99.personalfinancetracker.features.activity.TransactionEditorContent
import com.rizzog99.personalfinancetracker.ui.CaptureHarness
import com.rizzog99.personalfinancetracker.ui.formatters.formatCurrency
import com.rizzog99.personalfinancetracker.ui.theme.PersonalFinanceTheme
import com.rizzog99.personalfinancetracker.ui.theme.ThemeMode
import java.io.File
import java.math.BigDecimal
import java.time.LocalDate
import java.util.Locale
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class ReceiptScanEditorTest {
    @get:Rule
    val rule = createComposeRule()

    private val context = InstrumentationRegistry.getInstrumentation().targetContext
    private val app = context.applicationContext as PersonalFinanceApplication
    private val width = context.resources.configuration.screenWidthDp
    private val originalLocale = Locale.getDefault()
    private val images = mutableMapOf<Kind, File>()
    private val cell = mutableStateOf(CaptureHarness.Cell("en-light", locale = Locale.ENGLISH, widthDp = width))
    private val picker = FixturePicker()
    private val expenses = FinanceCategory("fixtures-expenses", "Groceries", "receipt", TransactionType.EXPENSE, "categoryAmber", null, "EUR")
    private val otherIncome = FinanceCategory("fixtures-other-income", "Other income", "receipt", TransactionType.INCOME, "categoryAmber", null, "EUR")
    private val income = FinanceCategory("fixtures-income", "Salary", "receipt", TransactionType.INCOME, "categoryAmber", null, "EUR")
    private var saved: FinanceTransaction? = null

    @After
    fun removeFixtureData() {
        Locale.setDefault(originalLocale)
        images.values.forEach(File::delete)
    }

    @Test
    fun ac03_showsOnlyCredibleChoicesAndAppliesSelection() {
        startEditor()
        scan(Kind.Ambiguous)
        awaitMessage(R.string.receipt_total_ambiguous)

        assertTotalChoices(1)
        rule.onNode(choice("15.00")).performScrollTo().performClick()
        awaitMessage(R.string.receipt_review_before_saving)
        assertTotalChoices(0)
        scan(Kind.Alternate)
        awaitScannedNote("EMPORIO LUMINOSO")
        assertSaved("-15.00")
    }

    @Test
    fun ac03_textAndAmountEnteredByHandSurviveTheSameAmbiguousScan() {
        startEditor()
        enterManualFields()
        scan(Kind.Ambiguous)
        // Both outcomes are terminal but only the correct one keeps candidate buttons hidden.
        awaitMessage(R.string.receipt_total_ambiguous, R.string.receipt_review_before_saving, R.string.receipt_date_clamped)

        assertTotalChoices(0)
        assertSaved("-9.90", "manual draft")
    }

    @Test
    fun ac03_freshAmbiguityClearsAmountFromPreviousScan() {
        startEditor()
        scan(Kind.Clear)
        awaitMessage(R.string.receipt_review_before_saving, R.string.receipt_date_clamped)
        assertTrue("first scan filled the amount", amountText().contains("12"))

        scan(Kind.Ambiguous)
        awaitMessage(R.string.receipt_total_ambiguous)
        assertTotalChoices(1)
        assertEquals("", amountText())
    }

    @Test
    fun ac03_retypingTheSameAmountMakesItManual() {
        startEditor()
        scan(Kind.Clear)
        awaitMessage(R.string.receipt_review_before_saving, R.string.receipt_date_clamped)
        assertTrue(amountText().contains("12"))
        val field = rule.onAllNodes(hasSetTextAction())[0].performScrollTo()
        field.performTextReplacement("12.5")
        field.performTextReplacement("12.50")

        scan(Kind.AlternateAmbiguous)
        awaitScannedNote("EMPORIO LUMINOSO")
        assertTotalChoices(0)
        assertSaved("-12.50")
    }

    @Test
    fun ac04_confirmingTheAlreadyDisplayedDateKeepsItManual() {
        val date = hasClickAction() and hasText(string(R.string.transaction_date), substring = true)
        startEditor()
        val initiallyDisplayedDate = rule.onNode(date).fetchSemanticsNode().config
            .getOrNull(SemanticsProperties.Text).orEmpty()
        scan(Kind.Clear)
        awaitMessage(R.string.receipt_review_before_saving)
        val recognizedDate = rule.onNode(date).fetchSemanticsNode().config
            .getOrNull(SemanticsProperties.Text).orEmpty()
        assertTrue("fixture must have changed the empty form's date", initiallyDisplayedDate != recognizedDate)

        rule.runOnIdle { cell.value = cell.value.copy(id = "manual-date") }
        rule.onNode(date).performScrollTo().performClick()
        rule.onNode(hasClickAction() and hasText(string(R.string.done))).performClick()
        scan(Kind.Clear)
        awaitMessage(R.string.receipt_review_before_saving)
        assertEquals(initiallyDisplayedDate, rule.onNode(date).fetchSemanticsNode().config.getOrNull(SemanticsProperties.Text).orEmpty())
    }

    @Test
    fun ac04_unreadableAndCancelledScansKeepDraftAndCleanAppOwnedImages() {
        startEditor()
        enterManualFields()
        val before = cameraFiles()
        picker.cancelCamera = true
        scan(Kind.Clear, camera = true)
        assertEquals(1, picker.cameraWrites)
        assertEquals(before, cameraFiles())
        rule.onAllNodes(hasText(string(R.string.receipt_unreadable))).assertCountEquals(0)

        picker.cancelCamera = false
        scan(Kind.Unreadable, camera = true)
        assertEquals(2, picker.cameraWrites)
        awaitMessage(R.string.receipt_unreadable)
        assertEquals(before, cameraFiles())
        assertTotalChoices(0)
        assertSaved("-9.90", "manual draft")
    }

    @Test
    fun ac04_recognitionFailureRetainsManualDraft() {
        startEditor()
        enterManualFields()
        val before = cameraFiles()
        val invalid = File.createTempFile("receipt-invalid-", ".jpg", app.cacheDir)
        try {
            invalid.writeText("invalid synthetic image")
            picker.next = Uri.fromFile(invalid)
            launchPicker(camera = true)
            assertEquals(1, picker.cameraWrites)
            awaitMessage(R.string.receipt_unreadable)
            assertEquals(before, cameraFiles())
            assertSaved("-9.90", "manual draft")
        } finally {
            invalid.delete()
        }
    }

    @Test
    fun ac04_successfulCaptureCleansAppOwnedImage() {
        startEditor()
        val before = cameraFiles()
        scan(Kind.Clear, camera = true)
        assertEquals(1, picker.cameraWrites)
        awaitMessage(R.string.receipt_review_before_saving)
        assertEquals(before, cameraFiles())
        assertSaved("-12.50", "MERCATO AURORA")
    }

    @Test
    fun ac04_restoredManualDraftKeepsIncomeTypeAndCategory() {
        val restoration = StateRestorationTester(rule)
        startEditor(restoration)
        rule.onNode(hasClickAction() and hasText(string(R.string.filter_income))).performScrollTo().performClick()
        rule.onNode(hasClickAction() and hasText(income.name)).performScrollTo().performClick()
        enterManualFields()

        restoration.emulateSavedInstanceStateRestore()

        picker.cancelCamera = true
        scan(Kind.Clear, camera = true)
        assertSaved("9.90", "manual draft", income.id)
    }

    @Test
    fun ac03_ac04_captureReceiptReviewMatrix() {
        val device = if (width >= 840) "tablet" else "phone"
        startEditor()
        val dir = CaptureHarness.outputDir("receipt-ocr-$device")
        for (locale in listOf(Locale.ENGLISH, Locale.ITALIAN)) {
            for (theme in listOf(ThemeMode.LIGHT, ThemeMode.DARK)) {
                for (scale in listOf(1f, 2f)) {
                    val id = "${locale.language}-${theme.name.lowercase(Locale.ROOT)}-${(scale * 100).toInt()}"
                    Locale.setDefault(locale)
                    rule.runOnIdle { cell.value = CaptureHarness.Cell(id, locale, width, theme, scale) }
                    scan(Kind.Clear)
                    awaitMessage(R.string.receipt_review_before_saving, R.string.receipt_date_clamped)
                    capture(dir, "$id-success")

                    scan(Kind.Ambiguous)
                    awaitMessage(R.string.receipt_total_ambiguous)
                    assertTotalChoices(1)
                    capture(dir, "$id-choices")

                    scan(Kind.Unreadable)
                    awaitMessage(R.string.receipt_unreadable)
                    assertTotalChoices(0)
                    capture(dir, "$id-unreadable")
                }
            }
        }
    }

    private fun startEditor(restoration: StateRestorationTester? = null) {
        Locale.setDefault(cell.value.locale ?: Locale.ENGLISH)
        val content: @Composable () -> Unit = {
            val current = cell.value
            val localized = CaptureHarness.localeContext(LocalContext.current, current.locale)
            val configuration = Configuration(localized.resources.configuration).apply {
                screenWidthDp = current.widthDp
                fontScale = current.fontScale
            }
            CompositionLocalProvider(
                LocalContext provides localized,
                LocalConfiguration provides configuration,
                LocalDensity provides Density(LocalDensity.current.density, current.fontScale),
                LocalActivityResultRegistryOwner provides picker,
            ) {
                PersonalFinanceTheme(themeMode = current.theme) {
                    Surface(modifier = Modifier.fillMaxSize()) {
                        key(current.id) {
                            TransactionEditorContent(
                                editingTransaction = null,
                                categories = listOf(expenses, otherIncome, income),
                                receiptMappingRepository = app.receiptMappingRepository,
                                onDismiss = {},
                                onSave = { transaction, _, _ -> saved = transaction },
                            )
                        }
                    }
                }
            }
        }
        if (restoration == null) rule.setContent(content) else restoration.setContent(content)
    }

    private fun string(id: Int) = CaptureHarness.localeContext(context, cell.value.locale).getString(id)

    private fun enterManualFields() {
        rule.onAllNodes(hasSetTextAction())[0].performScrollTo().performTextReplacement("9.90")
        rule.onNode(hasSetTextAction() and hasText(string(R.string.note)))
            .performScrollTo().performTextReplacement("manual draft")
    }

    private fun amountText() = rule.onAllNodes(hasSetTextAction())[0].fetchSemanticsNode().config
        .getOrNull(SemanticsProperties.EditableText)?.text.orEmpty()

    private fun scan(kind: Kind, camera: Boolean = false) {
        picker.next = Uri.fromFile(images.getOrPut(kind) { SyntheticReceiptImage.create(app, kind, LocalDate.now().minusDays(2)) })
        launchPicker(camera)
    }

    private fun launchPicker(camera: Boolean = false) {
        rule.onNodeWithContentDescription(string(R.string.scan_receipt)).performClick()
        rule.onNode(hasClickAction() and hasText(string(if (camera) R.string.take_photo else R.string.choose_photo))).performClick()
    }

    private fun awaitMessage(vararg messages: Int) = rule.waitUntil(20_000) {
        messages.any { rule.onAllNodes(hasText(string(it))).fetchSemanticsNodes().isNotEmpty() }
    }

    private fun awaitScannedNote(note: String) = rule.waitUntil(20_000) {
        rule.onAllNodes(hasSetTextAction() and hasText(note)).fetchSemanticsNodes().isNotEmpty()
    }

    private fun choice(amount: String) = hasClickAction() and hasText(formatCurrency(BigDecimal(amount), "EUR"))

    private fun assertTotalChoices(count: Int) {
        rule.onAllNodes(choice("12.50")).assertCountEquals(count)
        rule.onAllNodes(choice("15.00")).assertCountEquals(count)
    }

    private fun assertSaved(amount: String, note: String? = null, categoryId: String = expenses.id) {
        rule.onNodeWithContentDescription(string(R.string.add_transaction)).performClick()
        rule.runOnIdle {
            assertEquals(amount.toBigDecimal(), saved?.amount)
            if (note != null) assertEquals(note, saved?.note)
            assertEquals(categoryId, saved?.categoryId)
        }
    }

    private fun capture(dir: File, label: String) {
        CaptureHarness.writePng(rule, dir, label)
        CaptureHarness.writeSemantics(rule, dir, label)
    }

    private fun cameraFiles() = File(app.cacheDir, "receipt-capture").list().orEmpty().toSet()

    private inner class FixturePicker : ActivityResultRegistry(), ActivityResultRegistryOwner {
        override val activityResultRegistry: ActivityResultRegistry get() = this
        var next: Uri? = null
        var cancelCamera = false
        var cameraWrites = 0
            private set

        override fun <I, O> onLaunch(
            requestCode: Int,
            contract: ActivityResultContract<I, O>,
            input: I,
            options: ActivityOptionsCompat?,
        ) {
            val uri = next
            if (uri == null) {
                dispatchResult(requestCode, Activity.RESULT_CANCELED, null)
                return
            }
            when (contract) {
                is ActivityResultContracts.PickVisualMedia ->
                    dispatchResult(requestCode, Activity.RESULT_OK, Intent().setData(uri))
                is ActivityResultContracts.TakePicture -> {
                    val output = checkNotNull(app.contentResolver.openOutputStream(input as Uri))
                    output.use { stream ->
                        checkNotNull(app.contentResolver.openInputStream(uri)).use { source -> source.copyTo(stream) }
                    }
                    cameraWrites++
                    dispatchResult(requestCode, if (cancelCamera) Activity.RESULT_CANCELED else Activity.RESULT_OK, Intent())
                }
                else -> error("Unexpected receipt picker contract: ${contract.javaClass.simpleName}")
            }
        }
    }
}
