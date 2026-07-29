package com.rithwikshetty.tab

import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.junit4.v2.createComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performTextReplacement
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.rithwikshetty.tab.data.LocalPerson
import com.rithwikshetty.tab.domain.SimplifiedDebt
import com.rithwikshetty.tab.ui.settlements.SettlementEditorScreen
import com.rithwikshetty.tab.ui.theme.TabTheme
import java.math.BigDecimal
import java.util.UUID
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class SettlementEditorScreenTest {
    @get:Rule
    val composeRule = createComposeRule()

    @Test
    fun suggestionPrefillsPeopleAndSavesExactDecimal() {
        var savedAmount: String? = null
        var savedFrom: UUID? = null
        var savedTo: UUID? = null
        composeRule.setContent {
            TabTheme {
                SettlementEditorScreen(
                    people = listOf(
                        person(FROM_ID, "Alex"),
                        person(TO_ID, "Test User"),
                    ),
                    existing = null,
                    suggestion = SimplifiedDebt(
                        fromUser = FROM_ID,
                        toUser = TO_ID,
                        currency = "GBP",
                        amount = BigDecimal("6.35"),
                    ),
                    isWorking = false,
                    onBack = {},
                    onSave = { from, to, amount, _, _, existing ->
                        savedFrom = from
                        savedTo = to
                        savedAmount = amount
                        assertNull(existing)
                    },
                )
            }
        }

        composeRule.onNodeWithTag("settlementAmount").assertIsDisplayed()
        composeRule.onNodeWithText("Alex").assertIsDisplayed()
        composeRule.onNodeWithText("Test User").assertIsDisplayed()
        composeRule.onNodeWithTag("settlementAmount").performTextReplacement("6.35")
        composeRule.onNodeWithTag("saveSettlement").performClick()
        composeRule.waitForIdle()

        assertEquals(FROM_ID, savedFrom)
        assertEquals(TO_ID, savedTo)
        assertEquals("6.35", savedAmount)
    }

    private fun person(id: UUID, name: String): LocalPerson = LocalPerson(
        id = id,
        userId = null,
        email = "${name.lowercase().replace(" ", ".")}@tab.local",
        displayName = name,
        hasJoined = false,
    )

    private companion object {
        val FROM_ID: UUID = UUID.fromString("11111111-1111-1111-1111-111111111111")
        val TO_ID: UUID = UUID.fromString("22222222-2222-2222-2222-222222222222")
    }
}
