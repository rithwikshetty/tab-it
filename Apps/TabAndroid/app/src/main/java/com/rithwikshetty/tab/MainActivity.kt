package com.rithwikshetty.tab

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.activity.viewModels
import com.rithwikshetty.tab.ui.app.TabApp
import com.rithwikshetty.tab.ui.app.TabViewModel
import com.rithwikshetty.tab.ui.theme.TabTheme

class MainActivity : ComponentActivity() {
    private val viewModel: TabViewModel by viewModels {
        TabViewModel.Factory((application as TabApplication).container)
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        setContent {
            TabTheme {
                TabApp(viewModel)
            }
        }
    }
}
