package com.rithwikshetty.tab.ui.theme

import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color

private val SageLightColors = lightColorScheme(
    primary = Color(0xFF4F7549),
    onPrimary = Color.White,
    primaryContainer = Color(0xFFEEF2E7),
    onPrimaryContainer = Color(0xFF28281F),
    background = Color(0xFFFAF7F0),
    onBackground = Color(0xFF28281F),
    surface = Color.White,
    onSurface = Color(0xFF28281F),
    surfaceContainer = Color(0xFFF1ECE2),
    surfaceVariant = Color(0xFFF1ECE2),
    onSurfaceVariant = Color(0xFF777267),
    error = Color(0xFFB16D3F),
)

private val SageDarkColors = darkColorScheme(
    primary = Color(0xFF98BD90),
    onPrimary = Color(0xFF183714),
    primaryContainer = Color(0xFF334F2F),
    onPrimaryContainer = Color(0xFFD9E8D4),
    background = Color(0xFF171A16),
    onBackground = Color(0xFFEDF0E8),
    surface = Color(0xFF20251F),
    onSurface = Color(0xFFEDF0E8),
    surfaceContainer = Color(0xFF2A3028),
    surfaceVariant = Color(0xFF2A3028),
    onSurfaceVariant = Color(0xFFADB5A8),
    error = Color(0xFFE0A17A),
)

@Composable
fun TabTheme(
    darkTheme: Boolean = isSystemInDarkTheme(),
    content: @Composable () -> Unit,
) {
    MaterialTheme(
        colorScheme = if (darkTheme) SageDarkColors else SageLightColors,
        content = content,
    )
}
