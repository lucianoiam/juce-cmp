package cmpui

import androidx.compose.ui.window.Window
import androidx.compose.ui.window.application
import cmpui.renderer.runIOSurfaceRenderer

/**
 * Application entry point.
 *
 * Supports two modes:
 * - Standalone: Normal desktop window (default)
 * - Embedded: Renders to IOSurface for host integration (--embed flag)
 *
 * In embedded mode, the host passes --iosurface-id=<id> to specify
 * which IOSurface to render to. Optional --disable-gpu falls back to CPU.
 */
fun main(args: Array<String>) {
    val embedMode = args.contains("--embed")
    
    if (embedMode) {
        // Hide from Dock - we're a background renderer for the host
        System.setProperty("apple.awt.UIElement", "true")
        
        // Parse --iosurface-id=<id> from host
        val surfaceID = args
            .firstOrNull { it.startsWith("--iosurface-id=") }
            ?.substringAfter("=")
            ?.toIntOrNull()
            ?: error("Missing --iosurface-id=<id> argument")
        
        // --disable-gpu forces CPU rendering (for debugging)
        val disableGpu = args.contains("--disable-gpu")
        
        // Start rendering to the shared IOSurface
        runIOSurfaceRenderer(surfaceID, disableGpu) {
            App()
        }
    } else {
        // Standalone mode - regular desktop window
        application {
            Window(
                onCloseRequest = ::exitApplication,
                title = "CMP UI"
            ) {
                App()
            }
        }
    }
}
