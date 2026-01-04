// SPDX-FileCopyrightText: 2026 Luciano Iam <oss@lucianoiam.com>
// SPDX-License-Identifier: MIT

package juce_cmp.demo

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.safeContentPadding
import androidx.compose.foundation.layout.width
import androidx.compose.material3.Button
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp
import org.jetbrains.compose.resources.painterResource
import org.jetbrains.compose.ui.tooling.preview.Preview

import juce_cmp.demo.resources.Res
import juce_cmp.demo.resources.compose_multiplatform
import juce_cmp.UISender
// Knob is in the same package, no import needed

@Composable
@Preview
fun App() {
    MaterialTheme {
        var showContent by remember { mutableStateOf(false) }
        
        Column(
            modifier = Modifier
                .background(MaterialTheme.colorScheme.primaryContainer)
                .safeContentPadding()
                .fillMaxSize(),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            // Shape knob - controls oscillator waveform (0=sine, 1=square)
            var shapeValue by remember { mutableStateOf(0f) }
            
            Row(
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(16.dp)
            ) {
                // Click me button
                Button(
                    onClick = { showContent = !showContent }
                ) {
                    Text("Click me!")
                }
                
                // Knob with label
                Column(horizontalAlignment = Alignment.CenterHorizontally) {
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
                }
            }
            
            Spacer(modifier = Modifier.height(16.dp))
            
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