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

    if (Library.isEmbedded) {
        Library.embeddedApplication(
            // DEV: Uncomment to generate loading_preview.png from first rendered frame
            // onFrameRendered = captureFirstFrame("/tmp/loading_preview.png"),
            onJuceEvent = { tree ->
                // Handle events from host (JuceValueTree payload)
                if (tree.type == "param") {
                    val id = tree["id"].toInt()
                    val value = tree["value"].toDouble().toFloat()
                    if (id >= 0) {
                        ParameterState.update(id, value)
                    }
                }
            }
        ) {
            UserInterface()
        }
    } else {
        // Standalone mode - regular desktop window
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
