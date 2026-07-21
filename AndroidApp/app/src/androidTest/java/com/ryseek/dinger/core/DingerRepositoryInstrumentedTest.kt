package com.ryseek.dinger.core

import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class DingerRepositoryInstrumentedTest {
    @Test
    fun nativeCoreRoundTripCoversSearchCardsQuizAndExport() = runBlocking {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val repository = DingerRepository(context)
        val bootstrap = repository.initialize()
        assertTrue(bootstrap.decks.isNotEmpty())

        val hit = repository.search("Haus", "sourceToTarget")
            .first { candidate -> candidate.targetTerms.any { it.surface == "house" } }
        val deck = repository.createDeck("Android JNI 🦉")
        assertEquals("Android JNI 🦉", deck.name)

        try {
            val saved = repository.saveCard(
                hit = hit,
                deckId = deck.id,
                sourceTermIds = setOf(hit.sourceTerms.first().termId),
                targetTermIds = setOf(hit.targetTerms.first { it.surface == "house" }.termId),
            )
            assertTrue(saved.isNew)

            val detail = repository.deckDetail(deck.id)
            assertEquals(1, detail.rows.size)
            assertEquals("house", detail.rows.single().backSurfaces.single())

            val started = repository.startQuiz(
                QuizConfig(
                    deckId = deck.id,
                    mode = "typing",
                    direction = "native",
                    maxQuestions = 1,
                    includeNew = true,
                    showExamples = true,
                    practiceMode = true,
                )
            )
            assertNotNull(started.question)
            assertFalse(started.completed)

            val inferredGrade = repository.typedGrade("house")
            assertEquals(2, inferredGrade)
            val completed = repository.gradeQuiz(inferredGrade)
            assertTrue(completed.completed)
            assertEquals(1, completed.progress.answered)

            val exported = repository.exportDeck(deck.id)
            assertTrue(exported.filename.endsWith(".json"))
            assertTrue(exported.bytes.isNotEmpty())
        } finally {
            repository.cancelQuiz()
            repository.deleteDeck(deck.id)
        }
    }
}
