package cmpui.widgets

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.gestures.detectDragGestures
import androidx.compose.foundation.layout.size
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import kotlin.math.atan2
import kotlin.math.cos
import kotlin.math.sin

/**
 * A knob control for audio plugin UIs.
 *
 * @param value Current value from 0f to 1f
 * @param onValueChange Callback when value changes
 * @param modifier Modifier for the component
 * @param size Diameter of the knob
 * @param trackColor Color of the background track
 * @param valueColor Color of the value arc
 * @param indicatorColor Color of the position indicator
 * @param trackWidth Width of the arc stroke
 * @param sensitivity Drag sensitivity (higher = more sensitive)
 */
@Composable
fun Knob(
    value: Float,
    onValueChange: (Float) -> Unit,
    modifier: Modifier = Modifier,
    size: Dp = 60.dp,
    trackColor: Color = Color.DarkGray,
    valueColor: Color = Color(0xFF00BCD4),  // Cyan
    indicatorColor: Color = Color.White,
    trackWidth: Dp = 5.dp,
    sensitivity: Float = 0.005f
) {
    val sweepAngle = 270f  // Total rotation range in degrees
    val startAngle = 135f  // Start from bottom-left (pointing to 7 o'clock)
    
    // Use rememberUpdatedState to access current value without restarting gesture
    val currentValue by rememberUpdatedState(value)
    val currentOnValueChange by rememberUpdatedState(onValueChange)
    
    Canvas(
        modifier = modifier
            .size(size)
            .pointerInput(Unit) {
                detectDragGestures { change, dragAmount ->
                    change.consume()
                    // Vertical drag (up = increase) and horizontal drag (right = increase)
                    val delta = (-dragAmount.y + dragAmount.x) * sensitivity
                    val newValue = (currentValue + delta).coerceIn(0f, 1f)
                    currentOnValueChange(newValue)
                }
            }
    ) {
        val strokeWidth = trackWidth.toPx()
        val radius = (this.size.minDimension - strokeWidth) / 2f
        val center = Offset(this.size.width / 2f, this.size.height / 2f)
        val arcSize = Size(radius * 2, radius * 2)
        val topLeft = Offset(center.x - radius, center.y - radius)
        
        // Background track arc
        drawArc(
            color = trackColor,
            startAngle = startAngle,
            sweepAngle = sweepAngle,
            useCenter = false,
            topLeft = topLeft,
            size = arcSize,
            style = Stroke(width = strokeWidth, cap = StrokeCap.Round)
        )
        
        // Value arc
        if (value > 0f) {
            drawArc(
                color = valueColor,
                startAngle = startAngle,
                sweepAngle = sweepAngle * value,
                useCenter = false,
                topLeft = topLeft,
                size = arcSize,
                style = Stroke(width = strokeWidth, cap = StrokeCap.Round)
            )
        }
        
        // Position indicator (dot at current value position)
        val indicatorAngle = Math.toRadians((startAngle + sweepAngle * value).toDouble())
        val indicatorRadius = radius
        val indicatorX = center.x + (indicatorRadius * cos(indicatorAngle)).toFloat()
        val indicatorY = center.y + (indicatorRadius * sin(indicatorAngle)).toFloat()
        
        drawCircle(
            color = indicatorColor,
            radius = strokeWidth * 0.8f,
            center = Offset(indicatorX, indicatorY)
        )
        
        // Center dot
        drawCircle(
            color = trackColor,
            radius = radius * 0.3f,
            center = center
        )
    }
}
