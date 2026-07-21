package com.ryseek.dinger.ui

import android.app.Application
import android.net.Uri
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import com.ryseek.dinger.core.*
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch

class DingerViewModel(application: Application) : AndroidViewModel(application) {
    private val repository = DingerRepository(application)
    private val mutableState = MutableStateFlow(AppUiState())
    val state: StateFlow<AppUiState> = mutableState.asStateFlow()
    private var searchJob: Job? = null
    private var replacementJob: Job? = null

    init {
        viewModelScope.launch {
            try {
                val payload = repository.initialize { message ->
                    mutableState.update { it.copy(startupMessage = message) }
                }
                applyBootstrap(payload)
            } catch (error: Throwable) {
                mutableState.update {
                    it.copy(initializing = false, error = error.message ?: "Could not start Dinger")
                }
            }
        }
    }

    fun dismissMessage() = mutableState.update { it.copy(error = null, notice = null) }

    fun refresh() = launchBusy {
        applyBootstrap(repository.bootstrap())
    }

    fun setQuery(query: String) {
        mutableState.update { it.copy(query = query) }
        scheduleSearch()
    }

    fun setSearchDirection(direction: String) {
        mutableState.update { it.copy(searchDirection = direction) }
        scheduleSearch(delayMs = 0)
    }

    fun useHistory(item: SearchHistory) {
        mutableState.update { it.copy(query = item.query, searchDirection = item.direction) }
        scheduleSearch(delayMs = 0)
    }

    private fun scheduleSearch(delayMs: Long = 180) {
        searchJob?.cancel()
        val snapshot = mutableState.value
        if (snapshot.query.isBlank()) {
            mutableState.update { it.copy(searchResults = emptyList(), searching = false) }
            return
        }
        searchJob = viewModelScope.launch {
            delay(delayMs)
            mutableState.update { it.copy(searching = true) }
            try {
                val results = repository.search(mutableState.value.query.trim(), mutableState.value.searchDirection)
                val history = repository.history()
                mutableState.update {
                    it.copy(
                        searchResults = results,
                        searching = false,
                        recentSearches = history.recentSearches,
                        recentOpened = history.recentOpened,
                    )
                }
            } catch (error: Throwable) {
                mutableState.update { it.copy(searching = false, error = error.message) }
            }
        }
    }

    fun openEntry(hit: SenseHit) {
        mutableState.update { it.copy(entry = EntryUiState(loading = true)) }
        viewModelScope.launch {
            try {
                val details = repository.openSense(hit)
                val source = details.hit.sourceTerms.firstOrNull()?.termId?.let { setOf(it) } ?: emptySet()
                val target = details.hit.targetTerms.firstOrNull()?.termId?.let { setOf(it) } ?: emptySet()
                mutableState.update {
                    it.copy(
                        entry = EntryUiState(
                            details = details,
                            selectedSourceTermIds = source,
                            selectedTargetTermIds = target,
                            selectedDeckId = details.decks.firstOrNull()?.id,
                        ),
                        recentOpened = listOf(details.hit) + it.recentOpened.filterNot { old -> old.senseId == hit.senseId },
                    )
                }
            } catch (error: Throwable) {
                mutableState.update { it.copy(entry = EntryUiState(), error = error.message) }
            }
        }
    }

    fun toggleEntryTerm(source: Boolean, termId: Long) {
        val entry = mutableState.value.entry
        val current = if (source) entry.selectedSourceTermIds else entry.selectedTargetTermIds
        val next = if (termId in current && current.size > 1) current - termId else current + termId
        mutableState.update {
            it.copy(entry = if (source) entry.copy(selectedSourceTermIds = next) else entry.copy(selectedTargetTermIds = next))
        }
        viewModelScope.launch {
            try {
                val updated = repository.examples(
                    mutableState.value.entry.selectedSourceTermIds + mutableState.value.entry.selectedTargetTermIds
                )
                mutableState.update { state ->
                    val details = state.entry.details ?: return@update state
                    state.copy(entry = state.entry.copy(details = details.copy(examples = updated)))
                }
            } catch (error: Throwable) {
                mutableState.update { it.copy(error = error.message) }
            }
        }
    }

    fun selectEntryDeck(deckId: Long) = mutableState.update {
        it.copy(entry = it.entry.copy(selectedDeckId = deckId))
    }

    fun saveEntryCard() = launchBusy {
        val entry = mutableState.value.entry
        val details = entry.details ?: return@launchBusy
        val deckId = entry.selectedDeckId ?: error("Choose a deck")
        val result = repository.saveCard(
            details.hit,
            deckId,
            entry.selectedSourceTermIds,
            entry.selectedTargetTermIds,
        )
        val message = when {
            result.isNew -> "Card added."
            result.didUpdate -> "Card selection updated."
            else -> "Card already exists in this deck."
        }
        mutableState.update { it.copy(notice = message) }
        refreshDataOnly()
    }

    fun createDeck(name: String) = launchBusy {
        repository.createDeck(name.trim())
        refreshDataOnly()
    }

    fun renameDeck(deckId: Long, name: String) = launchBusy {
        repository.renameDeck(deckId, name.trim())
        refreshDataOnly()
        if (mutableState.value.deckDetail?.deck?.id == deckId) openDeck(deckId)
    }

    fun deleteDeck(deckId: Long) = launchBusy {
        repository.deleteDeck(deckId)
        mutableState.update { it.copy(deckDetail = null, notice = "Deck deleted.") }
        refreshDataOnly()
    }

    fun openDeck(deckId: Long) {
        mutableState.update { it.copy(deckDetail = null, busy = true) }
        viewModelScope.launch {
            try {
                val detail = repository.deckDetail(deckId)
                mutableState.update { it.copy(deckDetail = detail, busy = false) }
            } catch (error: Throwable) {
                mutableState.update { it.copy(busy = false, error = error.message) }
            }
        }
    }

    fun openCard(row: CardRow) {
        mutableState.update { it.copy(card = CardUiState(row)) }
        viewModelScope.launch {
            try {
                val example = repository.cardExample(row.id)
                mutableState.update { state -> state.copy(card = state.card?.copy(example = example)) }
            } catch (error: Throwable) {
                mutableState.update { it.copy(error = error.message) }
            }
        }
    }

    fun suspendCard(row: CardRow, suspended: Boolean) = launchBusy {
        repository.suspendCard(row.id, suspended)
        mutableState.value.deckDetail?.deck?.id?.let { deckId ->
            mutableState.update { it.copy(deckDetail = repository.deckDetail(deckId)) }
        }
        mutableState.update { state -> state.copy(card = state.card?.copy(row = row.copy(suspended = suspended))) }
    }

    fun invertCard(row: CardRow) = launchBusy {
        repository.invertCard(row.id)
        mutableState.update {
            it.copy(deckDetail = repository.deckDetail(row.card.deckId), card = null, notice = "Card direction swapped.")
        }
    }

    fun deleteCard(row: CardRow) = launchBusy {
        repository.deleteCard(row.id)
        mutableState.update {
            it.copy(deckDetail = repository.deckDetail(row.card.deckId), card = null, notice = "Card deleted.")
        }
    }

    fun exportDeck(deckId: Long) = launchBusy {
        mutableState.update { it.copy(exportedFile = repository.exportDeck(deckId)) }
    }

    fun exportAll() = launchBusy {
        mutableState.update { it.copy(exportedFile = repository.exportAll()) }
    }

    fun clearExport() = mutableState.update { it.copy(exportedFile = null) }

    fun writeExport(uri: Uri) {
        val file = mutableState.value.exportedFile ?: return
        viewModelScope.launch {
            try {
                val output = getApplication<Application>().contentResolver.openOutputStream(uri)
                    ?: error("Could not open the selected destination")
                output.use { it.write(file.bytes) }
                mutableState.update { it.copy(exportedFile = null, notice = "Export saved.") }
            } catch (error: Throwable) {
                mutableState.update { it.copy(exportedFile = null, error = error.message) }
            }
        }
    }

    fun importDecks(uri: Uri) = launchBusy {
        val bytes = getApplication<Application>().contentResolver.openInputStream(uri)?.use { it.readBytes() }
            ?: error("Could not read that file")
        repository.importDecks(bytes)
        mutableState.update { it.copy(notice = "Deck import completed.") }
        refreshDataOnly()
    }

    fun updateQuizConfig(transform: (QuizConfig) -> QuizConfig) = mutableState.update {
        it.copy(quizConfig = transform(it.quizConfig))
    }

    fun startQuiz() {
        mutableState.update { it.copy(quizLoading = true, quizState = null, quizRevealedGrade = null) }
        viewModelScope.launch {
            try {
                val quiz = repository.startQuiz(mutableState.value.quizConfig)
                mutableState.update { it.copy(quizState = quiz, quizLoading = false) }
            } catch (error: Throwable) {
                mutableState.update { it.copy(quizLoading = false, error = error.message) }
            }
        }
    }

    fun setTypedAnswer(answer: String) = mutableState.update { it.copy(typedAnswer = answer) }

    fun revealFlashcard() = mutableState.update { it.copy(quizRevealedGrade = -1) }

    fun submitTyped() = launchQuiz {
        val grade = repository.typedGrade(mutableState.value.typedAnswer)
        mutableState.update { it.copy(quizRevealedGrade = grade) }
    }

    fun submitChoice(index: Int) = launchQuiz {
        val grade = repository.choiceGrade(index)
        mutableState.update { it.copy(quizRevealedGrade = grade) }
    }

    fun gradeQuiz(grade: Int) = launchQuiz {
        val quiz = repository.gradeQuiz(grade)
        mutableState.update {
            it.copy(quizState = quiz, quizRevealedGrade = null, typedAnswer = "", replacementResults = emptyList())
        }
        if (quiz.completed) refreshDataOnly()
    }

    fun setReplacementQuery(query: String) {
        mutableState.update { it.copy(replacementQuery = query) }
        replacementJob?.cancel()
        if (query.isBlank()) {
            mutableState.update { it.copy(replacementResults = emptyList()) }
            return
        }
        replacementJob = viewModelScope.launch {
            delay(180)
            try {
                val hits = repository.search(query, "auto")
                mutableState.update { it.copy(replacementResults = hits) }
            } catch (error: Throwable) {
                mutableState.update { it.copy(error = error.message) }
            }
        }
    }

    fun replaceQuizCard(hit: SenseHit) = launchQuiz {
        val quiz = repository.replaceQuizCard(hit)
        mutableState.update {
            it.copy(quizState = quiz, replacementQuery = "", replacementResults = emptyList(), notice = "Card meaning replaced.")
        }
    }

    fun cancelQuiz() = launchQuiz {
        repository.cancelQuiz()
        mutableState.update { it.copy(quizState = null, quizRevealedGrade = null) }
    }

    private suspend fun refreshDataOnly() {
        val payload = repository.bootstrap()
        applyBootstrap(payload)
    }

    private fun applyBootstrap(payload: BootstrapPayload) {
        mutableState.update {
            it.copy(
                initializing = false,
                busy = false,
                decks = payload.decks,
                activity = payload.activity,
                recentSearches = payload.recentSearches,
                recentOpened = payload.recentOpened,
                error = null,
            )
        }
    }

    private fun launchBusy(block: suspend () -> Unit) {
        viewModelScope.launch {
            mutableState.update { it.copy(busy = true, error = null) }
            try {
                block()
                mutableState.update { it.copy(busy = false) }
            } catch (error: Throwable) {
                mutableState.update { it.copy(busy = false, error = error.message ?: "Operation failed") }
            }
        }
    }

    private fun launchQuiz(block: suspend () -> Unit) {
        viewModelScope.launch {
            mutableState.update { it.copy(quizLoading = true, error = null) }
            try {
                block()
                mutableState.update { it.copy(quizLoading = false) }
            } catch (error: Throwable) {
                mutableState.update { it.copy(quizLoading = false, error = error.message) }
            }
        }
    }
}
