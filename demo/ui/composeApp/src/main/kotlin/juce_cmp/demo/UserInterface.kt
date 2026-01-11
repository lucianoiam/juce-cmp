// SPDX-FileCopyrightText: 2026 Luciano Iam <oss@lucianoiam.com>
// SPDX-License-Identifier: MIT

package juce_cmp.demo

import androidx.compose.animation.core.*
import androidx.compose.foundation.layout.*
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp
import org.jetbrains.compose.ui.tooling.preview.Preview
import juce_cmp.widgets.ResizeHandle
import juce_cmp.demo.ParameterState.Index.Shape

@Composable
@Preview
fun UserInterface() {
    MaterialTheme {
        Box(modifier = Modifier.fillMaxSize()) {
            // Background with animations
            Background()
            FallingSnow()
            AnimatedWords()

            // Banner at top
            Title()

            // Shape knob in vertical center
            Box(
                modifier = Modifier.fillMaxSize(),
                contentAlignment = Alignment.Center
            ) {
                // Fade in knob so first frame is predictable (one-time animation)
                var targetAlpha by remember { mutableStateOf(0f) }
                val knobAlpha by animateFloatAsState(
                    targetValue = targetAlpha,
                    animationSpec = tween(150, easing = LinearEasing)
                )

                LaunchedEffect(Unit) {
                    targetAlpha = 1f
                }

                // Observe ParameterState so host automation updates the UI
                val paramState = ParameterState.getState()
                val shapeValue = paramState[Shape] ?: 0f

                Column(
                    horizontalAlignment = Alignment.CenterHorizontally,
                    modifier = Modifier.alpha(knobAlpha)
                ) {
                    Text(
                        text = "Shape",
                        style = MaterialTheme.typography.labelMedium,
                        color = Color.DarkGray
                    )
                    Spacer(modifier = Modifier.height(8.dp))
                    Knob(
                        value = shapeValue,
                        onValueChange = { ParameterState.set(Shape, it) }
                    )
                    Spacer(modifier = Modifier.height(8.dp))
                    Text(
                        text = if (shapeValue < 0.1f) "Sine"
                               else if (shapeValue > 0.9f) "Square"
                               else "${(shapeValue * 100).toInt()}%",
                        style = MaterialTheme.typography.bodySmall,
                        color = Color.DarkGray
                    )
                }
            }

            // Resize handle in bottom right corner
            ResizeHandle()
        }
    }
}
