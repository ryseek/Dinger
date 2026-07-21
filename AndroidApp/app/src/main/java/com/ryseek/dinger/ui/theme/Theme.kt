package com.ryseek.dinger.ui.theme

import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color

private val LightColors = lightColorScheme(
    primary = Color(0xFF386A20),
    onPrimary = Color.White,
    primaryContainer = Color(0xFFB8F397),
    onPrimaryContainer = Color(0xFF062100),
    secondary = Color(0xFF55624C),
    secondaryContainer = Color(0xFFD9E7CB),
    onSecondaryContainer = Color(0xFF131F0D),
    tertiary = Color(0xFF386668),
    tertiaryContainer = Color(0xFFBBEBEC),
    background = Color(0xFFFAFDF6),
    surface = Color(0xFFFAFDF6),
    surfaceVariant = Color(0xFFDFE4D8),
)

private val DarkColors = darkColorScheme(
    primary = Color(0xFF9DD67E),
    primaryContainer = Color(0xFF205107),
    secondary = Color(0xFFBDCBB1),
    secondaryContainer = Color(0xFF3E4A36),
    tertiary = Color(0xFFA0CFD0),
    tertiaryContainer = Color(0xFF1E4E50),
)

@Composable
fun DingerTheme(content: @Composable () -> Unit) {
    MaterialTheme(
        colorScheme = if (isSystemInDarkTheme()) DarkColors else LightColors,
        content = content,
    )
}
