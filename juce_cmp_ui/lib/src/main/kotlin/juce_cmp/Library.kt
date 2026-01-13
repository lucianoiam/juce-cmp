// SPDX-FileCopyrightText: 2026 Luciano Iam <oss@lucianoiam.com>
// SPDX-License-Identifier: MIT

package juce_cmp

import androidx.compose.runtime.Composable
import juce_cmp.ipc.Ipc
import juce_cmp.ipc.JuceValueTree
import juce_cmp.renderer.runIOSurfaceRenderer
import java.io.FileDescriptor
import java.io.FileOutputStream
import java.io.PrintStream

/**
 * Main entry point for the juce_cmp library.
 *
 * Client applications MUST call init() as the very first thing in main(),
 * before any other code runs. This sets up the socket-based IPC channel.
 */
object Library {
    private var initialized = false
    private var socketFD: Int? = null
    private var scaleFactor: Float = 1f
    private var ipc: Ipc? = null

    /**
     * Whether the application was launched by a host.
     */
    val hasHost: Boolean
        get() = socketFD != null

    /**
     * Send a JuceValueTree event to the host.
     */
    fun send(tree: JuceValueTree) {
        ipc?.send(tree)
    }

    /**
     * Initialize the juce_cmp library.
     *
     * MUST be called as the very first thing in main(), before any
     * library initialization or other code that might print to stdout.
     *
     * This performs critical setup:
     * - Parses command-line arguments for embedded mode detection
     * - Sets up socket-based IPC with the host
     * - Redirects System.out to stderr so library noise doesn't corrupt the protocol
     *
     * @param args Command-line arguments from main()
     */
    fun init(args: Array<String> = emptyArray()) {
        if (initialized) return
        initialized = true

        // Parse --socket-fd=<fd> to detect embedded mode
        val socketArg = args.firstOrNull { it.startsWith("--socket-fd=") }
        if (socketArg != null) {
            // Hide from Dock - we're a background renderer for the host
            System.setProperty("apple.awt.UIElement", "true")

            socketFD = socketArg
                .substringAfter("=")
                .toIntOrNull()
                ?: error("Invalid --socket-fd value")

            // Parse --scale=<factor> for Retina support (e.g., 2.0)
            scaleFactor = args
                .firstOrNull { it.startsWith("--scale=") }
                ?.substringAfter("=")
                ?.toFloatOrNull()
                ?: 1f

            // Create IPC channel on the inherited socket FD
            ipc = Ipc(socketFD!!)

            // Redirect System.out to stderr so library noise doesn't corrupt our protocol
            System.setOut(PrintStream(FileOutputStream(FileDescriptor.err), true))
        }
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
        val fd = socketFD ?: error("host() called but not in embedded mode")
        val channel = ipc ?: error("host() called but IPC not initialized")

        runIOSurfaceRenderer(
            socketFD = fd,
            scaleFactor = scaleFactor,
            ipc = channel,
            onFrameRendered = onFrameRendered,
            onJuceEvent = onEvent,
            content = content
        )
    }
}
