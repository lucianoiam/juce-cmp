// SPDX-FileCopyrightText: 2026 Luciano Iam <oss@lucianoiam.com>
// SPDX-License-Identifier: MIT

package juce_cmp.events

import java.io.InputStream
import java.nio.ByteBuffer
import java.nio.ByteOrder
import juce_cmp.input.InputEvent

/**
 * Receives binary events from the host process via stdin pipe.
 *
 * Protocol: 1-byte event type followed by type-specific payload.
 * See ipc_protocol.h for details.
 *
 * Note: This is the Kotlin-side EventReceiver (host → UI direction).
 * The C++ EventReceiver in juce_cmp handles the opposite direction (UI → host).
 */
class EventReceiver(
    private val input: InputStream = System.`in`,
    private val onInputEvent: (InputEvent) -> Unit,
    private val onJuceEvent: ((JuceValueTree) -> Unit)? = null
) {
    @Volatile
    private var running = false
    private var thread: Thread? = null

    private companion object {
        const val EVENT_TYPE_INPUT = 0
        const val EVENT_TYPE_CMP = 1
        const val EVENT_TYPE_JUCE = 2
    }

    /** Returns true if the receiver is still running (stdin not closed) */
    val isRunning: Boolean get() = running

    fun start() {
        if (running) return
        running = true
        thread = Thread({
            while (running) {
                try {
                    val eventType = input.read()
                    System.err.println("[EventReceiver] Got event type: $eventType")
                    if (eventType < 0) {
                        running = false
                        kotlin.system.exitProcess(0)
                    }

                    when (eventType) {
                        EVENT_TYPE_INPUT -> handleInputEvent()
                        EVENT_TYPE_CMP -> handleCmpEvent()
                        EVENT_TYPE_JUCE -> handleJuceEvent()
                        else -> System.err.println("[EventReceiver] Unknown event type: $eventType")
                    }
                } catch (e: Exception) {
                    if (running) {
                        System.err.println("[EventReceiver] Error: ${e.message}")
                    }
                }
            }
        }, "EventReceiver")
        thread?.isDaemon = true
        thread?.start()
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
            onInputEvent(event)
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
                    onJuceEvent.invoke(tree)
                }
            }
        }
    }

    fun stop() {
        running = false
        thread?.interrupt()
        thread = null
    }
}
