// SPDX-FileCopyrightText: 2026 Luciano Iam <oss@lucianoiam.com>
// SPDX-License-Identifier: MIT

package juce_cmp.demo

import androidx.compose.runtime.mutableStateMapOf
import androidx.compose.runtime.snapshots.SnapshotStateMap
import juce_cmp.Library
import juce_cmp.ipc.JuceValueTree

/**
 * Global parameter state that syncs between host and UI.
 *
 * Handles bidirectional parameter synchronization:
 * - RX: Host sends "param" events via onHostEvent() to update UI state
 * - TX: UI calls set() which updates state and notifies host
 *
 * The Compose UI observes these values and recomposes automatically.
 *
 * Usage in Compose:
 * ```
 * val paramState = ParameterState.getState()
 * val shapeValue = paramState[0] ?: 0f
 *
 * Knob(
 *     value = shapeValue,
 *     onValueChange = { ParameterState.set(0, it) }
 * )
 * ```
 */
object ParameterState {
    /** Parameter indices - must match host definitions */
    object Index {
        const val Shape = 0
    }

    // Thread-safe observable map of parameter ID -> value
    private val parameters: SnapshotStateMap<Int, Float> = mutableStateMapOf()

    /**
     * Get the current value of a parameter.
     * Returns the default if not yet set.
     */
    fun get(paramId: Int, default: Float = 0f): Float {
        return parameters[paramId] ?: default
    }

    /**
     * Set a parameter value from the UI.
     * Updates local state and sends to host.
     */
    fun set(paramId: Int, value: Float) {
        parameters[paramId] = value
        val tree = JuceValueTree("param")
        tree["id"] = paramId
        tree["value"] = value.toDouble()
        Library.send(tree)
    }

    /**
     * Get the state map for observation in Compose.
     */
    fun getState(): SnapshotStateMap<Int, Float> = parameters

    /**
     * Handle a "param" event from the host.
     * Updates local state without sending back to host.
     */
    fun onEvent(tree: JuceValueTree) {
        if (tree.type == "param") {
            val id = tree["id"].toInt()
            val value = tree["value"].toDouble().toFloat()
            if (id >= 0) {
                parameters[id] = value
            }
        }
    }
}
