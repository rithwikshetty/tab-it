package com.rithwikshetty.tab

import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.junit4.v2.createAndroidComposeRule
import androidx.compose.ui.test.onNodeWithText
import androidx.test.ext.junit.runners.AndroidJUnit4
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class FoundationScreenTest {
    @get:Rule
    val composeRule = createAndroidComposeRule<MainActivity>()

    @Test
    fun showsLocalDevelopmentStatus() {
        composeRule.onNodeWithText("Android foundation").assertIsDisplayed()
        composeRule.onNodeWithText("Local Supabase only").assertIsDisplayed()
        composeRule.onNodeWithText("LOCAL").assertIsDisplayed()
    }
}
