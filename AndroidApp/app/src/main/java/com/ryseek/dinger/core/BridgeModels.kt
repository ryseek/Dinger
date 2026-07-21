package com.ryseek.dinger.core

import org.json.JSONArray
import org.json.JSONObject

data class Term(
    val termId: Long,
    val surface: String,
    val headword: String,
    val pos: String?,
    val gender: String?,
    val languageCode: String,
)

data class SenseHit(
    val senseId: Long,
    val entryId: Long,
    val matchedTermId: Long,
    val matchedLanguageCode: String,
    val sourceTerms: List<Term>,
    val targetTerms: List<Term>,
    val domain: List<String>,
    val context: String?,
    val matchRank: Int,
)

data class Deck(
    val id: Long,
    val name: String,
    val sourceLang: String,
    val targetLang: String,
    val createdAt: Long,
)

data class ExampleSentence(
    val id: Long,
    val germanText: String,
    val englishText: String,
)

data class SearchHistory(
    val id: Long,
    val query: String,
    val direction: String,
    val searchedAt: Long,
)

data class StudyWord(
    val cardId: Long,
    val front: String,
    val back: String,
    val deckName: String,
    val reviewCount: Int,
    val failedReviewCount: Int,
    val isNew: Boolean,
)

data class StudyDay(
    val date: Long,
    val reviewCount: Int,
    val correctCount: Int,
    val words: List<StudyWord>,
)

data class StudyActivity(val days: List<StudyDay>, val currentStreak: Int)

data class Card(
    val id: Long,
    val deckId: Long,
    val senseId: Long,
    val direction: String,
    val suspended: Boolean,
)

data class CardRow(
    val id: Long,
    val card: Card,
    val frontSurfaces: List<String>,
    val backSurfaces: List<String>,
    val dueAt: Long?,
    val repetitions: Int,
    val intervalDays: Int,
    val lastReviewedAt: Long?,
    val reviewCount: Int,
    val successfulReviewCount: Int,
    val suspended: Boolean,
)

data class DifficultCard(
    val id: Long,
    val front: String,
    val back: String,
    val againCount: Int,
    val reviewCount: Int,
)

data class DeckStatistics(
    val totalCards: Int,
    val reviewedCards: Int,
    val dueCards: Int,
    val totalReviews: Int,
    val totalRepetitions: Int,
    val matureCards: Int,
    val learningCards: Int,
    val reviewsThisWeek: Int,
    val dueTomorrow: Int,
    val successfulReviews: Int,
    val hardestCards: List<DifficultCard>,
) {
    val reviewedFraction: Float get() = if (totalCards == 0) 0f else reviewedCards.toFloat() / totalCards
    val retentionRate: Float get() = if (totalReviews == 0) 0f else successfulReviews.toFloat() / totalReviews
}

data class DeckDetail(val deck: Deck, val rows: List<CardRow>, val statistics: DeckStatistics)

data class QuizQuestion(
    val id: Long,
    val kind: String,
    val front: String,
    val displayFronts: List<String>,
    val displayAnswers: List<String>,
    val choices: List<String>,
    val correctIndex: Int?,
    val frontExample: String?,
    val backExample: String?,
    val sourceLanguageCode: String,
    val targetLanguageCode: String,
)

data class QuizProgress(
    val answered: Int,
    val total: Int,
    val correct: Int,
    val again: Int,
    val hard: Int,
    val good: Int,
    val easy: Int,
)

data class QuizState(val question: QuizQuestion?, val progress: QuizProgress, val completed: Boolean)
data class EntryDetails(val hit: SenseHit, val examples: List<ExampleSentence>, val decks: List<Deck>)
data class HistoryPayload(val recentSearches: List<SearchHistory>, val recentOpened: List<SenseHit>)
data class BootstrapPayload(
    val decks: List<Deck>,
    val activity: StudyActivity,
    val recentSearches: List<SearchHistory>,
    val recentOpened: List<SenseHit>,
)

internal fun JSONObject.requireSuccess(): JSONObject {
    if (!optBoolean("ok")) error(optString("error", "DingerCore request failed"))
    return getJSONObject("data")
}

internal fun JSONObject.requireSuccessArray(): JSONArray {
    if (!optBoolean("ok")) error(optString("error", "DingerCore request failed"))
    return getJSONArray("data")
}

internal fun parseTerm(json: JSONObject) = Term(
    termId = json.getLong("termId"),
    surface = json.getString("surface"),
    headword = json.getString("headword"),
    pos = json.nullableString("pos"),
    gender = json.nullableString("gender"),
    languageCode = json.getString("languageCode"),
)

internal fun parseHit(json: JSONObject) = SenseHit(
    senseId = json.getLong("senseId"),
    entryId = json.getLong("entryId"),
    matchedTermId = json.getLong("matchedTermId"),
    matchedLanguageCode = json.getString("matchedLanguageCode"),
    sourceTerms = json.getJSONArray("sourceTerms").mapObjects(::parseTerm),
    targetTerms = json.getJSONArray("targetTerms").mapObjects(::parseTerm),
    domain = json.getJSONArray("domain").mapStrings(),
    context = json.nullableString("context"),
    matchRank = json.getInt("matchRank"),
)

internal fun parseDeck(json: JSONObject) = Deck(
    id = json.getLong("id"),
    name = json.getString("name"),
    sourceLang = json.getString("source_lang"),
    targetLang = json.getString("target_lang"),
    createdAt = json.getLong("created_at"),
)

internal fun parseExample(json: JSONObject) = ExampleSentence(
    id = json.getLong("id"),
    germanText = json.getString("germanText"),
    englishText = json.getString("englishText"),
)

internal fun parseHistory(json: JSONObject) = SearchHistory(
    id = json.getLong("id"),
    query = json.getString("query"),
    direction = json.getString("direction"),
    searchedAt = json.getLong("searched_at"),
)

internal fun parseActivity(json: JSONObject) = StudyActivity(
    days = json.getJSONArray("days").mapObjects { day ->
        StudyDay(
            date = day.getLong("date"),
            reviewCount = day.getInt("reviewCount"),
            correctCount = day.getInt("correctCount"),
            words = day.getJSONArray("words").mapObjects { word ->
                StudyWord(
                    cardId = word.getLong("cardId"),
                    front = word.getString("front"),
                    back = word.getString("back"),
                    deckName = word.getString("deckName"),
                    reviewCount = word.getInt("reviewCount"),
                    failedReviewCount = word.getInt("failedReviewCount"),
                    isNew = word.getBoolean("isNew"),
                )
            },
        )
    },
    currentStreak = json.getInt("currentStreak"),
)

internal fun parseCard(json: JSONObject) = Card(
    id = json.getLong("id"),
    deckId = json.getLong("deck_id"),
    senseId = json.getLong("sense_id"),
    direction = json.getString("direction"),
    suspended = json.getBoolean("suspended"),
)

internal fun parseCardRow(json: JSONObject) = CardRow(
    id = json.getLong("id"),
    card = parseCard(json.getJSONObject("card")),
    frontSurfaces = json.getJSONArray("frontSurfaces").mapStrings(),
    backSurfaces = json.getJSONArray("backSurfaces").mapStrings(),
    dueAt = json.nullableLong("dueAt"),
    repetitions = json.getInt("repetitions"),
    intervalDays = json.getInt("intervalDays"),
    lastReviewedAt = json.nullableLong("lastReviewedAt"),
    reviewCount = json.getInt("reviewCount"),
    successfulReviewCount = json.getInt("successfulReviewCount"),
    suspended = json.getBoolean("suspended"),
)

internal fun parseStatistics(json: JSONObject) = DeckStatistics(
    totalCards = json.getInt("totalCards"),
    reviewedCards = json.getInt("reviewedCards"),
    dueCards = json.getInt("dueCards"),
    totalReviews = json.getInt("totalReviews"),
    totalRepetitions = json.getInt("totalRepetitions"),
    matureCards = json.getInt("matureCards"),
    learningCards = json.getInt("learningCards"),
    reviewsThisWeek = json.getInt("reviewsThisWeek"),
    dueTomorrow = json.getInt("dueTomorrow"),
    successfulReviews = json.getInt("successfulReviews"),
    hardestCards = json.getJSONArray("hardestCards").mapObjects { card ->
        DifficultCard(
            id = card.getLong("id"),
            front = card.getString("front"),
            back = card.getString("back"),
            againCount = card.getInt("againCount"),
            reviewCount = card.getInt("reviewCount"),
        )
    },
)

internal fun parseQuestion(json: JSONObject) = QuizQuestion(
    id = json.getLong("id"),
    kind = json.getString("kind"),
    front = json.getString("front"),
    displayFronts = json.getJSONArray("displayFronts").mapStrings(),
    displayAnswers = json.getJSONArray("displayAnswers").mapStrings(),
    choices = json.getJSONArray("choices").mapStrings(),
    correctIndex = json.nullableInt("correctIndex"),
    frontExample = json.nullableString("frontExample"),
    backExample = json.nullableString("backExample"),
    sourceLanguageCode = json.getString("sourceLanguageCode"),
    targetLanguageCode = json.getString("targetLanguageCode"),
)

internal fun parseQuizState(json: JSONObject) = QuizState(
    question = json.optJSONObject("question")?.let(::parseQuestion),
    progress = json.getJSONObject("progress").let { progress ->
        QuizProgress(
            answered = progress.getInt("answered"),
            total = progress.getInt("total"),
            correct = progress.getInt("correct"),
            again = progress.getInt("again"),
            hard = progress.getInt("hard"),
            good = progress.getInt("good"),
            easy = progress.getInt("easy"),
        )
    },
    completed = json.getBoolean("completed"),
)

private fun JSONObject.nullableString(name: String): String? = if (isNull(name)) null else getString(name)
private fun JSONObject.nullableLong(name: String): Long? = if (isNull(name)) null else getLong(name)
private fun JSONObject.nullableInt(name: String): Int? = if (isNull(name)) null else getInt(name)
private fun JSONArray.mapStrings(): List<String> = List(length()) { getString(it) }
private fun <T> JSONArray.mapObjects(transform: (JSONObject) -> T): List<T> =
    List(length()) { transform(getJSONObject(it)) }
