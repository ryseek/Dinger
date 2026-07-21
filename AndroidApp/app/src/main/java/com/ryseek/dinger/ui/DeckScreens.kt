@file:OptIn(androidx.compose.material3.ExperimentalMaterial3Api::class)

package com.ryseek.dinger.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.FileDownload
import androidx.compose.material.icons.filled.FileUpload
import androidx.compose.material.icons.filled.MoreVert
import androidx.compose.material.icons.filled.SwapHoriz
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.FilledTonalButton
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.ListItem
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.ryseek.dinger.core.CardRow
import com.ryseek.dinger.core.Deck
import com.ryseek.dinger.core.StudyDay
import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter

private enum class DeckDialog { Create, Rename, Delete }

@Composable
fun DecksScreen(
    state: AppUiState,
    viewModel: DingerViewModel,
    onDeck: (Long) -> Unit,
    onImport: () -> Unit,
) {
    var dialog by remember { mutableStateOf<DeckDialog?>(null) }
    var selectedDeck by remember { mutableStateOf<Deck?>(null) }
    var text by remember { mutableStateOf("") }

    LazyColumn(Modifier.fillMaxSize().testTag("decks-screen")) {
        item {
            Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                Text("Cards", style = MaterialTheme.typography.headlineMedium, fontWeight = FontWeight.Bold)
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    Button(onClick = { text = ""; selectedDeck = null; dialog = DeckDialog.Create }) {
                        Icon(Icons.Default.Add, null); Spacer(Modifier.width(6.dp)); Text("New deck")
                    }
                    OutlinedButton(onClick = onImport) {
                        Icon(Icons.Default.FileUpload, null); Spacer(Modifier.width(6.dp)); Text("Import")
                    }
                    OutlinedButton(onClick = viewModel::exportAll, enabled = state.decks.isNotEmpty()) {
                        Icon(Icons.Default.FileDownload, null); Spacer(Modifier.width(6.dp)); Text("All")
                    }
                }
            }
        }
        item { ActivityPanel(state.activity.days, state.activity.currentStreak) }
        item { SectionHeader("Decks") }
        if (state.decks.isEmpty()) item { EmptyMessage("Create a deck, then save words from the dictionary.") }
        items(state.decks, key = Deck::id) { deck ->
            DeckListRow(
                deck = deck,
                onOpen = { onDeck(deck.id) },
                onRename = { selectedDeck = deck; text = deck.name; dialog = DeckDialog.Rename },
                onExport = { viewModel.exportDeck(deck.id) },
                onDelete = { selectedDeck = deck; dialog = DeckDialog.Delete },
            )
            HorizontalDivider()
        }
        item { Spacer(Modifier.height(24.dp)) }
    }

    when (dialog) {
        DeckDialog.Create, DeckDialog.Rename -> AlertDialog(
            onDismissRequest = { dialog = null },
            title = { Text(if (dialog == DeckDialog.Create) "New deck" else "Rename deck") },
            text = {
                OutlinedTextField(
                    value = text,
                    onValueChange = { text = it },
                    label = { Text("Name") },
                    singleLine = true,
                )
            },
            confirmButton = {
                TextButton(
                    enabled = text.isNotBlank(),
                    onClick = {
                        if (dialog == DeckDialog.Create) viewModel.createDeck(text)
                        else selectedDeck?.let { viewModel.renameDeck(it.id, text) }
                        dialog = null
                    },
                ) { Text("Save") }
            },
            dismissButton = { TextButton(onClick = { dialog = null }) { Text("Cancel") } },
        )
        DeckDialog.Delete -> AlertDialog(
            onDismissRequest = { dialog = null },
            title = { Text("Delete ${selectedDeck?.name}?") },
            text = { Text("Every card and review in this deck will be removed.") },
            confirmButton = {
                TextButton(onClick = { selectedDeck?.let { viewModel.deleteDeck(it.id) }; dialog = null }) {
                    Text("Delete", color = MaterialTheme.colorScheme.error)
                }
            },
            dismissButton = { TextButton(onClick = { dialog = null }) { Text("Cancel") } },
        )
        null -> Unit
    }
}

@Composable
private fun DeckListRow(
    deck: Deck,
    onOpen: () -> Unit,
    onRename: () -> Unit,
    onExport: () -> Unit,
    onDelete: () -> Unit,
) {
    var menu by remember { mutableStateOf(false) }
    ListItem(
        headlineContent = { Text(deck.name, fontWeight = FontWeight.SemiBold) },
        supportingContent = { Text("${deck.sourceLang.uppercase()} → ${deck.targetLang.uppercase()}") },
        trailingContent = {
            Box {
                IconButton(onClick = { menu = true }) { Icon(Icons.Default.MoreVert, "Deck actions") }
                DropdownMenu(expanded = menu, onDismissRequest = { menu = false }) {
                    DropdownMenuItem(text = { Text("Rename") }, onClick = { menu = false; onRename() })
                    DropdownMenuItem(text = { Text("Export") }, onClick = { menu = false; onExport() })
                    DropdownMenuItem(text = { Text("Delete") }, onClick = { menu = false; onDelete() })
                }
            }
        },
        modifier = Modifier.clickable(onClick = onOpen),
    )
}

@Composable
private fun ActivityPanel(days: List<StudyDay>, streak: Int) {
    var selected by remember(days) { mutableStateOf(days.lastOrNull()) }
    val visible = days.takeLast(14)
    Card(Modifier.fillMaxWidth().padding(horizontal = 16.dp)) {
        Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text("Study activity", style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.Bold)
                Spacer(Modifier.weight(1f))
                Text("🔥 $streak-day streak", color = MaterialTheme.colorScheme.primary)
            }
            if (visible.isEmpty()) {
                Text("No reviews yet.", color = MaterialTheme.colorScheme.onSurfaceVariant)
            } else {
                Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                    visible.forEach { day ->
                        val strength = (day.reviewCount.coerceAtMost(10) / 10f).coerceAtLeast(if (day.reviewCount > 0) .2f else .06f)
                        Box(
                            Modifier.size(18.dp)
                                .background(MaterialTheme.colorScheme.primary.copy(alpha = strength), RoundedCornerShape(4.dp))
                                .clickable { selected = day }
                        )
                    }
                }
                selected?.let { day ->
                    Text("${day.date.dateLabel()} · ${day.reviewCount} reviews · ${day.correctCount} correct")
                    day.words.take(5).forEach { word ->
                        Text("${word.front} → ${word.back}  ·  ${word.deckName}", style = MaterialTheme.typography.bodySmall)
                    }
                }
            }
        }
    }
}

@Composable
fun DeckDetailScreen(
    state: AppUiState,
    viewModel: DingerViewModel,
    onBack: () -> Unit,
    onCard: (CardRow) -> Unit,
) {
    val detail = state.deckDetail
    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text(detail?.deck?.name ?: "Deck") },
                navigationIcon = { IconButton(onClick = onBack) { Icon(Icons.AutoMirrored.Filled.ArrowBack, "Back") } },
                actions = {
                    detail?.let {
                        IconButton(onClick = { viewModel.exportDeck(it.deck.id) }) {
                            Icon(Icons.Default.FileDownload, "Export deck")
                        }
                    }
                },
            )
        }
    ) { padding ->
        if (detail == null) {
            Box(Modifier.fillMaxSize().padding(padding), contentAlignment = Alignment.Center) { CircularProgressIndicator() }
            return@Scaffold
        }
        LazyColumn(Modifier.fillMaxSize().padding(padding).testTag("deck-detail")) {
            item {
                val stats = detail.statistics
                Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
                    Text("Progress", style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.Bold)
                    LinearProgressIndicator(progress = { stats.reviewedFraction }, modifier = Modifier.fillMaxWidth())
                    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                        Stat("Cards", stats.totalCards)
                        Stat("Due", stats.dueCards)
                        Stat("Mature", stats.matureCards)
                        Stat("This week", stats.reviewsThisWeek)
                    }
                    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                        Stat("Reviewed", stats.reviewedCards)
                        Stat("Reviews", stats.totalReviews)
                        Stat("Learning", stats.learningCards)
                        Stat("Reps", stats.totalRepetitions)
                    }
                    Text("Retention ${(stats.retentionRate * 100).toInt()}% · ${stats.dueTomorrow} due tomorrow")
                }
            }
            if (detail.statistics.hardestCards.isNotEmpty()) {
                item { SectionHeader("Needs attention") }
                items(detail.statistics.hardestCards, key = { "hard-${it.id}" }) { card ->
                    ListItem(
                        headlineContent = { Text("${card.front} → ${card.back}") },
                        supportingContent = { Text("${card.againCount} again out of ${card.reviewCount} reviews") },
                    )
                }
            }
            item { SectionHeader("Cards (${detail.rows.size})") }
            if (detail.rows.isEmpty()) item { EmptyMessage("Save words from the dictionary to add cards.") }
            itemsIndexed(detail.rows, key = { _, row -> row.id }) { _, row ->
                CardListRow(row) { onCard(row) }
                HorizontalDivider()
            }
            item { Spacer(Modifier.height(24.dp)) }
        }
    }
}

@Composable
private fun Stat(label: String, value: Int) {
    Column(horizontalAlignment = Alignment.CenterHorizontally) {
        Text(value.toString(), style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.Bold)
        Text(label, style = MaterialTheme.typography.labelSmall)
    }
}

@Composable
private fun CardListRow(row: CardRow, onClick: () -> Unit) {
    ListItem(
        headlineContent = { Text(row.frontSurfaces.joinToString(" · "), maxLines = 1, overflow = TextOverflow.Ellipsis) },
        supportingContent = {
            Text(
                row.backSurfaces.joinToString(" · ") + " · " +
                    if (row.suspended) "Suspended" else if (row.repetitions == 0) "New" else "${row.intervalDays}d interval",
                maxLines = 2,
                overflow = TextOverflow.Ellipsis,
            )
        },
        modifier = Modifier.alpha(if (row.suspended) .55f else 1f).clickable(onClick = onClick),
    )
}

@Composable
fun CardScreen(state: AppUiState, viewModel: DingerViewModel, onBack: () -> Unit, onDeleted: () -> Unit) {
    val item = state.card
    var confirmDelete by remember { mutableStateOf(false) }
    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("Card") },
                navigationIcon = { IconButton(onClick = onBack) { Icon(Icons.AutoMirrored.Filled.ArrowBack, "Back") } },
            )
        }
    ) { padding ->
        if (item == null) {
            Box(Modifier.fillMaxSize().padding(padding), contentAlignment = Alignment.Center) { CircularProgressIndicator() }
            return@Scaffold
        }
        val row = item.row
        LazyColumn(
            Modifier.fillMaxSize().padding(padding).padding(16.dp).testTag("card-screen"),
            verticalArrangement = Arrangement.spacedBy(16.dp),
        ) {
            item {
                Card(Modifier.fillMaxWidth(), colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.primaryContainer)) {
                    Column(Modifier.padding(24.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                        Text(row.frontSurfaces.joinToString(" · "), style = MaterialTheme.typography.headlineSmall)
                        HorizontalDivider()
                        Text(row.backSurfaces.joinToString(" · "), style = MaterialTheme.typography.titleLarge)
                    }
                }
            }
            item {
                Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    Text("Reviews ${row.reviewCount} · Successful ${row.successfulReviewCount}")
                    Text("Repetitions ${row.repetitions} · Interval ${row.intervalDays} days")
                    row.dueAt?.let { Text("Due ${it.dateLabel()}") }
                }
            }
            item {
                Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                    Text("Suspended", modifier = Modifier.weight(1f))
                    Switch(checked = row.suspended, onCheckedChange = { viewModel.suspendCard(row, it) })
                }
            }
            item {
                FilledTonalButton(onClick = { viewModel.invertCard(row); onDeleted() }, modifier = Modifier.fillMaxWidth()) {
                    Icon(Icons.Default.SwapHoriz, null); Spacer(Modifier.width(8.dp)); Text("Swap direction")
                }
            }
            item {
                OutlinedButton(onClick = { confirmDelete = true }, modifier = Modifier.fillMaxWidth()) {
                    Text("Delete card", color = MaterialTheme.colorScheme.error)
                }
            }
            example(item.example)
        }
    }
    if (confirmDelete && item != null) {
        AlertDialog(
            onDismissRequest = { confirmDelete = false },
            title = { Text("Delete this card?") },
            text = { Text("Its review history will also be removed.") },
            confirmButton = {
                TextButton(onClick = { viewModel.deleteCard(item.row); confirmDelete = false; onDeleted() }) {
                    Text("Delete", color = MaterialTheme.colorScheme.error)
                }
            },
            dismissButton = { TextButton(onClick = { confirmDelete = false }) { Text("Cancel") } },
        )
    }
}

private fun androidx.compose.foundation.lazy.LazyListScope.example(example: com.ryseek.dinger.core.ExampleSentence?) {
    if (example == null) return
    item {
        Card(Modifier.fillMaxWidth()) {
            Column(Modifier.padding(16.dp)) {
                Text("Example", fontWeight = FontWeight.Bold)
                Text(example.germanText)
                Text(example.englishText, color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
        }
    }
}

private val dateFormatter = DateTimeFormatter.ofPattern("MMM d, yyyy")
private fun Long.dateLabel(): String = Instant.ofEpochMilli(this).atZone(ZoneId.systemDefault()).format(dateFormatter)
