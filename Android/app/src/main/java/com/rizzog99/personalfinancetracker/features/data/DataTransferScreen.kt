package com.rizzog99.personalfinancetracker.features.data

import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.verticalScroll
import androidx.compose.foundation.rememberScrollState
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.ArrowBack
import androidx.compose.material.icons.outlined.FileDownload
import androidx.compose.material.icons.outlined.FileOpen
import androidx.compose.material3.Button
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Scaffold
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
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
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import androidx.lifecycle.viewmodel.compose.viewModel
import com.rizzog99.personalfinancetracker.PersonalFinanceApplication
import com.rizzog99.personalfinancetracker.R
import com.rizzog99.personalfinancetracker.domain.export.CsvExportService
import com.rizzog99.personalfinancetracker.domain.export.XlsxExportService
import com.rizzog99.personalfinancetracker.domain.import.CsvImportParser
import com.rizzog99.personalfinancetracker.domain.import.CsvColumnMapping
import com.rizzog99.personalfinancetracker.domain.import.TransactionImportMapper
import com.rizzog99.personalfinancetracker.domain.import.SignConvention
import com.rizzog99.personalfinancetracker.domain.import.XlsxImportService
import com.rizzog99.personalfinancetracker.ui.components.FinanceCard
import com.rizzog99.personalfinancetracker.ui.theme.LocalFinancePalette
import kotlinx.coroutines.launch

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun DataTransferScreen(onBack: () -> Unit) {
    val context = LocalContext.current
    val application = context.applicationContext as PersonalFinanceApplication
    val viewModel: DataTransferViewModel = viewModel(
        factory = DataTransferViewModel.factory(application.transactionRepository, application.categoryRepository),
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
            onImport = { transactions, selections ->
                viewModel.import(transactions, selections) { success ->
                    scope.launch { snackbarHostState.showSnackbar(context.getString(if (success) R.string.import_complete else R.string.import_failed)) }
                    if (success) importedFile = null
                }
            },
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
                    containerColor = androidx.compose.ui.graphics.Color.Transparent,
                    titleContentColor = MaterialTheme.colorScheme.onBackground,
                    navigationIconContentColor = LocalFinancePalette.current.textMid,
                ),
            )
        },
        snackbarHost = { SnackbarHost(snackbarHostState) },
        containerColor = androidx.compose.ui.graphics.Color.Transparent,
    ) { padding ->
        Column(
            modifier = Modifier.fillMaxSize().padding(padding).padding(16.dp).verticalScroll(rememberScrollState()),
            verticalArrangement = Arrangement.spacedBy(16.dp),
        ) {
            Text(stringResource(R.string.export_section), style = MaterialTheme.typography.labelLarge, color = LocalFinancePalette.current.textDim)
            FinanceCard {
                Column(modifier = Modifier.fillMaxWidth().padding(20.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    Text(stringResource(R.string.export_csv), style = MaterialTheme.typography.titleMedium)
                    Text(stringResource(R.string.export_csv_detail), color = LocalFinancePalette.current.textMid)
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
            Text(stringResource(R.string.import_section), style = MaterialTheme.typography.labelLarge, color = LocalFinancePalette.current.textDim)
            FinanceCard {
                Column(modifier = Modifier.fillMaxWidth().padding(20.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    Text(stringResource(R.string.import_csv), style = MaterialTheme.typography.titleMedium)
                    Text(stringResource(R.string.import_csv_detail), color = LocalFinancePalette.current.textMid)
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
private fun ImportWizardScreen(file: CsvImportParser.CsvFile, existing: List<com.rizzog99.personalfinancetracker.domain.transaction.FinanceTransaction>, categories: List<com.rizzog99.personalfinancetracker.domain.category.FinanceCategory>, onCancel: () -> Unit, onImport: (List<com.rizzog99.personalfinancetracker.domain.transaction.FinanceTransaction>, Map<String, String?>) -> Unit) {
    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text(stringResource(R.string.import_export_title)) },
                navigationIcon = { IconButton(onClick = onCancel) { Icon(Icons.AutoMirrored.Outlined.ArrowBack, stringResource(R.string.back)) } },
                colors = TopAppBarDefaults.topAppBarColors(containerColor = androidx.compose.ui.graphics.Color.Transparent),
            )
        },
        containerColor = androidx.compose.ui.graphics.Color.Transparent,
    ) { padding ->
        Column(modifier = Modifier.fillMaxSize().padding(padding).padding(16.dp).verticalScroll(rememberScrollState())) {
            ImportWizard(file, existing, categories, onCancel, onImport)
        }
    }
}

@Composable
private fun SheetPicker(workbook: XlsxImportService.Workbook, onSelect: (XlsxImportService.Sheet) -> Unit) {
    FinanceCard {
        Column(modifier = Modifier.fillMaxWidth().padding(20.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Text(stringResource(R.string.import_choose_sheet), style = MaterialTheme.typography.titleMedium)
            Text(stringResource(R.string.import_choose_sheet_detail), color = LocalFinancePalette.current.textMid)
            workbook.sheets.forEach { sheet -> TextButton(onClick = { onSelect(sheet) }) { Text(sheet.name) } }
        }
    }
}

@Composable
private fun ImportWizard(file: CsvImportParser.CsvFile, existing: List<com.rizzog99.personalfinancetracker.domain.transaction.FinanceTransaction>, categories: List<com.rizzog99.personalfinancetracker.domain.category.FinanceCategory>, onCancel: () -> Unit, onImport: (List<com.rizzog99.personalfinancetracker.domain.transaction.FinanceTransaction>, Map<String, String?>) -> Unit) {
    var step by remember(file) { mutableStateOf(1) }
    var dateColumn by remember(file) { mutableStateOf(file.headers.matching("date", "period")) }
    var amountColumn by remember(file) { mutableStateOf(file.headers.matching("amount", "value")) }
    var categoryColumn by remember(file) { mutableStateOf(file.headers.matching("category")) }
    var noteColumn by remember(file) { mutableStateOf(file.headers.matching("note", "description")) }
    var typeColumn by remember(file) { mutableStateOf(file.headers.matching("type", "income/expense")) }
    var dateFormat by remember(file) { mutableStateOf(TransactionImportMapper.supportedDateFormats.firstOrNull { format -> file.rows.firstOrNull()?.getOrNull(file.headers.indexOf(dateColumn ?: ""))?.let { runCatching { java.time.LocalDate.parse(it, java.time.format.DateTimeFormatter.ofPattern(format)) }.isSuccess || runCatching { java.time.LocalDateTime.parse(it, java.time.format.DateTimeFormatter.ofPattern(format)) }.isSuccess } == true } ?: "dd/MM/yyyy") }
    var signConvention by remember(file) { mutableStateOf(SignConvention.EXPENSES_NEGATIVE) }
    val validation = if (dateColumn != null && amountColumn != null) runCatching { TransactionImportMapper.validate(file, CsvColumnMapping(dateColumn!!, amountColumn!!, categoryColumn, noteColumn, typeColumn, dateFormat, signConvention)) }.getOrNull() else null
    val mappedCategories = validation?.transactions.orEmpty().mapNotNull { it.categoryLabel.takeIf(String::isNotBlank) }.distinct()
    var categorySelections by remember(file, categoryColumn, categories) { mutableStateOf(mappedCategories.associateWith { label -> categories.firstOrNull { it.name.equals(label, true) }?.id }) }
    val resolved = validation?.transactions.orEmpty().map { transaction ->
        categorySelections[transaction.categoryLabel]?.let { id -> categories.firstOrNull { it.id == id } }?.let { category -> transaction.copy(categoryId = category.id, categoryLabel = category.name) } ?: transaction
    }
    val duplicates = resolved.filter { candidate -> existing.any { it.timestamp == candidate.timestamp && it.amount.compareTo(candidate.amount) == 0 && it.note == candidate.note } }
    val candidates = resolved - duplicates.toSet()
    var confirming by remember(file, dateColumn, amountColumn, categoryColumn, noteColumn, typeColumn, dateFormat, signConvention, categorySelections) { mutableStateOf(false) }
    val canContinue = dateColumn != null && amountColumn != null && validation != null
    val title = when (step) { 1 -> R.string.import_map_columns; 2 -> R.string.import_map_categories; else -> R.string.import_preview_title }
    Column(modifier = Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(16.dp)) {
        Row(modifier = Modifier.fillMaxWidth(), verticalAlignment = androidx.compose.ui.Alignment.CenterVertically) {
            Text(stringResource(title), style = MaterialTheme.typography.headlineSmall, modifier = Modifier.weight(1f))
            Text(stringResource(R.string.import_step_of, step, 3), color = LocalFinancePalette.current.textMid)
        }
        when (step) {
            1 -> {
                Text(stringResource(R.string.import_columns_detail), color = LocalFinancePalette.current.textMid)
                FinanceCard { Column(modifier = Modifier.fillMaxWidth().padding(20.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    Text(stringResource(R.string.import_preview, file.rows.size), color = LocalFinancePalette.current.textDim, style = MaterialTheme.typography.labelLarge)
                    Text(file.headers.joinToString(" · "), style = MaterialTheme.typography.labelSmall, maxLines = 1)
                    file.rows.take(3).forEach { row -> Text(row.take(file.headers.size).joinToString(" · ").ifBlank { "—" }, style = MaterialTheme.typography.bodySmall, maxLines = 1) }
                } }
                Text(stringResource(R.string.import_required), color = LocalFinancePalette.current.textDim, style = MaterialTheme.typography.labelLarge)
                FinanceCard { Column(modifier = Modifier.fillMaxWidth().padding(20.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                    MappingSelector(R.string.import_date_column, dateColumn, file.headers) { dateColumn = it }
                    MappingSelector(R.string.import_amount_column, amountColumn, file.headers) { amountColumn = it }
                } }
                Text(stringResource(R.string.import_optional), color = LocalFinancePalette.current.textDim, style = MaterialTheme.typography.labelLarge)
                FinanceCard { Column(modifier = Modifier.fillMaxWidth().padding(20.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                    MappingSelector(R.string.import_type_column, typeColumn, file.headers) { typeColumn = it }
                    MappingSelector(R.string.import_category_column, categoryColumn, file.headers) { categoryColumn = it }
                    MappingSelector(R.string.import_note_column, noteColumn, file.headers) { noteColumn = it }
                } }
                FinanceCard { Column(modifier = Modifier.fillMaxWidth().padding(20.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                    MappingSelector(R.string.import_date_format, dateFormat, TransactionImportMapper.supportedDateFormats) { dateFormat = it ?: dateFormat }
                    if (typeColumn == null) SignConventionSelector(signConvention) { signConvention = it }
                } }
            }
            2 -> {
                Text(stringResource(R.string.import_categories_detail), color = LocalFinancePalette.current.textMid)
                if (mappedCategories.isEmpty()) Text(stringResource(R.string.import_no_categories), color = LocalFinancePalette.current.textMid)
                mappedCategories.groupBy { label -> if (validation?.transactions?.firstOrNull { it.categoryLabel == label }?.amount?.signum() ?: -1 < 0) R.string.import_expenses else R.string.import_income }.forEach { (type, labels) ->
                    Text(stringResource(type), color = LocalFinancePalette.current.textDim, style = MaterialTheme.typography.labelLarge)
                    FinanceCard { Column(modifier = Modifier.fillMaxWidth().padding(20.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                        labels.forEach { label -> CategorySelector(label, categorySelections[label], categories) { selection -> categorySelections = categorySelections + (label to selection) } }
                    } }
                }
            }
            else -> {
                FinanceCard { Row(modifier = Modifier.fillMaxWidth().padding(16.dp), horizontalArrangement = Arrangement.SpaceBetween) {
                    ImportMetric(stringResource(R.string.import_total), validation?.transactions?.size ?: 0)
                    ImportMetric(stringResource(R.string.import_new), candidates.size)
                    ImportMetric(stringResource(R.string.import_duplicates), duplicates.size)
                    ImportMetric(stringResource(R.string.import_errors), validation?.rejectedRows ?: 0)
                } }
                Text(stringResource(R.string.import_cannot_undo), color = LocalFinancePalette.current.textMid)
                FinanceCard { Column(modifier = Modifier.fillMaxWidth().padding(20.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
                    candidates.take(8).forEach { transaction -> Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                        Column(modifier = Modifier.weight(1f)) { Text(transaction.categoryLabel.ifBlank { stringResource(R.string.import_uncategorized) }); Text(transaction.note, style = MaterialTheme.typography.bodySmall, color = LocalFinancePalette.current.textMid) }
                        Text(transaction.amount.toPlainString(), color = if (transaction.amount.signum() < 0) MaterialTheme.colorScheme.error else LocalFinancePalette.current.positive)
                    } }
                } }
            }
        }
        Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
            TextButton(onClick = { if (step == 1) onCancel() else step-- }) { Text(stringResource(if (step == 1) R.string.cancel else R.string.back)) }
            Button(onClick = { if (step < 3) step++ else confirming = true }, enabled = if (step == 1) canContinue else candidates.isNotEmpty()) {
                if (step < 3) Text(stringResource(R.string.continue_label)) else Text(stringResource(R.string.import_transactions, candidates.size))
            }
        }
    }
    if (confirming) {
        AlertDialog(
            onDismissRequest = { confirming = false },
            title = { Text(stringResource(R.string.import_confirm_title)) },
            text = { Text(stringResource(R.string.import_confirm_message, candidates.size)) },
            confirmButton = { Button(onClick = { confirming = false; onImport(candidates, categorySelections) }) { Text(stringResource(R.string.import_transactions, candidates.size)) } },
            dismissButton = { TextButton(onClick = { confirming = false }) { Text(stringResource(R.string.cancel)) } },
        )
    }
}

@Composable
private fun ImportMetric(label: String, value: Int) = Column(horizontalAlignment = androidx.compose.ui.Alignment.CenterHorizontally) {
    Text(value.toString(), style = MaterialTheme.typography.headlineSmall)
    Text(label, style = MaterialTheme.typography.labelSmall, color = LocalFinancePalette.current.textMid)
}

@Composable
private fun CategorySelector(label: String, selection: String?, categories: List<com.rizzog99.personalfinancetracker.domain.category.FinanceCategory>, onSelected: (String?) -> Unit) {
    var expanded by remember(label) { mutableStateOf(false) }
    Row(modifier = Modifier.fillMaxWidth(), verticalAlignment = androidx.compose.ui.Alignment.CenterVertically) {
        Text(label, modifier = Modifier.weight(1f))
        Box {
            TextButton(onClick = { expanded = true }) { Text(categories.firstOrNull { it.id == selection }?.name ?: stringResource(R.string.import_create_category, label)) }
            DropdownMenu(expanded = expanded, onDismissRequest = { expanded = false }) {
                DropdownMenuItem(text = { Text(stringResource(R.string.import_create_category, label)) }, onClick = { onSelected(null); expanded = false })
                categories.forEach { category -> DropdownMenuItem(text = { Text(category.name) }, onClick = { onSelected(category.id); expanded = false }) }
            }
        }
    }
}

@Composable
private fun SignConventionSelector(selected: SignConvention, onSelected: (SignConvention) -> Unit) {
    var expanded by remember { mutableStateOf(false) }
    Row(modifier = Modifier.fillMaxWidth(), verticalAlignment = androidx.compose.ui.Alignment.CenterVertically) {
        Text(stringResource(R.string.import_sign_convention), modifier = Modifier.weight(1f))
        Box {
            TextButton(onClick = { expanded = true }) { Text(stringResource(if (selected == SignConvention.EXPENSES_NEGATIVE) R.string.import_expenses_negative else R.string.import_expenses_positive)) }
            DropdownMenu(expanded = expanded, onDismissRequest = { expanded = false }) {
                DropdownMenuItem(text = { Text(stringResource(R.string.import_expenses_negative)) }, onClick = { onSelected(SignConvention.EXPENSES_NEGATIVE); expanded = false })
                DropdownMenuItem(text = { Text(stringResource(R.string.import_expenses_positive)) }, onClick = { onSelected(SignConvention.EXPENSES_POSITIVE); expanded = false })
            }
        }
    }
}

@Composable
private fun MappingSelector(labelRes: Int, selected: String?, headers: List<String>, onSelected: (String?) -> Unit) {
    var expanded by remember { mutableStateOf(false) }
    Row(modifier = Modifier.fillMaxWidth(), verticalAlignment = androidx.compose.ui.Alignment.CenterVertically) {
        Text(stringResource(labelRes), modifier = Modifier.weight(1f))
        Box {
            TextButton(onClick = { expanded = true }) { Text(selected ?: stringResource(R.string.import_not_mapped)) }
            DropdownMenu(expanded = expanded, onDismissRequest = { expanded = false }) {
                DropdownMenuItem(text = { Text(stringResource(R.string.import_not_mapped)) }, onClick = { onSelected(null); expanded = false })
                headers.forEach { header -> DropdownMenuItem(text = { Text(header) }, onClick = { onSelected(header); expanded = false }) }
            }
        }
    }
}

private fun List<String>.matching(vararg names: String): String? = firstOrNull { header ->
    names.any { name -> header.contains(name, ignoreCase = true) }
}
