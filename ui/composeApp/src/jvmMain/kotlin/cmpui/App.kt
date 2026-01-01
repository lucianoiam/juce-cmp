package cmpui

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.animateColorAsState
import androidx.compose.animation.core.*
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.safeContentPadding
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp
import org.jetbrains.compose.resources.painterResource
import org.jetbrains.compose.ui.tooling.preview.Preview

import cmpui.composeapp.generated.resources.Res
import cmpui.composeapp.generated.resources.compose_multiplatform
import cmpui.widgets.Knob
import cmpui.bridge.UISender

@Composable
@Preview
fun App() {
    MaterialTheme {
        var showContent by remember { mutableStateOf(false) }
        
        // Animate hue from 0 to 360 degrees continuously
        val infiniteTransition = rememberInfiniteTransition()
        val hue by infiniteTransition.animateFloat(
            initialValue = 0f,
            targetValue = 360f,
            animationSpec = infiniteRepeatable(
                animation = tween(6000, easing = LinearEasing),
                repeatMode = RepeatMode.Restart
            )
        )
        val buttonColor = Color.hsl(hue, 0.7f, 0.5f)
        
        Column(
            modifier = Modifier
                .background(MaterialTheme.colorScheme.primaryContainer)
                .safeContentPadding()
                .fillMaxSize(),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            Button(
                onClick = { showContent = !showContent },
                colors = ButtonDefaults.buttonColors(containerColor = buttonColor)
            ) {
                Text("Click me!")
            }
            
            Spacer(modifier = Modifier.height(16.dp))
            
            // Shape knob - controls oscillator waveform (0=sine, 1=square)
            var shapeValue by remember { mutableStateOf(0f) }
            Text(
                text = "Shape",
                style = MaterialTheme.typography.labelMedium
            )
            Knob(
                value = shapeValue,
                onValueChange = { 
                    shapeValue = it
                    UISender.setParameter(0, it)  // paramId 0 = shape
                }
            )
            Text(
                text = if (shapeValue < 0.1f) "Sine" 
                       else if (shapeValue > 0.9f) "Square" 
                       else "${(shapeValue * 100).toInt()}%",
                style = MaterialTheme.typography.bodySmall
            )
            
            AnimatedVisibility(showContent) {
                val greeting = remember { Greeting().greet() }
                Column(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalAlignment = Alignment.CenterHorizontally,
                ) {
                    Image(painterResource(Res.drawable.compose_multiplatform), null)
                    Text("Compose: $greeting")
                }
            }
        }
    }
}