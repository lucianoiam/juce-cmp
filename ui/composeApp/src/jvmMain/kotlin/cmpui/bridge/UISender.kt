package cmpui.bridge

import java.io.File
import java.io.FileOutputStream
import java.io.OutputStream
import java.nio.ByteBuffer
import java.nio.ByteOrder

/**
 * Opcodes for UI→Host messages.
 * Must match common/ui_protocol.h
 */
object Opcode {
    const val SET_PARAM = 1
}

/**
 * Sends binary messages from UI to host.
 *
 * Protocol: 8-byte header (opcode + payloadSize) followed by payload.
 * See common/ui_protocol.h for protocol definition.
 *
 * Why we don't use stdout:
 * The JVM and libraries (JNA, Compose, etc.) emit text to stdout (warnings, logs).
 * This corrupts any binary protocol on stdout. Instead, the host creates a named
 * pipe (FIFO) and passes its path via --ipc-pipe=<path>. We open this dedicated
 * channel for clean binary IPC.
 *
 * Thread-safe: uses synchronized writes.
 */
object UISender {
    private var ipcPipePath: String? = null
    private var output: OutputStream? = null
    private val lock = Any()
    
    /**
     * Initialize the sender with the IPC pipe path from command line args.
     * Called once at startup.
     */
    fun initialize(args: Array<String>) {
        for (arg in args) {
            if (arg.startsWith("--ipc-pipe=")) {
                ipcPipePath = arg.substringAfter("--ipc-pipe=")
                break
            }
        }
        
        if (ipcPipePath != null) {
            try {
                output = FileOutputStream(File(ipcPipePath!!))
            } catch (e: Exception) {
                // Silently fail if not in embedded mode
            }
        }
    }
    
    /**
     * Send a parameter change to the host.
     *
     * @param paramId Parameter index (0 = shape, etc.)
     * @param value Parameter value (0.0 - 1.0)
     */
    fun setParameter(paramId: Int, value: Float) {
        val stream = output ?: return
        
        // Header (8 bytes) + Payload (8 bytes) = 16 bytes total
        val buffer = ByteBuffer.allocate(16).order(ByteOrder.LITTLE_ENDIAN)
        
        // Header
        buffer.putInt(Opcode.SET_PARAM)  // opcode
        buffer.putInt(8)                  // payloadSize
        
        // Payload
        buffer.putInt(paramId)            // paramId
        buffer.putFloat(value)            // value
        
        synchronized(lock) {
            stream.write(buffer.array())
            stream.flush()
        }
    }
}
