// SPDX-FileCopyrightText: 2026 Luciano Iam <oss@lucianoiam.com>
// SPDX-License-Identifier: MIT

package juce_cmp.demo

import androidx.compose.animation.core.*
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.rotate
import androidx.compose.ui.draw.scale
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.DpOffset
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import org.jetbrains.compose.ui.tooling.preview.Preview
import juce_cmp.ParameterState
import juce_cmp.UISender
import kotlin.random.Random

@Composable
fun Words() {
    val duration = 5000

    val infiniteTransition = rememberInfiniteTransition()
    // Start at initial angle (-50f) so first frame is predictable
    val angle by infiniteTransition.animateFloat(
        initialValue = -50f,
        targetValue = 30f,
        animationSpec = infiniteRepeatable(
            animation = tween(duration, easing = FastOutSlowInEasing),
            repeatMode = RepeatMode.Reverse
        )
    )
    // Start at initial scale (1f) so first frame is predictable
    val scale by infiniteTransition.animateFloat(
        initialValue = 1f,
        targetValue = 7f,
        animationSpec = infiniteRepeatable(
            animation = tween(duration, easing = FastOutSlowInEasing),
            repeatMode = RepeatMode.Reverse
        )
    )

    val color1 = Color(0x6B, 0x57, 0xFF)
    val color2 = Color(0xFE, 0x28, 0x57)
    val color3 = Color(0xFD, 0xB6, 0x0D)
    val color4 = Color(0xFC, 0xF8, 0x4A)

    BoxWithConstraints(
        modifier = Modifier.fillMaxSize()
    ) {
        val centerX = maxWidth / 2
        val centerY = maxHeight / 2

        // Position rotating words closer to center (reduced margin)
        val marginH = maxWidth * 0.2f
        val marginV = maxHeight * 0.2f
        Word(position = DpOffset(marginH, marginV), angle = angle, scale = scale, text = "Hello", color = color1)
        Word(position = DpOffset(marginH, maxHeight - marginV), angle = angle, scale = scale, text = "こんにちは", color = color2)
        Word(position = DpOffset(maxWidth - marginH, marginV), angle = angle, scale = scale, text = "你好", color = color3)
        Word(position = DpOffset(maxWidth - marginH, maxHeight - marginV), angle = angle, scale = scale, text = "Привет", color = color4)
    }
}

@Composable
fun Word(
    position: DpOffset,
    angle: Float,
    scale: Float,
    text: String,
    color: Color,
    alpha: Float = 0.8f,
    fontSize: androidx.compose.ui.unit.TextUnit = 16.sp,
    textAlign: androidx.compose.ui.text.style.TextAlign? = null
) {
    Text(
        modifier = Modifier
            .offset(position.x, position.y)
            .rotate(angle)
            .scale(scale)
            .alpha(alpha),
        color = color,
        fontWeight = FontWeight.Bold,
        text = text,
        fontSize = fontSize,
        textAlign = textAlign
    )
}

@Composable
fun FallingSnow() {
    BoxWithConstraints(Modifier.fillMaxSize()) {
        repeat(50) {
            val size = remember { 20.dp + 10.dp * Random.nextFloat() }
            val alpha = remember { 0.10f + 0.15f * Random.nextFloat() }
            val sizePx = with(LocalDensity.current) { size.toPx() }
            val x = remember { (constraints.maxWidth * Random.nextFloat()).toInt() }

            val infiniteTransition = rememberInfiniteTransition()
            val t by infiniteTransition.animateFloat(
                initialValue = 0f,
                targetValue = 1f,
                animationSpec = infiniteRepeatable(
                    animation = tween(16000 + (16000 * Random.nextFloat()).toInt(), easing = LinearEasing),
                    repeatMode = RepeatMode.Restart
                )
            )
            // All balls start from top (initialT = 0) so first frame is clean
            val y = (-sizePx + (constraints.maxHeight + sizePx) * t).toInt()

            Box(
                Modifier
                    .offset { IntOffset(x, y) }
                    .clip(CircleShape)
                    .alpha(alpha)
                    .background(Color.White)
                    .size(size)
            )
        }
    }
}

@Composable
fun Background() = Box(
    Modifier
        .fillMaxSize()
        // NOTE: This should match the loading screen background in PluginEditor.cpp (juce::Colour(0xFF6F97FF))
        .background(Color(0xFF6F97FF))
)

@Composable
fun ResizeHandle() {
    Box(
        modifier = Modifier
            .fillMaxSize()
            .padding(bottom = 3.dp, end = 3.dp),
        contentAlignment = Alignment.BottomEnd
    ) {
        Canvas(modifier = Modifier.size(16.dp)) {
            val handleColor = Color.DarkGray.copy(alpha = 0.7f)
            val strokeWidth = 2f

            // Draw three diagonal lines like JUCE resize handle
            // Bottom line (longest)
            drawLine(
                color = handleColor,
                start = Offset(size.width - 4.dp.toPx(), size.height),
                end = Offset(size.width, size.height - 4.dp.toPx()),
                strokeWidth = strokeWidth
            )

            // Middle line
            drawLine(
                color = handleColor,
                start = Offset(size.width - 8.dp.toPx(), size.height),
                end = Offset(size.width, size.height - 8.dp.toPx()),
                strokeWidth = strokeWidth
            )

            // Top line (shortest)
            drawLine(
                color = handleColor,
                start = Offset(size.width - 12.dp.toPx(), size.height),
                end = Offset(size.width, size.height - 12.dp.toPx()),
                strokeWidth = strokeWidth
            )
        }
    }
}

@Composable
@Preview
fun UserInterface() {
    MaterialTheme {
        Box(modifier = Modifier.fillMaxSize()) {
            // Background with animations
            Background()
            FallingSnow()
            Words()

            // Banner at top
            Box(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(top = 24.dp),
                contentAlignment = Alignment.TopCenter
            ) {
                Column(
                    horizontalAlignment = Alignment.CenterHorizontally,
                    verticalArrangement = Arrangement.Center
                ) {
                    Text(
                        text = "JUCE",
                        color = Color(52, 67, 235),
                        fontWeight = FontWeight.Bold,
                        fontSize = (16 * 6 * 0.25f).sp,
                        modifier = Modifier.alpha(0.4f)
                    )
                    Text(
                        text = "+",
                        color = Color(52, 67, 235),
                        fontWeight = FontWeight.Bold,
                        fontSize = (16 * 6 * 0.25f).sp,
                        modifier = Modifier.alpha(0.4f)
                    )
                    Text(
                        text = "Compose",
                        color = Color(52, 67, 235),
                        fontWeight = FontWeight.Bold,
                        fontSize = (16 * 6 * 0.25f).sp,
                        modifier = Modifier.alpha(0.4f)
                    )
                    Text(
                        text = "Multiplatform",
                        color = Color(52, 67, 235),
                        fontWeight = FontWeight.Bold,
                        fontSize = (16 * 6 * 0.25f).sp,
                        modifier = Modifier.alpha(0.4f)
                    )
                }
            }

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
                val shapeValue = paramState[0] ?: 0f

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
                        onValueChange = {
                            ParameterState.update(0, it)
                            UISender.setParameter(0, it)
                        }
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
