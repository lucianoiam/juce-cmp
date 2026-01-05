// SPDX-FileCopyrightText: 2026 Luciano Iam <oss@lucianoiam.com>
// SPDX-License-Identifier: MIT

package juce_cmp.demo

import androidx.compose.ui.window.Window
import androidx.compose.ui.window.application
import juce_cmp.UISender
import juce_cmp.renderer.runIOSurfaceRenderer
import juce_cmp.renderer.captureFirstFrame

/**
 * Application entry point.
 *
 * Supports two modes:
 * - Standalone: Normal desktop window (default)
 * - Embedded: Renders to IOSurface for host integration (--embed flag)
 *
 * In embedded mode, the host passes --iosurface-id=<id> to specify
 * which IOSurface to render to.
 */
fun main(args: Array<String>) {
    val embedMode = args.contains("--embed")
    
    if (embedMode) {
        // Hide from Dock - we're a background renderer for the host
        System.setProperty("apple.awt.UIElement", "true")
        
        // Initialize IPC sender with pipe path from args
        UISender.initialize(args)
        
        // Parse --iosurface-id=<id> from host
        val surfaceID = args
            .firstOrNull { it.startsWith("--iosurface-id=") }
            ?.substringAfter("=")
            ?.toIntOrNull()
            ?: error("Missing --iosurface-id=<id> argument")
        
        // Parse --scale=<factor> for Retina support (e.g., 2.0)
        val scaleFactor = args
            .firstOrNull { it.startsWith("--scale=") }
            ?.substringAfter("=")
            ?.toFloatOrNull()
            ?: 1f

        // Start rendering to the shared IOSurface
        runIOSurfaceRenderer(
            surfaceID = surfaceID,
            scaleFactor = scaleFactor,
            onFrameRendered = captureFirstFrame("/tmp/loading_preview.png")
        ) {
            UserInterface()
        }
    } else {
        // Standalone mode - regular desktop window
        application {
            Window(
                onCloseRequest = ::exitApplication,
                title = "CMP UI"
            ) {
                UserInterface()
            }
        }
    }
}
