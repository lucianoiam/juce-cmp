// SPDX-FileCopyrightText: 2026 Luciano Iam <oss@lucianoiam.com>
// SPDX-License-Identifier: MIT

package juce_cmp.ipc

import java.io.InputStream
import java.io.OutputStream
import java.nio.ByteBuffer
import java.nio.ByteOrder
import juce_cmp.input.InputEvent

/**
 * Bidirectional IPC channel between UI and host process.
 *
 * Protocol: 1-byte event type followed by type-specific payload.
 * See ipc_protocol.h for details.
 *
 * - Receiving runs on a background thread (host → UI)
 * - Sending is synchronous and thread-safe (UI → host)
 */
class Ipc(
    private val input: InputStream,
    private val output: OutputStream
) {
    @Volatile
    private var running = false
    private var thread: Thread? = null
    private val writeLock = Any()

    private companion object {
        const val EVENT_TYPE_INPUT = 0
        const val EVENT_TYPE_CMP = 1
        const val EVENT_TYPE_JUCE = 2
        const val CMP_SUBTYPE_FIRST_FRAME = 0
    }

    /** Returns true if the receiver is still running (stdin not closed) */
    val isRunning: Boolean get() = running

    // ---- Receiving (Host → UI) ----

    private var onInputEvent: ((InputEvent) -> Unit)? = null
    private var onJuceEvent: ((JuceValueTree) -> Unit)? = null

    fun startReceiving(
        onInputEvent: (InputEvent) -> Unit,
        onJuceEvent: ((JuceValueTree) -> Unit)? = null
    ) {
        if (running) return
        this.onInputEvent = onInputEvent
        this.onJuceEvent = onJuceEvent
        running = true
        thread = Thread({
            while (running) {
                try {
                    val eventType = input.read()
                    if (eventType < 0) {
                        running = false
                        kotlin.system.exitProcess(0)
                    }

                    when (eventType) {
                        EVENT_TYPE_INPUT -> handleInputEvent()
                        EVENT_TYPE_CMP -> handleCmpEvent()
                        EVENT_TYPE_JUCE -> handleJuceEvent()
                    }
                } catch (e: Exception) {
                    // Silently ignore exceptions when running
                }
            }
        }, "Ipc")
        thread?.isDaemon = true
        thread?.start()
    }

    fun stopReceiving() {
        running = false
        thread?.interrupt()
        thread = null
    }

    private fun handleInputEvent() {
        val buffer = ByteArray(16)
        var bytesRead = 0
        while (bytesRead < 16 && running) {
            val n = input.read(buffer, bytesRead, 16 - bytesRead)
            if (n < 0) {
                running = false
                kotlin.system.exitProcess(0)
            }
            bytesRead += n
        }

        if (bytesRead == 16) {
            val byteBuffer = ByteBuffer.wrap(buffer).order(ByteOrder.LITTLE_ENDIAN)
            val event = InputEvent(
                type = byteBuffer.get().toInt() and 0xFF,
                action = byteBuffer.get().toInt() and 0xFF,
                button = byteBuffer.get().toInt() and 0xFF,
                modifiers = byteBuffer.get().toInt() and 0xFF,
                x = byteBuffer.short.toInt(),
                y = byteBuffer.short.toInt(),
                data1 = byteBuffer.short.toInt(),
                data2 = byteBuffer.short.toInt(),
                timestamp = byteBuffer.int.toLong() and 0xFFFFFFFFL
            )
            onInputEvent?.invoke(event)
        }
    }

    private fun handleCmpEvent() {
        val subtype = input.read()
        if (subtype < 0) {
            running = false
            kotlin.system.exitProcess(0)
        }
        // CMP events are UI → Host only, shouldn't receive them here
    }

    private fun handleJuceEvent() {
        val sizeBuffer = ByteArray(4)
        var bytesRead = 0
        while (bytesRead < 4 && running) {
            val n = input.read(sizeBuffer, bytesRead, 4 - bytesRead)
            if (n < 0) {
                running = false
                kotlin.system.exitProcess(0)
            }
            bytesRead += n
        }

        if (bytesRead == 4) {
            val size = ByteBuffer.wrap(sizeBuffer).order(ByteOrder.LITTLE_ENDIAN).int
            if (size > 0 && onJuceEvent != null) {
                val payload = ByteArray(size)
                var payloadRead = 0
                while (payloadRead < size && running) {
                    val n = input.read(payload, payloadRead, size - payloadRead)
                    if (n < 0) {
                        running = false
                        kotlin.system.exitProcess(0)
                    }
                    payloadRead += n
                }

                if (payloadRead == size) {
                    val tree = JuceValueTree.fromByteArray(payload)
                    onJuceEvent?.invoke(tree)
                }
            }
        }
    }

    // ---- Sending (UI → Host) ----

    /**
     * Send a JuceValueTree to the host.
     * Format: EVENT_TYPE_JUCE + 4-byte size + ValueTree bytes
     */
    fun send(tree: JuceValueTree) {
        val treeBytes = tree.toByteArray()
        val sizeBuffer = ByteBuffer.allocate(4).order(ByteOrder.LITTLE_ENDIAN)
        sizeBuffer.putInt(treeBytes.size)

        synchronized(writeLock) {
            output.write(EVENT_TYPE_JUCE)
            output.write(sizeBuffer.array())
            output.write(treeBytes)
            output.flush()
        }
    }

    /**
     * Notify host that first frame has been rendered and surface is ready.
     * Format: EVENT_TYPE_CMP + CMP_SUBTYPE_FIRST_FRAME
     */
    fun sendFirstFrameRendered() {
        synchronized(writeLock) {
            output.write(EVENT_TYPE_CMP)
            output.write(CMP_SUBTYPE_FIRST_FRAME)
            output.flush()
        }
    }
}
