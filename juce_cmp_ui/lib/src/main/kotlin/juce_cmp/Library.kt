// SPDX-FileCopyrightText: 2026 Luciano Iam <oss@lucianoiam.com>
// SPDX-License-Identifier: MIT

package juce_cmp

import androidx.compose.runtime.Composable
import juce_cmp.events.EventSender
import juce_cmp.events.JuceValueTree
import juce_cmp.renderer.runIOSurfaceRenderer
import java.io.FileDescriptor
import java.io.FileOutputStream
import java.io.PrintStream

/**
 * Main entry point for the juce_cmp library.
 *
 * Client applications MUST call init() as the very first thing in main(),
 * before any other code runs. This sets up stdout capture for binary IPC.
 */
object Library {
    private var initialized = false
    private var surfaceID: Int? = null
    private var scaleFactor: Float = 1f

    /**
     * Whether the application was launched by a host.
     */
    val hasHost: Boolean
        get() = surfaceID != null

    /**
     * Initialize the juce_cmp library.
     *
     * MUST be called as the very first thing in main(), before any
     * library initialization or other code that might print to stdout.
     *
     * This performs critical setup:
     * - Parses command-line arguments for embedded mode detection
     * - Captures raw stdout (fd 1) for binary IPC with the host
     * - Redirects System.out to stderr so library noise doesn't corrupt the protocol
     *
     * @param args Command-line arguments from main()
     */
    fun init(args: Array<String> = emptyArray()) {
        if (initialized) return
        initialized = true

        // Parse args to detect embedded mode
        if (args.contains("--embed")) {
            // Hide from Dock - we're a background renderer for the host
            System.setProperty("apple.awt.UIElement", "true")

            // Parse --iosurface-id=<id> from host
            surfaceID = args
                .firstOrNull { it.startsWith("--iosurface-id=") }
                ?.substringAfter("=")
                ?.toIntOrNull()
                ?: error("Missing --iosurface-id=<id> argument")

            // Parse --scale=<factor> for Retina support (e.g., 2.0)
            scaleFactor = args
                .firstOrNull { it.startsWith("--scale=") }
                ?.substringAfter("=")
                ?.toFloatOrNull()
                ?: 1f
        }

        // Capture the raw stdout before anyone else can pollute it
        // FileDescriptor.out is the JVM's reference to fd 1
        EventSender.setOutput(FileOutputStream(FileDescriptor.out))

        // Redirect System.out to stderr so library noise doesn't corrupt our protocol
        // All println(), library warnings, etc. will now go to stderr
        System.setOut(PrintStream(FileOutputStream(FileDescriptor.err), true))
    }

    /**
     * Run the embedded application, rendering to the host's shared surface.
     *
     * This function blocks and renders Compose content until the host closes
     * the connection. Mirrors the Compose `application { }` pattern.
     *
     * @param onEvent Optional callback when host sends events (JuceValueTree payload)
     * @param onFrameRendered Optional callback after each frame (for debugging/capture)
     * @param content The Compose content to render
     */
    fun host(
        onEvent: ((tree: JuceValueTree) -> Unit)? = null,
        onFrameRendered: ((frameNumber: Long, surface: org.jetbrains.skia.Surface) -> Unit)? = null,
        content: @Composable () -> Unit
    ) {
        val id = surfaceID ?: error("host() called but not in embedded mode")

        runIOSurfaceRenderer(
            surfaceID = id,
            scaleFactor = scaleFactor,
            onFrameRendered = onFrameRendered,
            onEvent = onEvent,
            content = content
        )
    }
}
