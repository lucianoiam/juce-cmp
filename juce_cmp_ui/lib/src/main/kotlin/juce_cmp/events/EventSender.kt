// SPDX-FileCopyrightText: 2026 Luciano Iam <oss@lucianoiam.com>
// SPDX-License-Identifier: MIT

package juce_cmp.events

import java.io.OutputStream
import java.nio.ByteBuffer
import java.nio.ByteOrder

/**
 * Sends events from UI to host over stdout (UI → host direction).
 *
 * Protocol: 1-byte event type followed by type-specific payload.
 * See ipc_protocol.h for details.
 *
 * Thread-safe: uses synchronized writes.
 *
 * Note: The output stream is set by Library.init() which must be called
 * as the very first thing in main().
 */
object EventSender {
    private var output: OutputStream? = null
    private val lock = Any()

    private const val EVENT_TYPE_CMP = 1
    private const val EVENT_TYPE_JUCE = 2
    private const val CMP_SUBTYPE_FIRST_FRAME = 0

    /** Called by Library.init() to set the output stream. */
    internal fun setOutput(stream: OutputStream) {
        output = stream
    }

    /**
     * Send a JuceValueTree to the host.
     * Format: EVENT_TYPE_JUCE + 4-byte size + ValueTree bytes
     */
    fun send(tree: JuceValueTree) {
        val stream = output ?: return

        val treeBytes = tree.toByteArray()
        val sizeBuffer = ByteBuffer.allocate(4).order(ByteOrder.LITTLE_ENDIAN)
        sizeBuffer.putInt(treeBytes.size)

        synchronized(lock) {
            stream.write(EVENT_TYPE_JUCE)
            stream.write(sizeBuffer.array())
            stream.write(treeBytes)
            stream.flush()
        }
    }

    /**
     * Notify host that first frame has been rendered and surface is ready.
     * Format: EVENT_TYPE_CMP + CMP_SUBTYPE_FIRST_FRAME
     */
    fun sendFirstFrameRendered() {
        val stream = output ?: return

        synchronized(lock) {
            stream.write(EVENT_TYPE_CMP)
            stream.write(CMP_SUBTYPE_FIRST_FRAME)
            stream.flush()
        }
    }
}
