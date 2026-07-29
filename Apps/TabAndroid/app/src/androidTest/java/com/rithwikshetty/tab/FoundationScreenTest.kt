package com.rithwikshetty.tab

import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.junit4.v2.createAndroidComposeRule
import androidx.compose.ui.test.onAllNodesWithText
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.performClick
import androidx.test.ext.junit.runners.AndroidJUnit4
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class AppShellTest {
    @get:Rule
    val composeRule = createAndroidComposeRule<MainActivity>()

    @Test
    fun localSignInOpensTripsNavigation() {
        composeRule.waitUntil(timeoutMillis = 15_000) {
            composeRule.onAllNodesWithText("Sign in").fetchSemanticsNodes().isNotEmpty() ||
                composeRule.onAllNodesWithText("Trips").fetchSemanticsNodes().isNotEmpty()
        }
        if (composeRule.onAllNodesWithText("Sign in").fetchSemanticsNodes().isNotEmpty()) {
            composeRule.onNodeWithText("Sign in").performClick()
        }
        composeRule.waitUntil(timeoutMillis = 20_000) {
            composeRule.onAllNodesWithText("Trips").fetchSemanticsNodes().isNotEmpty()
        }
        composeRule.onNodeWithContentDescription("Refresh trips").assertIsDisplayed()

        composeRule.activityRule.scenario.recreate()
        composeRule.waitUntil(timeoutMillis = 15_000) {
            composeRule.onAllNodesWithText("Settings").fetchSemanticsNodes().isNotEmpty()
        }
        composeRule.onNodeWithText("Settings").performClick()
        composeRule.onNodeWithText("Sign out").performClick()
        composeRule.onNodeWithTag("confirmSignOut").performClick()
        composeRule.waitUntil(timeoutMillis = 20_000) {
            composeRule.onAllNodesWithText("Sign in").fetchSemanticsNodes().isNotEmpty()
        }
        composeRule.onNodeWithText("Sign in").assertIsDisplayed()
    }
}
