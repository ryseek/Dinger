package com.ryseek.dinger.core

import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Test

class BridgeModelsTest {
    @Test
    fun parsesDatabaseRecordsUsingTheirStableBridgeKeys() {
        val deck = parseDeck(
            JSONObject(
                """{"id":7,"name":"Study","source_lang":"de","target_lang":"en","created_at":1700000000000}"""
            )
        )
        assertEquals(7L, deck.id)
        assertEquals("de", deck.sourceLang)

        val history = parseHistory(
            JSONObject(
                """{"id":3,"query":"Haus","direction":"auto","source_lang":"de","target_lang":"en","searched_at":1700000000000}"""
            )
        )
        assertEquals("Haus", history.query)
        assertEquals(1_700_000_000_000L, history.searchedAt)

        val card = parseCard(
            JSONObject(
                """{"id":11,"deck_id":7,"sense_id":1,"front_term_id":1,"back_term_id":2,"front_term_ids":"1","back_term_ids":"2","direction":"s2t","created_at":1700000000000,"suspended":false}"""
            )
        )
        assertEquals(7L, card.deckId)
        assertEquals(1L, card.senseId)
        assertFalse(card.suspended)
    }

    @Test
    fun parsesQuizStateAndNullableQuestion() {
        val state = parseQuizState(
            JSONObject(
                """
                {
                  "completed": true,
                  "question": null,
                  "progress": {"answered":1,"total":1,"correct":1,"again":0,"hard":0,"good":1,"easy":0}
                }
                """.trimIndent()
            )
        )
        assertEquals(null, state.question)
        assertEquals(1, state.progress.answered)
        assertEquals(true, state.completed)
    }
}
