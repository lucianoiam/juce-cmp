// SPDX-FileCopyrightText: 2026 Luciano Iam <oss@lucianoiam.com>
// SPDX-License-Identifier: MIT

package juce_cmp.ipc

import com.sun.jna.Library
import com.sun.jna.Memory
import com.sun.jna.Native
import com.sun.jna.Pointer
import java.nio.ByteBuffer
import java.nio.ByteOrder
import javax.sound.midi.MidiMessage
import javax.sound.midi.ShortMessage
import javax.sound.midi.SysexMessage
import juce_cmp.input.InputEvent

/**
 * Native library interface for socket I/O operations.
 */
private interface SocketLib : Library {
    fun socketRead(socketFD: Int, buffer: Pointer, length: Long): Long
    fun socketWrite(socketFD: Int, buffer: Pointer, length: Long): Long

    companion object {
        val INSTANCE: SocketLib by lazy {
            val libFile = Native.extractFromResourcePath("iosurface_renderer")
            Native.load(libFile.absolutePath, SocketLib::class.java)
        }
    }
}

/**
 * Bidirectional IPC channel between UI and host process.
 *
 * Uses a Unix socket for bidirectional communication via native JNA calls.
 * Protocol: 1-byte event type followed by type-specific payload.
 * See ipc_protocol.h for details.
 *
 * - Receiving runs on a background thread (host → UI)
 * - Sending is synchronous and thread-safe (UI → host)
 */
class Ipc(private val socketFD: Int) {
    @Volatile
    private var running = false
    private var thread: Thread? = null
    private val writeLock = Any()

    // Reusable buffers for native I/O
    private val readBuffer = Memory(1024)
    private val writeBuffer = Memory(1024)

    /** Returns true if the receiver is still running (socket not closed) */
    val isRunning: Boolean get() = running

    // ---- Receiving (Host → UI) ----

    private var onInputEvent: ((InputEvent) -> Unit)? = null
    private var onJuceEvent: ((JuceValueTree) -> Unit)? = null
    private var onMidiEvent: ((MidiMessage) -> Unit)? = null

    fun startReceiving(
        onInputEvent: (InputEvent) -> Unit,
        onJuceEvent: ((JuceValueTree) -> Unit)? = null,
        onMidiEvent: ((MidiMessage) -> Unit)? = null
    ) {
        if (running) return
        this.onInputEvent = onInputEvent
        this.onJuceEvent = onJuceEvent
        this.onMidiEvent = onMidiEvent
        running = true
        thread = Thread({
            while (running) {
                try {
                    val eventType = readByte()
                    if (eventType < 0) {
                        running = false
                        kotlin.system.exitProcess(0)
                    }

                    when (eventType) {
                        EventType.INPUT -> handleInputEvent()
                        EventType.CMP -> handleCmpEvent()
                        EventType.JUCE -> handleJuceEvent()
                        EventType.MIDI -> handleMidiEvent()
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

    private fun readByte(): Int {
        val n = SocketLib.INSTANCE.socketRead(socketFD, readBuffer, 1)
        if (n <= 0) return -1
        return readBuffer.getByte(0).toInt() and 0xFF
    }

    private fun readFully(size: Int): ByteArray? {
        val data = ByteArray(size)
        var offset = 0
        while (offset < size && running) {
            val toRead = minOf(1024L, (size - offset).toLong())
            val n = SocketLib.INSTANCE.socketRead(socketFD, readBuffer, toRead)
            if (n <= 0) return null
            for (i in 0 until n.toInt()) {
                data[offset + i] = readBuffer.getByte(i.toLong())
            }
            offset += n.toInt()
        }
        return if (offset == size) data else null
    }

    private fun handleInputEvent() {
        val buffer = readFully(16) ?: run {
            running = false
            kotlin.system.exitProcess(0)
        }

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

    private fun handleCmpEvent() {
        val subtype = readByte()
        if (subtype < 0) {
            running = false
            kotlin.system.exitProcess(0)
        }

        // CmpEvent.FRAME_READY is UI → Host only
        // IOSurface sharing uses Mach port IPC, not socket events
    }

    private fun handleJuceEvent() {
        val sizeBuffer = readFully(4) ?: run {
            running = false
            kotlin.system.exitProcess(0)
        }

        val size = ByteBuffer.wrap(sizeBuffer).order(ByteOrder.LITTLE_ENDIAN).int
        if (size > 0 && onJuceEvent != null) {
            val payload = readFully(size) ?: run {
                running = false
                kotlin.system.exitProcess(0)
            }

            val tree = JuceValueTree.fromByteArray(payload)
            onJuceEvent?.invoke(tree)
        }
    }

    private fun handleMidiEvent() {
        val size = readByte()
        if (size < 0) {
            running = false
            kotlin.system.exitProcess(0)
        }

        if (size > 0 && onMidiEvent != null) {
            val payload = readFully(size) ?: run {
                running = false
                kotlin.system.exitProcess(0)
            }

            val message = createMidiMessage(payload)
            if (message != null) {
                onMidiEvent?.invoke(message)
            }
        }
    }

    private fun createMidiMessage(data: ByteArray): MidiMessage? {
        if (data.isEmpty()) return null
        val status = data[0].toInt() and 0xFF
        return if (status == 0xF0 || status == 0xF7) {
            SysexMessage(data, data.size)
        } else {
            when (data.size) {
                1 -> ShortMessage(status)
                2 -> ShortMessage(status, data[1].toInt() and 0xFF, 0)
                3 -> ShortMessage(status, data[1].toInt() and 0xFF, data[2].toInt() and 0xFF)
                else -> null
            }
        }
    }

    // ---- Sending (UI → Host) ----

    private fun writeFully(data: ByteArray) {
        var offset = 0
        while (offset < data.size) {
            val toWrite = minOf(1024, data.size - offset)
            for (i in 0 until toWrite) {
                writeBuffer.setByte(i.toLong(), data[offset + i])
            }
            val n = SocketLib.INSTANCE.socketWrite(socketFD, writeBuffer, toWrite.toLong())
            if (n <= 0) return
            offset += n.toInt()
        }
    }

    /**
     * Send a JuceValueTree to the host.
     * Format: EventType.JUCE + 4-byte size + ValueTree bytes
     */
    fun sendJuceEvent(tree: JuceValueTree) {
        val treeBytes = tree.toByteArray()
        val sizeBuffer = ByteBuffer.allocate(4).order(ByteOrder.LITTLE_ENDIAN)
        sizeBuffer.putInt(treeBytes.size)

        synchronized(writeLock) {
            writeFully(byteArrayOf(EventType.JUCE.toByte()))
            writeFully(sizeBuffer.array())
            writeFully(treeBytes)
        }
    }

    /**
     * Notify host that first frame has been rendered to a new surface.
     * Format: EventType.CMP + CmpEvent.SURFACE_READY
     */
    fun sendSurfaceReady() {
        synchronized(writeLock) {
            writeFully(byteArrayOf(EventType.CMP.toByte(), CmpEvent.SURFACE_READY.toByte()))
        }
    }

    /**
     * Send a MIDI message to the host.
     * Format: EventType.MIDI + 1-byte size + raw MIDI bytes
     */
    fun sendMidiEvent(message: MidiMessage) {
        val data = message.message
        val length = message.length
        if (length == 0 || length > 255) return

        synchronized(writeLock) {
            writeFully(byteArrayOf(EventType.MIDI.toByte(), length.toByte()))
            writeFully(data.copyOf(length))
        }
    }
}
