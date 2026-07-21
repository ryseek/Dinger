package com.ryseek.dinger.core

import android.content.Context
import android.util.Base64
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import org.json.JSONArray
import org.json.JSONObject
import java.io.File

data class ExportedFile(val filename: String, val bytes: ByteArray)
data class SaveResult(val isNew: Boolean, val didUpdate: Boolean)

class DingerRepository(private val context: Context) {
    suspend fun initialize(onProgress: (String) -> Unit = {}): BootstrapPayload = withContext(Dispatchers.IO) {
        val directory = File(context.filesDir, "database").apply { mkdirs() }
        val database = File(directory, "dinger.sqlite")
        if (!database.exists()) {
            onProgress("Installing the German–English dictionary…")
            val temporary = File(directory, "dinger.sqlite.installing")
            temporary.delete()
            try {
                context.assets.open("de-en.sqlite").use { input ->
                    temporary.outputStream().buffered().use { output -> input.copyTo(output, 1024 * 1024) }
                }
                check(temporary.renameTo(database)) { "Could not finish installing the dictionary" }
            } catch (error: Throwable) {
                temporary.delete()
                throw error
            }
        }
        onProgress("Opening DingerCore…")
        JSONObject(DingerNative.open(database.absolutePath)).requireSuccess()
        bootstrap()
    }

    suspend fun bootstrap(): BootstrapPayload = ioCall("bootstrap") { data ->
        BootstrapPayload(
            decks = data.getJSONArray("decks").objects(::parseDeck),
            activity = parseActivity(data.getJSONObject("activity")),
            recentSearches = data.getJSONArray("recentSearches").objects(::parseHistory),
            recentOpened = data.getJSONArray("recentOpened").objects(::parseHit),
        )
    }

    suspend fun search(query: String, direction: String): List<SenseHit> = ioArrayCall(
        request = JSONObject().put("action", "search").put("query", query).put("direction", direction),
        parser = ::parseHit,
    )

    suspend fun history(): HistoryPayload = ioCall("history") { data ->
        HistoryPayload(
            recentSearches = data.getJSONArray("recentSearches").objects(::parseHistory),
            recentOpened = data.getJSONArray("recentOpened").objects(::parseHit),
        )
    }

    suspend fun openSense(hit: SenseHit, termIds: Set<Long>? = null): EntryDetails = withContext(Dispatchers.IO) {
        val request = JSONObject()
            .put("action", "openSense")
            .put("senseId", hit.senseId)
            .put("matchedTermId", hit.matchedTermId)
        termIds?.let { request.put("termIds", JSONArray(it.toList())) }
        val data = call(request).requireSuccess()
        EntryDetails(
            hit = parseHit(data.getJSONObject("hit")),
            examples = data.getJSONArray("examples").objects(::parseExample),
            decks = data.getJSONArray("decks").objects(::parseDeck),
        )
    }

    suspend fun examples(termIds: Set<Long>): List<ExampleSentence> = ioArrayCall(
        JSONObject().put("action", "examples").put("termIds", JSONArray(termIds.toList())),
        ::parseExample,
    )

    suspend fun createDeck(name: String): Deck = ioCall(
        JSONObject().put("action", "createDeck").put("name", name),
        ::parseDeck,
    )

    suspend fun renameDeck(id: Long, name: String): Deck = ioCall(
        JSONObject().put("action", "renameDeck").put("deckId", id).put("name", name),
        ::parseDeck,
    )

    suspend fun deleteDeck(id: Long) = ioMessage(JSONObject().put("action", "deleteDeck").put("deckId", id))

    suspend fun deckDetail(id: Long): DeckDetail = ioCall(
        JSONObject().put("action", "deckDetail").put("deckId", id)
    ) { data ->
        DeckDetail(
            deck = parseDeck(data.getJSONObject("deck")),
            rows = data.getJSONArray("rows").objects(::parseCardRow),
            statistics = parseStatistics(data.getJSONObject("statistics")),
        )
    }

    suspend fun activity(): StudyActivity = ioCall("activity", ::parseActivity)

    suspend fun saveCard(
        hit: SenseHit,
        deckId: Long,
        sourceTermIds: Set<Long>,
        targetTermIds: Set<Long>,
    ): SaveResult = ioCall(
        JSONObject()
            .put("action", "saveCard")
            .put("senseId", hit.senseId)
            .put("matchedTermId", hit.matchedTermId)
            .put("deckId", deckId)
            .put("cardDirection", "s2t")
            .put("sourceTermIds", JSONArray(sourceTermIds.toList()))
            .put("targetTermIds", JSONArray(targetTermIds.toList()))
    ) { data -> SaveResult(data.getBoolean("isNew"), data.getBoolean("didUpdate")) }

    suspend fun suspendCard(cardId: Long, suspended: Boolean) = ioMessage(
        JSONObject().put("action", "suspendCard").put("cardId", cardId).put("suspended", suspended)
    )

    suspend fun invertCard(cardId: Long): Card = ioCall(
        JSONObject().put("action", "invertCard").put("cardId", cardId),
        ::parseCard,
    )

    suspend fun deleteCard(cardId: Long) = ioMessage(
        JSONObject().put("action", "deleteCard").put("cardId", cardId)
    )

    suspend fun cardExample(cardId: Long): ExampleSentence? = ioCall(
        JSONObject().put("action", "cardExample").put("cardId", cardId)
    ) { data -> data.optJSONObject("value")?.let(::parseExample) }

    suspend fun exportDeck(deckId: Long): ExportedFile = export(
        JSONObject().put("action", "exportDeck").put("deckId", deckId)
    )

    suspend fun exportAll(): ExportedFile = export(JSONObject().put("action", "exportAllDecks"))

    suspend fun importDecks(bytes: ByteArray): List<Deck> = ioArrayCall(
        JSONObject()
            .put("action", "importDecks")
            .put("base64", Base64.encodeToString(bytes, Base64.NO_WRAP)),
        ::parseDeck,
    )

    suspend fun startQuiz(config: QuizConfig): QuizState = ioCall(
        JSONObject()
            .put("action", "quizStart")
            .put("deckId", config.deckId)
            .put("quizMode", config.mode)
            .put("quizDirection", config.direction)
            .put("maxQuestions", config.maxQuestions)
            .put("includeNew", config.includeNew)
            .put("showExamples", config.showExamples)
            .put("practiceMode", config.practiceMode),
        ::parseQuizState,
    )

    suspend fun typedGrade(answer: String): Int = ioCall(
        JSONObject().put("action", "quizTypedGrade").put("answer", answer)
    ) { it.getInt("grade") }

    suspend fun choiceGrade(index: Int): Int = ioCall(
        JSONObject().put("action", "quizChoiceGrade").put("choiceIndex", index)
    ) { it.getInt("grade") }

    suspend fun gradeQuiz(grade: Int): QuizState = ioCall(
        JSONObject().put("action", "quizGrade").put("grade", grade),
        ::parseQuizState,
    )

    suspend fun replaceQuizCard(hit: SenseHit): QuizState {
        val source = hit.sourceTerms.firstOrNull()?.termId ?: error("Replacement has no source term")
        val target = hit.targetTerms.firstOrNull()?.termId ?: error("Replacement has no target term")
        return ioCall(
            JSONObject()
                .put("action", "quizReplace")
                .put("senseId", hit.senseId)
                .put("matchedTermId", hit.matchedTermId)
                .put("selectedSourceTermId", source)
                .put("selectedTargetTermId", target),
            ::parseQuizState,
        )
    }

    suspend fun cancelQuiz() = ioMessage(JSONObject().put("action", "quizCancel"))

    private suspend fun export(request: JSONObject): ExportedFile = ioCall(request) { data ->
        ExportedFile(
            filename = data.getString("filename"),
            bytes = Base64.decode(data.getString("base64"), Base64.DEFAULT),
        )
    }

    private suspend fun ioMessage(request: JSONObject): String = ioCall(request) { it.getString("message") }

    private suspend fun <T> ioCall(action: String, parse: (JSONObject) -> T): T =
        ioCall(JSONObject().put("action", action), parse)

    private suspend fun <T> ioCall(request: JSONObject, parse: (JSONObject) -> T): T =
        withContext(Dispatchers.IO) { parse(call(request).requireSuccess()) }

    private suspend fun <T> ioArrayCall(request: JSONObject, parser: (JSONObject) -> T): List<T> =
        withContext(Dispatchers.IO) { call(request).requireSuccessArray().objects(parser) }

    private fun call(request: JSONObject): JSONObject = JSONObject(DingerNative.call(request.toString()))
}

data class QuizConfig(
    val deckId: Long?,
    val mode: String,
    val direction: String,
    val maxQuestions: Int,
    val includeNew: Boolean,
    val showExamples: Boolean,
    val practiceMode: Boolean,
)

private fun <T> org.json.JSONArray.objects(parser: (JSONObject) -> T): List<T> =
    List(length()) { parser(getJSONObject(it)) }
