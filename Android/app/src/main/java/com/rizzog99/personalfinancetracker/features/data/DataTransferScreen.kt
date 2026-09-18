package com.rizzog99.personalfinancetracker.features.data

import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.IntrinsicSize
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.ui.draw.clip
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.foundation.verticalScroll
import androidx.compose.foundation.rememberScrollState
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.ArrowBack
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.KeyboardArrowDown
import androidx.compose.material.icons.outlined.Close
import androidx.compose.material.icons.outlined.FileDownload
import androidx.compose.material.icons.outlined.FileOpen
import androidx.compose.material.icons.outlined.Info
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.Checkbox
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilledTonalButton
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.ListItem
import androidx.compose.material3.ListItemDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.SegmentedButtonDefaults
import androidx.compose.material3.SingleChoiceSegmentedButtonRow
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.SegmentedButton
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.pluralStringResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.lifecycle.viewmodel.compose.viewModel
import com.rizzog99.personalfinancetracker.PersonalFinanceApplication
import com.rizzog99.personalfinancetracker.R
import com.rizzog99.personalfinancetracker.domain.export.CsvExportService
import com.rizzog99.personalfinancetracker.domain.export.XlsxExportService
import com.rizzog99.personalfinancetracker.domain.import.CategoryAutoMapper
import com.rizzog99.personalfinancetracker.domain.import.CsvImportParser
import com.rizzog99.personalfinancetracker.domain.import.CsvColumnMapping
import com.rizzog99.personalfinancetracker.domain.import.RecurringCandidate
import com.rizzog99.personalfinancetracker.domain.import.RecurringImportDetector
import com.rizzog99.personalfinancetracker.domain.import.TransactionImportMapper
import com.rizzog99.personalfinancetracker.domain.import.SignConvention
import com.rizzog99.personalfinancetracker.domain.import.XlsxImportService
import com.rizzog99.personalfinancetracker.domain.import.removingLeadingEmoji
import com.rizzog99.personalfinancetracker.domain.recurrence.NewRecurrenceRule
import com.rizzog99.personalfinancetracker.domain.recurrence.RecurrenceFrequency
import com.rizzog99.personalfinancetracker.domain.category.FinanceCategory
import com.rizzog99.personalfinancetracker.domain.category.TransactionType
import com.rizzog99.personalfinancetracker.domain.transaction.FinanceTransaction
import com.rizzog99.personalfinancetracker.features.categories.categoryColor
import com.rizzog99.personalfinancetracker.ui.components.FinanceCard
import com.rizzog99.personalfinancetracker.ui.components.categoryIconFor
import com.rizzog99.personalfinancetracker.ui.formatters.formatCurrency
import com.rizzog99.personalfinancetracker.ui.formatters.formatTransactionDate
import com.rizzog99.personalfinancetracker.ui.theme.LocalFinanceExtendedColors
import kotlinx.coroutines.launch

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun DataTransferScreen(onBack: () -> Unit) {
    val context = LocalContext.current
    val application = context.applicationContext as PersonalFinanceApplication
    val viewModel: DataTransferViewModel = viewModel(
        factory = DataTransferViewModel.factory(application.transactionRepository, application.categoryRepository, application.recurrenceRepository),
    )
    val state by viewModel.uiState.collectAsState()
    val snackbarHostState = remember { SnackbarHostState() }
    val scope = rememberCoroutineScope()
    var importedFile by remember { mutableStateOf<CsvImportParser.CsvFile?>(null) }
    var importedWorkbook by remember { mutableStateOf<XlsxImportService.Workbook?>(null) }
    var importError by remember { mutableStateOf<String?>(null) }
    val openCsvDocument = rememberLauncherForActivityResult(
        ActivityResultContracts.OpenDocument(),
    ) { uri ->
        if (uri == null) return@rememberLauncherForActivityResult
        runCatching {
            requireNotNull(context.contentResolver.openInputStream(uri)) { "Could not open the selected file." }.use { input ->
                val bytes = input.readBytes()
                if (bytes.take(2).toByteArray().contentEquals(byteArrayOf('P'.code.toByte(), 'K'.code.toByte()))) {
                    val workbook = XlsxImportService.readWorkbook(bytes)
                    if (workbook.sheets.size == 1) workbook.sheets.single().file else {
                        importedWorkbook = workbook
                        return@use null
                    }
                }
                else CsvImportParser.parse(bytes.toString(Charsets.UTF_8))
            }
        }.onSuccess {
            if (it != null) importedFile = it
            importError = null
        }.onFailure {
            importedFile = null
            importedWorkbook = null
            importError = context.getString(R.string.import_file_error)
        }
    }
    val createCsvDocument = rememberLauncherForActivityResult(
        ActivityResultContracts.CreateDocument("text/csv"),
    ) { uri ->
        if (uri == null) return@rememberLauncherForActivityResult
        val exported = runCatching {
            context.contentResolver.openOutputStream(uri)?.bufferedWriter()?.use { writer ->
                writer.write(CsvExportService.generate(state.transactions))
            } ?: error("Could not open the selected file.")
        }
        scope.launch {
            snackbarHostState.showSnackbar(
                context.getString(if (exported.isSuccess) R.string.export_complete else R.string.export_failed),
            )
        }
    }
    val createXlsxDocument = rememberLauncherForActivityResult(ActivityResultContracts.CreateDocument("application/vnd.openxmlformats-officedocument.spreadsheetml.sheet")) { uri ->
        if (uri == null) return@rememberLauncherForActivityResult
        val exported = runCatching { context.contentResolver.openOutputStream(uri)?.use { it.write(XlsxExportService.generate(state.transactions)) } ?: error("Could not open file") }
        scope.launch { snackbarHostState.showSnackbar(context.getString(if (exported.isSuccess) R.string.export_complete else R.string.export_failed)) }
    }

    importedFile?.let { file ->
        ImportWizardScreen(
            file = file,
            existing = state.transactions,
            categories = state.categories,
            onCancel = { importedFile = null },
            onImport = { transactions, selections, finished ->
                viewModel.import(transactions, selections) { resolved ->
                    if (resolved != null) {
                        scope.launch { snackbarHostState.showSnackbar(context.getString(R.string.import_complete)) }
                    }
                    finished(resolved)
                }
            },
            onAddRecurrenceRules = { rules, finished -> viewModel.addRecurrenceRules(rules, finished) },
            onFinish = { importedFile = null },
        )
        return
    }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text(stringResource(R.string.import_export_title), modifier = Modifier.semantics { heading() }) },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.AutoMirrored.Outlined.ArrowBack, stringResource(R.string.back))
                    }
                },
                colors = TopAppBarDefaults.topAppBarColors(
                    containerColor = MaterialTheme.colorScheme.surface,
                    titleContentColor = MaterialTheme.colorScheme.onSurface,
                    navigationIconContentColor = MaterialTheme.colorScheme.onSurfaceVariant,
                ),
            )
        },
        snackbarHost = { SnackbarHost(snackbarHostState) },
        containerColor = MaterialTheme.colorScheme.surface,
        contentColor = MaterialTheme.colorScheme.onSurface,
    ) { padding ->
        Column(
            modifier = Modifier.fillMaxSize().padding(padding).padding(16.dp).verticalScroll(rememberScrollState()),
            verticalArrangement = Arrangement.spacedBy(16.dp),
        ) {
            Text(stringResource(R.string.export_section), style = MaterialTheme.typography.labelLarge, color = MaterialTheme.colorScheme.outline)
            FinanceCard {
                Column(modifier = Modifier.fillMaxWidth().padding(20.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    Text(stringResource(R.string.export_csv), style = MaterialTheme.typography.titleMedium)
                    Text(stringResource(R.string.export_csv_detail), color = MaterialTheme.colorScheme.onSurfaceVariant)
                    Button(
                        onClick = { createCsvDocument.launch("personal-finance-transactions.csv") },
                        enabled = state.transactions.isNotEmpty(),
                    ) {
                        Icon(Icons.Outlined.FileDownload, contentDescription = null)
                        Text(stringResource(R.string.export_csv), modifier = Modifier.padding(start = 8.dp))
                    }
                    TextButton(onClick = { createXlsxDocument.launch("personal-finance-transactions.xlsx") }, enabled = state.transactions.isNotEmpty()) { Text(stringResource(R.string.export_xlsx)) }
                }
            }
            Text(stringResource(R.string.import_section), style = MaterialTheme.typography.labelLarge, color = MaterialTheme.colorScheme.outline)
            FinanceCard {
                Column(modifier = Modifier.fillMaxWidth().padding(20.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    Text(stringResource(R.string.import_csv), style = MaterialTheme.typography.titleMedium)
                    Text(stringResource(R.string.import_csv_detail), color = MaterialTheme.colorScheme.onSurfaceVariant)
                    Button(onClick = { openCsvDocument.launch(arrayOf("text/csv", "text/comma-separated-values", "text/plain", "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet")) }) {
                        Icon(Icons.Outlined.FileOpen, contentDescription = null)
                        Text(stringResource(R.string.choose_csv), modifier = Modifier.padding(start = 8.dp))
                    }
                    importError?.let { Text(it, color = MaterialTheme.colorScheme.error) }
                }
            }
            importedWorkbook?.let { workbook -> SheetPicker(workbook) { sheet -> importedWorkbook = null; importedFile = sheet.file } }
        }
    }
}
@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun ImportWizardScreen(
    file: CsvImportParser.CsvFile,
    existing: List<FinanceTransaction>,
    categories: List<FinanceCategory>,
    onCancel: () -> Unit,
    onImport: (List<FinanceTransaction>, Map<String, String?>, (List<FinanceTransaction>?) -> Unit) -> Unit,
    onAddRecurrenceRules: (List<NewRecurrenceRule>, (Boolean) -> Unit) -> Unit,
    onFinish: () -> Unit,
) {
    var step by remember(file) { mutableStateOf(1) }
    var dateColumn by remember(file) { mutableStateOf(file.headers.matching("date", "period")) }
    var amountColumn by remember(file) { mutableStateOf(file.headers.matching("amount", "value")) }
    var categoryColumn by remember(file) { mutableStateOf(file.headers.matching("category")) }
    var noteColumn by remember(file) { mutableStateOf(file.headers.matching("note", "description")) }
    var typeColumn by remember(file) { mutableStateOf(file.headers.matching("type", "income/expense")) }
    var dateFormat by remember(file) { mutableStateOf(TransactionImportMapper.supportedDateFormats.firstOrNull { format -> file.rows.firstOrNull()?.getOrNull(file.headers.indexOf(dateColumn ?: ""))?.let { runCatching { java.time.LocalDate.parse(it, java.time.format.DateTimeFormatter.ofPattern(format)) }.isSuccess || runCatching { java.time.LocalDateTime.parse(it, java.time.format.DateTimeFormatter.ofPattern(format)) }.isSuccess } == true } ?: "dd/MM/yyyy") }
    var signConvention by remember(file) { mutableStateOf(SignConvention.SIGNED) }
    val validation = if (dateColumn != null && amountColumn != null) runCatching { TransactionImportMapper.validate(file, CsvColumnMapping(dateColumn!!, amountColumn!!, categoryColumn, noteColumn, typeColumn, dateFormat, signConvention)) }.getOrNull() else null
    val mappedCategories = validation?.transactions.orEmpty().mapNotNull { it.categoryLabel.takeIf(String::isNotBlank) }.distinct()
    fun autoMatch() = mappedCategories.associateWith { label ->
        val type = if (validation?.transactions?.firstOrNull { it.categoryLabel == label }?.amount?.signum() ?: -1 < 0) TransactionType.EXPENSE else TransactionType.INCOME
        CategoryAutoMapper.bestMatch(label, categories.filter { it.type == type })?.id
    }
    var categorySelections by remember(file, categoryColumn, categories) { mutableStateOf(autoMatch()) }
    val resolved = validation?.transactions.orEmpty().map { transaction ->
        categorySelections[transaction.categoryLabel]?.let { id -> categories.firstOrNull { it.id == id } }?.let { category -> transaction.copy(categoryId = category.id, categoryLabel = category.name) } ?: transaction
    }
    val duplicates = resolved.filter { candidate -> existing.any { it.timestamp == candidate.timestamp && it.amount.compareTo(candidate.amount) == 0 && it.note == candidate.note } }
    val candidates = resolved - duplicates.toSet()
    var importing by remember(file) { mutableStateOf(false) }
    var importFailed by remember(file) { mutableStateOf(false) }
    var importedTransactions by remember(file) { mutableStateOf<List<FinanceTransaction>?>(null) }
    var showHelp by remember { mutableStateOf(false) }
    val canContinue = dateColumn != null && amountColumn != null && validation != null

    val recurringCandidates = remember(importedTransactions) { importedTransactions?.let(RecurringImportDetector::detect).orEmpty() }
    var selectedRules by remember(recurringCandidates) { mutableStateOf(recurringCandidates.indices.toSet()) }
    var addingRules by remember { mutableStateOf(false) }
    var addRulesFailed by remember { mutableStateOf(false) }

    val stepTitles = arrayOf(
        R.string.import_map_columns,
        R.string.import_map_categories,
        R.string.import_preview_title,
        R.string.import_recurring_title,
    )
    val stepDetails = arrayOf(
        R.string.import_columns_detail,
        R.string.import_categories_detail,
        R.string.import_cannot_undo,
        R.string.import_recurring_detail,
    )

    if (showHelp) {
        AlertDialog(
            onDismissRequest = { showHelp = false },
            title = { Text(stringResource(stepTitles[step - 1])) },
            text = { Text(stringResource(stepDetails[step - 1])) },
            confirmButton = { TextButton(onClick = { showHelp = false }) { Text(stringResource(R.string.dismiss)) } },
        )
    }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text(stringResource(R.string.import_export_title)) },
                navigationIcon = {
                    when (step) {
                        1 -> IconButton(onClick = onCancel) { Icon(Icons.Outlined.Close, stringResource(R.string.cancel)) }
                        2, 3 -> IconButton(onClick = { step-- }) { Icon(Icons.AutoMirrored.Outlined.ArrowBack, stringResource(R.string.back)) }
                        else -> {}
                    }
                },
                actions = {
                    when (step) {
                        1 -> IconButton(onClick = { showHelp = true }) { Icon(Icons.Outlined.Info, stringResource(R.string.import_help)) }
                        2 -> FilledTonalButton(onClick = { categorySelections = autoMatch() }, modifier = Modifier.padding(end = 8.dp)) {
                            Text(stringResource(R.string.import_auto_match))
                        }
                        else -> {}
                    }
                },
                colors = TopAppBarDefaults.topAppBarColors(containerColor = MaterialTheme.colorScheme.surface),
            )
        },
        bottomBar = {
            Column(modifier = Modifier.fillMaxWidth().background(MaterialTheme.colorScheme.surface)) {
                HorizontalDivider(thickness = 1.dp, color = MaterialTheme.colorScheme.outlineVariant)
                if (step < 4) {
                    Row(
                        modifier = Modifier.fillMaxWidth().padding(16.dp),
                        horizontalArrangement = Arrangement.spacedBy(12.dp, Alignment.End),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        TextButton(onClick = { if (step == 1) onCancel() else step-- }) {
                            Text(stringResource(if (step == 1) R.string.cancel else R.string.back))
                        }
                        Button(
                            onClick = {
                                if (step < 3) step++ else {
                                    importing = true
                                    importFailed = false
                                    onImport(candidates, categorySelections) { result ->
                                        importing = false
                                        if (result != null) {
                                            importedTransactions = result
                                            step = 4
                                        } else {
                                            importFailed = true
                                        }
                                    }
                                }
                            },
                            modifier = Modifier.height(56.dp),
                            shape = RoundedCornerShape(50),
                            enabled = !importing && (when (step) {
                                1 -> canContinue
                                3 -> candidates.isNotEmpty()
                                else -> true
                            }),
                        ) {
                            if (importing) Text(stringResource(R.string.importing_transactions))
                            else if (step < 3) Text(stringResource(R.string.continue_label)) else Text(stringResource(R.string.import_transactions, candidates.size))
                        }
                    }
                    if (importFailed) {
                        Text(stringResource(R.string.import_failed), color = MaterialTheme.colorScheme.error, modifier = Modifier.padding(start = 16.dp, end = 16.dp, bottom = 8.dp))
                    }
                } else {
                    Row(
                        modifier = Modifier.fillMaxWidth().padding(16.dp),
                        horizontalArrangement = Arrangement.spacedBy(12.dp, Alignment.End),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        if (recurringCandidates.isNotEmpty()) {
                            TextButton(onClick = onFinish, enabled = !addingRules) { Text(stringResource(R.string.import_skip)) }
                            Button(
                                onClick = {
                                    addingRules = true
                                    addRulesFailed = false
                                    val rules = selectedRules.map { index ->
                                        val candidate = recurringCandidates[index]
                                        NewRecurrenceRule(
                                            frequency = candidate.frequency,
                                            interval = candidate.interval,
                                            startDate = candidate.nextDate,
                                            amount = candidate.amount,
                                            note = candidate.note,
                                            categoryLabel = candidate.categoryLabel,
                                            categoryId = candidate.categoryId,
                                            currencyCode = candidate.currencyCode,
                                        )
                                    }
                                    onAddRecurrenceRules(rules) { success ->
                                        addingRules = false
                                        if (success) onFinish() else addRulesFailed = true
                                    }
                                },
                                modifier = Modifier.height(56.dp),
                                shape = RoundedCornerShape(50),
                                enabled = !addingRules && selectedRules.isNotEmpty(),
                            ) {
                                Text(pluralStringResource(R.plurals.import_add_rules_button, selectedRules.size, selectedRules.size))
                            }
                        } else {
                            Button(onClick = onFinish, modifier = Modifier.height(56.dp), shape = RoundedCornerShape(50)) {
                                Text(stringResource(R.string.import_done))
                            }
                        }
                    }
                    if (addRulesFailed) {
                        Text(stringResource(R.string.import_failed), color = MaterialTheme.colorScheme.error, modifier = Modifier.padding(start = 16.dp, end = 16.dp, bottom = 8.dp))
                    }
                }
            }
        },
        containerColor = MaterialTheme.colorScheme.surface,
        contentColor = MaterialTheme.colorScheme.onSurface,
    ) { padding ->
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(padding)
                .padding(16.dp)
                .verticalScroll(rememberScrollState()),
            verticalArrangement = Arrangement.spacedBy(16.dp),
        ) {
            // Step headline
            Text(
                stringResource(stepTitles[step - 1]),
                style = MaterialTheme.typography.headlineMedium,
                modifier = Modifier.semantics { heading() }
            )

            // Progress track (4 segments)
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .height(4.dp),
                horizontalArrangement = Arrangement.spacedBy(4.dp),
            ) {
                repeat(4) { index ->
                    Box(
                        modifier = Modifier
                            .weight(1f)
                            .height(4.dp)
                            .background(
                                color = if (index < step) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.surfaceContainerHighest,
                                shape = RoundedCornerShape(2.dp)
                            )
                    )
                }
            }

            // Caption line
            Text(
                stringResource(R.string.import_step_of_rows, step, 4, file.rows.size),
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                style = MaterialTheme.typography.labelSmall
            )

            Spacer(modifier = Modifier.height(8.dp))

            // Step content
            when (step) {
                1 -> {
                    Text(stringResource(R.string.import_columns_detail), color = MaterialTheme.colorScheme.onSurfaceVariant)
                    FinanceCard {
                        Column(modifier = Modifier.fillMaxWidth().padding(20.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                            Text(stringResource(R.string.import_preview_label), color = MaterialTheme.colorScheme.primary, style = MaterialTheme.typography.labelLarge, fontWeight = FontWeight.Bold)
                            // Wide files (many columns) scroll horizontally instead of squeezing every
                            // column to 1/N of the screen width, which forced headers onto several lines.
                            val sampleRows = file.rows.take(3)
                            val columnAlignments = file.headers.indices.map { index ->
                                val samples = sampleRows.mapNotNull { it.getOrNull(index) }.filter(String::isNotBlank)
                                val looksNumeric = samples.isNotEmpty() && samples.all { it.replace(",", ".").toDoubleOrNull() != null }
                                if (looksNumeric) TextAlign.End else TextAlign.Start
                            }
                            Column(modifier = Modifier.horizontalScroll(rememberScrollState())) {
                                Column(modifier = Modifier.width(IntrinsicSize.Max)) {
                                    Row(
                                        modifier = Modifier
                                            .fillMaxWidth()
                                            .background(MaterialTheme.colorScheme.surfaceContainerHighest, RoundedCornerShape(8.dp))
                                            .padding(horizontal = 8.dp, vertical = 8.dp),
                                        horizontalArrangement = Arrangement.spacedBy(16.dp),
                                    ) {
                                        file.headers.forEachIndexed { index, header ->
                                            Text(
                                                header.uppercase(),
                                                style = MaterialTheme.typography.labelSmall,
                                                fontWeight = FontWeight.Bold,
                                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                                                maxLines = 1,
                                                overflow = TextOverflow.Ellipsis,
                                                textAlign = columnAlignments[index],
                                                modifier = Modifier.width(PreviewColumnWidth),
                                            )
                                        }
                                    }
                                    sampleRows.forEach { row ->
                                        HorizontalDivider(thickness = 1.dp, color = MaterialTheme.colorScheme.surfaceContainerHighest, modifier = Modifier.fillMaxWidth())
                                        Row(
                                            modifier = Modifier.fillMaxWidth().padding(horizontal = 8.dp, vertical = 10.dp),
                                            horizontalArrangement = Arrangement.spacedBy(16.dp),
                                        ) {
                                            row.take(file.headers.size).forEachIndexed { index, cell ->
                                                Text(
                                                    cell.ifBlank { "—" },
                                                    style = MaterialTheme.typography.bodySmall,
                                                    maxLines = 1,
                                                    overflow = TextOverflow.Ellipsis,
                                                    textAlign = columnAlignments[index],
                                                    modifier = Modifier.width(PreviewColumnWidth),
                                                )
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                    Text(stringResource(R.string.import_required), color = MaterialTheme.colorScheme.outline, style = MaterialTheme.typography.labelLarge)
                    FinanceCard {
                        Column(modifier = Modifier.fillMaxWidth()) {
                            MappingSelectorListItem(R.string.import_date_column, dateColumn, file.headers) { dateColumn = it }
                            HorizontalDivider(thickness = 1.dp, color = MaterialTheme.colorScheme.surfaceContainerHighest)
                            MappingSelectorListItem(R.string.import_amount_column, amountColumn, file.headers) { amountColumn = it }
                        }
                    }
                    Text(stringResource(R.string.import_optional), color = MaterialTheme.colorScheme.outline, style = MaterialTheme.typography.labelLarge)
                    FinanceCard {
                        Column(modifier = Modifier.fillMaxWidth()) {
                            MappingSelectorListItem(R.string.import_type_column, typeColumn, file.headers) { typeColumn = it }
                            HorizontalDivider(thickness = 1.dp, color = MaterialTheme.colorScheme.surfaceContainerHighest)
                            MappingSelectorListItem(R.string.import_category_column, categoryColumn, file.headers) { categoryColumn = it }
                            HorizontalDivider(thickness = 1.dp, color = MaterialTheme.colorScheme.surfaceContainerHighest)
                            MappingSelectorListItem(R.string.import_note_column, noteColumn, file.headers) { noteColumn = it }
                        }
                    }
                    FinanceCard {
                        Column(modifier = Modifier.fillMaxWidth()) {
                            MappingSelectorListItem(R.string.import_date_format, dateFormat, TransactionImportMapper.supportedDateFormats) { dateFormat = it ?: dateFormat }
                            if (typeColumn == null) {
                                HorizontalDivider(thickness = 1.dp, color = MaterialTheme.colorScheme.surfaceContainerHighest)
                                Column(modifier = Modifier.fillMaxWidth().padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                                    Text(stringResource(R.string.import_sign_convention), style = MaterialTheme.typography.bodyMedium)
                                    SignConventionSegmentedButton(signConvention) { signConvention = it }
                                    Text(
                                        stringResource(
                                            when (signConvention) {
                                                SignConvention.SIGNED -> R.string.import_sign_detail_signed
                                                SignConvention.ALL_EXPENSES -> R.string.import_sign_detail_all_expenses
                                                SignConvention.ALL_INCOME -> R.string.import_sign_detail_all_income
                                            }
                                        ),
                                        style = MaterialTheme.typography.bodySmall,
                                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                                    )
                                }
                            }
                        }
                    }
                }
                2 -> {
                    Text(stringResource(R.string.import_categories_detail), color = MaterialTheme.colorScheme.onSurfaceVariant)
                    if (mappedCategories.isEmpty()) {
                        Text(stringResource(R.string.import_no_categories), color = MaterialTheme.colorScheme.onSurfaceVariant)
                    } else {
                        val matchedCount = mappedCategories.count { categorySelections[it] != null }
                        val newCount = mappedCategories.size - matchedCount
                        mappedCategories.groupBy { label -> if (validation?.transactions?.firstOrNull { it.categoryLabel == label }?.amount?.signum() ?: -1 < 0) TransactionType.EXPENSE else TransactionType.INCOME }.forEach { (type, labels) ->
                            Text(stringResource(if (type == TransactionType.EXPENSE) R.string.import_expenses else R.string.import_income, labels.size), color = MaterialTheme.colorScheme.outline, style = MaterialTheme.typography.labelLarge)
                            val categoriesForType = categories.filter { it.type == type }
                            FinanceCard {
                                Column(modifier = Modifier.fillMaxWidth()) {
                                    labels.forEachIndexed { idx, label ->
                                        if (idx > 0) HorizontalDivider(thickness = 1.dp, color = MaterialTheme.colorScheme.surfaceContainerHighest)
                                        CategorySelectorListItem(label, categorySelections[label], categoriesForType) { selection -> categorySelections = categorySelections + (label to selection) }
                                    }
                                }
                            }
                        }
                        Text(
                            stringResource(R.string.import_categories_footer, matchedCount, pluralStringResource(R.plurals.import_categories_new, newCount, newCount)),
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                            style = MaterialTheme.typography.bodySmall,
                        )
                    }
                }
                3 -> {
                    val neutralContainer = MaterialTheme.colorScheme.surfaceContainerHighest
                    val neutralContent = MaterialTheme.colorScheme.onSurfaceVariant
                    Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        ImportMetric(stringResource(R.string.import_total), validation?.transactions?.size ?: 0, MaterialTheme.colorScheme.primaryContainer, MaterialTheme.colorScheme.onPrimaryContainer)
                        ImportMetric(stringResource(R.string.import_new), candidates.size, LocalFinanceExtendedColors.current.positiveContainer, LocalFinanceExtendedColors.current.positive)
                        ImportMetric(stringResource(R.string.import_duplicates), duplicates.size, neutralContainer, neutralContent)
                        ImportMetric(stringResource(R.string.import_errors), validation?.rejectedRows ?: 0, neutralContainer, neutralContent)
                    }
                    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                        Icon(Icons.Outlined.Info, contentDescription = null, modifier = Modifier.size(16.dp), tint = MaterialTheme.colorScheme.onSurfaceVariant)
                        Text(stringResource(R.string.import_cannot_undo), color = MaterialTheme.colorScheme.onSurfaceVariant, style = MaterialTheme.typography.bodySmall)
                    }
                    FinanceCard {
                        Column(modifier = Modifier.fillMaxWidth().padding(20.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                            candidates.take(8).forEach { transaction ->
                                val category = categories.firstOrNull { it.id == transaction.categoryId }
                                Row(modifier = Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                                    Box(
                                        modifier = Modifier.size(40.dp).clip(CircleShape).background(categoryColor(category?.colorToken ?: "categoryGray").copy(alpha = 0.15f)),
                                        contentAlignment = Alignment.Center,
                                    ) {
                                        Icon(categoryIconFor(category?.iconToken ?: "tag"), contentDescription = null, tint = categoryColor(category?.colorToken ?: "categoryGray"), modifier = Modifier.size(20.dp))
                                    }
                                    Column(modifier = Modifier.weight(1f)) {
                                        Text(transaction.categoryLabel.ifBlank { stringResource(R.string.import_uncategorized) }, fontWeight = FontWeight.Bold)
                                        Text(transaction.note, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant, maxLines = 1)
                                    }
                                    Column(horizontalAlignment = Alignment.End) {
                                        Text(
                                            formatCurrency(transaction.amount, transaction.currencyCode),
                                            fontWeight = FontWeight.Bold,
                                            color = if (transaction.amount.signum() < 0) MaterialTheme.colorScheme.error else LocalFinanceExtendedColors.current.positive,
                                        )
                                        Text(formatTransactionDate(transaction.timestamp), style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                                    }
                                }
                            }
                        }
                    }
                }
                4 -> {
                    Row(
                        modifier = Modifier
                            .fillMaxWidth()
                            .background(LocalFinanceExtendedColors.current.positiveContainer, RoundedCornerShape(16.dp))
                            .padding(16.dp),
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(12.dp),
                    ) {
                        Icon(Icons.Filled.CheckCircle, contentDescription = null, tint = LocalFinanceExtendedColors.current.positive)
                        Text(
                            stringResource(R.string.import_imported_count, importedTransactions?.size ?: 0),
                            color = LocalFinanceExtendedColors.current.positive,
                            fontWeight = FontWeight.Bold,
                        )
                    }
                    if (recurringCandidates.isEmpty()) {
                        Text(stringResource(R.string.import_recurring_none), color = MaterialTheme.colorScheme.onSurfaceVariant)
                    } else {
                        Text(stringResource(R.string.import_recurring_detail), color = MaterialTheme.colorScheme.onSurfaceVariant)
                        FinanceCard {
                            Column(modifier = Modifier.fillMaxWidth()) {
                                recurringCandidates.forEachIndexed { index, candidate ->
                                    if (index > 0) HorizontalDivider(thickness = 1.dp, color = MaterialTheme.colorScheme.surfaceContainerHighest)
                                    RecurringCandidateRow(
                                        candidate = candidate,
                                        category = categories.firstOrNull { it.id == candidate.categoryId },
                                        checked = index in selectedRules,
                                        onCheckedChange = { checked -> selectedRules = if (checked) selectedRules + index else selectedRules - index },
                                    )
                                }
                            }
                        }
                        Text(stringResource(R.string.import_rules_note), style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    }
                }
            }
        }
    }
}

@Composable
private fun SheetPicker(workbook: XlsxImportService.Workbook, onSelect: (XlsxImportService.Sheet) -> Unit) {
    FinanceCard {
        Column(modifier = Modifier.fillMaxWidth().padding(20.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Text(stringResource(R.string.import_choose_sheet), style = MaterialTheme.typography.titleMedium)
            Text(stringResource(R.string.import_choose_sheet_detail), color = MaterialTheme.colorScheme.onSurfaceVariant)
            workbook.sheets.forEach { sheet -> TextButton(onClick = { onSelect(sheet) }) { Text(sheet.name) } }
        }
    }
}

@Composable
private fun RowScope.ImportMetric(label: String, value: Int, containerColor: androidx.compose.ui.graphics.Color, contentColor: androidx.compose.ui.graphics.Color) {
    Column(
        modifier = Modifier
            .weight(1f)
            .background(containerColor, RoundedCornerShape(12.dp))
            .padding(vertical = 12.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Text(value.toString(), style = MaterialTheme.typography.headlineSmall, fontWeight = FontWeight.Bold, color = contentColor)
        Text(label, style = MaterialTheme.typography.labelSmall, color = contentColor)
    }
}

@Composable
private fun CategorySelectorListItem(label: String, selection: String?, categories: List<FinanceCategory>, onSelected: (String?) -> Unit) {
    var expanded by remember(label) { mutableStateOf(false) }
    // The CSV's own emoji stays on the row label, but the name offered for a new category is
    // stripped of it — the emoji doesn't get saved as part of the category name either.
    val createName = label.removingLeadingEmoji().trim().ifBlank { label }
    Box {
        ListItem(
            headlineContent = { Text(label) },
            trailingContent = { MappingTrailingValue(categories.firstOrNull { it.id == selection }?.name ?: stringResource(R.string.import_create_category, createName)) },
            colors = ListItemDefaults.colors(containerColor = androidx.compose.ui.graphics.Color.Transparent),
            modifier = Modifier.fillMaxWidth().clickable { expanded = true },
        )
        DropdownMenu(expanded = expanded, onDismissRequest = { expanded = false }) {
            DropdownMenuItem(text = { Text(stringResource(R.string.import_create_category, createName)) }, onClick = { onSelected(null); expanded = false })
            categories.forEach { category -> DropdownMenuItem(text = { Text(category.name) }, onClick = { onSelected(category.id); expanded = false }) }
        }
    }
}

/** iOS's sign convention menu becomes an outlined segmented control with a check on the selected option. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun SignConventionSegmentedButton(selected: SignConvention, onSelected: (SignConvention) -> Unit) {
    val options = listOf(
        SignConvention.SIGNED to R.string.import_sign_signed,
        SignConvention.ALL_EXPENSES to R.string.import_sign_all_expenses,
        SignConvention.ALL_INCOME to R.string.import_sign_all_income,
    )
    SingleChoiceSegmentedButtonRow(modifier = Modifier.fillMaxWidth()) {
        options.forEachIndexed { index, (convention, labelRes) ->
            SegmentedButton(
                selected = selected == convention,
                onClick = { onSelected(convention) },
                shape = SegmentedButtonDefaults.itemShape(index = index, count = options.size),
                icon = { if (selected == convention) Icon(Icons.Filled.Check, contentDescription = null, modifier = Modifier.size(18.dp)) },
            ) {
                Text(stringResource(labelRes))
            }
        }
    }
}

@Composable
private fun MappingSelectorListItem(labelRes: Int, selected: String?, headers: List<String>, onSelected: (String?) -> Unit) {
    var expanded by remember { mutableStateOf(false) }
    Box {
        ListItem(
            headlineContent = { Text(stringResource(labelRes)) },
            trailingContent = { MappingTrailingValue(selected ?: stringResource(R.string.import_not_mapped)) },
            colors = ListItemDefaults.colors(containerColor = androidx.compose.ui.graphics.Color.Transparent),
            modifier = Modifier.fillMaxWidth().clickable { expanded = true },
        )
        DropdownMenu(expanded = expanded, onDismissRequest = { expanded = false }) {
            DropdownMenuItem(text = { Text(stringResource(R.string.import_not_mapped)) }, onClick = { onSelected(null); expanded = false })
            headers.forEach { header -> DropdownMenuItem(text = { Text(header) }, onClick = { onSelected(header); expanded = false }) }
        }
    }
}

/** A picker row's trailing value: primary-indigo text plus a drop-down caret instead of a chevron push. */
@Composable
private fun MappingTrailingValue(text: String) {
    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(2.dp)) {
        Text(text, style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.primary, fontWeight = FontWeight.Bold)
        Icon(Icons.Filled.KeyboardArrowDown, contentDescription = null, tint = MaterialTheme.colorScheme.primary, modifier = Modifier.size(20.dp))
    }
}

@Composable
private fun RecurringCandidateRow(candidate: RecurringCandidate, category: FinanceCategory?, checked: Boolean, onCheckedChange: (Boolean) -> Unit) {
    val accent = categoryColor(category?.colorToken ?: "categoryGray")
    val cadence = when (candidate.frequency) {
        RecurrenceFrequency.WEEKLY -> if (candidate.interval == 1) stringResource(R.string.cadence_weekly) else stringResource(R.string.cadence_weekly_n, candidate.interval)
        RecurrenceFrequency.MONTHLY -> if (candidate.interval == 1) stringResource(R.string.cadence_monthly) else stringResource(R.string.cadence_monthly_n, candidate.interval)
        RecurrenceFrequency.YEARLY -> stringResource(R.string.cadence_yearly)
    }
    Row(
        modifier = Modifier.fillMaxWidth().padding(vertical = 12.dp, horizontal = 16.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Checkbox(checked = checked, onCheckedChange = onCheckedChange)
        Box(
            modifier = Modifier.size(36.dp).clip(CircleShape).background(accent.copy(alpha = 0.15f)),
            contentAlignment = Alignment.Center,
        ) {
            Icon(categoryIconFor(category?.iconToken ?: "tag"), contentDescription = null, tint = accent, modifier = Modifier.size(18.dp))
        }
        Column(modifier = Modifier.weight(1f)) {
            Text(candidate.note.ifBlank { candidate.categoryLabel }, fontWeight = FontWeight.Bold, maxLines = 1)
            Text(
                stringResource(R.string.import_starts, cadence, formatTransactionDate(candidate.nextDate)),
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            Text(stringResource(R.string.import_seen_times, candidate.occurrences), style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
        Text(
            formatCurrency(candidate.amount, candidate.currencyCode),
            fontWeight = FontWeight.Bold,
            color = if (candidate.amount.signum() < 0) MaterialTheme.colorScheme.error else LocalFinanceExtendedColors.current.positive,
        )
    }
}

private fun List<String>.matching(vararg names: String): String? = firstOrNull { header ->
    names.any { name -> header.contains(name, ignoreCase = true) }
}

private val PreviewColumnWidth = 88.dp
