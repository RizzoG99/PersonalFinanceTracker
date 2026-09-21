package com.rizzog99.personalfinancetracker.features.settings

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.ArrowBack
import androidx.compose.material.icons.outlined.UnfoldMore
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.lifecycle.viewmodel.compose.viewModel
import com.rizzog99.personalfinancetracker.PersonalFinanceApplication
import com.rizzog99.personalfinancetracker.R
import com.rizzog99.personalfinancetracker.domain.category.FinanceCategory
import com.rizzog99.personalfinancetracker.domain.receipt.ReceiptCategoryConcept
import com.rizzog99.personalfinancetracker.features.categories.categoryColor
import com.rizzog99.personalfinancetracker.ui.components.categoryIconFor

/**
 * Lets the user state, once, which of their own categories each kind of purchase belongs to.
 *
 * Both the receipt scanner and the CSV importer consult this before falling back to matching a
 * keyword against category *names* — the only tier that works for a category the user invented or
 * renamed to something no synonym table reaches.
 */
@Composable
fun ScanCategoriesRoute(onBack: () -> Unit) {
    val application = LocalContext.current.applicationContext as PersonalFinanceApplication
    val viewModel: ScanCategoriesViewModel = viewModel(
        factory = ScanCategoriesViewModel.factory(
            application.categoryRepository,
            application.receiptCategoryMapRepository,
        ),
    )
    val state by viewModel.uiState.collectAsState()
    ScanCategoriesScreen(
        categories = state.categories,
        pairings = state.pairings,
        onPair = viewModel::pair,
        onDismiss = onBack,
    )
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ScanCategoriesScreen(
    categories: List<FinanceCategory>,
    pairings: Map<String, String>,
    onPair: (ReceiptCategoryConcept, String?) -> Unit,
    onDismiss: () -> Unit,
) {
    Scaffold(
        modifier = Modifier.fillMaxSize(),
        topBar = {
            TopAppBar(
                title = { Text(stringResource(R.string.scan_categories_title)) },
                navigationIcon = {
                    IconButton(onClick = onDismiss) {
                        Icon(
                            Icons.AutoMirrored.Outlined.ArrowBack,
                            contentDescription = stringResource(R.string.back),
                        )
                    }
                },
                colors = TopAppBarDefaults.topAppBarColors(containerColor = MaterialTheme.colorScheme.surface),
            )
        },
        containerColor = MaterialTheme.colorScheme.surface,
        contentColor = MaterialTheme.colorScheme.onSurface,
    ) { innerPadding ->
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(innerPadding)
                .verticalScroll(rememberScrollState())
                .padding(horizontal = 24.dp, vertical = 8.dp)
                .padding(bottom = 24.dp),
            verticalArrangement = Arrangement.spacedBy(4.dp),
        ) {
            Text(
                text = stringResource(R.string.scan_categories_description),
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.padding(bottom = 8.dp),
            )
            ReceiptCategoryConcept.entries.forEachIndexed { index, concept ->
                if (index > 0) HorizontalDivider(color = MaterialTheme.colorScheme.outlineVariant)
                ConceptRow(
                    concept = concept,
                    categories = categories,
                    paired = categories.firstOrNull { it.id == pairings[concept.key] },
                    onPair = { onPair(concept, it) },
                )
            }
        }
    }
}

@Composable
private fun ConceptRow(
    concept: ReceiptCategoryConcept,
    categories: List<FinanceCategory>,
    paired: FinanceCategory?,
    onPair: (String?) -> Unit,
) {
    var expanded by remember { mutableStateOf(false) }
    val accent = categoryColor(paired?.colorToken ?: "categoryGray")
    val title = stringResource(concept.titleRes)
    val automatic = stringResource(R.string.scan_categories_automatic)
    Row(
        modifier = Modifier
            .fillMaxWidth()
            // The whole row is the target, so it clears 48 dp even when the label wraps.
            .clickable(role = Role.Button, enabled = categories.isNotEmpty()) { expanded = true }
            .padding(vertical = 12.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Box(
            modifier = Modifier
                .size(40.dp)
                .clip(CircleShape)
                .background(accent.copy(alpha = 0.15f)),
            contentAlignment = Alignment.Center,
        ) {
            Icon(
                categoryIconFor(if (paired != null) paired.iconToken else concept.iconToken),
                contentDescription = null,
                tint = accent,
                modifier = Modifier.size(20.dp),
            )
        }
        Text(
            text = title,
            modifier = Modifier.weight(1f),
            fontWeight = FontWeight.Bold,
            style = MaterialTheme.typography.bodyLarge,
        )
        Box {
            Row(
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(4.dp),
                // One spoken phrase instead of "Fuel" then a loose "Automatic" with no subject.
                modifier = Modifier.semantics {
                    contentDescription = "$title: ${paired?.name ?: automatic}"
                },
            ) {
                Text(
                    text = paired?.name ?: automatic,
                    style = MaterialTheme.typography.bodyMedium,
                    color = if (paired != null) {
                        MaterialTheme.colorScheme.primary
                    } else {
                        MaterialTheme.colorScheme.onSurfaceVariant
                    },
                    // Long Italian category names must truncate rather than shove the caret off
                    // screen, but the box still grows with font scale.
                    maxLines = 1,
                    modifier = Modifier.widthIn(max = 160.dp),
                )
                Icon(
                    Icons.Outlined.UnfoldMore,
                    contentDescription = null,
                    modifier = Modifier.size(16.dp),
                    tint = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
            DropdownMenu(expanded = expanded, onDismissRequest = { expanded = false }) {
                DropdownMenuItem(
                    text = { Text(automatic) },
                    onClick = { onPair(null); expanded = false },
                )
                categories.forEach { category ->
                    DropdownMenuItem(
                        text = { Text(category.name) },
                        leadingIcon = {
                            Icon(
                                categoryIconFor(category.iconToken),
                                contentDescription = null,
                                tint = categoryColor(category.colorToken),
                                modifier = Modifier.size(20.dp),
                            )
                        },
                        onClick = { onPair(category.id); expanded = false },
                    )
                }
            }
        }
    }
}
