// SPDX-FileCopyrightText: 2026 Luciano Iam <oss@lucianoiam.com>
// SPDX-License-Identifier: MIT

package juce_cmp.demo

import androidx.compose.ui.window.Window
import androidx.compose.ui.window.application
import juce_cmp.Library
import juce_cmp.renderer.captureFirstFrame

/**
 * Application entry point.
 *
 * Supports two modes:
 * - Standalone: Normal desktop window (default)
 * - Embedded: Renders to host's shared surface (--embed flag)
 */
fun main(args: Array<String>) {
    // MUST be first - initializes library and parses args
    Library.init(args)

    if (Library.hasHost) {
        Library.host(
            // DEV: Uncomment to generate loading_preview.png from first rendered frame
            // onFrameRendered = captureFirstFrame("/tmp/loading_preview.png"),
            onEvent = ParameterState::onEvent
        ) {
            UserInterface()
        }
    } else {
        // Standalone mode - regular desktop window for development.
        // Allows running the Compose UI independently with hot reload,
        // without requiring the JUCE host.
        application {
            Window(
                onCloseRequest = ::exitApplication,
                title = "CMP UI Standalone"
            ) {
                UserInterface()
            }
        }
    }
}
