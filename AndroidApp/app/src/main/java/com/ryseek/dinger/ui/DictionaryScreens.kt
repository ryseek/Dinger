package com.ryseek.dinger.ui

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.AddCard
import androidx.compose.material.icons.filled.Search
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.Checkbox
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.ExposedDropdownMenuBox
import androidx.compose.material3.ExposedDropdownMenuDefaults
import androidx.compose.material3.FilterChip
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.ListItem
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.font.FontStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.ryseek.dinger.core.ExampleSentence
import com.ryseek.dinger.core.SenseHit
import com.ryseek.dinger.core.Term

@Composable
fun DictionaryScreen(state: AppUiState, viewModel: DingerViewModel, onEntry: (SenseHit) -> Unit) {
    LazyColumn(Modifier.fillMaxSize().testTag("dictionary-screen")) {
        item {
            Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
                Text("Dictionary", style = MaterialTheme.typography.headlineMedium, fontWeight = FontWeight.Bold)
                OutlinedTextField(
                    value = state.query,
                    onValueChange = viewModel::setQuery,
                    modifier = Modifier.fillMaxWidth().testTag("search-field"),
                    label = { Text("German or English") },
                    leadingIcon = { Icon(Icons.Default.Search, null) },
                    singleLine = true,
                )
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    DirectionChip("auto", "Auto", state.searchDirection, viewModel::setSearchDirection)
                    DirectionChip("sourceToTarget", "DE → EN", state.searchDirection, viewModel::setSearchDirection)
                    DirectionChip("targetToSource", "EN → DE", state.searchDirection, viewModel::setSearchDirection)
                }
            }
        }
        if (state.searching) item { CircularProgressIndicator(Modifier.padding(horizontal = 16.dp)) }
        if (state.query.isNotBlank()) {
            if (!state.searching && state.searchResults.isEmpty()) {
                item { EmptyMessage("No dictionary entries found.") }
            }
            items(state.searchResults, key = { "result-${it.senseId}-${it.matchedTermId}" }) { hit ->
                SenseHitRow(hit, onClick = { onEntry(hit) })
                HorizontalDivider()
            }
        } else {
            if (state.recentOpened.isNotEmpty()) {
                item { SectionHeader("Recently opened") }
                items(state.recentOpened.take(8), key = { "opened-${it.senseId}-${it.matchedTermId}" }) { hit ->
                    SenseHitRow(hit, onClick = { onEntry(hit) })
                }
            }
            if (state.recentSearches.isNotEmpty()) {
                item { SectionHeader("Recent searches") }
                items(state.recentSearches.take(12), key = { "history-${it.id}" }) { item ->
                    ListItem(
                        headlineContent = { Text(item.query) },
                        supportingContent = { Text(directionLabel(item.direction)) },
                        modifier = Modifier.clickable { viewModel.useHistory(item) },
                    )
                }
            }
            if (state.recentOpened.isEmpty() && state.recentSearches.isEmpty()) {
                item { EmptyMessage("Search the German–English dictionary to get started.") }
            }
        }
    }
}

@Composable
private fun DirectionChip(value: String, label: String, selected: String, onSelect: (String) -> Unit) {
    FilterChip(selected = selected == value, onClick = { onSelect(value) }, label = { Text(label) })
}

@Composable
fun SenseHitRow(hit: SenseHit, onClick: () -> Unit, modifier: Modifier = Modifier) {
    val forward = hit.matchedLanguageCode == "de"
    val primary = (if (forward) hit.sourceTerms else hit.targetTerms).surfaces()
    val secondary = (if (forward) hit.targetTerms else hit.sourceTerms).surfaces()
    ListItem(
        headlineContent = { Text(primary.ifBlank { "—" }, fontWeight = FontWeight.SemiBold) },
        supportingContent = {
            Column {
                Text(secondary.ifBlank { "—" })
                val detail = listOfNotNull(hit.domain.takeIf { it.isNotEmpty() }?.joinToString(), hit.context)
                    .joinToString(" · ")
                if (detail.isNotBlank()) Text(detail, style = MaterialTheme.typography.bodySmall)
            }
        },
        modifier = modifier.fillMaxWidth().clickable(onClick = onClick),
    )
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun EntryScreen(state: AppUiState, viewModel: DingerViewModel, onBack: () -> Unit) {
    val entry = state.entry
    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("Dictionary entry") },
                navigationIcon = {
                    IconButton(onClick = onBack) { Icon(Icons.AutoMirrored.Filled.ArrowBack, "Back") }
                },
            )
        }
    ) { padding ->
        if (entry.loading || entry.details == null) {
            Column(
                Modifier.fillMaxSize().padding(padding),
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.Center,
            ) { CircularProgressIndicator() }
            return@Scaffold
        }
        val details = entry.details
        LazyColumn(
            Modifier.fillMaxSize().padding(padding).testTag("entry-screen"),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            item {
                TermSelection(
                    title = "German",
                    terms = details.hit.sourceTerms,
                    selected = entry.selectedSourceTermIds,
                    onToggle = { viewModel.toggleEntryTerm(true, it) },
                )
            }
            item {
                TermSelection(
                    title = "English",
                    terms = details.hit.targetTerms,
                    selected = entry.selectedTargetTermIds,
                    onToggle = { viewModel.toggleEntryTerm(false, it) },
                )
            }
            if (!details.hit.context.isNullOrBlank() || details.hit.domain.isNotEmpty()) {
                item {
                    Card(Modifier.fillMaxWidth().padding(horizontal = 16.dp)) {
                        Text(
                            listOfNotNull(details.hit.domain.joinToString().ifBlank { null }, details.hit.context)
                                .joinToString(" · "),
                            Modifier.padding(16.dp),
                            fontStyle = FontStyle.Italic,
                        )
                    }
                }
            }
            item { DeckPicker(state = entry, decks = details.decks, onSelect = viewModel::selectEntryDeck) }
            item {
                Button(
                    onClick = viewModel::saveEntryCard,
                    enabled = entry.selectedDeckId != null && entry.selectedSourceTermIds.isNotEmpty() &&
                        entry.selectedTargetTermIds.isNotEmpty() && !state.busy,
                    modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp).testTag("save-card"),
                ) {
                    Icon(Icons.Default.AddCard, null)
                    Spacer(Modifier.width(8.dp))
                    Text("Save as card")
                }
            }
            if (details.examples.isNotEmpty()) {
                item { SectionHeader("Examples") }
                items(details.examples, key = ExampleSentence::id) { ExampleRow(it) }
            }
            item { Spacer(Modifier.height(24.dp)) }
        }
    }
}

@Composable
private fun TermSelection(title: String, terms: List<Term>, selected: Set<Long>, onToggle: (Long) -> Unit) {
    Column(Modifier.padding(horizontal = 16.dp)) {
        Text(title, style = MaterialTheme.typography.titleMedium)
        terms.forEach { term ->
            Row(
                Modifier.fillMaxWidth().clickable { onToggle(term.termId) },
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Checkbox(checked = term.termId in selected, onCheckedChange = { onToggle(term.termId) })
                Column {
                    Text(term.surface, fontWeight = FontWeight.SemiBold)
                    val attributes = listOfNotNull(term.pos, term.gender).joinToString(" · ")
                    if (attributes.isNotBlank()) Text(attributes, style = MaterialTheme.typography.bodySmall)
                }
            }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun DeckPicker(state: EntryUiState, decks: List<com.ryseek.dinger.core.Deck>, onSelect: (Long) -> Unit) {
    var expanded by remember { mutableStateOf(false) }
    val selected = decks.firstOrNull { it.id == state.selectedDeckId }
    ExposedDropdownMenuBox(
        expanded = expanded,
        onExpandedChange = { expanded = it },
        modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp),
    ) {
        OutlinedTextField(
            value = selected?.name ?: "No deck available",
            onValueChange = {},
            readOnly = true,
            label = { Text("Deck") },
            trailingIcon = { ExposedDropdownMenuDefaults.TrailingIcon(expanded) },
            modifier = Modifier.menuAnchor().fillMaxWidth(),
        )
        ExposedDropdownMenu(expanded = expanded, onDismissRequest = { expanded = false }) {
            decks.forEach { deck ->
                DropdownMenuItem(text = { Text(deck.name) }, onClick = { onSelect(deck.id); expanded = false })
            }
        }
    }
}

@Composable
private fun ExampleRow(example: ExampleSentence) {
    Column(Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 6.dp)) {
        Text(example.germanText)
        Text(example.englishText, color = MaterialTheme.colorScheme.onSurfaceVariant)
    }
}

@Composable
fun SectionHeader(title: String) {
    Text(
        title,
        Modifier.fillMaxWidth().padding(start = 16.dp, end = 16.dp, top = 18.dp, bottom = 6.dp),
        style = MaterialTheme.typography.titleMedium,
        fontWeight = FontWeight.Bold,
    )
}

@Composable
fun EmptyMessage(message: String) {
    Text(
        message,
        Modifier.fillMaxWidth().padding(32.dp),
        color = MaterialTheme.colorScheme.onSurfaceVariant,
    )
}

private fun List<Term>.surfaces(): String = distinctBy { it.surface.lowercase() }.joinToString(" · ") { it.surface }
private fun directionLabel(direction: String) = when (direction) {
    "sourceToTarget" -> "German → English"
    "targetToSource" -> "English → German"
    else -> "Automatic direction"
}
