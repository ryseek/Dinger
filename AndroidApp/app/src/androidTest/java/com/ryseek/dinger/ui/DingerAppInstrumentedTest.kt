package com.ryseek.dinger.ui

import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.hasTestTag
import androidx.compose.ui.test.hasText
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.performTextInput
import com.ryseek.dinger.MainActivity
import org.junit.Rule
import org.junit.Test

class DingerAppInstrumentedTest {
    @get:Rule
    val compose = createAndroidComposeRule<MainActivity>()

    @Test
    fun appStartsAndSearchesTheBundledDictionary() {
        compose.waitUntil(120_000) {
            compose.onAllNodes(hasTestTag("dictionary-screen")).fetchSemanticsNodes().isNotEmpty()
        }
        compose.onNodeWithTag("dictionary-screen").assertIsDisplayed()
        compose.onNodeWithTag("search-field").performTextInput("Haus")
        compose.waitUntil(30_000) {
            compose.onAllNodes(hasText("house", substring = true, ignoreCase = true)).fetchSemanticsNodes().isNotEmpty()
        }
        compose.onNodeWithTag("search-field").assertIsDisplayed()
    }
}
