package cmpui.input

import java.io.InputStream
import java.nio.ByteBuffer
import java.nio.ByteOrder

/**
 * Reads binary input events from stdin.
 * 
 * Protocol: 16-byte fixed-size events (see common/input_protocol.h).
 * This runs on a background thread and delivers events via callback.
 */
class InputReceiver(
    private val input: InputStream = System.`in`,
    private val onEvent: (InputEvent) -> Unit
) {
    @Volatile
    private var running = false
    private var thread: Thread? = null
    
    fun start() {
        if (running) return
        running = true
        thread = Thread({
            val buffer = ByteArray(16)
            val byteBuffer = ByteBuffer.wrap(buffer).order(ByteOrder.LITTLE_ENDIAN)
            
            while (running) {
                try {
                    // Read exactly 16 bytes (one event)
                    var bytesRead = 0
                    while (bytesRead < 16 && running) {
                        val n = input.read(buffer, bytesRead, 16 - bytesRead)
                        if (n < 0) {
                            // EOF - parent closed pipe
                            running = false
                            break
                        }
                        bytesRead += n
                    }
                    
                    if (bytesRead == 16) {
                        byteBuffer.rewind()
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
                        onEvent(event)
                    }
                } catch (e: Exception) {
                    if (running) {
                        System.err.println("[Input] Error reading event: ${e.message}")
                    }
                }
            }
        }, "InputReceiver")
        thread?.isDaemon = true
        thread?.start()
    }
    
    fun stop() {
        running = false
        thread?.interrupt()
        thread = null
    }
}
