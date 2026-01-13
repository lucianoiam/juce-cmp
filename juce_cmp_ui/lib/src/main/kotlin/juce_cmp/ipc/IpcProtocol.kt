// SPDX-FileCopyrightText: 2026 Luciano Iam <oss@lucianoiam.com>
// SPDX-License-Identifier: MIT

package juce_cmp.ipc

/**
 * IPC Protocol constants - mirrors ipc_protocol.h
 *
 * Format: 1-byte event type followed by type-specific payload.
 * Uses a Unix socket pair for bidirectional communication.
 */

// Event types (first byte of every message)
object EventType {
    const val GFX = 0
    const val INPUT = 1
    const val JUCE = 2
}

// GFX event types (second byte for EventType.GFX)
object GfxEvent {
    const val SURFACE_ID = 0    // Host→UI: 4-byte surface ID follows
    const val FIRST_FRAME = 1   // UI→Host: surface ready to display
}
