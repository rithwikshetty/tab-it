package com.rithwikshetty.tab

import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.junit4.v2.createComposeRule
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performScrollTo
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.rithwikshetty.tab.domain.SplitwiseImport
import com.rithwikshetty.tab.ui.app.ImportPreviewUiState
import com.rithwikshetty.tab.ui.importing.SplitwiseImportScreen
import com.rithwikshetty.tab.ui.theme.TabTheme
import org.junit.Assert.assertEquals
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class SplitwiseImportScreenTest {
    @get:Rule
    val composeRule = createComposeRule()

    @Test
    fun previewExplainsContentsAndRequiresIdentityChoice() {
        val parsed = SplitwiseImport.parse(
            """
            Date,Description,Category,Cost,Currency,Alice,Bob
            2026-07-01,Dinner,Food and drink,10.00,GBP,5.00,-5.00
            2026-07-02,Repayment,Payment,3.00,GBP,3.00,-3.00
            """.trimIndent(),
        )
        var selectedTripName: String? = null
        var selectedPerson: String? = null

        composeRule.setContent {
            TabTheme {
                SplitwiseImportScreen(
                    preview = ImportPreviewUiState(parsed, "summer-trip.csv"),
                    isWorking = false,
                    onBack = {},
                    onChooseFile = {},
                    onClearPreview = {},
                    onImport = { tripName, person, _ ->
                        selectedTripName = tripName
                        selectedPerson = person
                    },
                    onImported = {},
                )
            }
        }

        composeRule.onNodeWithText("1 expense, 1 settlement, 2 people")
            .assertIsDisplayed()
        composeRule.onNodeWithText("Which person is you?").assertIsDisplayed()
        composeRule.onNodeWithText("Bob").performClick()
        composeRule.onNodeWithText("Import trip").performScrollTo().performClick()
        composeRule.waitForIdle()

        assertEquals("summer-trip", selectedTripName)
        assertEquals("Bob", selectedPerson)
    }
}
