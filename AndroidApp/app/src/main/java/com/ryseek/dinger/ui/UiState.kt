package com.ryseek.dinger.ui

import com.ryseek.dinger.core.*

data class EntryUiState(
    val details: EntryDetails? = null,
    val selectedSourceTermIds: Set<Long> = emptySet(),
    val selectedTargetTermIds: Set<Long> = emptySet(),
    val selectedDeckId: Long? = null,
    val loading: Boolean = false,
)

data class CardUiState(val row: CardRow, val example: ExampleSentence? = null)

data class AppUiState(
    val initializing: Boolean = true,
    val startupMessage: String = "Preparing Dinger…",
    val busy: Boolean = false,
    val error: String? = null,
    val notice: String? = null,
    val decks: List<Deck> = emptyList(),
    val activity: StudyActivity = StudyActivity(emptyList(), 0),
    val recentSearches: List<SearchHistory> = emptyList(),
    val recentOpened: List<SenseHit> = emptyList(),
    val query: String = "",
    val searchDirection: String = "auto",
    val searchResults: List<SenseHit> = emptyList(),
    val searching: Boolean = false,
    val entry: EntryUiState = EntryUiState(),
    val deckDetail: DeckDetail? = null,
    val card: CardUiState? = null,
    val quizConfig: QuizConfig = QuizConfig(null, "mixed", "native", 20, true, false, false),
    val quizState: QuizState? = null,
    val quizLoading: Boolean = false,
    val quizRevealedGrade: Int? = null,
    val typedAnswer: String = "",
    val replacementQuery: String = "",
    val replacementResults: List<SenseHit> = emptyList(),
    val exportedFile: ExportedFile? = null,
)
