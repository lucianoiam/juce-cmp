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
    const val INPUT = 0
    const val CMP = 1
    const val JUCE = 2
}

// CMP event types (second byte for EventType.CMP)
// Note: IOSurface sharing uses Mach port IPC, not socket
object CmpEvent {
    const val SURFACE_READY = 0   // UI→Host: first frame rendered to new surface
}
