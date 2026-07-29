package com.rithwikshetty.tab

import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.assertIsEnabled
import androidx.compose.ui.test.junit4.v2.createAndroidComposeRule
import androidx.compose.ui.test.onAllNodesWithText
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performTextInput
import androidx.compose.ui.test.performTextReplacement
import androidx.test.ext.junit.runners.AndroidJUnit4
import java.util.UUID
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class AppShellTest {
    @get:Rule
    val composeRule = createAndroidComposeRule<MainActivity>()

    @Test
    fun localSignInOpensTripsNavigation() {
        ensureSignedIn()
        composeRule.onNodeWithContentDescription("Refresh trips").assertIsDisplayed()

        composeRule.activityRule.scenario.recreate()
        composeRule.waitUntil(timeoutMillis = 15_000) {
            composeRule.onAllNodesWithText("Settings").fetchSemanticsNodes().isNotEmpty()
        }
        composeRule.onNodeWithText("Settings").performClick()
        composeRule.onNodeWithText("Import from Splitwise").assertIsDisplayed()
        composeRule.onNodeWithText("Refresh local copy").assertIsDisplayed()
        composeRule.onNodeWithText("Sign out").performClick()
        composeRule.onNodeWithTag("confirmSignOut").performClick()
        composeRule.waitUntil(timeoutMillis = 20_000) {
            composeRule.onAllNodesWithText("Sign in").fetchSemanticsNodes().isNotEmpty()
        }
        composeRule.onNodeWithText("Sign in").assertIsDisplayed()
    }

    @Test
    fun seededTripSupportsCreateAndOpenExpenseFlow() {
        val description = "Android UI ${UUID.randomUUID().toString().take(8)}"
        ensureSignedIn()
        composeRule.waitUntil(timeoutMillis = 20_000) {
            composeRule.onAllNodesWithText("Lake District").fetchSemanticsNodes().isNotEmpty()
        }
        composeRule.onNodeWithText("Lake District").performClick()
        composeRule.onNodeWithTag("addExpense").performClick()
        composeRule.onNodeWithTag("expenseDescription").performTextInput(description)
        composeRule.onNodeWithTag("expenseAmount").performTextReplacement("14.75")
        composeRule.onNodeWithTag("saveExpense").performClick()

        composeRule.waitUntil(timeoutMillis = 20_000) {
            composeRule.onAllNodesWithText(description).fetchSemanticsNodes().isNotEmpty() &&
                composeRule.onAllNodesWithText("Expenses").fetchSemanticsNodes().isNotEmpty()
        }
        composeRule.onNodeWithText(description).performClick()
        composeRule.waitForIdle()
        composeRule.waitUntil(timeoutMillis = 10_000) {
            composeRule.onAllNodesWithText("14.75 GBP").fetchSemanticsNodes().isNotEmpty()
        }
        composeRule.onAllNodesWithText("14.75 GBP")[0].assertIsDisplayed()
        composeRule.onNodeWithText("Paid by").assertIsDisplayed()
        composeRule.onNodeWithText("Split between").assertIsDisplayed()
    }

    @Test
    fun seededTripShowsBalancesAndRecordsSuggestedRepayment() {
        ensureSignedIn()
        composeRule.waitUntil(timeoutMillis = 20_000) {
            composeRule.onAllNodesWithText("Lake District").fetchSemanticsNodes().isNotEmpty()
        }
        composeRule.onNodeWithText("Lake District").performClick()
        composeRule.onNodeWithText("Balances").performClick()
        composeRule.onNodeWithText("Suggested repayments").assertIsDisplayed()
        composeRule.waitUntil(timeoutMillis = 10_000) {
            composeRule.onAllNodesWithText("Settle").fetchSemanticsNodes().isNotEmpty()
        }
        composeRule.onAllNodesWithText("Settle")[0].performClick()
        composeRule.onNodeWithTag("settlementAmount").assertIsDisplayed()
        composeRule.waitUntil(timeoutMillis = 20_000) {
            runCatching {
                composeRule.onNodeWithTag("saveSettlement").assertIsEnabled()
            }.isSuccess
        }
        composeRule.onNodeWithTag("saveSettlement").performClick()

        composeRule.waitUntil(timeoutMillis = 20_000) {
            composeRule.onAllNodesWithText("Expenses").fetchSemanticsNodes().isNotEmpty()
        }
        composeRule.onNodeWithText("Balances").performClick()
        composeRule.onNodeWithText("Suggested repayments").assertIsDisplayed()
    }

    @Test
    fun friendsFlowResolvesExistingPersonIntoStandardExpenseEditor() {
        ensureSignedIn()
        composeRule.onNodeWithText("Friends").performClick()
        composeRule.waitUntil(timeoutMillis = 20_000) {
            composeRule.onAllNodesWithText("Alex").fetchSemanticsNodes().isNotEmpty()
        }
        composeRule.onNodeWithTag("addFriendExpense").performClick()
        composeRule.onNodeWithText("New friend expense").assertIsDisplayed()
        composeRule.onNodeWithText("Alex").performClick()
        composeRule.onNodeWithTag("resolveFriendExpense").performClick()

        composeRule.waitUntil(timeoutMillis = 20_000) {
            composeRule.onAllNodesWithText("New expense").fetchSemanticsNodes().isNotEmpty()
        }
        composeRule.onNodeWithTag("expenseDescription").assertIsDisplayed()
    }

    private fun ensureSignedIn() {
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
    }
}
