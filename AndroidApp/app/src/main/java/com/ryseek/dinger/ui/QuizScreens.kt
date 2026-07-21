package com.ryseek.dinger.ui

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
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
import androidx.compose.material.icons.filled.Build
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.ExposedDropdownMenuBox
import androidx.compose.material3.ExposedDropdownMenuDefaults
import androidx.compose.material3.FilledTonalButton
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Slider
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
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.ryseek.dinger.core.Deck
import com.ryseek.dinger.core.QuizConfig
import com.ryseek.dinger.core.QuizProgress
import com.ryseek.dinger.core.QuizQuestion

private val quizModes = listOf(
    "mixed" to "Mixed",
    "flashcard" to "Flashcard",
    "multipleChoice" to "Multiple choice",
    "typing" to "Typing",
)
private val quizDirections = listOf(
    "native" to "Card default",
    "sourceToTarget" to "German → English",
    "targetToSource" to "English → German",
    "mixed" to "Both (random)",
)

@Composable
fun QuizSetupScreen(state: AppUiState, viewModel: DingerViewModel) {
    val config = state.quizConfig
    LazyColumn(
        Modifier.fillMaxSize().padding(16.dp).testTag("quiz-setup"),
        verticalArrangement = Arrangement.spacedBy(16.dp),
    ) {
        item { Text("Quiz", style = MaterialTheme.typography.headlineMedium, fontWeight = FontWeight.Bold) }
        item {
            OptionPicker(
                label = "Deck",
                value = config.deckId,
                options = listOf(null to "All decks") + state.decks.map { it.id to it.name },
            ) { selected -> viewModel.updateQuizConfig { it.copy(deckId = selected) } }
        }
        item {
            OptionPicker("Mode", config.mode, quizModes) { mode ->
                viewModel.updateQuizConfig { it.copy(mode = mode) }
            }
        }
        item {
            OptionPicker("Prompt side", config.direction, quizDirections) { direction ->
                viewModel.updateQuizConfig { it.copy(direction = direction) }
            }
        }
        item {
            Column {
                Text("Questions: ${config.maxQuestions}", style = MaterialTheme.typography.titleSmall)
                Slider(
                    value = config.maxQuestions.toFloat(),
                    onValueChange = { value ->
                        val rounded = (value.toInt() / 5 * 5).coerceIn(5, 50)
                        viewModel.updateQuizConfig { it.copy(maxQuestions = rounded) }
                    },
                    valueRange = 5f..50f,
                    steps = 8,
                )
            }
        }
        item {
            QuizSwitch("Include new cards", config.includeNew, enabled = !config.practiceMode) {
                viewModel.updateQuizConfig { old -> old.copy(includeNew = it) }
            }
        }
        item {
            QuizSwitch("Show examples during question", config.showExamples) {
                viewModel.updateQuizConfig { old -> old.copy(showExamples = it) }
            }
        }
        item {
            QuizSwitch("Practice (ignore due dates)", config.practiceMode) {
                viewModel.updateQuizConfig { old -> old.copy(practiceMode = it, includeNew = old.includeNew || it) }
            }
        }
        item {
            Text(
                if (config.practiceMode) {
                    "All non-suspended cards can appear. Answers still update the spaced-repetition schedule."
                } else {
                    "Only cards whose interval has elapsed are drawn."
                },
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                style = MaterialTheme.typography.bodySmall,
            )
        }
        item {
            Button(
                onClick = viewModel::startQuiz,
                enabled = state.decks.isNotEmpty() && !state.quizLoading,
                modifier = Modifier.fillMaxWidth().testTag("start-quiz"),
            ) {
                Icon(Icons.Default.PlayArrow, null)
                Spacer(Modifier.width(8.dp))
                Text("Start quiz")
            }
        }
        if (state.decks.isEmpty()) item { EmptyMessage("Add a dictionary card before starting a quiz.") }
        item {
            Text(
                "Dictionary: TU Chemnitz / BEOLINGUS (GPL v2+). Examples: Tatoeba (CC BY 2.0 FR).\nAndroid prototype · made by ryseek",
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                style = MaterialTheme.typography.labelSmall,
            )
        }
    }
}

@Composable
private fun QuizSwitch(label: String, checked: Boolean, enabled: Boolean = true, onChange: (Boolean) -> Unit) {
    Row(
        Modifier.fillMaxWidth().clickable(enabled = enabled) { onChange(!checked) },
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(label, Modifier.weight(1f), color = if (enabled) MaterialTheme.colorScheme.onSurface else MaterialTheme.colorScheme.onSurfaceVariant)
        Switch(checked = checked, onCheckedChange = onChange, enabled = enabled)
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun <T> OptionPicker(label: String, value: T, options: List<Pair<T, String>>, onSelect: (T) -> Unit) {
    var expanded by remember { mutableStateOf(false) }
    ExposedDropdownMenuBox(expanded = expanded, onExpandedChange = { expanded = it }) {
        OutlinedTextField(
            value = options.firstOrNull { it.first == value }?.second ?: "Choose",
            onValueChange = {},
            readOnly = true,
            label = { Text(label) },
            trailingIcon = { ExposedDropdownMenuDefaults.TrailingIcon(expanded) },
            modifier = Modifier.menuAnchor().fillMaxWidth(),
        )
        ExposedDropdownMenu(expanded = expanded, onDismissRequest = { expanded = false }) {
            options.forEach { (option, title) ->
                DropdownMenuItem(
                    text = { Text(title) },
                    onClick = { onSelect(option); expanded = false },
                )
            }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun QuizPlayScreen(state: AppUiState, viewModel: DingerViewModel, onClose: () -> Unit) {
    val quiz = state.quizState
    val deckName = state.quizConfig.deckId?.let { id -> state.decks.firstOrNull { it.id == id }?.name } ?: "All decks"
    var fixing by remember { mutableStateOf(false) }
    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text(deckName) },
                navigationIcon = { IconButton(onClick = onClose) { Icon(Icons.Default.Close, "Close quiz") } },
            )
        }
    ) { padding ->
        if (quiz == null) {
            Box(Modifier.fillMaxSize().padding(padding), contentAlignment = Alignment.Center) { CircularProgressIndicator() }
            return@Scaffold
        }
        Column(
            Modifier.fillMaxSize().padding(padding).padding(16.dp).testTag("quiz-play"),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(16.dp),
        ) {
            QuizProgressBar(quiz.progress)
            when {
                quiz.completed && quiz.progress.total == 0 -> EmptyQuiz(onClose)
                quiz.completed -> QuizComplete(quiz.progress, onClose)
                quiz.question != null -> QuestionContent(
                    question = quiz.question,
                    config = state.quizConfig,
                    typedAnswer = state.typedAnswer,
                    revealedGrade = state.quizRevealedGrade,
                    loading = state.quizLoading,
                    onTyped = viewModel::setTypedAnswer,
                    onSubmitTyped = viewModel::submitTyped,
                    onChoice = viewModel::submitChoice,
                    onReveal = viewModel::revealFlashcard,
                    onGrade = viewModel::gradeQuiz,
                    onFix = { fixing = true },
                )
            }
        }
    }
    if (fixing) FixCardDialog(state, viewModel) { fixing = false }
}

@Composable
private fun QuizProgressBar(progress: QuizProgress) {
    Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
        LinearProgressIndicator(
            progress = { progress.answered.toFloat() / progress.total.coerceAtLeast(1) },
            modifier = Modifier.weight(1f),
        )
        Spacer(Modifier.width(12.dp))
        Text("${progress.answered}/${progress.total}")
    }
}

@Composable
private fun ColumnScope.QuestionContent(
    question: QuizQuestion,
    config: QuizConfig,
    typedAnswer: String,
    revealedGrade: Int?,
    loading: Boolean,
    onTyped: (String) -> Unit,
    onSubmitTyped: () -> Unit,
    onChoice: (Int) -> Unit,
    onReveal: () -> Unit,
    onGrade: (Int) -> Unit,
    onFix: () -> Unit,
) {
    Spacer(Modifier.height(8.dp))
    Text(question.front, style = MaterialTheme.typography.headlineLarge, textAlign = TextAlign.Center)
    if (config.showExamples && revealedGrade == null) {
        question.frontExample?.let { Text(it, textAlign = TextAlign.Center, color = MaterialTheme.colorScheme.onSurfaceVariant) }
    }
    Spacer(Modifier.height(8.dp))
    if (revealedGrade == null) {
        when (question.kind) {
            "flashcard" -> Button(onClick = onReveal, enabled = !loading) { Text("Show answer") }
            "typing" -> {
                OutlinedTextField(
                    value = typedAnswer,
                    onValueChange = onTyped,
                    label = { Text("Translation") },
                    singleLine = true,
                    modifier = Modifier.fillMaxWidth().testTag("typed-answer"),
                )
                Button(onClick = onSubmitTyped, enabled = typedAnswer.isNotBlank() && !loading) { Text("Check") }
            }
            "multipleChoice" -> question.choices.forEachIndexed { index, choice ->
                OutlinedButton(
                    onClick = { onChoice(index) },
                    enabled = !loading,
                    modifier = Modifier.fillMaxWidth().testTag("choice-$index"),
                ) { Text(choice, textAlign = TextAlign.Center) }
            }
        }
    } else {
        Card(Modifier.fillMaxWidth()) {
            Column(
                Modifier.fillMaxWidth().padding(20.dp),
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.spacedBy(10.dp),
            ) {
                question.displayFronts.forEach { Text(it, color = MaterialTheme.colorScheme.onSurfaceVariant) }
                HorizontalDivider()
                question.displayAnswers.forEach { Text(it, style = MaterialTheme.typography.titleLarge) }
                question.backExample?.let { Text(it, textAlign = TextAlign.Center, color = MaterialTheme.colorScheme.onSurfaceVariant) }
                if (revealedGrade >= 0) {
                    Text(
                        when (revealedGrade) { 0 -> "Incorrect"; 1 -> "Close"; else -> "Correct" },
                        color = if (revealedGrade == 0) MaterialTheme.colorScheme.error else MaterialTheme.colorScheme.primary,
                        fontWeight = FontWeight.Bold,
                    )
                }
                TextButton(onClick = onFix) { Icon(Icons.Default.Build, null); Spacer(Modifier.width(6.dp)); Text("Fix card") }
            }
        }
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            GradeButton("Again", 0, onGrade, Modifier.weight(1f), enabled = !loading)
            GradeButton("Hard", 1, onGrade, Modifier.weight(1f), enabled = !loading)
            GradeButton("Good", 2, onGrade, Modifier.weight(1f), enabled = !loading && revealedGrade != 0)
            GradeButton("Easy", 3, onGrade, Modifier.weight(1f), enabled = !loading && revealedGrade != 0)
        }
    }
    if (loading) CircularProgressIndicator()
}

@Composable
private fun GradeButton(label: String, grade: Int, onGrade: (Int) -> Unit, modifier: Modifier, enabled: Boolean) {
    FilledTonalButton(onClick = { onGrade(grade) }, modifier = modifier, enabled = enabled) { Text(label) }
}

@Composable
private fun ColumnScope.EmptyQuiz(onClose: () -> Unit) {
    Spacer(Modifier.weight(1f))
    Text("No cards due", style = MaterialTheme.typography.headlineSmall)
    Text("Enable Practice to review cards before they are due.", textAlign = TextAlign.Center)
    Button(onClick = onClose) { Text("Done") }
    Spacer(Modifier.weight(1f))
}

@Composable
private fun ColumnScope.QuizComplete(progress: QuizProgress, onClose: () -> Unit) {
    Spacer(Modifier.weight(1f))
    Text("Session complete", style = MaterialTheme.typography.headlineSmall)
    Text("${progress.correct} of ${progress.answered} correct")
    Text("Again ${progress.again} · Hard ${progress.hard} · Good ${progress.good} · Easy ${progress.easy}")
    Button(onClick = onClose) { Text("Done") }
    Spacer(Modifier.weight(1f))
}

@Composable
private fun FixCardDialog(state: AppUiState, viewModel: DingerViewModel, onDismiss: () -> Unit) {
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text("Replace card meaning") },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                OutlinedTextField(
                    value = state.replacementQuery,
                    onValueChange = viewModel::setReplacementQuery,
                    label = { Text("Search dictionary") },
                    singleLine = true,
                )
                LazyColumn(Modifier.height(260.dp)) {
                    items(state.replacementResults.take(20), key = { "replacement-${it.senseId}-${it.matchedTermId}" }) { hit ->
                        SenseHitRow(hit, onClick = { viewModel.replaceQuizCard(hit); onDismiss() })
                    }
                }
            }
        },
        confirmButton = {},
        dismissButton = { TextButton(onClick = onDismiss) { Text("Cancel") } },
    )
}
