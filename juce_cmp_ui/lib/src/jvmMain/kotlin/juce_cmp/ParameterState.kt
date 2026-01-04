// SPDX-FileCopyrightText: 2026 Luciano Iam <oss@lucianoiam.com>
// SPDX-License-Identifier: MIT

package juce_cmp

import androidx.compose.runtime.mutableStateMapOf
import androidx.compose.runtime.snapshots.SnapshotStateMap

/**
 * Global parameter state that syncs between host and UI.
 * 
 * When the host changes a parameter (automation, presets, etc.), it sends
 * a PARAM event which updates this state. The Compose UI observes these
 * values and recomposes automatically.
 * 
 * Usage in Compose:
 * ```
 * val shapeValue by ParameterState.observe(0, 0f)  // paramId, default
 * ```
 */
object ParameterState {
    // Thread-safe observable map of parameter ID -> value
    private val parameters: SnapshotStateMap<Int, Float> = mutableStateMapOf()
    
    /**
     * Update a parameter value from the host.
     * Called by the renderer when a PARAM event is received.
     */
    fun update(paramId: Int, value: Float) {
        parameters[paramId] = value
    }
    
    /**
     * Get the current value of a parameter.
     * Returns the default if not yet set.
     */
    fun get(paramId: Int, default: Float = 0f): Float {
        return parameters[paramId] ?: default
    }
    
    /**
     * Get the state map for observation in Compose.
     * Use with `derivedStateOf` or directly observe.
     */
    fun getState(): SnapshotStateMap<Int, Float> = parameters
}
