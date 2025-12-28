package com.lucianoiam.kmpui

import androidx.compose.ui.window.Window
import androidx.compose.ui.window.application

fun main(args: Array<String>) {
    val embedMode = args.contains("--embed")
    
    if (embedMode) {
        // Hide dock icon when running as embedded child process
        System.setProperty("apple.awt.UIElement", "true")
        
        // Parse --iosurface-id=<id> argument from parent process
        val surfaceID = args
            .firstOrNull { it.startsWith("--iosurface-id=") }
            ?.substringAfter("=")
            ?.toIntOrNull()
            ?: error("Missing --iosurface-id=<id> argument. This app must be launched by the host with --embed.")
        
        // Render Compose content to the shared IOSurface
        runIOSurfaceRenderer(surfaceID) {
            App()
        }
    } else {
        // Run as a normal desktop KMP application
        application {
            Window(
                onCloseRequest = ::exitApplication,
                title = "KMP UI"
            ) {
                App()
            }
        }
    }
}
