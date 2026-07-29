package com.rithwikshetty.tab

import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.junit4.v2.createComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performTextInput
import androidx.compose.ui.test.performTextReplacement
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.rithwikshetty.tab.data.LocalCategory
import com.rithwikshetty.tab.data.LocalPerson
import com.rithwikshetty.tab.domain.Expense
import com.rithwikshetty.tab.ui.expenses.ExpenseEditorScreen
import com.rithwikshetty.tab.ui.theme.TabTheme
import java.util.UUID
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class ExpenseEditorScreenTest {
    @get:Rule
    val composeRule = createComposeRule()

    @Test
    fun validatesThenBuildsAnExactDecimalExpense() {
        var saved: Expense? = null
        var backCount = 0
        composeRule.setContent {
            TabTheme {
                ExpenseEditorScreen(
                    tripId = TRIP_ID,
                    currentUserId = USER_ID,
                    people = listOf(
                        LocalPerson(
                            id = PERSON_ID,
                            userId = USER_ID,
                            email = "mock@tab.local",
                            displayName = "Test User",
                            hasJoined = true,
                        ),
                    ),
                    categories = listOf(
                        LocalCategory(CATEGORY_ID, "Food & Drink", "bowl-food", true),
                    ),
                    existing = null,
                    isWorking = false,
                    onBack = { backCount += 1 },
                    onSave = { expense, _ -> saved = expense },
                )
            }
        }

        composeRule.onNodeWithTag("saveExpense").performClick()
        composeRule.onNodeWithText("Description is required.").assertIsDisplayed()

        composeRule.onNodeWithTag("expenseDescription").performTextInput("Dinner")
        composeRule.onNodeWithText("Add receipt").assertExists()
        composeRule.onNodeWithTag("expenseAmount").performTextReplacement("10.25")
        composeRule.onNodeWithTag("payerAmount-$PERSON_ID").performTextReplacement("10.25")
        composeRule.onNodeWithTag("saveExpense").performClick()
        composeRule.waitForIdle()

        assertNotNull(saved)
        assertEquals("Dinner", saved?.description)
        assertEquals("10.25", saved?.amount?.amount?.toPlainString())
        assertEquals(1, backCount)
    }

    private companion object {
        val USER_ID: UUID = UUID.fromString("11111111-1111-1111-1111-111111111111")
        val PERSON_ID: UUID = UUID.fromString("61111111-1111-1111-1111-111111111111")
        val TRIP_ID: UUID = UUID.fromString("44444444-4444-4444-4444-444444444444")
        val CATEGORY_ID: UUID = UUID.fromString("00000001-0000-0000-0000-000000000000")
    }
}
